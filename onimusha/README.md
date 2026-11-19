# Onimusha: Way of the Sword texture budget fix

A REFramework script that keeps the game's texture streaming budget at or above a minimum you choose. Status: **0.1.0, tested on one 8 GB card only. Nobody has tried it on a 4 to 6 GB card yet.**

## What it does

Onimusha runs on RE Engine. Its texture streamer has a fixed memory budget, `via.render.StreamingManager.UsableVRAMSize`, that follows the Texture Quality preset. When the textures in view need more than that, the engine unloads detail and the textures turn blurry. The script reads that budget every frame and raises it when it is below your minimum. It never lowers the game's own value, unless you tick "Set exactly". It changes nothing on disk except its own settings file.

What was seen on the test machine (RTX 5060 Laptop 8 GB, game 1.0.1.0, REFramework nightly 01441):

| Texture Quality | Budget the game picked |
|---|---|
| The preset the game started on (name not recorded) | 1800 MiB |
| Medium | 1000 MiB |

- Lowering the budget by hand to 300 MiB, and then to 64 MiB, made the game drop textures within seconds, and they looked blurry.
- Raising it again brought the detail back.
- The game does not overwrite a value you set. It does reset it during some loads (it dipped to 1000 MiB for two seconds at one), and the script puts it back on the next frame.
- On that card, in the scene I tested, the texture memory in use peaked at about 1.6 GB on the highest preset, below the 1800 MiB budget. So I did **not** see blur in normal play on 8 GB. The script is aimed at cards where the preset's budget is below what a scene needs.

Not tested: a 4 or 6 GB card, the other presets, other scenes, the VRAM safety cap below.

## Install

1. Install [REFramework](https://github.com/praydog/REFramework-nightly/releases) for this game. The official release does not include this game; the nightly `REFramework.zip` worked. Put its `dinput8.dll` next to `OnimushaWotS.exe`.
2. Copy `reframework\autorun\onimusha_texture_fix.lua` from this download into the game's `reframework\autorun\` folder.
3. Start the game. Press **Insert** to open REFramework, open **Texture budget fix**.

The default is a 2048 MiB minimum, switched on. Settings are saved in `reframework\data\OnimushaTextureFix.json`. To remove it, delete the Lua file.

## Settings

- **Enabled.** Turns the script on or off.
- **Minimum texture budget (MiB).** The budget is raised to this value if the game's own is lower. A bigger number uses more VRAM.
- **Set exactly (can lower).** Forces the value up or down. For testing only; at a small value everything turns blurry. Leave it off for play.

The panel also shows the current budget, the texture memory in use and the number of loaded textures.

## VRAM safety cap

On a card with little VRAM, a budget bigger than what is free could crash the game. The script reads the VRAM the renderer reports (`Renderer.get_VramSize64`) and does not push the budget closer than 1536 MiB to it. If the cap applies, the panel says so, and your slider value is not changed. This code was written after the test and has not been run on a small card.

## If something goes wrong

- The game won't start or crashes: delete `dinput8.dll`. The game's protection may block REFramework on some builds.
- Everything is blurry: untick "Set exactly", or delete `reframework\data\OnimushaTextureFix.json`.
- No "Texture budget fix" panel: check the REFramework log in the game folder for a Lua error and open an issue with it.

## How it was found

The budget names come from the game's own type information: `StreamingVRAMSizeLow/High/Highest`, `VRAMGuardSize` and `UsableVRAMSize` appear in the exe and in REFramework's object dump. No launch arguments or ini keys for them were found in the exe.
