# Platewise

A macOS meal planner with **Snap & Cook**: photograph a dish and Apple Intelligence identifies it on-device,
writes the full recipe (ingredients, method, nutrition, allergy warnings), and Platewise links real YouTube tutorials.
No API keys, no cost, photos never leave the Mac.

## Features
- **Snap & Cook**: camera, file, drag-and-drop or paste a photo. Apple's on-device foundation model (vision, macOS 27+)
  returns the top 3 likely dishes with confidence, then a full recipe on demand. "Make it…" rewrites it healthier,
  vegetarian, quicker, etc. The app double-checks the small model's diet labels against the ingredients.
- **YouTube videos** from the YouTube Data API (optional key); otherwise a YouTube search link. Links never come from the AI.
- **Weekly meal plan**: drag recipes onto days × breakfast/lunch/dinner/snack, per-day calorie estimate.
- **Recipe library**: search, favorites, manual add/edit (ingredients parsed from lines like `1 1/2 cups flour, sifted`), serving scaling.
- **Grocery list**: built from the week's plan, quantities merged, grouped by aisle, checkboxes, copy as text.
- **Preferences**: diets, allergies (warned in every recipe) and dislikes, all passed to the model.

## Build
Needs macOS 14+ and the Xcode Command Line Tools with the macOS 27 SDK (for the Apple Intelligence helper).

```bash
./Scripts/make-signing.sh   # once: stable local signing so camera/Keychain permissions survive rebuilds
./build.sh                  # → build/Platewise.app
./package.sh                # → dist/Platewise-1.0.pkg / .dmg / .zip + How to Install.txt
```

**Why a helper?** Image input to Apple's model is new in the macOS 27 SDK, but the Command Line Tools' macOS 27 SDK
can't build SwiftUI (no SwiftUI macro plugin). So the UI builds against the 26.5 SDK, and `Helper/PlatewiseAI.swift` is
compiled separately against the 27 SDK into `Platewise.app/Contents/MacOS/platewise-ai`. The app runs it with a command
(`status`, `identify`, `recipe`) and JSON on stdin, and reads JSON back. Schemas use `DynamicGenerationSchema` (no
`@Generable` macro, whose plugin also isn't in the Command Line Tools).

Data: `~/Library/Application Support/Platewise/library.json` + `Photos/`. Optional YouTube key: login Keychain
(service `local.platewise.Platewise`).

Developer aids (run `build/Platewise.app/Contents/MacOS/Platewise` with):
- `PLATEWISE_SNAPSHOT=/tmp/shots`: writes a PNG of each section and quits.
- `PLATEWISE_SELFTEST=/tmp/report.json PLATEWISE_SELFTEST_IMAGE=photo.jpg` (or `PLATEWISE_SELFTEST_DISH="Chicken Karahi"`):
  runs the live pipeline and writes a report.

## Source map
| File | What |
|---|---|
| `Helper/PlatewiseAI.swift` | Apple Intelligence helper: on-device model, image input, generation schemas |
| `AppleAI.swift` | Runs the helper, availability status, error mapping |
| `ChefAI.swift` | Prompts, confidence normalisation, recipe tidy-up (diet-flag checks) |
| `YouTube.swift` | YouTube Data API search with search-link fallback |
| `ScanView.swift` | Snap & Cook flow (`ScanModel` state machine) |
| `RecipeDetailView.swift` | Recipe page: scaling, warnings, nutrition, videos, plan/grocery actions |
| `PlannerView.swift`, `RecipesView.swift`, `GroceryView.swift`, `SettingsView.swift` | The other sections |
| `Store.swift`, `Models.swift` | JSON persistence, plan/grocery logic, ingredient parsing |
| `Camera.swift` | AVFoundation still capture |
