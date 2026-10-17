# Mobile touch tests

Automated tests for the touch controls of the live web build
(https://marse337.github.io/iron-horizon/). Every target runs the same scenario
and checks real game values, not just screenshots. The game publishes those
values when the page is opened with `?test=1`; see `_publish_test_state` in
`scripts/game_manager.gd`.

| Target | What it is |
| :--- | :--- |
| `chrome-phone` | Your desktop Chrome emulating a Pixel 7 (landscape), with real multi-touch through DevTools |
| `chrome-tablet` | Desktop Chrome emulating a Galaxy Tab S4 |
| `webkit-iphone` | Playwright WebKit (Safari's engine) with an iPhone 14 profile |
| `webkit-ipad` | Playwright WebKit with an iPad Pro 11 profile |
| `android` | Real Chrome inside the Android emulator. It also sends real touchscreen taps and swipes through `adb` |

Apple's iOS Simulator only runs on macOS. WebKit is the closest you can get on
Windows; for real iPhones, use a cloud device service or a physical phone.

## Setup (once)

```powershell
cd tools\mobile-test
npm install
npx playwright install webkit
.\setup-android.ps1      # ~6 GB: JDK, Android SDK, emulator, Android 14 + Chrome image
```

## Run

```powershell
node touch-test.mjs chrome-phone          # or chrome-tablet / webkit-iphone / webkit-ipad
.\start-android.ps1                        # boots the phone emulator (-Tablet for the tablet)
node touch-test.mjs android
node touch-test.mjs chrome-phone http://localhost:8060/   # test a different URL
```

Each run prints PASS/FAIL per check. Screenshots and `report.json` go to
`results/<target>/`.

## What it checks

- **Loading and menus:** the game loads, and tapping START begins the wave.
- **Touch mode:** touch mode switches on after the first touch.
- **One-finger aiming:** a one-finger drag turns the turret by exactly the dragged distance and doesn't fire.
- **Holding FIRE:** holding FIRE fires, and the view doesn't move.
- **Two fingers:** aiming with a second finger while holding FIRE tracks the finger, with no jump. This is the bug that was reported.
- **Quick taps:** quick FIRE taps never move the view and each one fires. An instant tap fires the cannon.
- **Buttons:** SWAP, FLARE and SAM work, and pause/RESUME work by touch.
- **Portrait:** portrait shows the rotate-device prompt.
- **Android, real touchscreen:** swipe to aim, quick FIRE taps, and long-press FIRE.
