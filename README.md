# LayerETA

**LayerETA shows which layer you are on and swaps layer with one click. You never host.**

Part of the ETA family with [LevelETA](https://github.com/Nielsen2211/LevelETA) and [GoldETA](https://github.com/Nielsen2211/GoldETA). Same look, and each works on its own.

![LayerETA](screenshots/layereta-window.png)

- **Your layer at a glance**: a small box that says *Layer A*, *Layer B* and so on
- **One button**: click the box to fold it out, then click **Swap layer**
- **No hosting**: you only ask for a swap, you never invite others
- **Sends nothing on its own**: your request is placed in your chat box, and you send it yourself with Enter
- **Cleans up after itself**: accepts the invite, waits for the move and leaves the group again

---

## How to use it

1. Join the layer channel once: `/join layer`
2. Target or mouse over any NPC, so LayerETA can read your layer
3. Click the box to fold it out, and click **Swap layer**
4. Press **Enter** to send the request that is waiting in your chat box
5. A host on another layer invites you. LayerETA accepts, and leaves the group 20 seconds after you have moved

Click the box again to fold it back. Drag it to move it.

## How it knows your layer

The game does not tell addons which layer you are on. LayerETA reads it from the id of the NPCs around you, the same way other layer addons do. It gives each layer in a zone a letter, so you see *Layer B* instead of a long number. The letters start over every day.

## Works with other layer addons

The request uses the same format as LayerSwap, so players who host with LayerSwap (and addons that speak the same format) can invite you. You do not need any of them installed.

## Commands

| Command | What it does |
|---|---|
| `/leta` | Show or hide the box |
| `/leta swap` | Same as the Swap layer button |
| `/leta lock` | Lock or unlock the position |
| `/leta leave <seconds>` | How long to stay in the group after the move (default 20) |
| `/leta da` or `/leta en` | Danish or English |

## Install

Get it from CurseForge, or download this repo and put the folder in `World of Warcraft/_forever_/Interface/AddOns/LayerETA`.

## License

MIT. The Inter font is under the SIL Open Font License, see `Fonts/LICENSE-Inter.txt`.
