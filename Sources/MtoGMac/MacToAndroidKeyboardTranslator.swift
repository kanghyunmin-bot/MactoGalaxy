import ApplicationServices
import Foundation

enum MacToAndroidKeyboardTranslator {
    static let hangulToggleUsage = 0x90

    struct HidKey {
        let modifiers: Int
        let usage: Int
        let status: String?
    }

    struct AndroidKeyCombination {
        let keys: [String]
        let status: String?
    }

    static func hidKey(forMacKeyCode keyCode: Int, flags: CGEventFlags) -> HidKey? {
        if isHangulToggle(keyCode: keyCode, flags: flags) {
            return HidKey(
                modifiers: 0,
                usage: hangulToggleUsage,
                status: "한/영 전환을 Android 물리 키보드 LANG1로 전송"
            )
        }

        guard let usage = usageByMacKeyCode[keyCode] else { return nil }

        return HidKey(
            modifiers: hidModifiers(from: flags),
            usage: usage,
            status: shortcutStatus(keyCode: keyCode, flags: flags)
        )
    }

    static func adbCombination(forMacKeyCode keyCode: Int, flags: CGEventFlags) -> AndroidKeyCombination? {
        if isHangulToggle(keyCode: keyCode, flags: flags) {
            return AndroidKeyCombination(
                keys: ["KEYCODE_LANGUAGE_SWITCH"],
                status: "한/영 전환을 Android 언어 전환 키로 전송"
            )
        }

        guard isPrimaryShortcut(flags),
              let key = androidKeyCodeByMacKeyCode[keyCode] else {
            return nil
        }

        var keys = ["KEYCODE_CTRL_LEFT"]
        if flags.contains(.maskShift) {
            keys.append("KEYCODE_SHIFT_LEFT")
        }
        if flags.contains(.maskAlternate) {
            keys.append("KEYCODE_ALT_LEFT")
        }
        keys.append(key)

        return AndroidKeyCombination(
            keys: keys,
            status: shortcutStatus(keyCode: keyCode, flags: flags)
        )
    }

    static func specialAdbKey(forMacKeyCode keyCode: Int) -> String? {
        switch keyCode {
        case 51:
            return "DEL"
        case 117:
            return "FORWARD_DEL"
        case 36, 76:
            return "ENTER"
        case 48:
            return "TAB"
        case 49:
            return "SPACE"
        case 53:
            return "ESCAPE"
        case 123:
            return "DPAD_LEFT"
        case 124:
            return "DPAD_RIGHT"
        case 125:
            return "DPAD_DOWN"
        case 126:
            return "DPAD_UP"
        default:
            return nil
        }
    }

    static func androidKeyCodeName(forMacKeyCode keyCode: Int) -> String? {
        androidKeyCodeByMacKeyCode[keyCode]
    }

    private static func isHangulToggle(keyCode: Int, flags: CGEventFlags) -> Bool {
        keyCode == 54 && flags.contains(.maskCommand)
    }

    private static func isPrimaryShortcut(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand)
    }

    private static func hidModifiers(from flags: CGEventFlags) -> Int {
        var value = 0

        // Android/ChromeOS convention: Mac Command should behave like Android Ctrl.
        // Mac Control is intentionally not translated; it creates surprising shortcut collisions.
        if isPrimaryShortcut(flags) {
            value |= 0x01
        }
        if flags.contains(.maskShift) {
            value |= 0x02
        }
        if flags.contains(.maskAlternate) {
            value |= 0x04
        }

        return value
    }

    private static func shortcutStatus(keyCode: Int, flags: CGEventFlags) -> String? {
        guard flags.contains(.maskCommand),
              let name = androidKeyCodeByMacKeyCode[keyCode] else {
            return nil
        }

        switch name {
        case "KEYCODE_C":
            return "Mac Command+C를 Android Ctrl+C로 전송"
        case "KEYCODE_V":
            return "Mac Command+V를 Android Ctrl+V로 전송"
        case "KEYCODE_X":
            return "Mac Command+X를 Android Ctrl+X로 전송"
        case "KEYCODE_A":
            return "Mac Command+A를 Android Ctrl+A로 전송"
        case "KEYCODE_Z":
            return flags.contains(.maskShift)
                ? "Mac Command+Shift+Z를 Android Ctrl+Shift+Z로 전송"
                : "Mac Command+Z를 Android Ctrl+Z로 전송"
        case "KEYCODE_Y":
            return "Mac Command+Y를 Android Ctrl+Y로 전송"
        case "KEYCODE_F":
            return "Mac Command+F를 Android Ctrl+F로 전송"
        case "KEYCODE_S":
            return "Mac Command+S를 Android Ctrl+S로 전송"
        default:
            return nil
        }
    }

    private static let usageByMacKeyCode: [Int: Int] = [
        0: 0x04, 11: 0x05, 8: 0x06, 2: 0x07, 14: 0x08, 3: 0x09, 5: 0x0a,
        4: 0x0b, 34: 0x0c, 38: 0x0d, 40: 0x0e, 37: 0x0f, 46: 0x10, 45: 0x11,
        31: 0x12, 35: 0x13, 12: 0x14, 15: 0x15, 1: 0x16, 17: 0x17, 32: 0x18,
        9: 0x19, 13: 0x1a, 7: 0x1b, 16: 0x1c, 6: 0x1d,
        18: 0x1e, 19: 0x1f, 20: 0x20, 21: 0x21, 23: 0x22,
        22: 0x23, 26: 0x24, 28: 0x25, 25: 0x26, 29: 0x27,
        36: 0x28, 76: 0x28, 53: 0x29, 51: 0x2a, 117: 0x4c,
        48: 0x2b, 49: 0x2c, 27: 0x2d, 24: 0x2e, 33: 0x2f,
        30: 0x30, 42: 0x31, 41: 0x33, 39: 0x34, 43: 0x36,
        47: 0x37, 44: 0x38, 50: 0x35, 123: 0x50, 124: 0x4f,
        125: 0x51, 126: 0x52
    ]

    private static let androidKeyCodeByMacKeyCode: [Int: String] = [
        0: "KEYCODE_A", 11: "KEYCODE_B", 8: "KEYCODE_C", 2: "KEYCODE_D",
        14: "KEYCODE_E", 3: "KEYCODE_F", 5: "KEYCODE_G", 4: "KEYCODE_H",
        34: "KEYCODE_I", 38: "KEYCODE_J", 40: "KEYCODE_K", 37: "KEYCODE_L",
        46: "KEYCODE_M", 45: "KEYCODE_N", 31: "KEYCODE_O", 35: "KEYCODE_P",
        12: "KEYCODE_Q", 15: "KEYCODE_R", 1: "KEYCODE_S", 17: "KEYCODE_T",
        32: "KEYCODE_U", 9: "KEYCODE_V", 13: "KEYCODE_W", 7: "KEYCODE_X",
        16: "KEYCODE_Y", 6: "KEYCODE_Z",
        18: "KEYCODE_1", 19: "KEYCODE_2", 20: "KEYCODE_3", 21: "KEYCODE_4",
        23: "KEYCODE_5", 22: "KEYCODE_6", 26: "KEYCODE_7", 28: "KEYCODE_8",
        25: "KEYCODE_9", 29: "KEYCODE_0",
        27: "KEYCODE_MINUS", 24: "KEYCODE_EQUALS", 33: "KEYCODE_LEFT_BRACKET",
        30: "KEYCODE_RIGHT_BRACKET", 42: "KEYCODE_BACKSLASH", 41: "KEYCODE_SEMICOLON",
        39: "KEYCODE_APOSTROPHE", 43: "KEYCODE_COMMA", 47: "KEYCODE_PERIOD",
        44: "KEYCODE_SLASH", 50: "KEYCODE_GRAVE", 49: "KEYCODE_SPACE"
    ]
}

enum AoaHidUsageMapper {
    static let hangulToggleUsage = MacToAndroidKeyboardTranslator.hangulToggleUsage

    static func usage(forMacKeyCode keyCode: Int) -> Int? {
        MacToAndroidKeyboardTranslator.hidKey(forMacKeyCode: keyCode, flags: [])?.usage
    }

    static func modifiers(from flags: CGEventFlags) -> Int {
        MacToAndroidKeyboardTranslator.hidKey(forMacKeyCode: 0, flags: flags)?.modifiers ?? 0
    }
}
