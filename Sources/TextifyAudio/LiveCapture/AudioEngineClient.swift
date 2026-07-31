@preconcurrency import AVFoundation

public protocol AudioEngineClient: AnyObject, Sendable {
    func selectInput(_ input: LiveAudioInput) throws
    func start() throws
    func stop()
    func reset()
    func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws
    func removeTap()
}

protocol AudioInputChangeObserving: AnyObject, Sendable {
    func setInputChangeHandler(
        _ handler: (@Sendable () -> Void)?
    )
}
