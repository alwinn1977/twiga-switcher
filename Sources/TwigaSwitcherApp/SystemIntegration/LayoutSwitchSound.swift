import AppKit

public protocol LayoutSwitchSoundPlaying: AnyObject {
    func play()
}

public final class SystemLayoutSwitchSound: LayoutSwitchSoundPlaying {
    private let sound = NSSound(named: NSSound.Name("Tink"))

    public init() {}

    public func play() {
        if sound?.play() != true {
            NSSound.beep()
        }
    }
}
