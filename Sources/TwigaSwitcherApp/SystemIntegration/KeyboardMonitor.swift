import AppKit
import Carbon
import CoreGraphics
import TwigaSwitcherCore
import TwigaSwitcherLexicon

private func twigaswitcherTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}

public protocol KeyboardMonitoring: AnyObject, Sendable {
    var isRunning: Bool { get }
    var startError: String? { get }
    var onDiagnostic: ((String) -> Void)? { get set }
    var onRuleSuggestion: ((CorrectionPair) -> Void)? { get set }
    var onInputSourcesChanged: (() -> Void)? { get set }
    var missingLayouts: [KeyboardLayout] { get }
    func start() -> Bool
    func stop()
    func setRule(_ disposition: UserCorrectionDisposition, for pair: CorrectionPair) throws
    func setHotkeys(_ hotkeys: HotkeyConfiguration)
    func setSoundEnabled(_ enabled: Bool)
    func reloadDictionaries() async
}

public final class KeyboardMonitor: KeyboardMonitoring, @unchecked Sendable {
    private var processor: FocusedInputProcessor<LexiconCatalog, UserRuleStore>
    private let lexiconService: LexiconService
    private let ruleStore: UserRuleStore
    private let correctionCoordinator: LastCorrectionCoordinator
    private let normalizer = KeyboardEventNormalizer(syntheticMarker: EventPoster.syntheticMarker)
    private let focusProvider: any FocusSnapshotProviding
    private let executor: ReplacementExecutor
    private let inputSources: InputSourceManager
    private var inputSourceObservers: [NSObjectProtocol] = []
    private var healthTimer: Timer?
    public var missingLayouts: [KeyboardLayout] { inputSources.missingLayouts }
    public var onInputSourcesChanged: (() -> Void)?
    private let sound: any LayoutSwitchSoundPlaying
    private var hotkeys: HotkeyConfiguration
    private var soundEnabled: Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    public private(set) var isRunning = false
    public private(set) var startError: String?
    public var onDiagnostic: ((String) -> Void)?
    public var onRuleSuggestion: ((CorrectionPair) -> Void)?

    public init(
        lexiconService: LexiconService = LexiconService(),
        ruleStore: UserRuleStore? = nil,
        focusProvider: any FocusSnapshotProviding = FocusSafetyGuard(),
        executor: ReplacementExecutor? = nil,
        inputSources: InputSourceManager = InputSourceManager(),
        hotkeys: HotkeyConfiguration = HotkeyStore().configuration,
        sound: any LayoutSwitchSoundPlaying = SystemLayoutSwitchSound(),
        soundEnabled: Bool = UserDefaults.standard.object(forKey: "layoutSwitchSoundEnabled") as? Bool ?? true
    ) {
        let resolvedRuleStore = ruleStore ?? .sharedDefault
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
        self.inputSources = inputSources
        self.executor = executor ?? ReplacementExecutor(eventPoster: EventPoster(), inputSources: inputSources)
        self.hotkeys = hotkeys
        self.sound = sound
        self.soundEnabled = soundEnabled
    }

    public func start() -> Bool {
        guard tap == nil else { return true }
        refreshInputSources()
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
        let mask = [CGEventType.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: twigaswitcherTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap; source = newSource; isRunning = true
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.correctionCoordinator.invalidate()
            self?.processor.reset()
        }
        for name in [kTISNotifySelectedKeyboardInputSourceChanged!, kTISNotifyEnabledKeyboardInputSourcesChanged!] {
            inputSourceObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name as String), object: nil, queue: .main
            ) { [weak self] _ in self?.refreshInputSources() })
        }
        // Secure Input, sleep, or a busy target app can disable a tap without a
        // subsequent physical event. Recovery must not depend on manual switching.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
        return true
    }

    func checkHealth() {
        // A healthy event tap does not imply a healthy cached input source.
        synchronizeInputSources(retryUnavailable: true)
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            resetBuffer()
            correctionCoordinator.invalidate()
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func refreshInputSources() {
        if inputSources.refresh() {
            applyInputSourceChange()
        }
        onInputSourcesChanged?()
    }

    private func synchronizeInputSources(retryUnavailable: Bool = false) {
        if inputSources.refreshIfNeeded(retryUnavailable: retryUnavailable) {
            applyInputSourceChange()
            onInputSourcesChanged?()
        }
    }

    private func applyInputSourceChange() {
        correctionCoordinator.invalidate()
        if let tables = inputSources.tables { processor.updateConverter(tables.converter) }
        else { processor.reset() }
    }

    public func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        for observer in inputSourceObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        inputSourceObservers.removeAll()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        source = nil; tap = nil; activationObserver = nil; isRunning = false; resetBuffer()
    }

    public func resetBuffer() {
        processor.reset()
    }

    public func setHotkeys(_ hotkeys: HotkeyConfiguration) {
        self.hotkeys = hotkeys
    }

    public func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetBuffer()
            correctionCoordinator.invalidate()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            correctionCoordinator.invalidate()
            processor.reset()
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let marker = event.getIntegerValueField(.eventSourceUserData)
        guard marker != EventPoster.syntheticMarker else { return Unmanaged.passUnretained(event) }
        let isPhysical = event.getIntegerValueField(.eventSourceUnixProcessID) == 0
        if isRunning { synchronizeInputSources() }
        if isRunning && (!missingLayouts.isEmpty || inputSources.currentLayout == nil) {
            processor.reset()
            return Unmanaged.passUnretained(event)
        }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if let action = hotkeys.action(keyCode: keyCode, flags: event.flags),
           NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            return handleHotkey(action, event: event)
        }
        var length = 0; var units = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        let text = String(utf16CodeUnits: units, count: min(length, units.count))
        // Events posted by other applications may intentionally carry Unicode
        // unrelated to their virtual keycode (often zero). Do not reinterpret it.
        let physicalLayout = isPhysical ? inputSources.currentLayout : nil
        let raw = RawKeyEvent(text: text, keyCode: keyCode, flags: event.flags, marker: marker)
        let input = normalizer.normalize(raw, tables: inputSources.tables, currentLayout: physicalLayout)
        let needsFocus = processor.needsFocusSnapshot(for: input)
        let focus = needsFocus ? focusProvider.snapshot() : nil
        correctionCoordinator.invalidate()
        switch processor.handle(input, focus: focus) {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case let .replace(plan):
            let pair = processor.latestDecisionPair
            let result = executor.execute(plan)
            switch result {
            case .completed:
                if soundEnabled { sound.play() }
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
                processor.reset()
                correctionCoordinator.invalidate()
                onDiagnostic?("Matching input source is unavailable")
                return nil
            case .failedBeforeMutation:
                processor.reset()
                correctionCoordinator.invalidate()
                onDiagnostic?("Unable to post replacement events")
                return Unmanaged.passUnretained(event)
            case .partialFailure:
                processor.reset()
                correctionCoordinator.invalidate()
                onDiagnostic?("Replacement was interrupted")
                return nil
            }
        }
    }

    private func handleHotkey(_ action: HotkeyAction, event: CGEvent) -> Unmanaged<CGEvent>? {
        let focus = focusProvider.snapshot()
        switch action {
        case .undoCorrection:
            guard let focus,
                  let undo = correctionCoordinator.handleCommandZ(currentFocus: focus.identity) else {
                return Unmanaged.passUnretained(event)
            }
            let result = executor.reverse(undo.reversalPlan)
            correctionCoordinator.complete(undo, result: result)
            switch result {
            case .completed:
                processor.reset()
                if soundEnabled { sound.play() }
                return nil
            case .failedBeforeMutation:
                return Unmanaged.passUnretained(event)
            case .textReplacedLayoutUnavailable, .partialFailure:
                processor.reset()
                onDiagnostic?("Undo replacement was interrupted")
                return nil
            }

        case .forceCorrection:
            guard let focus else { return Unmanaged.passUnretained(event) }
            guard case let .replace(plan) = processor.forceCorrection(focus: focus) else {
                return Unmanaged.passUnretained(event)
            }
            let pair = processor.latestDecisionPair
            let result = executor.execute(plan)
            switch result {
            case .completed:
                if let pair { onRuleSuggestion?(pair) }
                if soundEnabled { sound.play() }
                if let pair {
                    correctionCoordinator.record(.init(
                        source: pair.source,
                        candidate: pair.candidate,
                        delimiter: plan.delimiter,
                        focus: focus.identity,
                        originalLayout: plan.targetLayout == .english ? .russian : .english
                    ))
                }
                return nil
            case .failedBeforeMutation:
                processor.reset()
                onDiagnostic?("Unable to post replacement events")
                return Unmanaged.passUnretained(event)
            case .textReplacedLayoutUnavailable:
                processor.reset()
                onDiagnostic?("Matching input source is unavailable")
                return nil
            case .partialFailure:
                processor.reset()
                onDiagnostic?("Replacement was interrupted")
                return nil
            }
        }
    }

    deinit { stop() }

    public func setRule(_ disposition: UserCorrectionDisposition, for pair: CorrectionPair) throws {
        try ruleStore.set(disposition: disposition, source: pair.source, candidate: pair.candidate)
    }

    public func reloadDictionaries() async {
        await lexiconService.reloadPacks()
    }

}
