import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = WindowOptions(
    size: const Size(360, 440),
    center: false,
    title: 'Posti',
    skipTaskbar: true,
  );

  // Start hidden (tray app behavior)
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.hide();
  });

  runApp(const PostiApp());
}

class TodoItem {
  String id;
  String text;
  bool done;
  bool archived;

  TodoItem({required this.id, required this.text, this.done = false, this.archived = false});

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done, 'archived': archived};

  static TodoItem fromJson(Map<String, dynamic> j) =>
      TodoItem(id: j['id'], text: j['text'], done: j['done'] ?? false, archived: j['archived'] ?? false);
}

class PostiApp extends StatefulWidget {
  const PostiApp({super.key});

  @override
  State<PostiApp> createState() => _PostiAppState();
}

class _PostiAppState extends State<PostiApp> with WindowListener {
  final List<TodoItem> _items = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  ThemeMode _themeMode = ThemeMode.light;

  // Persisted settings are saved together with todos in the same JSON file.


  String get _storagePath {
    String base;
    if (Platform.isWindows) {
      base = Platform.environment['APPDATA'] ?? Directory.current.path;
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      base = '$home/Library/Application Support';
    } else {
      // Linux / other
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      base = '$home/.local/share';
    }
    final dir = Directory('$base${Platform.pathSeparator}Posti');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}${Platform.pathSeparator}todos.json';
  }

  @override
  void initState() {
    super.initState();
    loadTodos();
    windowManager.addListener(this);
    _setupWindow();

    // Global escape key handler -> hide to tray
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  Future<void> _setupWindow() async {
    // Make the window hidden from taskbar (native runner is frameless).
    // Explicitly NOT always-on-top — the native side pushes the window to
    // HWND_BOTTOM so it sits just above the desktop, like a widget.
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setResizable(false);
    } catch (_) {}
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _inputFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ----------------------------- Persistence -----------------------------
  void loadTodos() {
    final f = File(_storagePath);
    if (!f.existsSync()) return;
    try {
      final raw = f.readAsStringSync();
      final decoded = jsonDecode(raw);
      _items.clear();

      if (decoded is List) {
        // legacy format (list of items)
        for (final e in decoded) {
          _items.add(TodoItem.fromJson(Map<String, dynamic>.from(e)));
        }
      } else if (decoded is Map) {
        final list = (decoded['items'] ?? []) as List<dynamic>;
        for (final e in list) {
          _items.add(TodoItem.fromJson(Map<String, dynamic>.from(e)));
        }
        // load persisted UI settings (theme)
        final theme = decoded['theme'] as String?;
        if (theme != null) {
          _themeMode = theme == 'dark' ? ThemeMode.dark : ThemeMode.light;
        }
      }

      setState(() {});
    } catch (_) {}
  }

  void saveTodos() {
    final f = File(_storagePath);
    final out = jsonEncode({
      'items': _items.map((e) => e.toJson()).toList(),
      'theme': _themeMode == ThemeMode.dark ? 'dark' : 'light',
    });
    f.writeAsStringSync(out);
  }

  // ------------------------------ UI logic ------------------------------
  void _addItem(String text) {
    if (text.trim().isEmpty) {
      _inputFocusNode.requestFocus();
      return;
    }
    final item = TodoItem(id: DateTime.now().millisecondsSinceEpoch.toString(), text: text.trim());
    setState(() {
      _items.insert(0, item);
      _controller.clear();
    });
    saveTodos();
    _inputFocusNode.requestFocus();
  }

  void _toggleDone(TodoItem item) {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) return;
    setState(() {
      _items[idx].done = !_items[idx].done;
      // always archive completed items
      _items[idx].archived = _items[idx].done;
    });
    saveTodos();
  }

  void _removeItem(TodoItem item) {
    setState(() {
      _items.removeWhere((e) => e.id == item.id);
    });
    saveTodos();
  }




  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      // persist immediately
      saveTodos();
    });
  }



  // --------------------------- WindowListener callbacks ------------------
  @override
  void onWindowClose() async {
    // instead of closing, hide to tray
    await windowManager.hide();
  }

  // ------------------------------- Build --------------------------------
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Posti',
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color.fromRGBO(255, 255, 255, 0.98),
        checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color.fromRGBO(0, 0, 0, 0.98),
        checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
      ),
      themeMode: _themeMode,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              // Custom draggable header (frameless window)
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (_) async => await windowManager.startDragging(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // small in-header icon (use system glyph; app/exe icon is provided as assets/icon.ico)
                            const Icon(Icons.task_alt, size: 18),
                            const SizedBox(width: 8),
                            const Text('Posti', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(_themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
                    onPressed: _toggleTheme,
                    tooltip: _themeMode == ThemeMode.light ? 'Switch to dark mode' : 'Switch to light mode',
                  ),
                  IconButton(
                    icon: const Icon(Icons.minimize),
                    onPressed: () async => await windowManager.hide(),
                    tooltip: 'Hide to tray',
                  )
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _inputFocusNode,
                      onSubmitted: _addItem,
                      decoration: const InputDecoration(hintText: 'Add a todo...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _addItem(_controller.text),
                    child: const Icon(Icons.add),
                  )
                ],
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final visible = _items.where((e) => !e.archived).toList();
                return Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('No todos yet — add one.'))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (c, i) {
                            final it = visible[i];
                            return Dismissible(
                              key: Key(it.id),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => _removeItem(it),
                              background: Container(
                                color: Colors.redAccent,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              child: CheckboxListTile(
                                value: it.done,
                                title: Text(it.text, style: it.done ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                                onChanged: (_) => _toggleDone(it),
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
                            );
                          },
                        ),
                );
              }),

              const SizedBox(height: 8),
              const Divider(),

              Builder(builder: (context) {
                final archived = _items.where((e) => e.archived).toList();
                if (archived.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    ExpansionTile(
                      key: const Key('archived_expansion_tile'),
                      title: Row(
                        children: [
                          Expanded(child: Text('Archived (${archived.length})')),
                          IconButton(
                            icon: const Icon(Icons.delete_forever),
                            tooltip: 'Clear archived items',
                            onPressed: archived.isNotEmpty ? _clearArchived : null,
                          )
                        ],
                      ),
                      // make the archived list scrollable when it grows
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: ListView(
                            shrinkWrap: true,
                            children: archived.map((it) {
                              return Dismissible(
                                key: Key('arch-${it.id}'),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) {
                                  setState(() {
                                    _items.removeWhere((e) => e.id == it.id);
                                  });
                                  saveTodos();
                                },
                                background: Container(
                                  color: Colors.redAccent,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                child: ListTile(
                                  title: Text(it.text, style: const TextStyle(color: Colors.grey)),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.restore),
                                    tooltip: 'Restore',
                                    onPressed: () {
                                      setState(() {
                                        final idx = _items.indexWhere((e) => e.id == it.id);
                                        if (idx != -1) {
                                          _items[idx].archived = false;
                                          _items[idx].done = false;
                                        }
                                      });
                                      saveTodos();
                                    },
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    )
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _clearArchived() {
    setState(() {
      _items.removeWhere((e) => e.archived);
    });
    saveTodos();
  }

  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      windowManager.hide();
      return true; // handled
    }
    return false;
  }
}
