<div align="center">

# SunBoost

**Make your MacBook screen bright enough to read in direct sunlight. It unlocks the extra brightness your Mac keeps for HDR video.**

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-1f2937?style=flat-square&logo=apple&logoColor=white)
![XDR screens](https://img.shields.io/badge/screen-MacBook%20XDR-0ea5e9?style=flat-square)
![Free](https://img.shields.io/badge/price-free-34d399?style=flat-square)
![MIT](https://img.shields.io/badge/license-MIT-6366f1?style=flat-square)

</div>

## What it does

A MacBook Pro screen can get much brighter than its brightness slider allows. macOS keeps that extra light for HDR video. In sunlight, the glare on an anti-glare screen washes out what you are reading. SunBoost lets the whole screen use that extra light.

- **Up to about 4 times brighter** than the slider's maximum. On the M5 MacBook Pro it was built on, macOS reports a headroom of about 4x.
- **Whole screen, not just video.** Windows, text and the desktop all get brighter.
- **Never goes past what the screen can do.** SunBoost reads the live limit and stays under it, so bright parts do not turn flat white.
- **Optional shadow lift.** Raises dark areas and pure black so dark parts of the screen do not vanish in glare.
- **Turns itself off.** Press Ctrl-C and the screen is back to normal at once. It also stops if the Mac gets hot.
- **Free and private.** No account. It never connects to the internet.

## Install (3 minutes)

1. Press **⌘ Space**, type **Terminal**, press **Return**.
2. Paste these lines and press **Return**:

   ```bash
   git clone https://github.com/ma67-ex/SunBoost.git
   cd SunBoost
   ./build.sh
   ./build_app.sh
   ```

3. Wait until it says **Built SunBoost.app**. `build.sh` makes the command line tool, `build_app.sh` makes the app.

If macOS asks you to install the command line developer tools, click **Install**, wait for it to finish, then run `./build.sh` again.

## Use it

### The app

1. Run `open SunBoost.app` in the SunBoost folder. A window opens and a sun appears in the menu bar.
2. Click the big **sun** button. The screen gets brighter within a second. Click it again to stop.
3. Drag **Brightness boost**, or tap **Comfort**, **Sun** or **Glare**. **Lift dark areas** and **Lift black** keep dark parts visible in glare.
4. Pick an **Auto-off** time if you want it to switch itself off.

The window also shows how hot the Mac is and how much brightness the screen allows right now. Quitting the app puts the screen back to normal.

### The command line

1. In Terminal, in the SunBoost folder, run:

   ```bash
   ./sunboost
   ```

2. The screen gets brighter within a second. Leave Terminal open.
3. Press **Ctrl-C** to stop. The screen goes back to normal.

Other ways to run it:

| Command | What it does |
|---|---|
| `./sunboost --gain 3` | Less bright, less heat. 3 is a good middle. |
| `./sunboost --seconds 600` | Turns itself off after 10 minutes |
| `./sunboost --shadows 0.7 --floor 0.05` | Lifts dark areas and black so they stay visible in glare |
| `./sunboost --help` | Shows every option |

## How it works

Two small tricks, both with normal macOS calls.

1. **Open the headroom.** The screen only unlocks its extra brightness while something on it is drawing HDR. SunBoost draws one invisible HDR pixel in the corner, so macOS keeps HDR mode on.
2. **Scale everything.** SunBoost multiplies the screen's brightness table by the gain. Normal white becomes up to 4x white, and everything else scales with it.

Every two seconds it re-reads the live headroom and re-applies, so it keeps working after sleep or when you plug in a display.

## Safety

**4.0 is the safe maximum.** It is the limit macOS itself reports for this screen, so it stays inside the range the display is built for. SunBoost never goes above the live limit, even if you ask for more (`--gain 8` still stops at about 4). It changes no system files and no hardware settings.

Cautions:

- **Heat.** Full brightness in direct sun heats the Mac from both sides. Take breaks, keep the vents clear, and do not run it on a soft surface like a bed or a bag. SunBoost turns itself off if macOS reports serious heat, but that is a last resort, not a plan.
- **Battery.** It drains the battery fast. Plug in if you plan to use it for long.
- **Your eyes.** It is very bright. Stop it when you go indoors or when it gets dark. Do not use it at night.
- **Do not leave it running.** Press Ctrl-C when you are done. If Terminal closes or the app crashes, macOS puts the screen back to normal on its own.
- **Stuck bright?** Run `pkill sunboost`, or restart the Mac. Both restore the screen.
- **Not tested for long sessions.** Only short tests were run on one Mac. Treat long use as at your own risk and watch the temperature.
- **No warranty.** This is free software under the MIT License, provided as is.

## Things to know

- **Colours are not accurate.** Do not use it for photo, video or design work.
- **Above about 4.0 it does not help.** More gain than the screen allows only turns bright parts flat white, so SunBoost caps it.
- **Tested on one Mac.** An M5 MacBook Pro with the built-in Liquid Retina XDR screen. Other MacBook Pro models with the same screen should work. Screens without HDR headroom are refused with a message.
- **The app is not signed by Apple.** If macOS blocks it, right-click `SunBoost.app`, choose **Open**, then **Open** again.

## Privacy

Everything stays on your Mac. SunBoost never opens a network connection and writes no files.

## For developers

The engine is [Sources/Shared/Booster.swift](Sources/Shared/Booster.swift), shared by the command line tool (`Sources/CLI`) and the SwiftUI app (`Sources/App`). It uses only public APIs: a `CAMetalLayer` with `wantsExtendedDynamicRangeContent`, `NSScreen.maximumExtendedDynamicRangeColorComponentValue` for the live headroom, and `CGSetDisplayTransferByTable` for the brightness curve. The table API accepts values above 1.0. The formula API (`CGSetDisplayTransferByFormula`) silently clamps at 1.0, so do not use it. The drawing needs a real draw call each frame, or macOS never opens the headroom.

`./sunboost --selftest` checks the curve maths. `build.sh` runs it after building.

Free to use and change under the [MIT License](LICENSE). If it helps you, give it a ⭐.
