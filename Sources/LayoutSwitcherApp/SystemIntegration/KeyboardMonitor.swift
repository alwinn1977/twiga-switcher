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
    var onLatestDecision: ((CorrectionPair?) -> Void)? { get set }
    func start() -> Bool
    func stop()
    func setRule(_ disposition: UserCorrectionDisposition, for pair: CorrectionPair) throws
}

public extension KeyboardMonitoring {
    var startError: String? { nil }
    func setRule(_ disposition: UserCorrectionDisposition, for pair: CorrectionPair) throws {}
}

public final class KeyboardMonitor: KeyboardMonitoring, @unchecked Sendable {
    private var processor: FocusedInputProcessor<LexiconCatalog, UserRuleStore>
    private let lexiconService: LexiconService
    private let ruleStore: UserRuleStore
    private let correctionCoordinator: LastCorrectionCoordinator
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
    public var onLatestDecision: ((CorrectionPair?) -> Void)?

    public init(
        lexiconService: LexiconService = LexiconService(),
        ruleStore: UserRuleStore? = nil,
        focusProvider: any FocusSnapshotProviding = FocusSafetyGuard(),
        executor: ReplacementExecutor = ReplacementExecutor(
            eventPoster: EventPoster(),
            inputSources: InputSourceManager()
        )
    ) {
        let resolvedRuleStore = ruleStore ?? Self.makeDefaultRuleStore()
        self.lexiconService = lexiconService
        self.ruleStore = resolvedRuleStore
        self.correctionCoordinator = LastCorrectionCoordinator(ruleStore: resolvedRuleStore)
        self.processor = FocusedInputProcessor(pipeline: InputPipeline(
            converter: LayoutConverter(),
            detector: LanguageDetector(
                lexicon: lexiconService.catalog,
                rules: resolvedRuleStore
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
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.correctionCoordinator.invalidate()
            self?.resetBuffer()
        }
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
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            correctionCoordinator.invalidate()
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            if let modifierEvent = normalizer.normalizeModifierChange(flags: event.flags) {
                correctionCoordinator.invalidate()
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
        if input == .commandZ {
            guard let focus,
                  let action = correctionCoordinator.handleCommandZ(currentFocus: focus.identity) else {
                return Unmanaged.passUnretained(event)
            }
            let result = executor.reverse(action.reversalPlan)
            do {
                try correctionCoordinator.complete(action, result: result)
            } catch {
                onDiagnostic?("Unable to save learned rule")
            }
            switch result {
            case .completed:
                return nil
            case .failedBeforeMutation:
                return Unmanaged.passUnretained(event)
            case .textReplacedLayoutUnavailable, .partialFailure:
                onDiagnostic?("Undo replacement was interrupted")
                return nil
            }
        }
        if case .character = input {
            correctionCoordinator.invalidate()
            onLatestDecision?(nil)
        }
        switch processor.handle(input, focus: focus) {
        case .passThrough:
            if case .boundary = input { onLatestDecision?(processor.latestDecisionPair) }
            return Unmanaged.passUnretained(event)
        case let .replace(plan):
            let pair = processor.latestDecisionPair
            onLatestDecision?(pair)
            let result = executor.execute(plan)
            switch result {
            case .completed:
                if let pair, let focus {
                    correctionCoordinator.record(.init(
                        source: pair.source,
                        candidate: pair.candidate,
                        delimiter: plan.delimiter,
                        focus: focus.identity,
                        originalLayout: plan.targetLayout == .english ? .russian : .english
                    ))
                }
                return nil
            case .textReplacedLayoutUnavailable:
                onDiagnostic?("Matching input source is unavailable")
                return nil
            case .failedBeforeMutation:
                correctionCoordinator.invalidate()
                onDiagnostic?("Unable to post replacement events")
                return Unmanaged.passUnretained(event)
            case .partialFailure:
                correctionCoordinator.invalidate()
                onDiagnostic?("Replacement was interrupted")
                return nil
            }
        }
    }

    deinit { stop() }

    public func setRule(_ disposition: UserCorrectionDisposition, for pair: CorrectionPair) throws {
        try ruleStore.set(disposition: disposition, source: pair.source, candidate: pair.candidate)
    }

    private static func makeDefaultRuleStore() -> UserRuleStore {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let url = applicationSupport
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("rules.json")
        if let store = try? UserRuleStore(fileURL: url) { return store }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutSwitcher-rules-\(UUID().uuidString).json")
        guard let store = try? UserRuleStore(fileURL: fallback) else {
            preconditionFailure("Unable to create user rule store")
        }
        return store
    }
}
