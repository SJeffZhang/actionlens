# ActionLensApp

Native macOS prototype for ActionLens.

## Current scope

- Capture a screenshot with macOS `screencapture -i`
- Or choose an existing image file
- Send the image directly to `deepseek-flash`
- Validate the structured JSON response with up to 5 retries
- Display title, summary, explanation, visible text, and reminder-ready items

## Run

```bash
cd "/Users/zhangshijie/Desktop/Project/Actionlens/actionlens/screenshot-to-task/ActionLensApp"
swift build --disable-sandbox
swift run --disable-sandbox ActionLensApp
```

You can also provide the API key through the UI. The prototype stores it in `UserDefaults`.

## Package as a real macOS app

To get a proper `.app` bundle that can appear in macOS privacy settings:

```bash
cd "/Users/zhangshijie/Desktop/Project/Actionlens/actionlens/screenshot-to-task/ActionLensApp"
bash scripts/package_app.sh
open "$HOME/Applications/ActionLens.app"
```

Then go to:

- `System Settings -> Privacy & Security -> Screen & System Audio Recording`

and enable `ActionLens`.

## Next steps

- Replace the manual capture button with a global shortcut flow
- Add menu bar mode
- Map validated items into Apple Reminders with EventKit
