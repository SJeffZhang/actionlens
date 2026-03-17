from flask import Flask, request, jsonify, render_template
from groq import Groq
from supabase import create_client
from dotenv import load_dotenv
import os
import base64
import json

# ── Load environment variables from .env file ──
load_dotenv()

# ── Why? We initialize all our services once at the top ──
# so they're ready to use anywhere in the app
app = Flask(__name__)
groq_client = Groq(api_key=os.getenv("GROQ_API_KEY"))
supabase = create_client(os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY"))


# ── This converts an image file to base64 text ──
# Why? AI APIs can't receive raw image files over HTTP
# Base64 encodes binary image data into plain text the API understands
def encode_image(image_file):
    return base64.b64encode(image_file.read()).decode("utf-8")


# ── This sends the image to Groq Vision AI ──
# and asks it to extract tasks from the screenshot
def extract_tasks_from_image(base64_image, filename):
    response = groq_client.chat.completions.create(
        model="meta-llama/llama-4-scout-17b-16e-instruct",
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        # Why two content blocks? Because multimodal AI
                        # accepts both image AND text in the same message
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{base64_image}"
                        }
                    },
                    {
                        "type": "text",
                        "text": """Look at this screenshot carefully.
                        Extract all actionable tasks, to-dos, or action items from it.
                        Return ONLY a valid JSON object in this exact format, nothing else:
                        {
                            "raw_text": "everything you can read in the image",
                            "tasks": ["task 1", "task 2", "task 3"]
                        }
                        If no tasks found, return empty list for tasks."""
                    }
                ]
            }
        ],
        max_tokens=1000
    )
    return response.choices[0].message.content


# ── Main route: handles image upload ──
@app.route("/upload", methods=["POST"])
def upload():
    # Why check for file? Always validate input before processing
    if "screenshot" not in request.files:
        return jsonify({"error": "No file uploaded"}), 400

    file = request.files["screenshot"]
    if file.filename == "":
        return jsonify({"error": "No file selected"}), 400

    # Step 1: Convert image to base64
    base64_image = encode_image(file)

    # Step 2: Send to Groq Vision AI
    raw_response = extract_tasks_from_image(base64_image, file.filename)

    # Step 3: Parse the JSON response from AI
    # Why try/except? AI might return slightly malformed JSON sometimes
    try:
        # Clean up response in case AI adds extra text
        clean = raw_response.strip()
        if "```json" in clean:
            clean = clean.split("```json")[1].split("```")[0].strip()
        elif "```" in clean:
            clean = clean.split("```")[1].split("```")[0].strip()
        result = json.loads(clean)
    except Exception as e:
        result = {"raw_text": raw_response, "tasks": []}

    # Step 4: Save to Supabase
    supabase.table("tasks").insert({
        "screenshot_name": file.filename,
        "raw_text": result.get("raw_text", ""),
        "tasks": result.get("tasks", [])
    }).execute()

    return jsonify(result)


# ── Home route: serves the HTML page ──
@app.route("/")
def index():
    return render_template("index.html")


if __name__ == "__main__":
    app.run(debug=True)

