import Foundation

struct AppConfig: Codable {
    var hotkey: String?
}

func configDir() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first!
    return base.appendingPathComponent("killwindow", isDirectory: true)
}

func configPath() -> URL {
    configDir().appendingPathComponent("config.json")
}

func loadConfig() -> AppConfig {
    guard let data = try? Data(contentsOf: configPath()) else { return AppConfig() }
    return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
}

func saveConfig(_ cfg: AppConfig) throws {
    try FileManager.default.createDirectory(
        at: configDir(), withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(cfg)
    try data.write(to: configPath(), options: .atomic)
}

func currentHotkey() -> HotKeySpec {
    loadConfig().hotkey.flatMap(parseHotkey) ?? defaultHotkey
}
