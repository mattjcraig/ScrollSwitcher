//
//  AppDelegate.swift
//  ScrollSwitcher
//
//  Created by Shadowfacts on 8/31/21.
//

import Cocoa
import IOKit
import Combine
import OSLog

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "main")

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // things that need to be retained to keep them from disappearing
    private var prefPanesSupport: Bundle!
    private var item: NSStatusItem!
    private var manager: IOHIDManager!
    private var cancellables = Set<AnyCancellable>()
    
    // internal not private because they need to be accessible from global IOHIDManager callbacks
    var hidDevicesChangedSubject = PassthroughSubject<Void, Never>()
    var trackpadCount = 0
    var mouseCount = 0
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button!.target = self
        item.button!.action = #selector(menuItemClicked)
        updateIcon()
        
        // update the icon when system prefs changes
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(updateIcon), name: .swipeScrollDirectionDidChangeNotification, object: nil)
        
        // register for HID device addition/removal notifications
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0 /* kIOHIDManagerOptionNone */)
        
        var dict = IOServiceMatching(kIOHIDDeviceKey)! as! [String: Any]
        dict[kIOHIDDeviceUsagePageKey] = kHIDPage_GenericDesktop
        dict[kIOHIDDeviceUsageKey] = kHIDUsage_GD_Mouse
        IOHIDManagerSetDeviceMatching(manager, dict as CFDictionary)
        
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceAdded(context:result:sender:device:), nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemoved(context:result:sender:device:), nil)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        
        // handle HID device changes debounced, because IOKit sends a whole at initialization (and seemingly duplicates when devices are removed/connected)
        hidDevicesChangedSubject
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [unowned self] (_) in
                logger.info("HID devices changed, trackpads: \(self.trackpadCount, privacy: .public), mice: \(self.mouseCount, privacy: .public)")
                self.updateDirectionForAutoMode()
            }
            .store(in: &cancellables)
    }
    
    @objc private func updateIcon() {
        item.button!.image = Direction.current.image
    }
    
    @objc private func menuItemClicked() {
        if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
            item.menu = createMenu()
            item.button!.performClick(nil)
        } else {
            toggleScrollDirection()
        }
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let state = Direction.current == .natural ? "On" : "Off"
        let status = NSMenuItem(title: "Natural Scrolling: \(state)", action: nil, keyEquivalent: "")
        status.isEnabled = true
        status.attributedTitle = NSAttributedString(string: "Natural Scrolling: \(state)", attributes: [
            .foregroundColor: NSColor.white,
        ])
        menu.addItem(status)
        let verb = Direction.current == .natural ? "Disable" : "Enable"
        let toggleItem = NSMenuItem(title: "\(verb) Natural Scrolling", action: #selector(toggleScrollDirection), keyEquivalent: "")
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let autoItem = NSMenuItem(title: "Auto Switching Mode", action: nil, keyEquivalent: "")
        let autoMenu = NSMenu()
        for mode in Preferences.AutoMode.allCases {
            let modeItem = NSMenuItem(title: mode.displayName, action: #selector(modeChanged(_:)), keyEquivalent: "")
            modeItem.tag = mode.rawValue
            modeItem.toolTip = mode.displayDescription
            modeItem.state = Preferences.autoMode == mode ? .on : .off
            autoMenu.addItem(modeItem)
        }
        autoItem.submenu = autoMenu
        menu.addItem(autoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
    
    @objc private func toggleScrollDirection() {
        setDirection(.current == Direction.natural ? .normal : .natural)
    }
    
    @objc private func modeChanged(_ sender: NSMenuItem) {
        Preferences.autoMode = Preferences.AutoMode(rawValue: sender.tag) ?? .disabled
        updateDirectionForAutoMode()
    }
    
    private func setDirection(_ new: Direction) {
        logger.debug("Changing scroll direction to \(new == .normal ? "Normal" : "Natural", privacy: .public)")
        setSwipeScrollDirection(new == .natural)
    }
    
    private func updateDirectionForAutoMode() {
        switch Preferences.autoMode {
        case .disabled:
            return
            
        case .normalWhenMousePresent:
            setDirection(mouseCount > 0 ? .normal : .natural)
            
        case .naturalWhenTrackpadPresent:
            setDirection(trackpadCount > 0 ? .natural : .normal)
        }
    }

}

extension AppDelegate: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        // remove the menu so the next time the item is clicked, it performs the primary action
        item.menu = nil
    }
}

extension Notification.Name {
    static let swipeScrollDirectionDidChangeNotification = Notification.Name(rawValue: "SwipeScrollDirectionDidChangeNotification")
}

func hidDeviceAdded(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    // it is not clear to me why you can interpolate device here but not in the log message
    let deviceDesc = "\(device)"
    
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
    guard let name = name else {
        logger.warning("Could not get product name for \(deviceDesc, privacy: .public)")
        return
    }
    
    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? UInt32
    guard let usage = usage else {
        logger.warning("Could not get usage for \(deviceDesc, privacy: .public)")
        return
    }
    // we get this callback for non kHIDUsage_GD_Mouse devices even though we specify that in the matching dict
    // (specifically, something with kHIDUsage_GD_SystemControl), so filter ourselves
    guard usage == kHIDUsage_GD_Mouse else {
        logger.info("Unexpected usage 0x\(usage, format: .hex, privacy: .public) for device '\(name, privacy: .public)'")
        return
    }
    
    logger.debug("HID device '\(name, privacy: .public)' added")
    
    let delegate = NSApp.delegate as! AppDelegate

    if deviceNameIsProbablyTrackpad(name) {
        delegate.trackpadCount += 1
    } else {
        delegate.mouseCount += 1
    }

    delegate.hidDevicesChangedSubject.send()
}

func hidDeviceRemoved(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    let deviceDesc = "\(device)"
    
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
    guard let name = name else {
        logger.warning("Could not get product name for \(deviceDesc, privacy: .public)")
        return
    }
    
    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? UInt32
    guard let usage = usage else {
        logger.warning("Could not get usage for \(deviceDesc, privacy: .public)")
        return
    }
    guard usage == kHIDUsage_GD_Mouse else {
        logger.info("Unexpected usage 0x\(usage, format: .hex, privacy: .public) for device '\(name, privacy: .public)'")
        return
    }
    
    logger.debug("HID device '\(name, privacy: .public)' removed")
    
    let delegate = NSApp.delegate as! AppDelegate

    if deviceNameIsProbablyTrackpad(name) {
        delegate.trackpadCount -= 1
    } else {
        delegate.mouseCount -= 1
    }

    delegate.hidDevicesChangedSubject.send()
}

// dumb heuristics because USB HID doesn't differentiate between mice/trackpads
func deviceNameIsProbablyTrackpad(_ name: String) -> Bool {
    if name.lowercased().contains("trackpad") {
        return true
    }
    return false
}
