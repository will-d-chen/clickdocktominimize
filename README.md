# ClickDockToMinimize

**ClickDockToMinimize** I built this macOS utility that brings a small (but one that I couldn't live without) feature from other operating systems: the ability to click on an active application's Dock icon to minimize its windows. You no longer have to go to the corner of the app and find the yellow circle or use hotkeys!

If an application is currently frontmost and has visible windows, simply clicking its icon in the Dock will minimize it. If the windows are already minimized, clicking the Dock icon will re-open it.

## Features

- **Click-to-Minimize**: Click the Dock icon of any open app to minimize its windows.
- **Background App**: Runs quietly in the background as a menu bar accessory.
- **App Mapping**: Sometimes the name of a Dock icon doesn't perfectly match the running application, the script will try several techniques to match them, but sometimes it still fails. In that case, you can use the menu bar icon to manually link an active app to your next Dock click. However, there are certain edge case apps that I still haven't figured out that refuse to close even after explicitly linking.


## Requirements

- **Permissions**: This app requires **Accessibility** and **Input Monitoring** permissions to function, as it needs to detect mouse clicks on the Dock and manage application windows. NOTE: this is an invasive permissions granting request, but it's the only way I could figure out how to do this. I built this as a personal project, and I am not a security expert, so I am not entirely sure if this is safe. But I assume it's fine since it's local only and the script is short enough that if you're worried I'm sending your keystrokes to the mothership you can verify it yourself.

## Installation & Setup

### Option 1: Build from Source (Recommended)

To compile the application yourself and create a macOS App Bundle (`.app`):

1. **Clone or Download** this repository.
2. Open your Terminal and navigate to the project folder.
3. Run the following commands to compile the Swift code and construct the application bundle:

```bash
# 1. Compile the executable
swiftc ClickDockToMinimize.swift -o ClickDockToMinimize -framework Cocoa -framework ApplicationServices

# 2. Create the App Bundle directory structure
mkdir -p ClickDockToMinimize.app/Contents/MacOS

# 3. Move the executable into the App Bundle
mv ClickDockToMinimize ClickDockToMinimize.app/Contents/MacOS/

# 4. Create an Info.plist file
cat <<EOF > ClickDockToMinimize.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClickDockToMinimize</string>
    <key>CFBundleIdentifier</key>
    <string>com.clickdocktominimize.app</string>
    <key>CFBundleName</key>
    <string>ClickDockToMinimize</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
```

4. You can now move the generated `ClickDockToMinimize.app` to your `/Applications` folder and run it.
5. On the first run, macOS will prompt you to grant permissions.
   - Go to **System Settings > Privacy & Security > Accessibility** and enable ClickDockToMinimize.
   - Go to **System Settings > Privacy & Security > Input Monitoring** and enable ClickDockToMinimize.
6. Restart the application for the permissions to take effect.

### Option 2: Download Pre-compiled App

Alternatively, if you do not want to build it yourself, you can check the **Releases** page of this GitHub repository to download a pre-compiled `ClickDockToMinimize.app.zip`.

## Usage

Once running, you will see a small Dock icon (`dock.rectangle`) in your menu bar.

1. **Normal Use**: Just click on any active application's Dock icon. If the app is in focus (frontmost), its windows will minimize.
2. **Menu Bar Options**:
   - **Link Active App to Next Dock Click**: If you find an app that isn't minimizing properly (often due to a mismatch between its Dock title and process name), make the app active, click this option in the menu bar, and then click its Dock icon. The app will be mapped successfully.
   - **Clear All Mappings**: Resets any custom mappings you've created.

## How it Works

ClickDockToMinimize uses a `CGEvent.tapCreate` to read global mouse clicks. When a left-click occurs, the app checks if the cursor is within the bounds of the macOS Dock. 

If it is, the app uses the `AXUIElement` (Accessibility) APIs to determine exactly which application icon was clicked. It then cross-references this with `NSWorkspace.shared.runningApplications`. If the clicked application is the current frontmost application and has visible (non-minimized) windows, the app sends a command via Accessibility APIs to set the `kAXMinimizedAttribute` of those windows to `true`.

If you have a better idea on how to do this, feel free to contribute.

## License

This project is open-source.
