import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AnalysisViewModel

    var body: some View {
        HSplitView {
            controlPane
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 420)

            resultPane
                .frame(minWidth: 620)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var controlPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ActionLens")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Menu bar prototype for screenshot-to-task analysis.")
                        .foregroundStyle(.secondary)
                }

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DeepSeek API Key")
                            .font(.headline)
                        SecureField("sk-...", text: $viewModel.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.apiKey) { _ in
                                viewModel.persistAPIKey()
                            }
                        Text("Stored locally in UserDefaults for this prototype.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("The menu bar app uses this key for both direct window analysis and the global shortcut flow.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Capture Flow")
                            .font(.headline)

                        HStack {
                            Button("Capture Screenshot") {
                                Task {
                                    await viewModel.captureScreenshot(autoAnalyze: false)
                                }
                            }
                            Button("Choose Image") {
                                viewModel.chooseImage()
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Menu bar shortcut")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Press Control + Option + A anywhere in macOS to start an interactive screenshot, then analyze it automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button("Analyze") {
                                Task {
                                    await viewModel.analyze()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.selectedImageURL == nil || viewModel.isAnalyzing)

                            Button("Reset") {
                                viewModel.reset()
                            }
                            .disabled(viewModel.isAnalyzing)
                        }

                        Text(viewModel.statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if let imageURL = viewModel.selectedImageURL {
                            Text(imageURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preview")
                            .font(.headline)

                        if let previewImage = viewModel.previewImage {
                            Image(nsImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 340)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(height: 220)
                                .overlay {
                                    Text("No screenshot selected")
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Error", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.headline)
                            Text(errorMessage)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var resultPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Structured Result")
                            .font(.title2)
                            .fontWeight(.semibold)
                        if let result = viewModel.analysisResult {
                            Text("Type: \(result.contentType)  |  Confidence: \(result.confidence.formatted(.number.precision(.fractionLength(2))))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No analysis yet.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if viewModel.isAnalyzing {
                        ProgressView()
                            .controlSize(.large)
                    }
                }

                if let result = viewModel.analysisResult {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], alignment: .leading, spacing: 12) {
                        badge("Source: \(result.analysisSource)")
                        badge("Vision: \(result.visionModel)")
                        badge("Attempts: \(result.analysisMeta.attemptsUsed)")
                        badge("Resets: \(result.analysisMeta.resetCount)")
                        badge(result.needsReview ? "Needs review" : "Ready", tone: result.needsReview ? .orange : .green)
                    }

                    card {
                        labeledSection("Title", value: result.title)
                    }

                    card {
                        labeledSection("Summary", value: result.summary)
                    }

                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Explanation")
                                .font(.headline)
                            Text(result.explanation.reasoningSummary)
                            FlowLayout(spacing: 8) {
                                ForEach(result.explanation.keySignals, id: \.self) { signal in
                                    badge(signal)
                                }
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Reminder-ready Items")
                                .font(.headline)
                            if result.items.isEmpty {
                                Text("No reminder-ready items survived validation.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(result.items) { item in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.title)
                                            .font(.headline)
                                        Text("kind: \(item.kind)  |  priority: \(item.priority)  |  due: \(item.dueDate ?? "none")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !item.notes.isEmpty {
                                            Text(item.notes)
                                        }
                                        Text(item.sourceSpan)
                                            .font(.system(.body, design: .monospaced))
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.secondary.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    if item.id != result.items.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Failure History / Resets")
                                .font(.headline)
                            if result.analysisMeta.failureHistory.isEmpty {
                                Text("No resets were needed for this run.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(result.analysisMeta.failureHistory) { entry in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Attempt \(entry.attempt)")
                                            .font(.headline)
                                        Text(entry.errors.joined(separator: "\n"))
                                            .font(.system(.body, design: .monospaced))
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.secondary.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                    }

                    card {
                        labeledSection("Visible Text", value: result.visibleText)
                    }
                } else {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ready")
                                .font(.headline)
                            Text("This native build now runs as a menu bar app, supports a global shortcut, and shows structured DeepSeek results in the main window.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func labeledSection(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(.headline)
            Text(value.isEmpty ? "None" : value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func badge(_ text: String, tone: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.opacity(0.12))
            .foregroundStyle(tone)
            .clipShape(Capsule())
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
