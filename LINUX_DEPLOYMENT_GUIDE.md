# Linux Deployment Guide for Fylooo

Flutter Linux builds generate a directory containing the executable and dependent libraries. To distribute your app, you should package these files into a user-friendly format.

## Step 1: Build the Linux App
Run this command in your project root:
```bash
flutter build linux --release
```
*The build artifacts will be located at:*
`build/linux/x64/release/bundle/`

## Step 2: Packaging for Distribution

There are several ways to package your Linux app. For a "portable" experience similar to Windows, **AppImage** is recommended.

### Option A: AppImage (Portable Single File)
AppImage is the closest equivalent to a "portable exe". It runs on most major Linux distributions.
1. Install `appimagetool`.
2. Create an `AppDir` structure:
   - Copy the contents of `build/linux/x64/release/bundle/` to `AppDir/usr/bin/`.
   - Add a `.desktop` file and the app icon.
3. Run `appimagetool AppDir/` to generate the `.AppImage` file.

### Option B: Debian Package (.deb)
Recommended for Ubuntu, Debian, and Mint users.
You can use the `flutter_to_debian` package or manually create the `DEBIAN/control` file.
1. Create a directory structure: `fylooo-1.1.0/usr/bin/` and `fylooo-1.1.0/DEBIAN/`.
2. Copy build files to `usr/bin/`.
3. Create a `control` file with metadata.
4. Run: `dpkg-deb --build fylooo-1.1.0`

### Option C: Snap or Flatpak
These are sandboxed formats. If you plan to publish on the "Snap Store" or "Flathub", follow their specific documentation:
- [Snapcraft Docs](https://snapcraft.io/docs/flutter-apps)
- [Flatpak Docs](https://docs.flatpak.org/)

## Summary of Files to Include
If you distribute a "Portable Folder" (zip), you **must** include:
- `fylooo` (the main executable)
- `lib/` directory (contains `libflutter_linux_gtk.so` and plugin libraries)
- `data/` directory (contains app assets)

## App Icon
I have configured `flutter_launcher_icons` to handle technical icon generation. When packaging (e.g., for `.deb` or `.desktop` files), use the icon generated in your assets or the branding images in `assets/images/`.
