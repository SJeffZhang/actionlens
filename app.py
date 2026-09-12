from flask import Flask, jsonify, render_template, request
from dotenv import load_dotenv
import base64
import json
import mimetypes
import os
import re
import urllib.error
import urllib.request


load_dotenv()

app = Flask(__name__)

DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY")
DEEPSEEK_API_URL = os.getenv(
    "DEEPSEEK_API_URL", "https://api.deepseek.com/chat/completions"
)
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-flash")
MAX_RESETS = 5

CONTENT_TYPES = {
    "meeting_notes",
    "course_notice",
    "job_description",
    "event_poster",
    "travel_guide",
    "generic",
}

ITEM_KINDS = {"todo", "study_task", "apply_task", "plan_step", "reminder"}
PRIORITIES = {"low", "medium", "high"}


def normalize_text(text):
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def build_signal_map(raw_text):
    lines = [line.strip() for line in raw_text.splitlines() if line.strip()]
    joined = "\n".join(lines)
    lowered = joined.lower()

    return {
        "line_count": len(lines),
        "has_deadline": bool(
            re.search(r"\b\d{1,2}[:/.-]\d{1,2}\b|deadline|due|ddl|截止|截至|考试|面试", lowered)
        ),
        "has_bullets": any(
            re.match(r"^(\-|\*|•|\d+[\.\)])\s+", line) for line in lines
        ),
        "has_salary_info": bool(re.search(r"k/月|k/mo|salary|薪资|年薪", lowered)),
        "has_job_signals": bool(
            re.search(r"\bjd\b|responsibilit|requirement|职责|要求|岗位|简历|投递", lowered)
        ),
        "has_course_signals": bool(
            re.search(r"课程|作业|考试|上课|chapter|assignment|lecture|syllabus", lowered)
        ),
        "has_meeting_signals": bool(
            re.search(r"会议|meeting|follow up|action item|待办|todo|纪要|同步", lowered)
        ),
        "has_event_signals": bool(
            re.search(r"报名|活动|讲座|海报|venue|speaker|register|event", lowered)
        ),
        "has_travel_signals": bool(
            re.search(r"旅行|行程|酒店|机票|景点|itinerary|travel|check-in", lowered)
        ),
    }


def guess_content_types(raw_text):
    lowered = raw_text.lower()
    scores = {
        "meeting_notes": 0,
        "course_notice": 0,
        "job_description": 0,
        "event_poster": 0,
        "travel_guide": 0,
        "generic": 0,
    }

    rules = {
        "meeting_notes": [
            "meeting",
            "会议",
            "纪要",
            "todo",
            "action item",
            "follow up",
            "待办",
        ],
        "course_notice": [
            "课程",
            "作业",
            "考试",
            "assignment",
            "lecture",
            "chapter",
            "deadline",
        ],
        "job_description": [
            "jd",
            "岗位",
            "职责",
            "要求",
            "salary",
            "简历",
            "投递",
            "responsibilities",
        ],
        "event_poster": [
            "活动",
            "报名",
            "讲座",
            "register",
            "venue",
            "speaker",
            "event",
        ],
        "travel_guide": [
            "旅行",
            "行程",
            "酒店",
            "景点",
            "travel",
            "itinerary",
            "check-in",
        ],
    }

    for content_type, keywords in rules.items():
        for keyword in keywords:
            if keyword in lowered:
                scores[content_type] += 1

    if all(score == 0 for score in scores.values()):
        return ["generic"]

    ranked = sorted(scores.items(), key=lambda item: item[1], reverse=True)
    candidates = [content_type for content_type, score in ranked if score > 0]
    return candidates[:3] or ["generic"]


def build_interpretation(raw_text):
    normalized_text = normalize_text(raw_text)
    signals = build_signal_map(normalized_text)
    candidates = guess_content_types(normalized_text)

    return {
        "raw_text": raw_text,
        "normalized_text": normalized_text,
        "suspected_type_candidates": candidates,
        "extracted_signals": signals,
        "instruction_profile": (
            "task_extraction_strict"
            if candidates[0] in {"meeting_notes", "course_notice", "job_description"}
            else "task_extraction_conservative"
        ),
    }


def build_data_url(file_storage):
    mime_type = (
        file_storage.mimetype
        or mimetypes.guess_type(file_storage.filename or "")[0]
        or "image/png"
    )
    payload = file_storage.read()
    file_storage.seek(0)
    encoded = base64.b64encode(payload).decode("utf-8")
    return f"data:{mime_type};base64,{encoded}"


def extract_json_object(raw_response):
    clean = raw_response.strip()
    if "```json" in clean:
        clean = clean.split("```json", 1)[1].split("```", 1)[0].strip()
    elif "```" in clean:
        clean = clean.split("```", 1)[1].split("```", 1)[0].strip()

    try:
        return json.loads(clean)
    except json.JSONDecodeError:
        pass

    start = clean.find("{")
    end = clean.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("Model response does not contain a JSON object.")

    return json.loads(clean[start : end + 1])


def deepseek_chat(
    messages,
    max_tokens=1800,
    force_json=True,
    model=None,
    reasoning_effort="medium",
    enable_thinking=True,
):
    if not DEEPSEEK_API_KEY:
        raise RuntimeError("DEEPSEEK_API_KEY is not configured.")

    payload = {
        "model": model or DEEPSEEK_MODEL,
        "messages": messages,
        "stream": False,
        "temperature": 0.1,
        "max_tokens": max_tokens,
        "reasoning_effort": reasoning_effort,
    }
    payload["thinking"] = {"type": "enabled"} if enable_thinking else {"type": "disabled"}
    if force_json:
        payload["response_format"] = {"type": "json_object"}
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        DEEPSEEK_API_URL,
        data=body,
        headers={
            "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            data = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"DeepSeek request failed: {exc.code} {error_body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"DeepSeek request failed: {exc.reason}") from exc

    return data["choices"][0]["message"]["content"]


def build_analysis_messages(image_data_url, attempt_number, failure_reason):
    contract = {
        "visible_text": "string with the screenshot text or important visible labels in reading order",
        "content_type": "meeting_notes|course_notice|job_description|event_poster|travel_guide|generic",
        "title": "string <= 80 chars",
        "summary": "string <= 200 chars",
        "confidence": "number between 0 and 1",
        "explanation": {
            "reasoning_summary": "one short sentence",
            "key_signals": ["signal 1", "signal 2"],
        },
        "items": [
            {
                "title": "string",
                "kind": "todo|study_task|apply_task|plan_step|reminder",
                "due_date": "ISO date string or null",
                "priority": "low|medium|high",
                "notes": "string",
                "source_span": "verbatim evidence from screenshot text",
            }
        ],
        "needs_review": "boolean",
    }

    instructions = [
        "You are the ActionLens visual interpretation layer for screenshot-to-reminder parsing.",
        "Return only valid JSON.",
        "Read the screenshot directly. Do not ask for OCR or external preprocessing.",
        "First extract the visible text into visible_text, then classify and structure the result.",
        "Only include tasks that can be justified by the screenshot text.",
        "Do not invent deadlines, owners, or tasks that are not grounded in the evidence.",
        "For event_poster and travel_guide, stay conservative and prefer fewer items.",
        "If confidence is low, set needs_review to true.",
    ]

    if failure_reason:
        instructions.append(
            "Previous attempt failed validation. Correct these problems exactly: "
            f"{failure_reason}"
        )

    user_payload = {
        "attempt_number": attempt_number,
        "required_contract": contract,
        "supported_content_types": sorted(CONTENT_TYPES),
        "supported_item_kinds": sorted(ITEM_KINDS),
        "priority_enum": sorted(PRIORITIES),
    }

    content = [
        {
            "type": "text",
            "text": (
                "\n".join(instructions)
                + "\n\nUse this interpretation payload:\n"
                + json.dumps(user_payload, ensure_ascii=False, indent=2)
            ),
        }
    ]

    if image_data_url:
        content.insert(
            0,
            {"type": "image_url", "image_url": {"url": image_data_url, "detail": "high"}},
        )

    return [
        {"role": "system", "content": "You generate structured reminder-ready JSON only."},
        {"role": "user", "content": content},
    ]


def meaningful_tokens(text):
    return {
        token
        for token in re.findall(r"[A-Za-z0-9\u4e00-\u9fff]{2,}", text.lower())
        if len(token) > 1
    }


def compact_grounding_text(text):
    text = normalize_text(str(text))
    text = re.sub(r"^\d+[\.\)]\s*", "", text)
    text = re.sub(r"[^\w\u4e00-\u9fff]+", "", text.lower())
    return text


def is_grounded_segment(candidate, source_text):
    candidate_compact = compact_grounding_text(candidate)
    source_compact = compact_grounding_text(source_text)

    if not candidate_compact or not source_compact:
        return False

    return (
        candidate_compact in source_compact
        or source_compact in candidate_compact
    )


def validate_result(result, interpretation):
    errors = []
    raw_text = interpretation["normalized_text"]

    for field in [
        "visible_text",
        "content_type",
        "title",
        "summary",
        "confidence",
        "explanation",
        "items",
        "needs_review",
    ]:
        if field not in result:
            errors.append(f"Missing field: {field}")

    if errors:
        return errors

    if not isinstance(result["visible_text"], str) or not normalize_text(result["visible_text"]):
        errors.append("visible_text must be a non-empty string.")

    if result["content_type"] not in CONTENT_TYPES:
        errors.append("content_type is outside the supported enum.")

    if not isinstance(result["title"], str) or not result["title"].strip():
        errors.append("title must be a non-empty string.")
    elif len(result["title"].strip()) > 80:
        errors.append("title exceeds 80 characters.")

    if not isinstance(result["summary"], str) or not result["summary"].strip():
        errors.append("summary must be a non-empty string.")
    elif len(result["summary"].strip()) > 200:
        errors.append("summary exceeds 200 characters.")

    if not isinstance(result["confidence"], (int, float)):
        errors.append("confidence must be numeric.")
    elif not 0 <= float(result["confidence"]) <= 1:
        errors.append("confidence must be between 0 and 1.")

    explanation = result["explanation"]
    if not isinstance(explanation, dict):
        errors.append("explanation must be an object.")
    else:
        if not isinstance(explanation.get("reasoning_summary"), str) or not explanation["reasoning_summary"].strip():
            errors.append("explanation.reasoning_summary is required.")
        if not isinstance(explanation.get("key_signals"), list):
            errors.append("explanation.key_signals must be a list.")

    if not isinstance(result["items"], list):
        errors.append("items must be a list.")
    if not isinstance(result["needs_review"], bool):
        errors.append("needs_review must be boolean.")

    expected_candidates = interpretation["suspected_type_candidates"]
    if (
        result["content_type"] != "generic"
        and expected_candidates
        and result["content_type"] not in expected_candidates
        and float(result["confidence"]) >= 0.7
    ):
        errors.append("content_type conflicts with interpretation candidates.")

    source_tokens = meaningful_tokens(raw_text)
    for index, item in enumerate(result.get("items", []), start=1):
        if not isinstance(item, dict):
            errors.append(f"item {index} must be an object.")
            continue

        title = str(item.get("title", "")).strip()
        kind = item.get("kind")
        priority = item.get("priority")
        source_span = str(item.get("source_span", "")).strip()

        if not title:
            errors.append(f"item {index} title is required.")
        if kind not in ITEM_KINDS:
            errors.append(f"item {index} kind is invalid.")
        if priority not in PRIORITIES:
            errors.append(f"item {index} priority is invalid.")
        if not source_span:
            errors.append(f"item {index} source_span is required.")

        if title:
            overlap = meaningful_tokens(title) & source_tokens
            grounded = (
                bool(overlap)
                or is_grounded_segment(title, raw_text)
                or is_grounded_segment(source_span, raw_text)
                or is_grounded_segment(title, source_span)
            )
            if not grounded and result["content_type"] in {
                "meeting_notes",
                "course_notice",
                "job_description",
            }:
                errors.append(f"item {index} title is not grounded in visible text.")

    return errors


def normalize_result(result, interpretation, attempts_used, history, mode):
    return {
        "content_type": result["content_type"],
        "title": result["title"].strip(),
        "summary": result["summary"].strip(),
        "confidence": round(float(result["confidence"]), 2),
        "explanation": {
            "reasoning_summary": result["explanation"]["reasoning_summary"].strip(),
            "key_signals": result["explanation"].get("key_signals", []),
        },
        "items": result.get("items", []),
        "needs_review": bool(result["needs_review"]),
        "raw_text": interpretation["normalized_text"],
        "interpretation": interpretation,
        "analysis_meta": {
            "mode": mode,
            "attempts_used": attempts_used,
            "reset_count": max(attempts_used - 1, 0),
            "failure_history": history,
        },
    }


def build_failure_result(interpretation, history, mode):
    summary = interpretation["normalized_text"][:200]
    return {
        "content_type": interpretation["suspected_type_candidates"][0]
        if interpretation["suspected_type_candidates"]
        else "generic",
        "title": "Needs manual review",
        "summary": summary or "AI parsing failed. Please review the screenshot manually.",
        "confidence": 0.0,
        "explanation": {
            "reasoning_summary": "The model could not produce a stable reminder-ready result.",
            "key_signals": ["Exceeded retry budget", "Returned invalid or drifting structure"],
        },
        "items": [],
        "needs_review": True,
        "raw_text": interpretation["normalized_text"],
        "interpretation": interpretation,
        "analysis_meta": {
            "mode": mode,
            "attempts_used": MAX_RESETS,
            "reset_count": MAX_RESETS,
            "failure_history": history,
        },
    }


def analyze_with_deepseek(image_data_url):
    failure_history = []
    last_failure = None
    last_interpretation = build_interpretation("")

    for attempt in range(1, MAX_RESETS + 1):
        messages = build_analysis_messages(
            image_data_url=image_data_url,
            attempt_number=attempt,
            failure_reason=last_failure,
        )

        try:
            raw_response = deepseek_chat(
                messages,
                max_tokens=2400,
                model=DEEPSEEK_MODEL,
                reasoning_effort="high",
            )
            result = extract_json_object(raw_response)
            interpretation = build_interpretation(result.get("visible_text", ""))
            last_interpretation = interpretation
            errors = validate_result(result, interpretation)
        except Exception as exc:
            errors = [str(exc)]
            result = None

        if not errors and result is not None:
            return normalize_result(
                result=result,
                interpretation=interpretation,
                attempts_used=attempt,
                history=failure_history,
                mode="deepseek",
            )

        failure_entry = {"attempt": attempt, "errors": errors}
        failure_history.append(failure_entry)
        last_failure = "; ".join(errors)

    return build_failure_result(
        interpretation=last_interpretation, history=failure_history, mode="deepseek"
    )


def heuristically_extract_items(raw_text, content_type):
    lines = [line.strip(" -*•\t") for line in raw_text.splitlines() if line.strip()]
    items = []

    for line in lines:
        if len(items) >= 5:
            break

        if re.match(r"^(\d+[\.\)]|todo|待办|action|follow up|作业|要求|职责)", line.lower()):
            items.append(
                {
                    "title": line[:80],
                    "kind": (
                        "study_task"
                        if content_type == "course_notice"
                        else "apply_task"
                        if content_type == "job_description"
                        else "todo"
                    ),
                    "due_date": None,
                    "priority": "medium",
                    "notes": "Heuristic fallback item. Review before saving.",
                    "source_span": line[:120],
                }
            )

    if not items and lines:
        items.append(
            {
                "title": lines[0][:80],
                "kind": "plan_step" if content_type in {"event_poster", "travel_guide"} else "todo",
                "due_date": None,
                "priority": "medium",
                "notes": "Heuristic fallback item. Review before saving.",
                "source_span": lines[0][:120],
            }
        )

    return items


def analyze_with_heuristics(raw_text):
    interpretation = build_interpretation(raw_text)
    content_type = interpretation["suspected_type_candidates"][0]
    items = heuristically_extract_items(interpretation["normalized_text"], content_type)

    return {
        "content_type": content_type,
        "title": interpretation["normalized_text"].splitlines()[0][:80]
        if interpretation["normalized_text"]
        else "Untitled screenshot",
        "summary": interpretation["normalized_text"][:200]
        or "Heuristic fallback produced a conservative summary.",
        "confidence": 0.35,
        "explanation": {
            "reasoning_summary": "This result was generated by local heuristics because no API key was configured.",
            "key_signals": interpretation["suspected_type_candidates"],
        },
        "items": items,
        "needs_review": True,
        "raw_text": interpretation["normalized_text"],
        "interpretation": interpretation,
        "analysis_meta": {
            "mode": "heuristic",
            "attempts_used": 1,
            "reset_count": 0,
            "failure_history": [],
        },
    }


@app.route("/")
def index():
    return render_template(
        "index.html",
        deepseek_configured=bool(DEEPSEEK_API_KEY),
        deepseek_model=DEEPSEEK_MODEL,
        max_resets=MAX_RESETS,
    )


@app.route("/analyze", methods=["POST"])
def analyze():
    file = request.files.get("screenshot")
    if not file or not file.filename:
        return jsonify({"error": "Please upload a screenshot image first."}), 400

    analysis_source = "vision_direct"

    if not file.mimetype or not file.mimetype.startswith("image/"):
        return jsonify({"error": "Only image uploads are supported."}), 400
    image_data_url = build_data_url(file)

    if not DEEPSEEK_API_KEY:
        return (
            jsonify(
                {
                    "error": (
                        "DEEPSEEK_API_KEY is missing. This demo now requires the DeepSeek "
                        "multimodal backend for direct image understanding."
                    )
                }
            ),
            400,
        )

    try:
        result = analyze_with_deepseek(image_data_url=image_data_url)
    except Exception as exc:
        return jsonify({"error": f"Analysis failed: {exc}"}), 502

    result["analysis_source"] = analysis_source
    result["vision_model"] = DEEPSEEK_MODEL
    return jsonify(result)


if __name__ == "__main__":
    app.run(debug=True)
