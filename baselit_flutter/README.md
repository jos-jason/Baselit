# Baselit for Android and Linux

A simpler Flutter companion to the iOS app. It stores data in the same layout
as an iOS backup (`baselit_backup.json` plus a `photos/` folder), so you move
your inventory between devices by exporting a backup on one and importing it
on the other (Settings, from the gear on the Search tab).

## Sync

Every Baselit app (this one and the iOS app) can keep the same inventory,
photos included, through the NAS's PocketBase server, the same way Inkpad does.
It uses the [nas-sync](https://github.com/jos-jason/nas-sync) package and its
shared `sync_items` collection, under app `baselit`, so the server needs no
setup of its own. In Settings, open **NAS Sync** and sign in with the server
address and your NAS account; the device needs Tailscale on to reach it.

Sign in first on the device with your full inventory. A device that already
has its own copy then asks whether to **Use Server's** inventory or **Merge**;
pick Use Server's if it was set up from a backup of the same inventory.

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
