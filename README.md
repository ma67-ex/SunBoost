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
   ```

3. Wait until it says **Built ./sunboost**.

If macOS asks you to install the command line developer tools, click **Install**, wait for it to finish, then run `./build.sh` again.

## Use it

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

## Things to know

- **Heat and battery.** Running near full brightness uses a lot of power and warms the Mac. Expect the battery to drain fast. macOS may dim the screen on its own when it gets hot, and SunBoost switches itself off if the Mac reports serious heat. These were not measured over long sessions, only in short tests.
- **Colours are not accurate.** Do not use it for photo, video or design work.
- **Above about 4.0 it does not help.** More gain than the screen allows only turns bright parts flat white, so SunBoost caps it.
- **Tested on one Mac.** An M5 MacBook Pro with the built-in Liquid Retina XDR screen. Other MacBook Pro models with the same screen should work. Screens without HDR headroom are refused with a message.
- **It is a command line tool.** There is no menu bar button yet.

## Privacy

Everything stays on your Mac. SunBoost never opens a network connection and writes no files.

## For developers

One file, [sunboost.swift](sunboost.swift). It uses only public APIs: a `CAMetalLayer` with `wantsExtendedDynamicRangeContent`, `NSScreen.maximumExtendedDynamicRangeColorComponentValue` for the live headroom, and `CGSetDisplayTransferByTable` for the brightness curve. The table API accepts values above 1.0. The formula API (`CGSetDisplayTransferByFormula`) silently clamps at 1.0, so do not use it. The drawing needs a real draw call each frame, or macOS never opens the headroom.

`./sunboost --selftest` checks the curve maths. `build.sh` runs it after building.

Free to use and change under the [MIT License](LICENSE). If it helps you, give it a ⭐.
