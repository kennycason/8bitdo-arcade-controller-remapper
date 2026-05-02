import ApplicationServices
import Foundation
import GameController
import IOKit.hid

enum InputName: String, CaseIterable {
    case buttonA
    case buttonB
    case buttonX
    case buttonY
    case leftShoulder
    case rightShoulder
    case leftTrigger
    case rightTrigger
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case leftThumbstickButton
    case rightThumbstickButton
    case buttonMenu
    case buttonOptions
    case buttonHome
}

enum KeyName: String, CaseIterable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case zero, one, two, three, four, five, six, seven, eight, nine
    case space, returnKey, escape, tab, delete
    case upArrow, downArrow, leftArrow, rightArrow
    case leftShift, rightShift
    case period, comma, slash, semicolon, apostrophe
    case leftBracket, rightBracket, minus, equals, grave

    var keyCode: CGKeyCode {
        switch self {
        case .a: return 0
        case .s: return 1
        case .d: return 2
        case .f: return 3
        case .h: return 4
        case .g: return 5
        case .z: return 6
        case .x: return 7
        case .c: return 8
        case .v: return 9
        case .b: return 11
        case .q: return 12
        case .w: return 13
        case .e: return 14
        case .r: return 15
        case .y: return 16
        case .t: return 17
        case .one: return 18
        case .two: return 19
        case .three: return 20
        case .four: return 21
        case .five: return 23
        case .six: return 22
        case .seven: return 26
        case .eight: return 28
        case .nine: return 25
        case .zero: return 29
        case .o: return 31
        case .u: return 32
        case .leftBracket: return 33
        case .i: return 34
        case .p: return 35
        case .returnKey: return 36
        case .l: return 37
        case .j: return 38
        case .apostrophe: return 39
        case .k: return 40
        case .semicolon: return 41
        case .comma: return 43
        case .slash: return 44
        case .n: return 45
        case .m: return 46
        case .period: return 47
        case .tab: return 48
        case .space: return 49
        case .grave: return 50
        case .delete: return 51
        case .escape: return 53
        case .rightBracket: return 30
        case .minus: return 27
        case .equals: return 24
        case .leftShift: return 56
        case .rightShift: return 60
        case .leftArrow: return 123
        case .rightArrow: return 124
        case .downArrow: return 125
        case .upArrow: return 126
        }
    }

    var displayName: String {
        switch self {
        case .upArrow: return "Up Arrow"
        case .downArrow: return "Down Arrow"
        case .leftArrow: return "Left Arrow"
        case .rightArrow: return "Right Arrow"
        case .returnKey: return "Return"
        case .leftShift: return "Left Shift"
        case .rightShift: return "Right Shift"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .apostrophe: return "'"
        case .semicolon: return ";"
        case .grave: return "`"
        case .space: return "Space"
        case .escape: return "Escape"
        case .tab: return "Tab"
        case .delete: return "Delete"
        default: return rawValue
        }
    }

    static func from(keyCode: CGKeyCode) -> KeyName? {
        allCases.first { $0.keyCode == keyCode }
    }
}

struct MappingProfile: Decodable {
    let profile: String
    let bindings: [String: String]
}

final class KeyEmitter {
    private let eventSource: CGEventSource?

    init() {
        // Use hidSystemState so injected keys update the global key-state map
        // that polling-based apps (like emulators) read.
        eventSource = CGEventSource(stateID: .hidSystemState)
    }

    func emit(keyCode: CGKeyCode, isDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: isDown) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }
}

final class Remapper {
    private let emitter = KeyEmitter()
    private var bindings: [InputName: KeyName]
    private var lastPressedState: [InputName: Bool] = [:]
    private var lastPhysicalState: [String: Bool] = [:]
    private let debug: Bool
    private var pollTimer: DispatchSourceTimer?
    private var hidManager: IOHIDManager?
    private var hatDirectionTimers: [InputName: DispatchSourceTimer] = [:]
    var onButtonPress: ((InputName, Bool) -> Void)?

    init(bindings: [InputName: KeyName], debug: Bool) {
        self.bindings = bindings
        self.debug = debug
    }

    func start() {
        // Start HID FIRST with exclusive access so GameController framework
        // doesn't seize the device and swallow events.
        startHIDFallback()

        if hidManager != nil {
            // HID seized the device — it's the sole input source.
            // Do NOT start GC polling, as the GC framework won't see button
            // presses and will immediately cancel every HID-reported press.
            print("Listening for controller input (HID exclusive)...")
            if debug {
                print("Debug mode enabled. HID exclusive — GC polling disabled.")
            }
            return
        }

        // HID seizure failed — fall back to GameController framework.
        if #available(macOS 11.3, *) {
            GCController.shouldMonitorBackgroundEvents = true
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )

        GCController.startWirelessControllerDiscovery {}

        for controller in GCController.controllers() {
            configure(controller: controller)
        }

        startPollingFallback()
        print("Listening for controller input (GC polling)...")
        if debug {
            print("Debug mode enabled. GC polling + value change active.")
        }
    }

    @objc private func controllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        print("Connected: \(controller.vendorName ?? "Unknown controller")")
        configure(controller: controller)
    }

    @objc private func controllerDidDisconnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        print("Disconnected: \(controller.vendorName ?? "Unknown controller")")
        clearPressedKeys()
    }

    private func configure(controller: GCController) {
        guard let gamepad = controller.extendedGamepad else {
            print("Controller does not expose extended gamepad profile.")
            return
        }

        gamepad.valueChangedHandler = { [weak self] gamepad, element in
            self?.handleValueChange(gamepad: gamepad, element: element)
        }

        print("Configured: \(controller.vendorName ?? "Unknown controller")")
    }

    private func startPollingFallback() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            self?.pollControllers()
        }
        timer.resume()
        pollTimer = timer
    }

    private func startHIDFallback() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matches: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: 0x01,
                kIOHIDDeviceUsageKey as String: 0x04, // joystick
            ],
            [
                kIOHIDDeviceUsagePageKey as String: 0x01,
                kIOHIDDeviceUsageKey as String: 0x05, // gamepad
            ],
            [
                kIOHIDDeviceUsagePageKey as String: 0x01,
                kIOHIDDeviceUsageKey as String: 0x08, // multi-axis controller
            ],
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, hidInputValueCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        // Seize device so GameController framework can't claim exclusive access
        // and silently swallow HID events.
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if openResult == kIOReturnSuccess {
            hidManager = manager
            if debug {
                print("HID fallback initialized.")
                printConnectedHIDDevices()
            }
        } else {
            print("Warning: HID fallback could not be opened (code \(openResult)).")
        }
    }

    private func printConnectedHIDDevices() {
        guard let hidManager else { return }
        guard let devices = IOHIDManagerCopyDevices(hidManager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            print("HID devices: none")
            return
        }

        print("HID devices (\(devices.count)):")
        for device in devices {
            let product = hidStringProperty(device, key: kIOHIDProductKey as CFString) ?? "Unknown"
            let usagePage = hidIntProperty(device, key: kIOHIDPrimaryUsagePageKey as CFString) ?? -1
            let usage = hidIntProperty(device, key: kIOHIDPrimaryUsageKey as CFString) ?? -1
            let vendorId = hidIntProperty(device, key: kIOHIDVendorIDKey as CFString) ?? -1
            let productId = hidIntProperty(device, key: kIOHIDProductIDKey as CFString) ?? -1
            print("  - \(product) vendor=\(vendorId) product=\(productId) usagePage=0x\(String(usagePage, radix: 16)) usage=0x\(String(usage, radix: 16))")
        }
    }

    private func pollControllers() {
        for controller in GCController.controllers() {
            if let gamepad = controller.extendedGamepad {
                sample(gamepad: gamepad)
                continue
            }
            samplePhysical(controller: controller)
        }
    }

    private var gcDebugLogged = false
    private func sample(gamepad: GCExtendedGamepad) {
        // One-time debug dump to verify GC is actually reporting button states
        if debug && !gcDebugLogged {
            if gamepad.buttonA.isPressed || gamepad.buttonB.isPressed
                || gamepad.dpad.up.isPressed || gamepad.dpad.down.isPressed
            {
                print("[gc-poll] GC framework IS reporting button presses")
                gcDebugLogged = true
            }
        }
        handle(input: .buttonA, pressed: gamepad.buttonA.isPressed)
        handle(input: .buttonB, pressed: gamepad.buttonB.isPressed)
        handle(input: .buttonX, pressed: gamepad.buttonX.isPressed)
        handle(input: .buttonY, pressed: gamepad.buttonY.isPressed)
        handle(input: .leftShoulder, pressed: gamepad.leftShoulder.isPressed)
        handle(input: .rightShoulder, pressed: gamepad.rightShoulder.isPressed)
        handle(input: .leftTrigger, pressed: gamepad.leftTrigger.isPressed)
        handle(input: .rightTrigger, pressed: gamepad.rightTrigger.isPressed)
        handle(input: .dpadUp, pressed: gamepad.dpad.up.isPressed)
        handle(input: .dpadDown, pressed: gamepad.dpad.down.isPressed)
        handle(input: .dpadLeft, pressed: gamepad.dpad.left.isPressed)
        handle(input: .dpadRight, pressed: gamepad.dpad.right.isPressed)

        if #available(macOS 10.14.1, *) {
            handle(input: .leftThumbstickButton, pressed: gamepad.leftThumbstickButton?.isPressed ?? false)
            handle(input: .rightThumbstickButton, pressed: gamepad.rightThumbstickButton?.isPressed ?? false)
        }
        if #available(macOS 10.15, *) {
            handle(input: .buttonMenu, pressed: gamepad.buttonMenu.isPressed)
            handle(input: .buttonOptions, pressed: gamepad.buttonOptions?.isPressed ?? false)
        }
        if #available(macOS 11.0, *) {
            handle(input: .buttonHome, pressed: gamepad.buttonHome?.isPressed ?? false)
        }
    }

    private func samplePhysical(controller: GCController) {
        guard #available(macOS 11.0, *) else { return }
        let profile = controller.physicalInputProfile

        for (name, button) in profile.buttons {
            processPhysicalInput(controller: controller, elementName: name, pressed: button.isPressed)
        }

        for (name, dpad) in profile.dpads {
            processPhysicalInput(controller: controller, elementName: "\(name).up", pressed: dpad.up.isPressed)
            processPhysicalInput(controller: controller, elementName: "\(name).down", pressed: dpad.down.isPressed)
            processPhysicalInput(controller: controller, elementName: "\(name).left", pressed: dpad.left.isPressed)
            processPhysicalInput(controller: controller, elementName: "\(name).right", pressed: dpad.right.isPressed)
        }
    }

    private func processPhysicalInput(controller: GCController, elementName: String, pressed: Bool) {
        let key = "\(ObjectIdentifier(controller).hashValue):\(elementName)"
        let previous = lastPhysicalState[key] ?? false
        if previous == pressed {
            return
        }
        lastPhysicalState[key] = pressed

        if let mapped = physicalNameToInput(elementName) {
            if debug {
                let action = pressed ? "down" : "up"
                print("[physical] \(elementName) -> \(mapped.rawValue) (\(action))")
            }
            handle(input: mapped, pressed: pressed)
            return
        }

        if debug && pressed {
            print("[physical-unmapped] \(elementName)")
        }
    }

    private func physicalNameToInput(_ rawName: String) -> InputName? {
        let name = rawName.lowercased()

        if name.contains("button a") || name.contains("buttona") || name.contains("south") {
            return .buttonA
        }
        if name.contains("button b") || name.contains("buttonb") || name.contains("east") {
            return .buttonB
        }
        if name.contains("button x") || name.contains("buttonx") || name.contains("west") {
            return .buttonX
        }
        if name.contains("button y") || name.contains("buttony") || name.contains("north") {
            return .buttonY
        }
        if name.contains("left shoulder") || name.contains("leftshoulder") || name.contains("l1") {
            return .leftShoulder
        }
        if name.contains("right shoulder") || name.contains("rightshoulder") || name.contains("r1") {
            return .rightShoulder
        }
        if name.contains("left trigger") || name.contains("lefttrigger") || name.contains("l2") {
            return .leftTrigger
        }
        if name.contains("right trigger") || name.contains("righttrigger") || name.contains("r2") {
            return .rightTrigger
        }
        if name.contains("dpad") && name.contains(".up") {
            return .dpadUp
        }
        if name.contains("dpad") && name.contains(".down") {
            return .dpadDown
        }
        if name.contains("dpad") && name.contains(".left") {
            return .dpadLeft
        }
        if name.contains("dpad") && name.contains(".right") {
            return .dpadRight
        }
        if name.contains("left thumb") || name.contains("leftstickbutton") || name.contains("left thumbstick button") {
            return .leftThumbstickButton
        }
        if name.contains("right thumb") || name.contains("rightstickbutton") || name.contains("right thumbstick button") {
            return .rightThumbstickButton
        }
        if name.contains("menu") || name.contains("start") {
            return .buttonMenu
        }
        if name.contains("options") || name.contains("select") || name.contains("back") {
            return .buttonOptions
        }
        if name.contains("home") || name.contains("guide") {
            return .buttonHome
        }

        return nil
    }

    private func handleValueChange(gamepad: GCExtendedGamepad, element: GCControllerElement) {
        route(element: element, expected: gamepad.buttonA, input: .buttonA)
        route(element: element, expected: gamepad.buttonB, input: .buttonB)
        route(element: element, expected: gamepad.buttonX, input: .buttonX)
        route(element: element, expected: gamepad.buttonY, input: .buttonY)
        route(element: element, expected: gamepad.leftShoulder, input: .leftShoulder)
        route(element: element, expected: gamepad.rightShoulder, input: .rightShoulder)
        route(element: element, expected: gamepad.leftTrigger, input: .leftTrigger)
        route(element: element, expected: gamepad.rightTrigger, input: .rightTrigger)
        route(element: element, expected: gamepad.dpad.up, input: .dpadUp)
        route(element: element, expected: gamepad.dpad.down, input: .dpadDown)
        route(element: element, expected: gamepad.dpad.left, input: .dpadLeft)
        route(element: element, expected: gamepad.dpad.right, input: .dpadRight)

        if #available(macOS 10.14.1, *) {
            if let leftThumb = gamepad.leftThumbstickButton {
                route(element: element, expected: leftThumb, input: .leftThumbstickButton)
            }
            if let rightThumb = gamepad.rightThumbstickButton {
                route(element: element, expected: rightThumb, input: .rightThumbstickButton)
            }
        }

        if #available(macOS 10.15, *) {
            route(element: element, expected: gamepad.buttonMenu, input: .buttonMenu)
            if let options = gamepad.buttonOptions {
                route(element: element, expected: options, input: .buttonOptions)
            }
        }

        if #available(macOS 11.0, *) {
            if let home = gamepad.buttonHome {
                route(element: element, expected: home, input: .buttonHome)
            }
        }
    }

    private func route(element: GCControllerElement, expected: GCControllerButtonInput, input: InputName) {
        guard element === expected else { return }
        handle(input: input, pressed: expected.isPressed)
    }

    fileprivate func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        if debug {
            print("[hid] page=0x\(String(usagePage, radix: 16)) usage=0x\(String(usage, radix: 16)) value=\(intValue)")
        }

        if usagePage == 0x09 {
            guard let input = hidButtonToInput(usage: usage) else { return }
            handle(input: input, pressed: intValue != 0)
            return
        }

        if usagePage == 0x01 {
            if usage == 0x39 {
                handleHatSwitch(intValue)
                return
            }

            switch usage {
            case 0x90:
                handle(input: .dpadUp, pressed: intValue != 0)
            case 0x91:
                handle(input: .dpadDown, pressed: intValue != 0)
            case 0x92:
                handle(input: .dpadRight, pressed: intValue != 0)
            case 0x93:
                handle(input: .dpadLeft, pressed: intValue != 0)
            default:
                break
            }
        }
    }

    private func hidButtonToInput(usage: UInt32) -> InputName? {
        switch usage {
        case 1: return .buttonB
        case 2: return .buttonA
        case 3: return .buttonY
        case 4: return .buttonX
        case 5: return .leftShoulder
        case 6: return .rightShoulder
        case 7: return .leftTrigger
        case 8: return .rightTrigger
        case 9: return .buttonOptions
        case 10: return .buttonMenu
        case 11: return .leftThumbstickButton
        case 12: return .rightThumbstickButton
        case 13: return .buttonHome
        default: return nil
        }
    }

    private func handleHatSwitch(_ value: Int) {
        let isNeutral = value >= 8 || value < 0
        let up = !isNeutral && (value == 0 || value == 1 || value == 7)
        let right = !isNeutral && (value == 1 || value == 2 || value == 3)
        let down = !isNeutral && (value == 3 || value == 4 || value == 5)
        let left = !isNeutral && (value == 5 || value == 6 || value == 7)

        // Debounce each direction's RELEASE independently.
        // Presses are instant; releases wait 8ms so hat transitions like
        // down(4) -> neutral(8) -> down+right(3) don't briefly drop "down".
        for (input, pressed) in [
            (InputName.dpadUp, up), (.dpadRight, right),
            (.dpadDown, down), (.dpadLeft, left),
        ] {
            if pressed {
                // Cancel any pending release and press immediately
                hatDirectionTimers[input]?.cancel()
                hatDirectionTimers[input] = nil
                handle(input: input, pressed: true)
            } else if lastPressedState[input] == true && hatDirectionTimers[input] == nil {
                // Direction was held but hat no longer reports it — debounce the release
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
                timer.schedule(deadline: .now() + .milliseconds(8))
                timer.setEventHandler { [weak self] in
                    self?.hatDirectionTimers[input] = nil
                    self?.handle(input: input, pressed: false)
                }
                timer.resume()
                hatDirectionTimers[input] = timer
            }
        }
    }

    private func handle(input: InputName, pressed: Bool) {
        let previous = lastPressedState[input] ?? false
        if previous == pressed {
            return
        }
        lastPressedState[input] = pressed

        // If configure mode callback is set, forward there instead of emitting keys
        if let onButtonPress {
            onButtonPress(input, pressed)
            return
        }

        guard let key = bindings[input] else { return }
        if debug {
            let action = pressed ? "down" : "up"
            print("[debug] \(input.rawValue) -> \(key.rawValue) (\(action))")
        }
        emitter.emit(keyCode: key.keyCode, isDown: pressed)
    }

    private func clearPressedKeys() {
        for (input, isPressed) in lastPressedState where isPressed {
            guard let key = bindings[input] else { continue }
            emitter.emit(keyCode: key.keyCode, isDown: false)
        }
        lastPressedState.removeAll()
    }
}

private func hidInputValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue?
) {
    guard result == kIOReturnSuccess else { return }
    guard let context, let value else { return }
    let remapper = Unmanaged<Remapper>.fromOpaque(context).takeUnretainedValue()
    remapper.handleHIDValue(value)
}

private func hidStringProperty(_ device: IOHIDDevice, key: CFString) -> String? {
    guard let value = IOHIDDeviceGetProperty(device, key) else { return nil }
    return value as? String
}

private func hidIntProperty(_ device: IOHIDDevice, key: CFString) -> Int? {
    guard let value = IOHIDDeviceGetProperty(device, key) else { return nil }
    if let number = value as? NSNumber {
        return number.intValue
    }
    return nil
}

// MARK: - Interactive Configure Mode

// Globals for atexit handler (C function pointers can't capture context)
nonisolated(unsafe) var configureOutputPath: String = ""
nonisolated(unsafe) var configureBindings: [String: String] = [:]

final class ConfigureSession: @unchecked Sendable {
    var waitingForKey = false
    var capturedInput: InputName?
    var capturedKeyCode: CGKeyCode?
    let controllerSemaphore = DispatchSemaphore(value: 0)
    let keyboardSemaphore = DispatchSemaphore(value: 0)
    var tap: CFMachPort?
    var bindings: [String: String] = [:]
}

private func configureKeyTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let session = Unmanaged<ConfigureSession>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = session.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    // Let Ctrl+C / Cmd+C through
    let flags = event.flags
    if flags.contains(.maskCommand) || flags.contains(.maskControl) {
        return Unmanaged.passUnretained(event)
    }

    // Ignore key repeat
    if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
        return nil
    }

    guard session.waitingForKey else { return nil }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    // For flagsChanged (modifier keys), only capture on press-down
    if type == .flagsChanged {
        // Check if this is a press (flag set) or release (flag cleared)
        let flags = event.flags
        let isPress = flags.contains(.maskShift) || flags.contains(.maskControl)
            || flags.contains(.maskAlternate) || flags.contains(.maskCommand)
        guard isPress else { return nil }
    }

    session.waitingForKey = false
    session.capturedKeyCode = keyCode
    session.keyboardSemaphore.signal()
    return nil
}

func runConfigure(outputPath: String, reset: Bool) {
    requestAccessibilityIfNeeded()
    guard isAccessibilityTrusted() else {
        print("Accessibility permission required for key capture. Please grant it and retry.")
        exit(1)
    }

    let session = ConfigureSession()

    // Load existing bindings from the file unless --reset is passed
    if !reset {
        let url = URL(fileURLWithPath: outputPath)
        if let data = try? Data(contentsOf: url),
           let profile = try? JSONDecoder().decode(MappingProfile.self, from: data)
        {
            session.bindings = profile.bindings
            configureBindings = session.bindings
            print("Loaded \(profile.bindings.count) existing binding(s) from \(outputPath)")
            print("New mappings will be merged on top. Use --reset to start fresh.")
        }
    }
    let sessionPtr = Unmanaged.passUnretained(session).toOpaque()

    // Reuse the exact same Remapper (HID seize + GC discovery) that works for normal mode.
    // Hook into button presses via the onButtonPress callback.
    let remapper = Remapper(bindings: defaultBindings(), debug: true)
    remapper.onButtonPress = { input, pressed in
        // Only fire on press-down
        guard pressed else { return }
        session.capturedInput = input
        session.controllerSemaphore.signal()
    }
    remapper.start()

    // Set up CGEvent tap to capture keyboard keys
    let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: configureKeyTapCallback,
        userInfo: sessionPtr
    ) else {
        print("Failed to create event tap. Ensure Accessibility is enabled.")
        exit(1)
    }

    session.tap = tap
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    signal(SIGINT) { _ in exit(0) }

    DispatchQueue.global().async {
        print("\nInteractive Mapping Configuration")
        print("For each button:")
        print("  1) Press a button on your CONTROLLER")
        print("  2) Then press the KEYBOARD key you want it to emit")
        print("Repeat for each button. Press Ctrl+C when done.")
        print("(If no response, disconnect and reconnect your controller.)\n")

        while true {
            print("Press a controller button... ", terminator: "")
            fflush(stdout)

            session.capturedInput = nil
            session.controllerSemaphore.wait()

            guard let input = session.capturedInput else { continue }
            print("detected \(input.rawValue)")

            print("  Now press the keyboard key for \(input.rawValue): ", terminator: "")
            fflush(stdout)

            Thread.sleep(forTimeInterval: 0.15)

            session.waitingForKey = true
            session.capturedKeyCode = nil
            session.keyboardSemaphore.wait()

            guard let keyCode = session.capturedKeyCode else {
                print("(cancelled)")
                continue
            }

            if let keyName = KeyName.from(keyCode: keyCode) {
                session.bindings[input.rawValue] = keyName.rawValue
                configureBindings = session.bindings
                print("\(keyName.displayName)")
                print("  Mapped: \(input.rawValue) -> \(keyName.rawValue)\n")
            } else {
                print("(unknown keyCode \(keyCode), try a different key)")
            }
        }
    }

    configureOutputPath = outputPath
    atexit {
        guard !configureBindings.isEmpty else {
            print("\nNo mappings configured.")
            return
        }

        let profile: [String: Any] = [
            "profile": "custom",
            "bindings": configureBindings,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: profile, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8)
        {
            let url = URL(fileURLWithPath: configureOutputPath)
            try? jsonString.write(to: url, atomically: true, encoding: .utf8)
            print("\nMapping saved to \(configureOutputPath) (\(configureBindings.count) bindings)")
        }
    }

    RunLoop.main.run()
}

func defaultBindings() -> [InputName: KeyName] {
    [
        .buttonA: .space,
        .buttonB: .z,
        .buttonX: .x,
        .buttonY: .a,
        .leftShoulder: .q,
        .rightShoulder: .w,
        .leftTrigger: .one,
        .rightTrigger: .two,
        .dpadUp: .upArrow,
        .dpadDown: .downArrow,
        .dpadLeft: .leftArrow,
        .dpadRight: .rightArrow,
        .leftThumbstickButton: .c,
        .rightThumbstickButton: .v,
        .buttonMenu: .returnKey,
        .buttonOptions: .escape,
        .buttonHome: .escape,
    ]
}

func loadBindings(from path: String?) -> [InputName: KeyName] {
    guard let path else {
        return defaultBindings()
    }

    let url = URL(fileURLWithPath: path)

    guard let data = try? Data(contentsOf: url) else {
        print("Could not read mapping at \(path). Falling back to defaults.")
        return defaultBindings()
    }

    guard let profile = try? JSONDecoder().decode(MappingProfile.self, from: data) else {
        print("Invalid mapping JSON. Falling back to defaults.")
        return defaultBindings()
    }

    var resolved = defaultBindings()
    for (inputRaw, keyRaw) in profile.bindings {
        guard let input = InputName(rawValue: inputRaw) else {
            print("Ignoring unknown input: \(inputRaw)")
            continue
        }
        guard let key = KeyName(rawValue: keyRaw) else {
            print("Ignoring unknown key name: \(keyRaw)")
            continue
        }
        resolved[input] = key
    }
    print("Loaded mapping profile: \(profile.profile)")
    return resolved
}

func requestAccessibilityIfNeeded() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
}

func isAccessibilityTrusted() -> Bool {
    AXIsProcessTrusted()
}

func printUsage() {
    print(
        """
        8bitdo-arcade-controller-remapper
        Usage:
          swift run -c release 8bitdo-arcade-controller-remapper [--mapping <path>] [--debug]
          swift run -c release 8bitdo-arcade-controller-remapper --configure [--mapping <output-path>]

        Options:
          --mapping <path>   Path to a JSON mapping file (default: built-in mapping)
          --debug            Print all HID events and key mappings
          --configure        Interactive mode: press keys to build a mapping file
                             Saves to --mapping path or ./mapping.json
                             Merges with existing file by default (PATCH)
          --reset            With --configure, start fresh instead of merging

        If --mapping is not provided, built-in defaults are used.
        """
    )
}

let args = CommandLine.arguments
var mappingPath: String?
var debug = false
var configure = false
var reset = false
var index = 1

while index < args.count {
    let arg = args[index]
    if arg == "--mapping", index + 1 < args.count {
        mappingPath = args[index + 1]
        index += 2
        continue
    }

    if arg == "--debug" {
        debug = true
        index += 1
        continue
    }

    if arg == "--configure" {
        configure = true
        index += 1
        continue
    }

    if arg == "--reset" {
        reset = true
        index += 1
        continue
    }

    if arg == "--help" || arg == "-h" {
        printUsage()
        exit(0)
    }

    print("Unknown argument: \(arg)")
    printUsage()
    exit(1)
}

if configure {
    let outputPath = mappingPath ?? "mapping.json"
    runConfigure(outputPath: outputPath, reset: reset)
    // runConfigure never returns (calls exit)
}

print("Requesting Accessibility permission for keyboard event injection...")
requestAccessibilityIfNeeded()
print("Accessibility trusted: \(isAccessibilityTrusted() ? "yes" : "no")")

let remapper = Remapper(bindings: loadBindings(from: mappingPath), debug: debug)
remapper.start()

RunLoop.main.run()
