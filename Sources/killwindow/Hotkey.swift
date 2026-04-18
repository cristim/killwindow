import Carbon.HIToolbox
import Foundation

struct HotKeySpec: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32  // Carbon modifier mask (cmdKey | optionKey | ...)
}

let defaultHotkey = HotKeySpec(
    keyCode: UInt32(kVK_ANSI_K),
    modifiers: UInt32(cmdKey | optionKey | controlKey)
)

// Lower-case key-name → Carbon virtual keycode.
let hotkeyKeyMap: [String: Int] = {
    var m: [String: Int] = [
        "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return,
        "tab": kVK_Tab, "delete": kVK_Delete, "backspace": kVK_Delete,
        "escape": kVK_Escape, "esc": kVK_Escape,
        "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "up": kVK_UpArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End,
        "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
    ]
    let letters: [(String, Int)] = [
        ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
        ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
        ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
        ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
        ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
        ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
        ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
    ]
    let digits: [(String, Int)] = [
        ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
        ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
        ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
    ]
    let fkeys: [(String, Int)] = [
        ("f1", kVK_F1),   ("f2", kVK_F2),   ("f3", kVK_F3),   ("f4", kVK_F4),
        ("f5", kVK_F5),   ("f6", kVK_F6),   ("f7", kVK_F7),   ("f8", kVK_F8),
        ("f9", kVK_F9),   ("f10", kVK_F10), ("f11", kVK_F11), ("f12", kVK_F12),
    ]
    for (k, v) in letters + digits + fkeys { m[k] = v }
    return m
}()

func parseHotkey(_ spec: String) -> HotKeySpec? {
    var mods = 0
    var key: String?
    for raw in spec.split(separator: "+") {
        let p = raw.trimmingCharacters(in: .whitespaces).lowercased()
        switch p {
        case "cmd", "command", "meta":  mods |= cmdKey
        case "opt", "option", "alt":    mods |= optionKey
        case "ctrl", "control":         mods |= controlKey
        case "shift":                   mods |= shiftKey
        default:                        key = p
        }
    }
    guard let k = key, let code = hotkeyKeyMap[k] else { return nil }
    return HotKeySpec(keyCode: UInt32(code), modifiers: UInt32(mods))
}

func formatHotkey(_ s: HotKeySpec) -> String {
    var parts: [String] = []
    if s.modifiers & UInt32(controlKey) != 0 { parts.append("ctrl") }
    if s.modifiers & UInt32(optionKey)  != 0 { parts.append("opt")  }
    if s.modifiers & UInt32(cmdKey)     != 0 { parts.append("cmd")  }
    if s.modifiers & UInt32(shiftKey)   != 0 { parts.append("shift")}
    let keyName = hotkeyKeyMap.first { $0.value == Int(s.keyCode) }?.key ?? "?"
    parts.append(keyName)
    return parts.joined(separator: "+")
}
