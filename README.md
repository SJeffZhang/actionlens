# Screenshot to Task Tool ✦

Upload any screenshot — Slack message, whiteboard, document — and get structured, actionable tasks extracted by multimodal AI instantly.

## 🧠 How It Works

1. Upload a screenshot (PNG, JPG, JPEG)
2. Image gets converted to base64 and sent to Groq Vision AI
3. Llama 4 Scout reads and understands the image
4. Extracts all actionable tasks as structured JSON
5. Tasks are saved to Supabase database
6. Displayed as interactive checkboxes

## 🛠️ Tech Stack

- **Flask** — Python web framework
- **Groq API** — Llama 4 Scout multimodal Vision AI
- **Supabase** — PostgreSQL database
- **Python dotenv** — environment variable management

## 🚀 Getting Started

### 1. Clone the repo
```
git clone https://github.com/Sachi1312/screenshot-to-task.git
cd screenshot-to-task
```

### 2. Install dependencies
```
pip install flask groq supabase python-dotenv
```

### 3. Create `.env` file
```
GROQ_API_KEY=your_groq_api_key
SUPABASE_URL=your_supabase_url
SUPABASE_KEY=your_supabase_service_role_key
```

### 4. Run the app
```
python app.py
```

Open `http://127.0.0.1:5000` in your browser.

## 📁 Project Structure
```
screenshot-to-task/
├── app.py              # Flask backend + Groq Vision AI
├── templates/
│   └── index.html      # Frontend UI
├── .env                # API keys (never commit this!)
├── .gitignore
└── README.md
```

## 💡 Core Concept

This project uses **Multimodal AI (Vision)** — models that can both see images and understand text. This is one of the fastest growing capabilities in enterprise software, used in tools like Google Lens, ChatGPT Vision, and more.
```

Then push it:
```
git add README.md
git commit -m "Add README"
git push