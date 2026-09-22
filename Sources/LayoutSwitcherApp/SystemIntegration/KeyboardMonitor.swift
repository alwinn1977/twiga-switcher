import AppKit
import CoreGraphics
import LayoutSwitcherCore

private func layoutSwitcherTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}

public final class KeyboardMonitor: @unchecked Sendable {
    private var pipeline: InputPipeline<SystemLexicon>
    private let normalizer = KeyboardEventNormalizer(syntheticMarker: EventPoster.syntheticMarker)
    private let focusGuard: FocusSafetyGuard
    private let executor: ReplacementExecutor
    private var health = TapHealth(maximumReenableAttempts: 1)
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    public private(set) var isRunning = false
    public var onStopped: ((String) -> Void)?

    public init(lexicon: SystemLexicon = SystemLexicon(), focusGuard: FocusSafetyGuard = FocusSafetyGuard(), executor: ReplacementExecutor = ReplacementExecutor(eventPoster: EventPoster(), inputSources: InputSourceManager())) {
        self.pipeline = InputPipeline(converter: LayoutConverter(), detector: LanguageDetector(lexicon: lexicon, allowlist: ["docker", "swift", "xcode", "github", "json", "http", "ssh"]))
        self.focusGuard = focusGuard; self.executor = executor
    }

    public func start() -> Bool {
        guard tap == nil else { return true }
        let mask = [CGEventType.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: layoutSwitcherTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap; source = newSource; isRunning = true
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.resetBuffer() }
        return true
    }

    public func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        source = nil; tap = nil; activationObserver = nil; isRunning = false; resetBuffer()
    }

    public func resetBuffer() { pipeline.reset() }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if health.handleDisable() == .reenable, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            else { stop(); onStopped?("Event monitor stopped") }
            return Unmanaged.passUnretained(event)
        }
        health.recordHealthyEvent()
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown { resetBuffer(); return Unmanaged.passUnretained(event) }
        guard type == .keyDown else { resetBuffer(); return Unmanaged.passUnretained(event) }
        var length = 0; var units = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        let text = String(utf16CodeUnits: units, count: length)
        let raw = RawKeyEvent(text: text, keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags, marker: event.getIntegerValueField(.eventSourceUserData))
        let input = normalizer.normalize(raw)
        let safe: Bool = { if case .boundary = input { return focusGuard.isSafe() }; return true }()
        switch pipeline.handle(input, focusIsSafe: safe) {
        case .passThrough: return Unmanaged.passUnretained(event)
        case let .replace(plan): _ = executor.execute(plan); return nil
        }
    }

    deinit { stop() }
}
