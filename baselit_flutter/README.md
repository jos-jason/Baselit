# Baselit for Android and Linux

A simpler Flutter companion to the iOS app. It stores data in the same layout
as an iOS backup (`baselit_backup.json` plus a `photos/` folder), so you move
your inventory between devices by exporting a backup on one and importing it
on the other (Settings, from the gear on the Search tab).

The look follows the iOS app: grouped gray background, white cards with 26pt
corners, gray icon tiles, Cupertino icons, a black and white accent, and a
floating pill tab bar. Text uses Inter, the closest free match to SF Pro.

## Install on Linux (Omarchy, Arch, and others)

Every push to `main` that changes this folder builds a Linux version on GitHub
and publishes it as the
[linux-latest pre-release](https://github.com/jos-jason/Baselit/releases/tag/linux-latest).

```bash
curl -LO https://github.com/jos-jason/Baselit/releases/download/linux-latest/baselit-linux-x64.tar.gz
tar -xzf baselit-linux-x64.tar.gz
cd baselit-linux-x64 && ./install.sh
```

Baselit then shows up in the app launcher, or run `baselit`. It needs GTK 3,
which Omarchy already has (`sudo pacman -S gtk3` otherwise). Remove it with
`./install.sh --uninstall`; your data in `~/.local/share/com.babymechanical.baselit`
is kept.

## Run from source

```bash
flutter run -d linux      # on a Linux machine
flutter run -d android    # with a phone or emulator connected
flutter run -d macos      # quick preview on a Mac
```

Linux builds only work on Linux. On Ubuntu, install the build tools first:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
```

## Preview renders

`flutter test --update-goldens test/preview_test.dart` renders the main screens
in light and dark mode to `test/goldens/` (macOS only, uses the system font).
The Flutter test runner fails on folder paths that contain an apostrophe, so
run tests from a copy of the project in such a case.
