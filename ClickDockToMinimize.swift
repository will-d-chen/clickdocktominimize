import Cocoa
import ApplicationServices

class ClickDockToMinimize: NSObject {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var dockElement: AXUIElement?
    var dockPID: pid_t = 0

    override init() {
        super.init()
        setupDockAccess()
        setupEventTap()
    }

    func setupDockAccess() {
        // Get the Dock process
        let dockApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        if let dockApp = dockApps.first {
            dockPID = dockApp.processIdentifier
            dockElement = AXUIElementCreateApplication(dockPID)
            NSLog("ClickDockToMinimize: Found Dock process (PID: \(dockPID))")
        } else {
            NSLog("ClickDockToMinimize: ERROR - Could not find Dock process")
        }
    }

    func setupEventTap() {
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let mySelf = Unmanaged<ClickDockToMinimize>.fromOpaque(refcon!).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    NSLog("ClickDockToMinimize: Event tap disabled by system, re-enabling...")
                    if let tap = mySelf.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let shouldConsume = mySelf.handleMouseClick(event: event)

                // If we handled it (minimized), consume the event (return nil)
                // Otherwise, pass it through
                if shouldConsume {
                    return nil  // Event consumed - dock won't see it
                } else {
                    return Unmanaged.passUnretained(event)  // Pass through
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("ClickDockToMinimize: ERROR - Failed to create event tap")
            return
        }

        self.eventTap = eventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        NSLog("ClickDockToMinimize: Event tap created successfully")
    }

    func handleMouseClick(event: CGEvent) -> Bool {
        let location = event.location

        // Check if click is in dock area
        guard let dockBounds = getDockBounds() else { return false }

        if dockBounds.contains(location) {
            NSLog("ClickDockToMinimize: Click in dock at (\(Int(location.x)), \(Int(location.y)))")

            // Find which app was clicked and handle it synchronously
            return handleDockClick(at: location)
        }

        return false  // Not a dock click, pass through
    }

    func getDockBounds() -> CGRect? {
        guard let screen = NSScreen.main else { return nil }

        // Dock is typically at bottom, but can be on sides
        // For now, assume bottom dock (most common)
        let screenHeight = screen.frame.height
        let screenWidth = screen.frame.width
        let dockHeight: CGFloat = 100

        return CGRect(x: 0, y: screenHeight - dockHeight, width: screenWidth, height: dockHeight)
    }

    func handleDockClick(at point: CGPoint) -> Bool {
        guard let dockElement = dockElement else {
            NSLog("ClickDockToMinimize: No dock element")
            return false
        }

        // Get the dock list (contains all dock icons)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            NSLog("ClickDockToMinimize: Could not get dock children")
            return false
        }

        // Find the list element (should be first child)
        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)

            if let role = roleRef as? String, role == "AXList" {
                // Get list items (dock icons)
                var listItemsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &listItemsRef) == .success,
                      let listItems = listItemsRef as? [AXUIElement] else {
                    continue
                }

                // Find which icon was clicked based on position
                if let clickedApp = findClickedApp(in: listItems, at: point) {
                    return handleAppClick(clickedApp)
                }
                break
            }
        }

        return false  // Didn't find/handle the click
    }

    func findClickedApp(in items: [AXUIElement], at point: CGPoint) -> NSRunningApplication? {
        for item in items {
            // Get position and size of this dock icon
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?

            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionRef) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeRef) == .success else {
                continue
            }

            var position = CGPoint.zero
            var size = CGSize.zero

            if AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
               AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) {

                let bounds = CGRect(origin: position, size: size)

                if bounds.contains(point) {
                    // Found the clicked icon! Get its title (app name)
                    var titleRef: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef) == .success,
                          let title = titleRef as? String else {
                        continue
                    }

                    NSLog("ClickDockToMinimize: Clicked dock icon: '\(title)'")

                    // Find the running app - try multiple matching strategies
                    let runningApps = NSWorkspace.shared.runningApplications

                    // Strategy 1: Exact match on localizedName
                    for app in runningApps {
                        if app.localizedName == title {
                            NSLog("ClickDockToMinimize: Found app by exact name match: \(app.localizedName ?? "unknown")")
                            return app
                        }
                    }

                    // Strategy 2: Case-insensitive match
                    for app in runningApps {
                        if app.localizedName?.lowercased() == title.lowercased() {
                            NSLog("ClickDockToMinimize: Found app by case-insensitive match: \(app.localizedName ?? "unknown")")
                            return app
                        }
                    }

                    // Strategy 3: Contains match (for apps like "Zen Browser" vs "Zen")
                    for app in runningApps {
                        if let appName = app.localizedName {
                            if appName.lowercased().contains(title.lowercased()) || title.lowercased().contains(appName.lowercased()) {
                                NSLog("ClickDockToMinimize: Found app by contains match: \(appName) <-> \(title)")
                                return app
                            }
                        }
                    }

                    // Strategy 4: Bundle name match
                    if let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: title) {
                        for app in runningApps {
                            if app.bundleURL == bundleURL {
                                NSLog("ClickDockToMinimize: Found app by bundle match")
                                return app
                            }
                        }
                    }

                    NSLog("ClickDockToMinimize: WARNING - Could not find running app for dock icon: '\(title)'")
                }
            }
        }
        return nil
    }

    func handleAppClick(_ app: NSRunningApplication) -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication

        if frontmost?.processIdentifier == app.processIdentifier {
            // App is frontmost - but check if it has visible windows
            if hasVisibleWindows(app) {
                // Has visible windows - minimize them and CONSUME the event!
                NSLog("ClickDockToMinimize: App is frontmost with visible windows, minimizing \(app.localizedName ?? "unknown")")
                minimizeAllWindows(for: app)

                // Hide the app so it's no longer frontmost
                // This way the next click will activate it properly
                app.hide()

                return true  // We handled it - consume the event
            } else {
                // No visible windows (all minimized) - let dock restore them
                NSLog("ClickDockToMinimize: App is frontmost but no visible windows, passing through to restore")
                return false  // Let the dock restore windows
            }
        } else {
            // App is not frontmost - let the dock handle activation normally
            NSLog("ClickDockToMinimize: App not frontmost (\(app.localizedName ?? "unknown")), passing through")
            return false  // Let the dock handle it
        }
    }

    func hasVisibleWindows(_ app: NSRunningApplication) -> Bool {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }

        // Check if any window is not minimized
        for window in windows {
            var minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)

            if let isMinimized = minimized as? Bool, !isMinimized {
                return true  // Found at least one visible window
            }
        }

        return false  // All windows are minimized
    }

    func minimizeAllWindows(for app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            NSLog("ClickDockToMinimize: Could not get windows for \(app.localizedName ?? "unknown")")
            return
        }

        var minimizedCount = 0
        for window in windows {
            var minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)

            if let isMinimized = minimized as? Bool, !isMinimized {
                let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                if result == .success {
                    minimizedCount += 1
                }
            }
        }

        NSLog("ClickDockToMinimize: Minimized \(minimizedCount) window(s)")
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var minimizer: ClickDockToMinimize?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Click Dock To Minimize")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Active", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Click on any dock icon to minimize!", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu

        checkPermissions()
        minimizer = ClickDockToMinimize()
    }

    func checkPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let alert = NSAlert()
                alert.messageText = "Permissions Required"
                alert.informativeText = "ClickDockToMinimize needs Accessibility permissions. Please grant access in System Settings > Privacy & Security > Accessibility, then restart the app."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
