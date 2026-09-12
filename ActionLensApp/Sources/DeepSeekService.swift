import Foundation
import UniformTypeIdentifiers

enum AnalysisError: LocalizedError {
    case missingAPIKey
    case unreadableImage
    case invalidResponse(String)
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Please provide a DeepSeek API key before analyzing."
        case .unreadableImage:
            return "The selected screenshot could not be read."
        case .invalidResponse(let message):
            return message
        case .httpError(let code, let body):
            return "DeepSeek request failed (\(code)): \(body)"
        }
    }
}

struct DeepSeekService {
    private let apiURL = URL(string: "https://api.deepseek.com/chat/completions")!
    private let model = "deepseek-flash"
    private let session = URLSession.shared

    func analyzeImage(at fileURL: URL, apiKey: String) async throws -> AnalysisResult {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw AnalysisError.missingAPIKey
        }

        let imageData = try Data(contentsOf: fileURL)
        guard !imageData.isEmpty else {
            throw AnalysisError.unreadableImage
        }

        let imageDataURL = try makeImageDataURL(data: imageData, fileURL: fileURL)
        var failureHistory: [AttemptFailure] = []
        var lastFailure = ""
        var lastVisibleText = ""

        for attempt in 1...maxResets {
            do {
                let rawResponse = try await deepSeekChat(
                    messages: buildAnalysisMessages(
                        imageDataURL: imageDataURL,
                        attemptNumber: attempt,
                        failureReason: lastFailure
                    ),
                    apiKey: trimmedAPIKey
                )
                let object = try extractJSONObject(from: rawResponse)
                let data = try JSONSerialization.data(withJSONObject: object)
                let payload = try JSONDecoder().decode(ModelPayload.self, from: data)
                let interpretation = Interpretation.build(from: payload.visibleText)
                let errors = validate(payload: payload, interpretation: interpretation)

                if errors.isEmpty {
                    return AnalysisResult(
                        contentType: payload.contentType,
                        title: payload.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        summary: payload.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                        confidence: payload.confidence,
                        explanation: payload.explanation,
                        items: payload.items,
                        needsReview: payload.needsReview,
                        visibleText: interpretation.normalizedText,
                        analysisSource: "vision_direct",
                        visionModel: model,
                        analysisMeta: AnalysisMeta(
                            mode: "deepseek",
                            attemptsUsed: attempt,
                            resetCount: max(attempt - 1, 0),
                            failureHistory: failureHistory
                        )
                    )
                }

                failureHistory.append(AttemptFailure(attempt: attempt, errors: errors))
                lastFailure = errors.joined(separator: "; ")
                lastVisibleText = interpretation.normalizedText
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failureHistory.append(AttemptFailure(attempt: attempt, errors: [message]))
                lastFailure = message
            }
        }

        let interpretation = Interpretation.build(from: lastVisibleText)
        return AnalysisResult(
            contentType: interpretation.suspectedTypeCandidates.first ?? "generic",
            title: "Needs manual review",
            summary: interpretation.normalizedText.isEmpty
                ? "AI parsing failed. Please review the screenshot manually."
                : String(interpretation.normalizedText.prefix(200)),
            confidence: 0,
            explanation: Explanation(
                reasoningSummary: "The model could not produce a stable reminder-ready result.",
                keySignals: ["Exceeded retry budget", "Returned invalid or drifting structure"]
            ),
            items: [],
            needsReview: true,
            visibleText: interpretation.normalizedText,
            analysisSource: "vision_direct",
            visionModel: model,
            analysisMeta: AnalysisMeta(
                mode: "deepseek",
                attemptsUsed: maxResets,
                resetCount: maxResets,
                failureHistory: failureHistory
            )
        )
    }

    private func deepSeekChat(messages: [[String: Any]], apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "temperature": 0.1,
            "max_tokens": 2400,
            "reasoning_effort": "high",
            "thinking": ["type": "enabled"],
            "response_format": ["type": "json_object"],
        ]

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let bodyText = String(data: data, encoding: .utf8) ?? ""

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw AnalysisError.httpError(httpResponse.statusCode, bodyText)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AnalysisError.invalidResponse("DeepSeek response did not include message.content.")
        }

        return content
    }

    private func buildAnalysisMessages(
        imageDataURL: String,
        attemptNumber: Int,
        failureReason: String
    ) -> [[String: Any]] {
        let contract: [String: Any] = [
            "visible_text": "string with the screenshot text or important visible labels in reading order",
            "content_type": supportedContentTypes.joined(separator: "|"),
            "title": "string <= 80 chars",
            "summary": "string <= 200 chars",
            "confidence": "number between 0 and 1",
            "explanation": [
                "reasoning_summary": "one short sentence",
                "key_signals": ["signal 1", "signal 2"],
            ],
            "items": [
                [
                    "title": "string",
                    "kind": supportedItemKinds.joined(separator: "|"),
                    "due_date": "ISO date string or null",
                    "priority": supportedPriorities.joined(separator: "|"),
                    "notes": "string",
                    "source_span": "verbatim evidence from screenshot text",
                ],
            ],
            "needs_review": "boolean",
        ]

        var instructions = [
            "You are the ActionLens visual interpretation layer for screenshot-to-reminder parsing.",
            "Return only valid JSON.",
            "Read the screenshot directly. Do not ask for OCR or external preprocessing.",
            "First extract the visible text into visible_text, then classify and structure the result.",
            "Only include tasks that can be justified by the screenshot text.",
            "Do not invent deadlines, owners, or tasks that are not grounded in the evidence.",
            "For event_poster and travel_guide, stay conservative and prefer fewer items.",
            "If confidence is low, set needs_review to true.",
        ]
        if !failureReason.isEmpty {
            instructions.append("Previous attempt failed validation. Correct these problems exactly: \(failureReason)")
        }

        let userPayload: [String: Any] = [
            "attempt_number": attemptNumber,
            "required_contract": contract,
            "supported_content_types": supportedContentTypes,
            "supported_item_kinds": supportedItemKinds,
            "priority_enum": supportedPriorities,
        ]

        let payloadText = (try? prettyJSON(userPayload)) ?? "{}"
        return [
            [
                "role": "system",
                "content": "You generate structured reminder-ready JSON only.",
            ],
            [
                "role": "user",
                "content": [
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": imageDataURL,
                            "detail": "original",
                        ],
                    ],
                    [
                        "type": "text",
                        "text": instructions.joined(separator: "\n") + "\n\nUse this contract:\n" + payloadText,
                    ],
                ],
            ],
        ]
    }

    private func validate(payload: ModelPayload, interpretation: Interpretation) -> [String] {
        var errors: [String] = []
        let rawText = interpretation.normalizedText

        if payload.visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("visible_text must be a non-empty string.")
        }
        if !supportedContentTypes.contains(payload.contentType) {
            errors.append("content_type is outside the supported enum.")
        }
        if payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("title must be a non-empty string.")
        } else if payload.title.count > 80 {
            errors.append("title exceeds 80 characters.")
        }
        if payload.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("summary must be a non-empty string.")
        } else if payload.summary.count > 200 {
            errors.append("summary exceeds 200 characters.")
        }
        if !(0...1).contains(payload.confidence) {
            errors.append("confidence must be between 0 and 1.")
        }
        if payload.explanation.reasoningSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("explanation.reasoning_summary is required.")
        }

        let expectedCandidates = interpretation.suspectedTypeCandidates
        if payload.contentType != "generic",
           !expectedCandidates.isEmpty,
           !expectedCandidates.contains(payload.contentType),
           payload.confidence >= 0.7 {
            errors.append("content_type conflicts with interpretation candidates.")
        }

        let sourceTokens = meaningfulTokens(in: rawText)
        for (index, item) in payload.items.enumerated() {
            if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("item \(index + 1) title is required.")
            }
            if !supportedItemKinds.contains(item.kind) {
                errors.append("item \(index + 1) kind is invalid.")
            }
            if !supportedPriorities.contains(item.priority) {
                errors.append("item \(index + 1) priority is invalid.")
            }
            if item.sourceSpan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("item \(index + 1) source_span is required.")
            }

            let overlap = meaningfulTokens(in: item.title).intersection(sourceTokens)
            let grounded = !overlap.isEmpty
                || isGroundedSegment(item.title, sourceText: rawText)
                || isGroundedSegment(item.sourceSpan, sourceText: rawText)
                || isGroundedSegment(item.title, sourceText: item.sourceSpan)

            if !grounded && strictTypes.contains(payload.contentType) {
                errors.append("item \(index + 1) title is not grounded in visible text.")
            }
        }

        return errors
    }

    private func makeImageDataURL(data: Data, fileURL: URL) throws -> String {
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "image/png"
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private func extractJSONObject(from rawResponse: String) throws -> [String: Any] {
        var clean = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonRange = clean.range(of: "```json") {
            clean = String(clean[jsonRange.upperBound...])
            if let closingRange = clean.range(of: "```") {
                clean = String(clean[..<closingRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let codeRange = clean.range(of: "```") {
            clean = String(clean[codeRange.upperBound...])
            if let closingRange = clean.range(of: "```") {
                clean = String(clean[..<closingRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let data = clean.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }

        guard let start = clean.firstIndex(of: "{"), let end = clean.lastIndex(of: "}") else {
            throw AnalysisError.invalidResponse("Model response does not contain a JSON object.")
        }

        let candidate = String(clean[start...end])
        guard let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalysisError.invalidResponse("Model response did not contain a decodable JSON object.")
        }
        return object
    }

    private func prettyJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func meaningfulTokens(in text: String) -> Set<String> {
        let pattern = #"[A-Za-z0-9\u{4e00}-\u{9fff}]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsText = text.lowercased() as NSString
        return Set(regex.matches(in: text.lowercased(), range: NSRange(location: 0, length: nsText.length)).compactMap {
            let token = nsText.substring(with: $0.range)
            return token.count > 1 ? token : nil
        })
    }

    private func isGroundedSegment(_ candidate: String, sourceText: String) -> Bool {
        let candidateCompact = compactGroundingText(candidate)
        let sourceCompact = compactGroundingText(sourceText)
        guard !candidateCompact.isEmpty, !sourceCompact.isEmpty else {
            return false
        }
        return candidateCompact.contains(sourceCompact) || sourceCompact.contains(candidateCompact)
    }

    private func compactGroundingText(_ text: String) -> String {
        let withoutBullets = text
            .replacingOccurrences(of: #"\r\n|\r"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+[\.\)]\s*"#, with: "", options: .regularExpression)
        return withoutBullets
            .lowercased()
            .replacingOccurrences(of: #"[^\w\u{4e00}-\u{9fff}]+"#, with: "", options: .regularExpression)
    }
}
