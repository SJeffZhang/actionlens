import AppKit
import Foundation

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published var apiKey: String
    @Published var selectedImageURL: URL?
    @Published var previewImage: NSImage?
    @Published var analysisResult: AnalysisResult?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var statusMessage = "Choose a screenshot or capture one to start testing the app."

    private let service = DeepSeekService()
    private let defaults = UserDefaults.standard
    private let apiKeyDefaultsKey = "ActionLens.apiKey"

    init() {
        self.apiKey = defaults.string(forKey: apiKeyDefaultsKey)
            ?? ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
            ?? ""
    }

    func persistAPIKey() {
        defaults.set(apiKey, forKey: apiKeyDefaultsKey)
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose a screenshot"

        if panel.runModal() == .OK, let url = panel.url {
            loadImage(from: url)
        }
    }

    func captureScreenshot(autoAnalyze: Bool = false) async {
        errorMessage = nil
        if autoAnalyze && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "DeepSeek API key is required before using the global shortcut."
            statusMessage = "Add your API key, then try the shortcut again."
            return
        }
        statusMessage = "Waiting for macOS screenshot selection..."

        do {
            let url = try await runScreencapture()
            loadImage(from: url)
            statusMessage = autoAnalyze
                ? "Screenshot captured. Starting analysis..."
                : "Screenshot captured. Ready to analyze."
            if autoAnalyze {
                await analyze()
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = message
            statusMessage = "Screenshot capture did not complete."
        }
    }

    func analyze() async {
        guard let selectedImageURL else {
            errorMessage = "Choose or capture a screenshot first."
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            errorMessage = "DeepSeek API key is required."
            return
        }

        isAnalyzing = true
        errorMessage = nil
        statusMessage = "Analyzing screenshot with DeepSeek Flash..."
        persistAPIKey()

        do {
            analysisResult = try await service.analyzeImage(at: selectedImageURL, apiKey: trimmedKey)
            let attempts = analysisResult?.analysisMeta.attemptsUsed ?? 0
            statusMessage = "Analysis finished in \(attempts) attempt\(attempts == 1 ? "" : "s")."
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = message
            statusMessage = "Analysis failed."
        }

        isAnalyzing = false
    }

    func reset() {
        selectedImageURL = nil
        previewImage = nil
        analysisResult = nil
        errorMessage = nil
        statusMessage = "Use the menu bar or global shortcut to start testing the app."
    }

    private func loadImage(from url: URL) {
        selectedImageURL = url
        previewImage = NSImage(contentsOf: url)
        analysisResult = nil
        errorMessage = previewImage == nil ? "The selected file could not be previewed." : nil
        statusMessage = previewImage == nil ? "Failed to load image preview." : "Screenshot ready to analyze."
    }

    private func runScreencapture() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("actionlens-\(UUID().uuidString).png")

            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", tempURL.path]

                do {
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: tempURL.path) else {
                        continuation.resume(throwing: AnalysisError.invalidResponse("Screenshot capture was cancelled or failed."))
                        return
                    }

                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
