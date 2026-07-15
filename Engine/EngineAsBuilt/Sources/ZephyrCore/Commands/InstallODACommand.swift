import Foundation
import SwiftSDL
import CSDL3

// =========================================================================
// MARK: - InstallODACommand
//
// Installs the ODA FileConverter CLI tool for DWG ↔ DXF conversion.
// Shows a modal with the ODA Community User Agreement, requires the user
// to check "I Agree" before proceeding, then downloads and runs the
// platform-appropriate installer into the user's Application Support folder.
//
// No admin privileges are required — the install target is user-writable.
// =========================================================================

@MainActor
public final class InstallODACommand: FeatureCommand {

    private enum State {
        case showingAgreement
        case downloading
        case installing
        case finished(success: Bool, message: String)
    }

    private var state: State = .showingAgreement
    private var agreed: Bool = false
    private var downloadProgress: Float = 0.0
    private var downloadSpeed: String = ""
    private var statusText: String = ""
    private var installTask: Task<Void, Never>?
    private var popupOpened: Bool = false
    private var okClicked: Bool = false  // Set when user clicks OK on finished modal

    // MARK: - ODA Download URLs

    /// Manifest URL for dynamically fetching the latest download URLs.
    /// Falls back to baked-in URLs if the manifest cannot be fetched.
    private static let manifestURL = "https://zephyr-cad.app/oda-manifest.json"

    /// Baked-in fallback URLs (version 27.1).
    private static let fallbackURLs: [String: String] = [
        "windows": "https://www.opendesign.com/guestfiles/get?filename=ODAFileConverter_QT6_vc16_amd64dll_27.1.msi",
        "macos_arm64": "https://www.opendesign.com/guestfiles/get?filename=ODAFileConverter_QT6_macOsX_arm64_15.0dll_27.1.dmg",
        "macos_x64": "https://www.opendesign.com/guestfiles/get?filename=ODAFileConverter_QT6_macOsX_x64_15.0dll_27.1.dmg",
    ]

    private static let agreementURL = "https://www.opendesign.com/agreements/2025/en/ODA%20Community%20User%20Agreement%2009-2025.pdf"

    // MARK: - Init

    public init() {}

    // MARK: - FeatureCommand

    public func start(engine: PhrostEngine, processor: CADCommandProcessor) {
        state = .showingAgreement
        agreed = false
        downloadProgress = 0.0
        downloadSpeed = ""
        statusText = ""
        popupOpened = false
        processor.commandPrompt = "ODA FileConverter installation."
    }

    public func cancel(engine: PhrostEngine, processor: CADCommandProcessor) {
        installTask?.cancel()
        installTask = nil
        state = .showingAgreement
        processor.commandPrompt = nil
    }

    public func handleMouseClick(
        worldX: Double, worldY: Double,
        engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        if okClicked {
            okClicked = false
            processor.commandPrompt = nil
            return .finished
        }
        return .continue
    }

    public func handleMouseMotion(
        worldX: Double, worldY: Double,
        engine: PhrostEngine, processor: CADCommandProcessor
    ) {}

    public func handleKeyDown(
        scancode: SDL_Scancode, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        if okClicked {
            okClicked = false
            processor.commandPrompt = nil
            return .finished
        }
        return .continue
    }

    public func renderOverlay(cam: CameraTransform, engine: PhrostEngine) {}

    public func renderImGui(engine: PhrostEngine) {
        switch state {
        case .showingAgreement:
            renderAgreementModal(engine: engine)
        case .downloading:
            renderDownloadModal(engine: engine)
        case .installing:
            renderInstallingModal(engine: engine)
        case .finished(let success, let message):
            renderFinishedModal(engine: engine, success: success, message: message)
        }
    }

    public var isSnappingEnabled: Bool { false }

    public func getDrawingSnapPoints() -> [Vector3] { [] }

    public func handleCommandText(
        _ text: String, engine: PhrostEngine, processor: CADCommandProcessor
    ) -> CommandResult {
        return .continue
    }

    // MARK: - Agreement Modal

    private func renderAgreementModal(engine: PhrostEngine) {
        let popupID = "Install ODA FileConverter##InstallODA"
        let theme = engine.ui.theme

        if !popupOpened {
            ImGuiOpenPopup(popupID, Int32(ImGuiPopupFlags_None.rawValue))
            popupOpened = true
        }

        let io = ImGuiGetIO()!
        let displayW = io.pointee.DisplaySize.x
        let displayH = io.pointee.DisplaySize.y
        let modalW = min(ImGuiGetFontSize() * 52, displayW * 0.70)
        let modalH = min(ImGuiGetFontSize() * 34, displayH * 0.70)

        ImGuiSetNextWindowPos(
            ImVec2(x: (displayW - modalW) * 0.5, y: (displayH - modalH) * 0.5),
            Int32(ImGuiCond_Appearing.rawValue),
            ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSize(ImVec2(x: modalW, y: modalH), Int32(ImGuiCond_Appearing.rawValue))

        var openFlag = true
        let flags = Int32(ImGuiWindowFlags_NoSavedSettings.rawValue) |
                    Int32(ImGuiWindowFlags_NoResize.rawValue) |
                    Int32(ImGuiWindowFlags_NoCollapse.rawValue)

        if ImGuiBeginPopupModal(popupID, &openFlag, flags) {
            defer { ImGuiEndPopup() }

            if !openFlag {
                state = .finished(success: false, message: "Installation cancelled.")
                return
            }

            // Title
            ImGuiTextV("ODA FileConverter Installation")
            ImGuiSpacing()
            ImGuiSeparator()
            ImGuiSpacing()

            // Description
            ImGuiTextWrappedV(
                "The ODA FileConverter is a free tool from the Open Design Alliance that converts " +
                "between DWG and DXF file formats. It is required to open and save AutoCAD DWG files.")

            ImGuiSpacing()
            ImGuiTextWrappedV(
                "To use this software, you must accept the ODA Community User Agreement. " +
                "Please review the agreement before proceeding.")

            ImGuiSpacing()

            // View Agreement button
            if ImGuiButton("View Agreement (opens in browser)", ImVec2(x: 0, y: 0)) {
                Self.agreementURL.withCString { SDL_OpenURL($0) }
            }

            ImGuiSpacing()
            ImGuiSeparator()
            ImGuiSpacing()

            // Checkbox: I Agree
            ImGuiCheckbox("I agree to the ODA Community User Agreement", &agreed)

            ImGuiSpacing()

            let installDir: String
            if let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first {
                installDir = appSupport.appendingPathComponent("ODAFileConverter").path
            } else {
                installDir = "~/Library/Application Support/ODAFileConverter"
            }

            ImGuiTextV("Install location:")
            ImGuiSameLine()
            ImGuiTextDisabledV(installDir)

            ImGuiSpacing()
            ImGuiSeparator()
            ImGuiSpacing()

            // Install button (disabled until agreed)
            if !agreed {
                ImGuiPushStyleVar(Int32(ImGuiStyleVar_Alpha.rawValue), Float(0.5))
                ImGuiButton("Install", ImVec2(x: 120, y: 0))
                ImGuiPopStyleVar()
                if ImGuiIsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled.rawValue) {
                    ImGuiSetTooltip("You must agree to the ODA Community User Agreement first.")
                }
            } else {
                if ImGuiButton("Install", ImVec2(x: 120, y: 0)) {
                    startInstallation()
                }
            }

            ImGuiSameLine()
            if ImGuiButton("Cancel", ImVec2(x: 120, y: 0)) {
                state = .finished(success: false, message: "Installation cancelled.")
            }
        }
    }

    // MARK: - Download Modal

    private func renderDownloadModal(engine: PhrostEngine) {
        let popupID = "Installing ODA FileConverter##InstallODA"

        let io = ImGuiGetIO()!
        let displayW = io.pointee.DisplaySize.x
        let displayH = io.pointee.DisplaySize.y
        let modalW = min(ImGuiGetFontSize() * 42, displayW * 0.50)
        let modalH = ImGuiGetFontSize() * 12

        ImGuiSetNextWindowPos(
            ImVec2(x: (displayW - modalW) * 0.5, y: (displayH - modalH) * 0.5),
            Int32(ImGuiCond_Always.rawValue),
            ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSize(ImVec2(x: modalW, y: modalH), Int32(ImGuiCond_Always.rawValue))

        var openFlag = true
        let flags = Int32(ImGuiWindowFlags_NoSavedSettings.rawValue) |
                    Int32(ImGuiWindowFlags_NoResize.rawValue) |
                    Int32(ImGuiWindowFlags_NoCollapse.rawValue) |
                    Int32(ImGuiWindowFlags_NoMove.rawValue)

        if ImGuiBeginPopupModal(popupID, &openFlag, flags) {
            defer { ImGuiEndPopup() }

            if !openFlag {
                installTask?.cancel()
                state = .finished(success: false, message: "Installation cancelled.")
                return
            }

            ImGuiTextV("Downloading ODA FileConverter...")
            ImGuiSpacing()

            // Progress bar
            ImGuiProgressBar(downloadProgress, ImVec2(x: 0, y: 0), nil)

            ImGuiSpacing()

            // Status text with speed
            if !statusText.isEmpty {
                ImGuiTextV(statusText)
            }
            if !downloadSpeed.isEmpty {
                ImGuiSameLine()
                ImGuiTextDisabledV(downloadSpeed)
            }

            ImGuiSpacing()
            if ImGuiButton("Cancel", ImVec2(x: 120, y: 0)) {
                installTask?.cancel()
                state = .finished(success: false, message: "Installation cancelled.")
            }
        }
    }

    // MARK: - Installing Modal

    private func renderInstallingModal(engine: PhrostEngine) {
        let popupID = "Installing ODA FileConverter##InstallODA"

        let io = ImGuiGetIO()!
        let displayW = io.pointee.DisplaySize.x
        let displayH = io.pointee.DisplaySize.y
        let modalW = min(ImGuiGetFontSize() * 42, displayW * 0.50)
        let modalH = ImGuiGetFontSize() * 10

        ImGuiSetNextWindowPos(
            ImVec2(x: (displayW - modalW) * 0.5, y: (displayH - modalH) * 0.5),
            Int32(ImGuiCond_Always.rawValue),
            ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSize(ImVec2(x: modalW, y: modalH), Int32(ImGuiCond_Always.rawValue))

        var openFlag = true
        let flags = Int32(ImGuiWindowFlags_NoSavedSettings.rawValue) |
                    Int32(ImGuiWindowFlags_NoResize.rawValue) |
                    Int32(ImGuiWindowFlags_NoCollapse.rawValue) |
                    Int32(ImGuiWindowFlags_NoMove.rawValue)

        if ImGuiBeginPopupModal(popupID, &openFlag, flags) {
            defer { ImGuiEndPopup() }

            ImGuiTextV(statusText.isEmpty ? "Installing ODA FileConverter..." : statusText)
            ImGuiSpacing()

            // Indeterminate progress
            ImGuiProgressBar(-1.0, ImVec2(x: 0, y: 0), nil)
        }
    }

    // MARK: - Finished Modal

    private func renderFinishedModal(engine: PhrostEngine, success: Bool, message: String) {
        let popupID = "ODA FileConverter##InstallODA"

        let io = ImGuiGetIO()!
        let displayW = io.pointee.DisplaySize.x
        let displayH = io.pointee.DisplaySize.y
        let modalW = min(ImGuiGetFontSize() * 42, displayW * 0.50)
        let modalH = ImGuiGetFontSize() * 10

        ImGuiSetNextWindowPos(
            ImVec2(x: (displayW - modalW) * 0.5, y: (displayH - modalH) * 0.5),
            Int32(ImGuiCond_Always.rawValue),
            ImVec2(x: 0, y: 0))
        ImGuiSetNextWindowSize(ImVec2(x: modalW, y: modalH), Int32(ImGuiCond_Always.rawValue))

        var openFlag = true
        let flags = Int32(ImGuiWindowFlags_NoSavedSettings.rawValue) |
                    Int32(ImGuiWindowFlags_NoResize.rawValue) |
                    Int32(ImGuiWindowFlags_NoCollapse.rawValue) |
                    Int32(ImGuiWindowFlags_NoMove.rawValue)

        if ImGuiBeginPopupModal(popupID, &openFlag, flags) {
            defer { ImGuiEndPopup() }

            if success {
                ImGuiTextColoredV(ImVec2(x: 0.2, y: 0.9, z: 0.3, w: 1.0), "Installation Complete!")
            } else {
                ImGuiTextColoredV(ImVec2(x: 0.9, y: 0.3, z: 0.3, w: 1.0), "Installation Failed")
            }

            ImGuiSpacing()
            ImGuiTextWrappedV(message)

            ImGuiSpacing()
            ImGuiSpacing()

            if ImGuiButton("OK", ImVec2(x: 120, y: 0)) || !openFlag {
                okClicked = true
                state = .showingAgreement  // Reset for next time
                popupOpened = false
            }
        }
    }

    // MARK: - Installation Logic

    private func startInstallation() {
        state = .downloading
        statusText = "Fetching download information..."
        downloadProgress = 0.0
        downloadSpeed = ""

        installTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Resolve download URL
                let downloadURL = try await self.resolveDownloadURL()

                // Download
                let downloadedFile = try await self.download(url: downloadURL)

                // Install
                await MainActor.run {
                    self.state = .installing
                    self.statusText = "Running installer..."
                }

                try await self.runInstaller(file: downloadedFile)

                // Cleanup
                try? FileManager.default.removeItem(at: downloadedFile)

                // Store converter path
                if let converterPath = await ODADWGConverter.locateConverter() {
                    UserDefaults.standard.set(converterPath, forKey: "ODAFileConverterPath")
                }

                await MainActor.run {
                    self.state = .finished(
                        success: true,
                        message: "ODA FileConverter has been installed successfully. " +
                            "You can now open and save DWG files."
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.state = .finished(success: false, message: "Installation cancelled.")
                }
            } catch {
                await MainActor.run {
                    self.state = .finished(
                        success: false,
                        message: "Installation error: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    /// Resolve the platform-appropriate download URL from the manifest or fallback.
    private func resolveDownloadURL() async throws -> URL {
        let platformKey: String
        #if os(Windows)
            platformKey = "windows"
        #elseif os(macOS)
            // Determine ARM vs x64 on macOS
            #if arch(arm64)
                platformKey = "macos_arm64"
            #else
                platformKey = "macos_x64"
            #endif
        #else
            throw NSError(domain: "InstallODA", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported platform"])
        #endif

        // Try manifest first
        if let manifestURL = URL(string: Self.manifestURL),
           let (data, _) = try? await URLSession.shared.data(from: manifestURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]],
           let entry = json[platformKey],
           let urlString = entry["url"],
           let url = URL(string: urlString) {
            return url
        }

        // Fallback
        if let fallback = Self.fallbackURLs[platformKey],
           let url = URL(string: fallback) {
            return url
        }

        throw NSError(domain: "InstallODA", code: -2,
                      userInfo: [NSLocalizedDescriptionKey: "No download URL for platform: \(platformKey)"])
    }

    /// Download a file with progress tracking.
    private func download(url: URL) async throws -> URL {
        await MainActor.run {
            self.statusText = "Downloading..."
            self.downloadProgress = 0.0
            self.downloadSpeed = ""
        }

        let request = URLRequest(url: url, timeoutInterval: 600)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        let expectedLength = Int(response.expectedContentLength)
        var data = Data()
        data.reserveCapacity(expectedLength > 0 ? expectedLength : 16 * 1024 * 1024)

        var lastUpdate = Date()
        var bytesSinceLastUpdate = 0
        let startTime = Date()

        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)

            let now = Date()
            bytesSinceLastUpdate += 1

            // Update progress every 100ms
            if now.timeIntervalSince(lastUpdate) > 0.1 {
                let elapsed = now.timeIntervalSince(startTime)
                let totalBytes = data.count

                if expectedLength > 0 {
                    let progress = Float(totalBytes) / Float(expectedLength)
                    let speed = elapsed > 0 ? Double(totalBytes) / elapsed : 0
                    let speedStr = formatSpeed(speed)

                    await MainActor.run {
                        self.downloadProgress = progress
                        self.statusText = "Downloading... \(Int(progress * 100))%"
                        self.downloadSpeed = speedStr
                    }
                } else {
                    let speed = elapsed > 0 ? Double(totalBytes) / elapsed : 0
                    let speedStr = formatSpeed(speed)
                    let sizeStr = formatBytes(totalBytes)

                    await MainActor.run {
                        self.statusText = "Downloaded \(sizeStr)"
                        self.downloadSpeed = speedStr
                    }
                }

                lastUpdate = now
                bytesSinceLastUpdate = 0
            }
        }

        // Write to temp file
        let tmpDir = FileManager.default.temporaryDirectory
        let filename = url.lastPathComponent
        let tmpFile = tmpDir.appendingPathComponent(filename)
        try data.write(to: tmpFile)

        return tmpFile
    }

    /// Run the platform-specific installer.
    private func runInstaller(file: URL) async throws {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw NSError(domain: "InstallODA", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot find Application Support directory"])
        }

        let targetDir = appSupport.appendingPathComponent("ODAFileConverter")
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        #if os(Windows)
        // Windows: msiexec /a "<msi>" /qb TARGETDIR="<targetDir>"
        try await runProcess(
            executable: "msiexec",
            arguments: ["/a", file.path, "/qb", "TARGETDIR=\(targetDir.path)"]
        )
        #elseif os(macOS)
        // macOS: hdiutil attach → cp → hdiutil detach → clear quarantine
        await MainActor.run {
            self.statusText = "Mounting disk image..."
        }

        // Attach DMG
        let attachResult = try await runProcess(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", file.path, "-nobrowse", "-plist"]
        )

        // Parse mount point from plist output
        let mountPoint: String
        if let plistData = attachResult.data(using: .utf8),
           let plist = try? PropertyListSerialization.propertyList(
               from: plistData, options: [], format: nil
           ) as? [String: Any],
           let entities = plist["system-entities"] as? [[String: Any]],
           let firstEntity = entities.first,
           let mp = firstEntity["mount-point"] as? String {
            mountPoint = mp
        } else {
            // Fallback: guess the volume name
            mountPoint = "/Volumes/ODAFileConverter"
        }

        defer {
            try? Process.run(
                URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["detach", mountPoint]
            )
        }

        await MainActor.run {
            self.statusText = "Copying files..."
        }

        // Copy .app to target
        let appName = "ODAFileConverter.app"
        let sourceApp = "\(mountPoint)/\(appName)"
        let targetApp = targetDir.appendingPathComponent(appName)

        if FileManager.default.fileExists(atPath: targetApp.path) {
            try FileManager.default.removeItem(at: targetApp)
        }

        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: sourceApp),
            to: targetApp
        )

        await MainActor.run {
            self.statusText = "Clearing quarantine flag..."
        }

        // Clear Gatekeeper quarantine flag (mandatory for Process execution)
        _ = try? await runProcess(
            executable: "/usr/bin/xattr",
            arguments: ["-r", "-d", "com.apple.quarantine", targetApp.path]
        )
        #endif
    }

    /// Run a subprocess and return its stdout as a string.
    @discardableResult
    private func runProcess(executable: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        print("[InstallODA] Running: \(executable) \(arguments.joined(separator: " "))")

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrStr = String(data: stderrData, encoding: .utf8) ?? "(no stderr)"
            print("[InstallODA] Error: exit \(process.terminationStatus), stderr: \(stderrStr)")
            throw NSError(domain: "InstallODA", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Installer failed: \(stderrStr)"])
        }

        return stdoutStr
    }

    // MARK: - Formatting Helpers

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
    }
}
