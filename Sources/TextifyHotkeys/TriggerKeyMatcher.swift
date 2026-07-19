public enum TriggerKeyMatcher {
    public static let rightCommandKeyCode: UInt16 = 54
    public static let leftCommandKeyCode: UInt16 = 55
    public static let rightOptionKeyCode: UInt16 = 61
    public static let leftOptionKeyCode: UInt16 = 58
    public static let rightControlKeyCode: UInt16 = 62
    public static let leftControlKeyCode: UInt16 = 59
    public static let spaceKeyCode: UInt16 = 49
    public static let escapeKeyCode: UInt16 = 53
    public static let commandFlagMask: UInt64 = 1 << 20
    public static let optionFlagMask: UInt64 = 1 << 19
    public static let controlFlagMask: UInt64 = 1 << 18
}
