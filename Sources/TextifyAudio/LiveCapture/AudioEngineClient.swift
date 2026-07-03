@preconcurrency import AVFoundation

public protocol AudioEngineClient: AnyObject, Sendable {
    func start() throws
    func stop()
    func reset()
    func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws
    func removeTap()
}
