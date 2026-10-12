import Foundation

// MARK: - UserSettings
//
// Persistable user preferences that survive app restarts.
// Stored as JSON in ~/Library/Application Support/Zephyr/settings.json (macOS)
// or %APPDATA%/Zephyr/settings.json (Windows).
//
// Settings already persisted elsewhere:
//   - UIFontLanguageProfile → UserDefaults ("Zephyr.UIFontLanguageProfile")
//   - Array associativity / type → UserDefaults
//   - ODA converter path → UserDefaults
// These are intentionally NOT duplicated here.

public struct UserSettings: Codable, Sendable {
    // MARK: - Theme
    public var isDarkTheme: Bool

    // MARK: - Panel Visibility
    public var layersPanelVisible: Bool
    public var drawPaletteVisible: Bool
    public var blockPanelVisible: Bool
    public var dataTablePanelVisible: Bool
    public var showPropertiesPanel: Bool

    // MARK: - Misc UI
    public var showFPS: Bool
    public var toolbarVisible: Bool
    public var radialNavVisible: Bool

    // MARK: - First-run setup
    /// Whether the welcome/setup popup was completed. Pre-flag settings
    /// files decode this as false, so upgrading users see the popup once.
    public var hasCompletedSetup: Bool

    // MARK: - Initialization

    /// Memberwise initializer (explicit: the custom Decodable init
    /// below suppresses the synthesized one).
    public init(
        isDarkTheme: Bool,
        layersPanelVisible: Bool,
        drawPaletteVisible: Bool,
        blockPanelVisible: Bool,
        dataTablePanelVisible: Bool,
        showPropertiesPanel: Bool,
        showFPS: Bool,
        toolbarVisible: Bool,
        radialNavVisible: Bool,
        hasCompletedSetup: Bool
    ) {
        self.isDarkTheme = isDarkTheme
        self.layersPanelVisible = layersPanelVisible
        self.drawPaletteVisible = drawPaletteVisible
        self.blockPanelVisible = blockPanelVisible
        self.dataTablePanelVisible = dataTablePanelVisible
        self.showPropertiesPanel = showPropertiesPanel
        self.showFPS = showFPS
        self.toolbarVisible = toolbarVisible
        self.radialNavVisible = radialNavVisible
        self.hasCompletedSetup = hasCompletedSetup
    }

    // MARK: - Default instance
    public static let `default` = UserSettings(
        isDarkTheme: true,
        layersPanelVisible: false,
        drawPaletteVisible: false,
        blockPanelVisible: false,
        dataTablePanelVisible: false,
        showPropertiesPanel: false,
        showFPS: false,
        toolbarVisible: true,
        radialNavVisible: false,
        hasCompletedSetup: false
    )

    /// Decodes leniently so settings files written before a field
    /// existed still load (missing keys fall back to defaults rather
    /// than resetting the whole file to `.default`).
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        isDarkTheme = try box.decodeIfPresent(Bool.self, forKey: .isDarkTheme)
            ?? fallback.isDarkTheme
        layersPanelVisible = try box.decodeIfPresent(Bool.self, forKey: .layersPanelVisible)
            ?? fallback.layersPanelVisible
        drawPaletteVisible = try box.decodeIfPresent(Bool.self, forKey: .drawPaletteVisible)
            ?? fallback.drawPaletteVisible
        blockPanelVisible = try box.decodeIfPresent(Bool.self, forKey: .blockPanelVisible)
            ?? fallback.blockPanelVisible
        dataTablePanelVisible = try box.decodeIfPresent(
            Bool.self, forKey: .dataTablePanelVisible) ?? fallback.dataTablePanelVisible
        showPropertiesPanel = try box.decodeIfPresent(Bool.self, forKey: .showPropertiesPanel)
            ?? fallback.showPropertiesPanel
        showFPS = try box.decodeIfPresent(Bool.self, forKey: .showFPS)
            ?? fallback.showFPS
        toolbarVisible = try box.decodeIfPresent(Bool.self, forKey: .toolbarVisible)
            ?? fallback.toolbarVisible
        radialNavVisible = try box.decodeIfPresent(Bool.self, forKey: .radialNavVisible)
            ?? fallback.radialNavVisible
        hasCompletedSetup = try box.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup)
            ?? fallback.hasCompletedSetup
    }

    /// Snapshots the live UI state into persistable settings. Single
    /// source of truth for shutdown saves and setup completion.
    @MainActor
    public static func capture(ui: EngineUIManager) -> UserSettings {
        UserSettings(
            isDarkTheme: ui.isDarkTheme,
            layersPanelVisible: ui.layersPanelVisible,
            drawPaletteVisible: ui.drawPaletteVisible,
            blockPanelVisible: ui.blockPanelVisible,
            dataTablePanelVisible: ui.dataTablePanelVisible,
            showPropertiesPanel: ui.showPropertiesPanel,
            showFPS: ui.showFPS,
            toolbarVisible: ui.toolbarVisible,
            radialNavVisible: ui.radialNavVisible,
            hasCompletedSetup: ui.hasCompletedSetup
        )
    }

    // MARK: - Persistence

    /// Directory where settings and other app data live.
    public static func appSupportDirectory() -> URL? {
        guard let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return dir.appendingPathComponent("Zephyr", isDirectory: true)
    }

    /// Path to the JSON settings file.
    public static func settingsURL() -> URL? {
        appSupportDirectory()?.appendingPathComponent("settings.json")
    }

    /// Path to the ImGui docking ini file.
    public static func imguiIniURL() -> URL? {
        appSupportDirectory()?.appendingPathComponent("imgui.ini")
    }

    /// Load settings from disk, returning the default if no file exists.
    public static func load() -> UserSettings {
        guard let url = settingsURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(UserSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    /// Write settings to disk. Creates the directory if needed.
    public func save() {
        guard let dir = Self.appSupportDirectory(),
              let url = Self.settingsURL() else { return }

        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
