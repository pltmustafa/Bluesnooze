//
//  AppDelegate.swift
//  Bluesnooze
//
//  Created by Oliver Peate on 07/04/2020.
//  Copyright © 2020 Oliver Peate. All rights reserved.
//

import Cocoa
import IOBluetooth
import LaunchAtLogin
import CoreWLAN

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var disableBluetoothOnPowerDownMenuItem: NSMenuItem!
    @IBOutlet weak var bluetoothActionOnScreenUnlockRestore: NSMenuItem!
    @IBOutlet weak var bluetoothActionOnScreenUnlockEnable: NSMenuItem!
    @IBOutlet weak var bluetoothActionOnScreenUnlockNothing: NSMenuItem!
    @IBOutlet weak var disableWifiOnPowerDownMenuItem: NSMenuItem!
    @IBOutlet weak var wifiActionOnScreenUnlockRestore: NSMenuItem!
    @IBOutlet weak var wifiActionOnScreenUnlockEnable: NSMenuItem!
    @IBOutlet weak var wifiActionOnScreenUnlockNothing: NSMenuItem!
    @IBOutlet weak var launchAtLoginMenuItem: NSMenuItem!
    @IBOutlet weak var hideIconMenuItem: NSMenuItem!

    private var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var prevBluetoothState: Int32 = IOBluetoothPreferenceGetControllerPowerState()
    private var prevWifiState: Bool = CWWiFiClient.shared().interface()?.powerOn() ?? true
    private var isPoweringDown = false

    private let powerQueue = DispatchQueue(label: "com.bluesnooze.powerQueue", qos: .userInitiated)
    private var stateTimer: DispatchSourceTimer?

    private var connectOnWakeSeparator: NSMenuItem?
    private var connectOnWakeToggleItem: NSMenuItem?
    private var connectWifiOnWakeSeparator: NSMenuItem?
    private var connectWifiOnWakeToggleItem: NSMenuItem?

    var connectWifiOnWake: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "connectWifiOnWake")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "connectWifiOnWake")
        }
    }

    var targetWifiSsid: String {
        get {
            return UserDefaults.standard.string(forKey: "targetWifiSsid") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "targetWifiSsid")
        }
    }

    var connectOnWake: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "connectOnWake")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "connectOnWake")
        }
    }

    var targetBluetoothMacAddress: String {
        get {
            return UserDefaults.standard.string(forKey: "targetBluetoothMacAddress") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "targetBluetoothMacAddress")
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        LaunchAtLogin.migrateIfNeeded() // Migrate to macOS 13 API (https://github.com/sindresorhus/LaunchAtLogin/releases/tag/v5.0.0)
        if !UserDefaults.standard.bool(forKey: "hideIcon") {
            initStatusItem()
        }
        setupNotificationHandlers()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.updatePowerStates()
        }
        timer.resume()
        self.stateTimer = timer

        if let bluetoothMenu = disableBluetoothOnPowerDownMenuItem.menu {
            let separator = NSMenuItem.separator()
            bluetoothMenu.addItem(separator)
            connectOnWakeSeparator = separator
            
            let toggleItem = NSMenuItem(title: "Connect on wake", action: nil, keyEquivalent: "")
            let subMenu = NSMenu(title: "Connect on wake")
            toggleItem.submenu = subMenu
            bluetoothMenu.addItem(toggleItem)
            connectOnWakeToggleItem = toggleItem
        }

        if let wifiMenu = disableWifiOnPowerDownMenuItem.menu {
            let separator = NSMenuItem.separator()
            wifiMenu.addItem(separator)
            connectWifiOnWakeSeparator = separator
            
            let toggleItem = NSMenuItem(title: "Connect on wake", action: nil, keyEquivalent: "")
            let subMenu = NSMenu(title: "Connect on wake")
            toggleItem.submenu = subMenu
            wifiMenu.addItem(toggleItem)
            connectWifiOnWakeToggleItem = toggleItem
        }
    }

    // Re-add the status bar icon when the app is launched a second time
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        initStatusItem()
        return true
    }

    // Settings

    var disableBluetoothOnPowerDown: Bool {
        get {
            if UserDefaults.standard.object(forKey: "disableBluetoothOnPowerDown") == nil {
                // the primary function of the program is enabled by default
                return true
            }
            return UserDefaults.standard.bool(forKey: "disableBluetoothOnPowerDown")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "disableBluetoothOnPowerDown")
        }
    }

    var bluetoothActionOnScreenUnlock: String {
        get {
            if let value = UserDefaults.standard.string(forKey: "bluetoothActionOnScreenUnlock") {
                return value
            }
            return "restore"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "bluetoothActionOnScreenUnlock")
        }
    }

    var disableWifiOnPowerDown: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "disableWifiOnPowerDown")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "disableWifiOnPowerDown")
        }
    }

    var wifiActionOnScreenUnlock: String {
        get {
            if let value = UserDefaults.standard.string(forKey: "wifiActionOnScreenUnlock") {
                return value
            }
            return "nothing"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "wifiActionOnScreenUnlock")
        }
    }

    // Click handlers

    @IBAction func handleMenuOpen(_ sender: NSMenu) {
        // Bluetooth
        disableBluetoothOnPowerDownMenuItem.state = boolToMenuState(v: disableBluetoothOnPowerDown)
        bluetoothActionOnScreenUnlockRestore.isEnabled = disableBluetoothOnPowerDown
        bluetoothActionOnScreenUnlockRestore.state = boolToMenuState(v: bluetoothActionOnScreenUnlock == "restore" ? (disableBluetoothOnPowerDown ? true : nil) : false)
        bluetoothActionOnScreenUnlockEnable.state = boolToMenuState(v: bluetoothActionOnScreenUnlock == "enable")
        bluetoothActionOnScreenUnlockNothing.state = boolToMenuState(v: bluetoothActionOnScreenUnlock == "nothing")

        // Update custom bluetooth items
        if let toggleItem = connectOnWakeToggleItem, let subMenu = toggleItem.submenu {
            subMenu.removeAllItems()
            
            // 1. "Disabled" item
            let disabledItem = NSMenuItem(title: "Disabled", action: #selector(disableConnectOnWake(_:)), keyEquivalent: "")
            disabledItem.state = boolToMenuState(v: !connectOnWake)
            subMenu.addItem(disabledItem)
            
            subMenu.addItem(NSMenuItem.separator())
            
            // 2. Paired devices
            var foundActive = false
            if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
                for device in devices {
                    let name = device.name ?? "Unknown Device"
                    let address = device.addressString ?? ""
                    guard !address.isEmpty else { continue }
                    
                    let item = NSMenuItem(title: name, action: #selector(pairedDeviceSelected(_:)), keyEquivalent: "")
                    item.representedObject = address
                    
                    let isSelected = connectOnWake && (address == targetBluetoothMacAddress)
                    item.state = boolToMenuState(v: isSelected)
                    if isSelected {
                        foundActive = true
                    }
                    subMenu.addItem(item)
                }
            }
            
            subMenu.addItem(NSMenuItem.separator())
            
            // 3. Custom MAC Address item
            let customTitle = targetBluetoothMacAddress.isEmpty ? "Custom MAC Address..." : "Custom MAC Address... (\(targetBluetoothMacAddress))"
            let customItem = NSMenuItem(title: customTitle, action: #selector(setMacAddressClicked(_:)), keyEquivalent: "")
            customItem.state = boolToMenuState(v: connectOnWake && !foundActive && !targetBluetoothMacAddress.isEmpty)
            subMenu.addItem(customItem)
        }

        // Wi-Fi
        disableWifiOnPowerDownMenuItem.state = boolToMenuState(v: disableWifiOnPowerDown)
        wifiActionOnScreenUnlockRestore.isEnabled = disableWifiOnPowerDown
        wifiActionOnScreenUnlockRestore.state = boolToMenuState(v: wifiActionOnScreenUnlock == "restore" ? (disableWifiOnPowerDown ? true : nil) : false)
        wifiActionOnScreenUnlockEnable.state = boolToMenuState(v: wifiActionOnScreenUnlock == "enable")
        wifiActionOnScreenUnlockNothing.state = boolToMenuState(v: wifiActionOnScreenUnlock == "nothing")

        // Update custom wifi items
        if let toggleItem = connectWifiOnWakeToggleItem, let subMenu = toggleItem.submenu {
            subMenu.removeAllItems()
            
            // 1. "Disabled" item
            let disabledItem = NSMenuItem(title: "Disabled", action: #selector(disableConnectWifiOnWake(_:)), keyEquivalent: "")
            disabledItem.state = boolToMenuState(v: !connectWifiOnWake)
            subMenu.addItem(disabledItem)
            
            subMenu.addItem(NSMenuItem.separator())
            
            // 2. Configured network profiles
            var foundActive = false
            if let interface = CWWiFiClient.shared().interface(),
               let configuration = interface.configuration() {
                let profiles = configuration.networkProfiles
                for profile in profiles {
                    if let p = profile as? CWNetworkProfile, let ssid = p.ssid, !ssid.isEmpty {
                        let item = NSMenuItem(title: ssid, action: #selector(wifiNetworkSelected(_:)), keyEquivalent: "")
                        item.representedObject = ssid
                        
                        let isSelected = connectWifiOnWake && (ssid == targetWifiSsid)
                        item.state = boolToMenuState(v: isSelected)
                        if isSelected {
                            foundActive = true
                        }
                        subMenu.addItem(item)
                    }
                }
            }
            
            subMenu.addItem(NSMenuItem.separator())
            
            // 3. Custom SSID item
            let customTitle = targetWifiSsid.isEmpty ? "Custom SSID..." : "Custom SSID... (\(targetWifiSsid))"
            let customItem = NSMenuItem(title: customTitle, action: #selector(setWifiSsidClicked(_:)), keyEquivalent: "")
            customItem.state = boolToMenuState(v: connectWifiOnWake && !foundActive && !targetWifiSsid.isEmpty)
            subMenu.addItem(customItem)
        }

        // Launch at login
        launchAtLoginMenuItem.state = boolToMenuState(v: LaunchAtLogin.isEnabled)

        // Hide icon
        hideIconMenuItem.state = boolToMenuState(v: UserDefaults.standard.bool(forKey: "hideIcon"))

        // Show menu
        statusItem.popUpMenu(statusMenu)
    }

    @IBAction func disableBluetoothOnPowerDownClicked(_ sender: NSMenuItem) {
        disableBluetoothOnPowerDown = !disableBluetoothOnPowerDown
        if bluetoothActionOnScreenUnlock == "restore" {
            bluetoothActionOnScreenUnlock = "nothing"
        }
    }

    @IBAction func bluetoothActionOnScreenUnlockRestoreClicked(_ sender: NSMenuItem) {
        bluetoothActionOnScreenUnlock = "restore"
    }

    @IBAction func bluetoothActionOnScreenUnlockEnableClicked(_ sender: NSMenuItem) {
        bluetoothActionOnScreenUnlock = "enable"
    }

    @IBAction func bluetoothActionOnScreenUnlockNothingClicked(_ sender: NSMenuItem) {
        bluetoothActionOnScreenUnlock = "nothing"
    }

    @IBAction func disableWifiOnPowerDownClicked(_ sender: NSMenuItem) {
        disableWifiOnPowerDown = !disableWifiOnPowerDown
        if wifiActionOnScreenUnlock == "restore" {
            wifiActionOnScreenUnlock = "nothing"
        }
    }

    @IBAction func wifiActionOnScreenUnlockRestoreClicked(_ sender: NSMenuItem) {
        wifiActionOnScreenUnlock = "restore"
    }

    @IBAction func wifiActionOnScreenUnlockEnableClicked(_ sender: NSMenuItem) {
        wifiActionOnScreenUnlock = "enable"
    }

    @IBAction func wifiActionOnScreenUnlockNothingClicked(_ sender: NSMenuItem) {
        wifiActionOnScreenUnlock = "nothing"
    }

    @IBAction func launchAtLoginClicked(_ sender: NSMenuItem) {
        LaunchAtLogin.isEnabled = !LaunchAtLogin.isEnabled
    }

    @IBAction func hideIconClicked(_ sender: NSMenuItem) {
        if UserDefaults.standard.bool(forKey: "hideIcon") {
            UserDefaults.standard.removeObject(forKey: "hideIcon")
            hideIconMenuItem.state = NSControl.StateValue.off
        } else {
            // Show a tip on how to get the icon back
            let alert = NSAlert()
            alert.messageText = "Important information"
            alert.informativeText = "Launch the app a second time to show the icon again."
            alert.alertStyle = NSAlert.Style.informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == NSApplication.ModalResponse.alertSecondButtonReturn {
                return
            }
            // Hide the icon
            UserDefaults.standard.set(true, forKey: "hideIcon")
            hideIconMenuItem.state = NSControl.StateValue.on
            statusItem.statusBar?.removeStatusItem(statusItem)
        }
    }

    @IBAction func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }

    private func updatePowerStates() {
        guard !isPoweringDown else { return }
        prevBluetoothState = IOBluetoothPreferenceGetControllerPowerState()
        if let interface = CWWiFiClient.shared().interface() {
            prevWifiState = interface.powerOn()
        }
    }

    // Notification handlers

    func setupNotificationHandlers() {
        [
            NSWorkspace.willSleepNotification: #selector(onPowerDown(note:)),
            NSWorkspace.willPowerOffNotification: #selector(onPowerDown(note:))
        ].forEach { notification, sel in
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: sel, name: notification, object: nil)
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { notification in
            self.onScreenUnlock(note: notification)
        }
    }

    @objc func onPowerDown(note: NSNotification) {
        isPoweringDown = true
        if disableBluetoothOnPowerDown {
            setBluetooth(powerOn: false)
        }
        if disableWifiOnPowerDown {
            setWifi(powerOn: false)
        }
    }

    @objc func onScreenUnlock(note: Notification) {
        isPoweringDown = false
        if bluetoothActionOnScreenUnlock == "enable" || (bluetoothActionOnScreenUnlock == "restore" && prevBluetoothState != 0) {
            setBluetooth(powerOn: true)
            if connectOnWake {
                connectToSpecificDevice()
            }
        }
        if wifiActionOnScreenUnlock == "enable" || (wifiActionOnScreenUnlock == "restore" && prevWifiState) {
            setWifi(powerOn: true)
            if connectWifiOnWake {
                connectToSpecificWifi()
            }
        }
    }

    private func setBluetooth(powerOn: Bool) {
        powerQueue.async {
            IOBluetoothPreferenceSetControllerPowerState(powerOn ? 1 : 0)
        }
    }

    private func setWifi(powerOn: Bool) {
        powerQueue.async {
            guard let interface = CWWiFiClient.shared().interface() else {
                print("[Bluesnooze] Failed to get Wi-Fi interface to set power.")
                return
            }
            do {
                try interface.setPower(powerOn)
                print("[Bluesnooze] Wi-Fi power set to \(powerOn)")
            } catch {
                print("[Bluesnooze] Failed to set Wi-Fi power to \(powerOn): \(error.localizedDescription)")
            }
        }
    }

    @objc func wifiNetworkSelected(_ sender: NSMenuItem) {
        if let ssid = sender.representedObject as? String {
            targetWifiSsid = ssid
            connectWifiOnWake = true
        }
    }

    @objc func disableConnectWifiOnWake(_ sender: NSMenuItem) {
        connectWifiOnWake = false
    }

    @objc func setWifiSsidClicked(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Wi-Fi Network SSID"
        alert.informativeText = "Enter the SSID of the Wi-Fi network you want to connect to on wake:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        inputTextField.placeholderString = "Network Name"
        inputTextField.stringValue = targetWifiSsid
        alert.accessoryView = inputTextField
        
        alert.window.initialFirstResponder = inputTextField
        
        if alert.runModal() == .alertFirstButtonReturn {
            let ssid = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            targetWifiSsid = ssid
            if !ssid.isEmpty {
                connectWifiOnWake = true
            }
        }
    }

    private func connectToSpecificWifi() {
        let ssid = targetWifiSsid
        guard !ssid.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard self?.isPoweringDown == false else { return }
            
            guard let interface = CWWiFiClient.shared().interface() else {
                print("[Bluesnooze] No Wi-Fi interface found.")
                return
            }
            
            if interface.ssid() == ssid {
                print("[Bluesnooze] Wi-Fi network \(ssid) is already connected.")
                return
            }
            
            print("[Bluesnooze] Scanning for Wi-Fi SSID: \(ssid)...")
            do {
                let networks = try interface.scanForNetworks(withName: ssid)
                guard let network = networks.first(where: { $0.ssid == ssid }) else {
                    print("[Bluesnooze] Wi-Fi network \(ssid) not found in scan.")
                    return
                }
                
                print("[Bluesnooze] Attempting to connect to Wi-Fi SSID: \(ssid)...")
                try interface.associate(to: network, password: nil)
                print("[Bluesnooze] Successfully initiated association to \(ssid)")
            } catch {
                print("[Bluesnooze] Failed to connect to Wi-Fi \(ssid), error: \(error.localizedDescription)")
            }
        }
    }

    @objc func pairedDeviceSelected(_ sender: NSMenuItem) {
        if let mac = sender.representedObject as? String {
            targetBluetoothMacAddress = mac
            connectOnWake = true
        }
    }

    @objc func disableConnectOnWake(_ sender: NSMenuItem) {
        connectOnWake = false
    }

    @objc func setMacAddressClicked(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Bluetooth Device MAC Address"
        alert.informativeText = "Enter the MAC address of the Bluetooth device you want to connect to on wake (e.g. 00-11-22-33-44-55 or 00:11:22:33:44:55):"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        inputTextField.placeholderString = "XX:XX:XX:XX:XX:XX"
        inputTextField.stringValue = targetBluetoothMacAddress
        alert.accessoryView = inputTextField
        
        alert.window.initialFirstResponder = inputTextField
        
        if alert.runModal() == .alertFirstButtonReturn {
            let mac = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            targetBluetoothMacAddress = mac
            if !mac.isEmpty {
                connectOnWake = true
            }
        }
    }

    private func connectToSpecificDevice() {
        let macAddress = targetBluetoothMacAddress
        guard !macAddress.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard self?.isPoweringDown == false else { return }
            
            guard let device = IOBluetoothDevice(addressString: macAddress) else {
                print("[Bluesnooze] Failed to initialize IOBluetoothDevice with address: \(macAddress)")
                return
            }
            
            if device.isConnected() {
                print("[Bluesnooze] Device \(macAddress) is already connected.")
                return
            }
            
            print("[Bluesnooze] Attempting to connect to \(macAddress)...")
            let result = device.openConnection()
            if result == kIOReturnSuccess {
                print("[Bluesnooze] Successfully connected to \(macAddress)")
            } else {
                print("[Bluesnooze] Failed to connect to \(macAddress), error code: \(result)")
            }
        }
    }

    // UI state

    private func initStatusItem() {
        if let icon = NSImage(named: "bluesnooze") {
            icon.isTemplate = true
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "Bluesnooze"
        }
        statusItem.button?.action = #selector(handleMenuOpen(_:))
    }

    private func boolToMenuState(v: Bool?) -> NSControl.StateValue {
        return v == true ? NSControl.StateValue.on :
               v == false ? NSControl.StateValue.off :
               NSControl.StateValue.mixed
    }
}
