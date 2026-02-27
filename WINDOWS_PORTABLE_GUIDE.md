# Generating a Portable Windows EXE for Fylooo

Flutter Windows builds generate a folder containing the `.exe` and multiple `.dll` files. To create a **single, portable `.exe`** file, you need to bundle these files together using a third-party tool.

## Recommended Tool: Enigma Virtual Box (Free)
Enigma Virtual Box is the easiest way to package a Flutter Windows build into a single executable without extracting files to a temp folder.

### Step 1: Build the Flutter App
Run this command in your project root:
```bash
flutter build windows --release
```
Your build files will be in:
`build/windows/x64/runner/Release/`

### Step 2: Bundle with Enigma Virtual Box
1. **Download & Install**: [Enigma Virtual Box](https://enigmaprotector.com/en/aboutvb.html).
2. **Enter Input File**: Select the `fylooo.exe` from your `Release` folder.
3. **Enter Output File**: Choose where you want the single portable `.exe` to be saved.
4. **Add Files**: 
   - Click **Add** -> **Add Folder Recursive**.
   - Select the **entire** `Release` folder (containing the dlls and `data` folder).
   - *Note: Ensure the base directory in the virtual tree matches what the exe expects (usually just the contents of the Release folder).*
5. **Process**: Click **Process**. It will generate one large `.exe` containing all dependencies.

---

## Alternative: Inno Setup (For Installers)
If you want a "Setup.exe" that installs the app but also offers a "portable" extraction mode:
1. Install [Inno Setup](https://jrsoftware.org/isinfo.php).
2. Create a script that includes all files in the `Release` folder.
3. This is better if you want a professional installer with desktop shortcuts.

## Summary of Files to Include
If you prefer to just zip the files (the "Portable Folder" approach), you **must** include:
- `fylooo.exe`
- `flutter_windows.dll`
- `window_manager_plugin.dll` (and any other `.dll` files)
- The `data/` folder (contains your app assets and icons)

**Tip**: Always test the generated `.exe` on a computer that doesn't have Flutter installed to ensure all DLLs were bundled correctly.
