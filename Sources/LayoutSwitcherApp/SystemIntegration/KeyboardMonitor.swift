import AppKit
import CoreGraphics
import LayoutSwitcherCore
import LayoutSwitcherLexicon

private func layoutSwitcherTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}

public protocol KeyboardMonitoring: AnyObject {
    var isRunning: Bool { get }
    var startError: String? { get }
    var onStopped: ((String) -> Void)? { get set }
    var onDiagnostic: ((String) -> Void)? { get set }
    func start() -> Bool
    func stop()
}

public extension KeyboardMonitoring {
    var startError: String? { nil }
}

public final class KeyboardMonitor: KeyboardMonitoring, @unchecked Sendable {
    private var processor: FocusedInputProcessor<LexiconCatalog, NoUserCorrectionRules>
    private let lexiconService: LexiconService
    private let normalizer = KeyboardEventNormalizer(syntheticMarker: EventPoster.syntheticMarker)
    private let focusProvider: any FocusSnapshotProviding
    private let executor: ReplacementExecutor
    private var health = TapHealth(maximumReenableAttempts: 1)
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    public private(set) var isRunning = false
    public private(set) var startError: String?
    public var onStopped: ((String) -> Void)?
    public var onDiagnostic: ((String) -> Void)?

    public init(
        lexiconService: LexiconService = LexiconService(),
        focusProvider: any FocusSnapshotProviding = FocusSafetyGuard(),
        executor: ReplacementExecutor = ReplacementExecutor(
            eventPoster: EventPoster(),
            inputSources: InputSourceManager()
        )
    ) {
        self.lexiconService = lexiconService
        self.processor = FocusedInputProcessor(pipeline: InputPipeline(
            converter: LayoutConverter(),
            detector: LanguageDetector(
                lexicon: lexiconService.catalog,
                rules: NoUserCorrectionRules()
            )
        ))
        self.focusProvider = focusProvider
        self.executor = executor
    }

    public func start() -> Bool {
        guard tap == nil else { return true }
        do {
            try lexiconService.start()
            startError = nil
        } catch {
            startError = lexiconService.fatalDiagnostic?.message ?? String(describing: error)
            return false
        }
        for diagnostic in lexiconService.diagnostics where !diagnostic.isFatal {
            onDiagnostic?(diagnostic.message)
        }
        health = TapHealth(maximumReenableAttempts: 1)
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

    public func resetBuffer() { processor.reset() }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetBuffer()
            if health.handleDisable() == .reenable, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            else { stop(); onStopped?("Event monitor stopped") }
            return Unmanaged.passUnretained(event)
        }
        health.recordHealthyEvent()
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown { resetBuffer(); return Unmanaged.passUnretained(event) }
        if type == .flagsChanged {
            if let modifierEvent = normalizer.normalizeModifierChange(flags: event.flags) {
                _ = processor.handle(modifierEvent, focus: nil)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        var length = 0; var units = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        let text = String(utf16CodeUnits: units, count: length)
        let raw = RawKeyEvent(text: text, keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags, marker: event.getIntegerValueField(.eventSourceUserData))
        let input = normalizer.normalize(raw)
        let focus = processor.needsFocusSnapshot(for: input) ? focusProvider.snapshot() : nil
        switch processor.handle(input, focus: focus) {
        case .passThrough: return Unmanaged.passUnretained(event)
        case let .replace(plan):
            let result = executor.execute(plan)
            switch result {
            case .completed:
                return nil
            case .textReplacedLayoutUnavailable:
                onDiagnostic?("Matching input source is unavailable")
                return nil
            case .failedBeforeMutation:
                onDiagnostic?("Unable to post replacement events")
                return Unmanaged.passUnretained(event)
            case .partialFailure:
                onDiagnostic?("Replacement was interrupted")
                return nil
            }
        }
    }

    deinit { stop() }
}
