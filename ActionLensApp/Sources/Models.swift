import Foundation

let maxResets = 5
let supportedContentTypes = [
    "meeting_notes",
    "course_notice",
    "job_description",
    "event_poster",
    "travel_guide",
    "generic",
]
let supportedItemKinds = ["todo", "study_task", "apply_task", "plan_step", "reminder"]
let supportedPriorities = ["low", "medium", "high"]

struct ModelPayload: Decodable {
    let visibleText: String
    let contentType: String
    let title: String
    let summary: String
    let confidence: Double
    let explanation: Explanation
    let items: [ReminderItem]
    let needsReview: Bool

    enum CodingKeys: String, CodingKey {
        case visibleText = "visible_text"
        case contentType = "content_type"
        case title
        case summary
        case confidence
        case explanation
        case items
        case needsReview = "needs_review"
    }
}

struct Explanation: Decodable {
    let reasoningSummary: String
    let keySignals: [String]

    enum CodingKeys: String, CodingKey {
        case reasoningSummary = "reasoning_summary"
        case keySignals = "key_signals"
    }
}

struct ReminderItem: Decodable, Identifiable {
    let id = UUID()
    let title: String
    let kind: String
    let dueDate: String?
    let priority: String
    let notes: String
    let sourceSpan: String

    enum CodingKeys: String, CodingKey {
        case title
        case kind
        case dueDate = "due_date"
        case priority
        case notes
        case sourceSpan = "source_span"
    }
}

struct AttemptFailure: Identifiable {
    let id = UUID()
    let attempt: Int
    let errors: [String]
}

struct AnalysisMeta {
    let mode: String
    let attemptsUsed: Int
    let resetCount: Int
    let failureHistory: [AttemptFailure]
}

struct AnalysisResult {
    let contentType: String
    let title: String
    let summary: String
    let confidence: Double
    let explanation: Explanation
    let items: [ReminderItem]
    let needsReview: Bool
    let visibleText: String
    let analysisSource: String
    let visionModel: String
    let analysisMeta: AnalysisMeta
}

struct SignalMap {
    let lineCount: Int
    let hasDeadline: Bool
    let hasBullets: Bool
    let hasSalaryInfo: Bool
    let hasJobSignals: Bool
    let hasCourseSignals: Bool
    let hasMeetingSignals: Bool
    let hasEventSignals: Bool
    let hasTravelSignals: Bool
}

struct Interpretation {
    let rawText: String
    let normalizedText: String
    let suspectedTypeCandidates: [String]
    let extractedSignals: SignalMap
    let instructionProfile: String

    static func build(from rawText: String) -> Interpretation {
        let normalizedText = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let signals = SignalMap.build(from: normalizedText)
        let candidates = guessContentTypes(from: normalizedText)

        return Interpretation(
            rawText: rawText,
            normalizedText: normalizedText,
            suspectedTypeCandidates: candidates,
            extractedSignals: signals,
            instructionProfile: candidates.first.map { strictTypes.contains($0) } == true
                ? "task_extraction_strict"
                : "task_extraction_conservative"
        )
    }
}

let strictTypes = Set(["meeting_notes", "course_notice", "job_description"])

extension SignalMap {
    static func build(from rawText: String) -> SignalMap {
        let lines = rawText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        let lowered = joined.lowercased()

        return SignalMap(
            lineCount: lines.count,
            hasDeadline: lowered.hasMatch(#"\b\d{1,2}[:/.-]\d{1,2}\b|deadline|due|ddl|截止|截至|考试|面试"#),
            hasBullets: lines.contains { $0.hasMatch(#"^(\-|\*|•|\d+[\.\)])\s+"#) },
            hasSalaryInfo: lowered.hasMatch(#"k/月|k/mo|salary|薪资|年薪"#),
            hasJobSignals: lowered.hasMatch(#"\bjd\b|responsibilit|requirement|职责|要求|岗位|简历|投递"#),
            hasCourseSignals: lowered.hasMatch(#"课程|作业|考试|上课|chapter|assignment|lecture|syllabus"#),
            hasMeetingSignals: lowered.hasMatch(#"会议|meeting|follow up|action item|待办|todo|纪要|同步"#),
            hasEventSignals: lowered.hasMatch(#"报名|活动|讲座|海报|venue|speaker|register|event"#),
            hasTravelSignals: lowered.hasMatch(#"旅行|行程|酒店|机票|景点|itinerary|travel|check-in"#)
        )
    }
}

private func guessContentTypes(from rawText: String) -> [String] {
    let lowered = rawText.lowercased()
    let rules: [String: [String]] = [
        "meeting_notes": ["meeting", "会议", "纪要", "todo", "action item", "follow up", "待办"],
        "course_notice": ["课程", "作业", "考试", "assignment", "lecture", "chapter", "deadline"],
        "job_description": ["jd", "岗位", "职责", "要求", "salary", "简历", "投递", "responsibilities"],
        "event_poster": ["活动", "报名", "讲座", "register", "venue", "speaker", "event", "ticket"],
        "travel_guide": ["旅行", "行程", "酒店", "景点", "travel", "itinerary", "check-in"],
    ]
    var scores = Dictionary(uniqueKeysWithValues: supportedContentTypes.map { ($0, 0) })

    for (contentType, keywords) in rules {
        for keyword in keywords where lowered.contains(keyword) {
            scores[contentType, default: 0] += 1
        }
    }

    let positive = scores
        .filter { $0.value > 0 }
        .sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }
        .map(\.key)

    return positive.isEmpty ? ["generic"] : Array(positive.prefix(3))
}

extension String {
    func hasMatch(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
