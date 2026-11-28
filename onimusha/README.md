# Onimusha: Way of the Sword texture budget fix

A REFramework script for blurry textures on low-VRAM graphics cards. Status: **0.2.0. It sharpened the textures on a test machine where an 8 GB card was made to report 4 GB. It has not been run on a real 4 GB card yet.**

## What causes the blur

Onimusha runs on RE Engine. Its texture streamer (`via.render.StreamingManager`) has a value called `VramBudgetLimitResolution`, a limit on texture resolution. The game raises it when it runs short of VRAM.

With the card reporting 3283 MiB of usable VRAM, as the 4 GB users' numbers indicate, on the Medium preset:

| | Game alone (limit 5) | With 0.2.0 (limit held at 3) |
|---|---|---|
| Textures use | 207 MiB | 659 MiB |
| Textures loaded | 697 | 1755 |
| Whole renderer | 3700 MiB | 4200 MiB |
| Look | blurry | sharper |

The two columns were read at different moments of one test session, so the numbers are not a controlled comparison.

## What the script does

- **Holds the resolution limit** at or below your maximum (default 3). A lower value of the game's own is left alone.
- **Raises the texture budget** (`UsableVRAMSize`) to your minimum (default 2048 MiB) when the game's own is lower. On its own this did **not** fix the blur.

It changes nothing on disk except its own settings and report files.

## The price

Sharper textures need more VRAM. In the test the renderer used about 900 MiB more than the card was said to have. The test card really had 8 GB, so nothing happened. **A real 4 GB card may stutter or crash.** If it does, raise the maximum to 4, or untick the fix, and please report it. Lowering other graphics settings or the render resolution should free VRAM; that is not tested.

## Install

1. Install [REFramework](https://github.com/praydog/REFramework-nightly/releases) for this game. The official release does not include this game; the nightly `REFramework.zip` worked. Put its `dinput8.dll` next to `OnimushaWotS.exe`.
2. Copy `reframework\autorun\onimusha_texture_fix.lua` from this download into the game's `reframework\autorun\` folder.
3. Start the game. Press **Insert** to open REFramework, open **Texture budget fix**.

Settings are saved in `reframework\data\OnimushaTextureFix.json`. To remove the mod, delete the Lua file.

## Settings

- **Enabled.** Turns the whole script on or off.
- **Fix blurry textures (limit).** On by default.
- **Highest resolution limit allowed.** Default 3. Lower is sharper and uses more VRAM. 3 is the value tested with this version.
- **Minimum texture budget (MiB).** The budget is raised to this value if the game's own is lower.
- **Set exactly (can lower).** For testing only; at a small value everything turns blurry.

## VRAM safety cap

The script does not push the texture **budget** closer than 1536 MiB to the VRAM the renderer reports (`Renderer.get_VramSize64`). The cap does not apply to the resolution limit.

## Reporting a problem

Press **Save report**. It writes `reframework\data\OnimushaTextureReport.txt`. Send that file with your card, your Texture Quality preset and what you see.

## If something goes wrong

- The game won't start or crashes: delete `dinput8.dll`. The game's protection may block REFramework on some builds.
- Stutter or crashes after installing the script: untick **Fix blurry textures (limit)**, or delete the Lua file.
- No "Texture budget fix" panel: check the REFramework log in the game folder for a Lua error and open an issue with it.

## Tested on

RTX 5060 Laptop (8 GB), game 1.0.1.0, REFramework nightly 01441. The 4 GB case was simulated by changing what DXGI reports to the game; no memory was actually taken away.
