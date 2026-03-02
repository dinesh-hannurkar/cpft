# Linux Deployment Guide for Fylooo

Complete step-by-step instructions to build, package, and distribute the Fylooo Linux desktop application.

---

## Prerequisites

Ensure the following are installed on your **Linux build machine** or **Ubuntu/Debian system**:

```bash
# Install Flutter dependencies
sudo apt-get update
sudo apt-get install -y \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libstdc++-12-dev \
    dpkg-dev zip

# Verify Flutter
flutter doctor
```

> All commands below assume your project root is `/path/to/cpft/`.

---

## Step 1: Build the Linux Release

```bash
cd /path/to/cpft
flutter build linux --release
```

The build output will be at:
```
build/linux/x64/release/bundle/
├── cpft                  ← main executable
├── lib/                  ← shared libraries (.so files)
└── data/                 ← assets, fonts, shaders
```

---

## Step 2: Create the `.deb` Package

### 2.1 — Set up the Package Directory Structure

```bash
# Set version variable
VERSION="1.1.5"
PKG_NAME="fylooo-${VERSION}-amd64"

mkdir -p ${PKG_NAME}/usr/bin/fylooo
mkdir -p ${PKG_NAME}/usr/share/applications
mkdir -p ${PKG_NAME}/usr/share/icons/hicolor/512x512/apps
mkdir -p ${PKG_NAME}/DEBIAN
```

### 2.2 — Copy the Build Bundle

```bash
cp -r build/linux/x64/release/bundle/. ${PKG_NAME}/usr/bin/fylooo/
```

### 2.3 — Copy the App Icon

```bash
cp assets/images/app-logo.png \
   ${PKG_NAME}/usr/share/icons/hicolor/512x512/apps/fylooo.png
```

### 2.4 — Create the `.desktop` Entry

```bash
cat > ${PKG_NAME}/usr/share/applications/fylooo.desktop << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Fylooo
Comment=High-speed wireless file transfer
Exec=/usr/bin/fylooo/cpft
Icon=fylooo
Terminal=false
Categories=Network;FileTransfer;
StartupNotify=true
EOF
```

### 2.5 — Create the `DEBIAN/control` File

```bash
cat > ${PKG_NAME}/DEBIAN/control << EOF
Package: fylooo
Version: ${VERSION}
Section: net
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libblkid1, liblzma5
Maintainer: Your Name <your@email.com>
Description: Fylooo — High-speed wireless file transfer
 Fylooo enables fast peer-to-peer file transfers over Wi-Fi and hotspot
 connections between Linux, Windows, and Android devices.
EOF
```

### 2.6 — Set Executable Permissions

```bash
chmod +x ${PKG_NAME}/usr/bin/fylooo/cpft

# Create postinst to set permissions on install
cat > ${PKG_NAME}/DEBIAN/postinst << EOF
#!/bin/bash
chmod +x /usr/bin/fylooo/cpft
EOF
chmod 755 ${PKG_NAME}/DEBIAN/postinst
```

### 2.7 — Build the `.deb` Package

```bash
dpkg-deb --build ${PKG_NAME}
# Output: fylooo-1.1.5-amd64.deb
```

---

## Step 3: Create the Update ZIP

The update ZIP is used by the in-app auto-updater. It must contain the flat bundle contents (same as the `.deb` bundle, without the package wrapper).

```bash
cd build/linux/x64/release/bundle
zip -r ../../../../../fylooo-linux-update-${VERSION}.zip .
cd -
```

The resulting `fylooo-linux-update-1.1.5.zip` should contain:
```
cpft
lib/
data/
```

---

## Step 4: Deploy to the Release Server

Copy both the installer and the update zip to your server's `dist/desktop_releases/` directory:

```bash
scp fylooo-${VERSION}-amd64.deb       user@yourserver:/path/to/dist/desktop_releases/
scp fylooo-linux-update-${VERSION}.zip user@yourserver:/path/to/dist/desktop_releases/
```

Or if you're running locally (Node.js dev server):
```bash
cp fylooo-${VERSION}-amd64.deb        dist/desktop_releases/
cp fylooo-linux-update-${VERSION}.zip dist/desktop_releases/
```

---

## Step 5: Update `releases.json`

Edit `dist/releases.json` and add or update the Linux entry:

```json
{
    "platform": "linux",
    "version": "v1.1.5",
    "release_type": "Stable",
    "filename": "fylooo-1.1.5-amd64.deb",
    "downloadUrl": "/desktop_releases/fylooo-1.1.5-amd64.deb",
    "update_zip": "/desktop_releases/fylooo-linux-update-1.1.5.zip",
    "date": "2026-02-28",
    "available": true,
    "notes": "Describe what changed in this release."
}
```

---

## Step 6: Verify the Release

1. **Check the `.deb` install works:**
   ```bash
   sudo dpkg -i fylooo-1.1.5-amd64.deb
   fylooo   # or find it in your app launcher
   ```

2. **Check the update ZIP can be extracted:**
   ```bash
   mkdir test_extract && cd test_extract
   unzip ../fylooo-linux-update-1.1.5.zip
   ./cpft   # should launch the app
   ```

3. **Confirm files are available from the server:**
   ```bash
   curl -I http://yourserver/desktop_releases/fylooo-1.1.5-amd64.deb
   curl -I http://yourserver/desktop_releases/fylooo-linux-update-1.1.5.zip
   ```
   Both should return `HTTP/1.1 200 OK`.

---

## Summary Checklist

```
[ ] flutter build linux --release
[ ] Create package directory structure
[ ] Copy bundle → package/usr/bin/fylooo/
[ ] Add .desktop file and icon
[ ] Create DEBIAN/control file
[ ] dpkg-deb --build → fylooo-X.X.X-amd64.deb
[ ] zip -r → fylooo-linux-update-X.X.X.zip (from bundle/)
[ ] Upload .deb and .zip to dist/desktop_releases/
[ ] Update releases.json with new version entry
[ ] Verify download URLs return HTTP 200
[ ] Test in-app auto-update from previous version
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `libgtk-3-0: not found` on target machine | `sudo apt-get install libgtk-3-0` |
| App won't launch after `.deb` install | `chmod +x /usr/bin/fylooo/cpft` |
| Update ZIP extraction fails | Verify ZIP was created from inside `bundle/` (no extra nesting) |
| `cpft` not found in ZIP | Re-create ZIP: `cd bundle && zip -r ../update.zip .` |
| In-app updater doesn't detect new version | Verify `version` in `releases.json` is newer than app's version |
