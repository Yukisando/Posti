# Posti

A simple desktop todo app with system tray support.

## Building

### Windows
```bash
flutter build windows --release
```

The executable will be in `build\windows\x64\runner\Release\posti.exe`

### macOS
**Note:** You can only build for macOS on a Mac with Xcode installed.

```bash
flutter build macos --release
```

The app bundle will be in `build/macos/Build/Products/Release/posti.app`

## Running in Development

```bash
# Windows
flutter run -d windows

# macOS
flutter run -d macos
```
