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
Inno Setup is great for creating a `Setup.exe`. If the app isn't opening on other systems, it's almost certainly because the **DLLs** or the **data folder** are missing from the script.

### 🛑 Crucial Inno Setup "[Files]" Section
Your `.iss` script must include more than just the `.exe`. Use this exact structure in your `[Files]` section:

```iss
[Files]
; The main application executable
Source: "build\windows\x64\runner\Release\fylooo.exe"; DestDir: "{app}"; Flags: ignoreversion

; The Flutter engine DLL
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion

; All other plugin DLLs (like window_manager_plugin.dll)
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion

; The DATA folder (icons, assets, fonts) - CRITICAL!
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
```

### ⚠️ Missing System Dependencies
If the app *still* doesn't open (or gives a "msvcp140.dll missing" error), the target computer needs the **Visual C++ Redistributable**.
- You can include the installer for it in your Inno Setup script, or
- Download and install it manually on the target machine: [Microsoft VCRedist 2015-2022](https://aka.ms/vs/17/release/vc_redist.x64.exe).

## Summary: What MUST be in the same folder
Whether you use a tool or just Zip the files, these 4 components must stay together:
1. `fylooo.exe`
2. `flutter_windows.dll` 
3. `*.dll` (All plugin DLLs)
4. `data/` (Folder containing assets)

**Tip**: The easiest way to verify is to copy the *entire* `build/windows/x64/runner/Release/` folder to a USB drive and try running it from there on another machine. If that works, ensure your Inno Setup script is catching all those files.
