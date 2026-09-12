# ActionLens

ActionLens is a macOS screenshot assistant that turns what you capture on screen into structured, reminder-ready output.

The current repository contains two layers:

- a **Web validation sandbox** used to iterate on the AI parsing pipeline
- a **native macOS prototype** with menu bar mode, screenshot capture, and global shortcut support

The long-term goal is:

`shortcut -> screenshot -> AI understanding -> user review -> Apple Reminders`

At the moment, the project already supports screenshot capture and structured result generation, but it **does not write to Apple Reminders yet**.

## What It Does Today

### Native macOS prototype

- runs as a **menu bar app**
- supports a global shortcut: `Control + Option + A`
- can trigger macOS interactive screenshot capture
- can also analyze an existing local image
- sends the image directly to `deepseek-flash`
- validates the model output against a fixed JSON contract
- retries automatically up to **5 times**
- shows:
  - content type
  - title
  - summary
  - explanation
  - visible text
  - reminder-ready items
  - retry / failure history

### Web validation sandbox

- upload a screenshot in the browser
- run the same DeepSeek-based structured extraction flow
- inspect output shape and retry behavior quickly during prompt iteration

The Web app is only a testing surface. The target product is the macOS app.

## Product Direction

ActionLens is designed for screenshot-heavy workflows such as:

- `课程通知 -> 学习安排`
- `会议截图 -> TODO`
- `活动海报 -> 参加计划`
- `招聘 JD -> 申请任务`
- `旅行攻略 -> itinerary`

The core idea is not just "read text from images", but to turn screenshots into **actionable next steps**.

## Current Architecture

### AI pipeline

The current implementation uses:

`image -> DeepSeek multimodal analysis -> schema validation -> retry loop -> structured result`

Key constraints in the current build:

- image-only input
- `deepseek-flash` as the vision model
- fixed JSON schema
- conservative extraction for generative scenes like posters and travel guides
- max retry / reset count: `5`

### Why there are two app surfaces

The repository started from a lightweight Flask demo and is now being evolved into a native macOS app.

- `app.py` + `templates/index.html`: fast iteration and prompt validation
- `ActionLensApp/`: native SwiftUI prototype for the actual product direction

## Repository Structure

```text
screenshot-to-task/
├── ActionLensApp/              # Native macOS prototype
│   ├── Package.swift
│   ├── README.md
│   ├── Sources/
│   │   ├── main.swift
│   │   ├── AppDelegate.swift
│   │   ├── AnalysisViewModel.swift
│   │   ├── ContentView.swift
│   │   ├── DeepSeekService.swift
│   │   ├── HotKeyManager.swift
│   │   └── Models.swift
│   └── scripts/
│       └── package_app.sh
├── app.py                      # Flask-based web validation sandbox
├── templates/
│   └── index.html              # Web demo UI
├── docs/
│   ├── feasibility.md          # Feasibility notes
│   ├── prd.md                  # Product requirements draft
│   └── vision-1.0.md           # Vision / AI pipeline notes
├── requirements.txt            # Python deps for the web sandbox
└── README.md
```

## Requirements

### For the macOS app prototype

- macOS
- Swift 5.10+
- Command Line Tools or Xcode
- DeepSeek API key

### For the web sandbox

- Python 3.9+
- `pip`
- DeepSeek API key

## Environment Variables

Create a local `.env` file for the web sandbox if needed:

```bash
DEEPSEEK_API_KEY=your_deepseek_api_key
DEEPSEEK_MODEL=deepseek-flash
```

For the macOS prototype, you can either:

- paste the API key into the app UI, or
- provide `DEEPSEEK_API_KEY` in the environment before launch

## Run the Native macOS App

### 1. Build and run from the terminal

```bash
cd "/Users/zhangshijie/Desktop/Project/Actionlens/actionlens/screenshot-to-task/ActionLensApp"
swift build --disable-sandbox
swift run --disable-sandbox ActionLensApp
```

Notes:

- the app runs as a **menu bar app**
- after launch, look at the macOS top menu bar for the ActionLens icon
- the terminal may look quiet after launch; that is expected for this app shape

### 2. Use the app

After launch:

1. Click the menu bar icon
2. Open `ActionLens`
3. Paste your DeepSeek API key into the app
4. Use one of these flows:
   - `Capture Screenshot`
   - `Choose Image...`
   - global shortcut: `Control + Option + A`

### 3. Package it as a real `.app`

If you want macOS to recognize it like a normal app in Privacy & Security settings:

```bash
cd "/Users/zhangshijie/Desktop/Project/Actionlens/actionlens/screenshot-to-task/ActionLensApp"
bash scripts/package_app.sh
open "$HOME/Applications/ActionLens.app"
```

This installs the app to:

[`~/Applications/ActionLens.app`](file:///Users/zhangshijie/Applications/ActionLens.app)

### 4. Grant screenshot-related permissions

Then go to:

- `System Settings -> Privacy & Security -> Screen & System Audio Recording`

and enable `ActionLens`.

If the app does not appear immediately, trigger screenshot capture once from the app, then revisit the settings page.

## Run the Web Validation Sandbox

```bash
cd "/Users/zhangshijie/Desktop/Project/Actionlens/actionlens/screenshot-to-task"
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python3 app.py
```

Then open:

```text
http://127.0.0.1:5000
```

If port `5000` is already occupied on your machine, run Flask on another port manually.

## What the Native Prototype Does Not Do Yet

The current app **does not yet**:

- write items into Apple Reminders
- request EventKit reminders permission
- provide editable reminder forms before save
- persist screenshot history
- support custom shortcut settings
- ship as a polished Xcode app project

So right now the app is best understood as:

`working native prototype + validated AI pipeline`

not the full finished product.

## Known Limitations

- The command-line-toolchain build flow is enough for prototyping, but a full Xcode app project will be better for shipping.
- DeepSeek output quality still depends on screenshot quality and scene type.
- Poster / travel scenes are inherently more generative and less deterministic than meeting or course screenshots.
- Apple Reminders integration is planned but not implemented in this repository yet.

## Development Notes

### Build artifacts

These folders are local artifacts and should not be treated as source:

- `ActionLensApp/.build/`
- `ActionLensApp/dist/`

### Current model

The active model direction in the prototype is:

- `deepseek-flash`

The project previously explored OCR-first routing, but the current implementation is centered on **direct multimodal image understanding**.

## Roadmap

Next major steps:

1. add EventKit integration
2. request Reminders permission
3. map validated items into `EKReminder`
4. add confirmation/edit flow before save
5. migrate from Swift Package prototype to a more complete app packaging workflow

## Documents

- [Product Requirements](file:///Users/zhangshijie/Desktop/Project/Actionlens/actionlens/screenshot-to-task/docs/prd.md)
- [Vision 1.0 Notes](file:///Users/zhangshijie/Desktop/Project/Actionlens/actionlens/screenshot-to-task/docs/vision-1.0.md)
- [Feasibility Notes](file:///Users/zhangshijie/Desktop/Project/Actionlens/actionlens/screenshot-to-task/docs/feasibility.md)
- [Native App README](file:///Users/zhangshijie/Desktop/Project/Actionlens/actionlens/screenshot-to-task/ActionLensApp/README.md)

## License / Origin

This repository started from the open-source project `screenshot-to-task` and is being evolved into `ActionLens`, a macOS screenshot-to-reminder product prototype.
