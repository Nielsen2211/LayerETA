# LayerETA

**LayerETA swaps layer with one click. You never host.**

Part of the ETA family with [LevelETA](https://github.com/Nielsen2211/LevelETA) and [GoldETA](https://github.com/Nielsen2211/GoldETA). Same look, and each works on its own.

![LayerETA](screenshots/layereta-window.png)

## Blizzard's change of 20 November 2026

Since a hotfix on 20 November 2026, WoW Forever hides the realm from addons: where the game used to give the realm name or ID, it now gives an empty name or 0. That realm ID inside the NPCs' IDs was the only way any addon could tell one layer from another. So since that day **no layer addon can see which layer you are on**, LayerSwap included, and nobody can ask for one layer in particular.

LayerETA 3.8 works with this:

- **No layer letters, no list of layers and no "Back to A"** while the game hides layers. If Blizzard shows them again, they come back by themselves.
- **Swap still works**: it moves you to another layer than the one you stand on. You don't need to target an NPC first.
- **10 swaps an hour**: the game moves a character at most ten times an hour. LayerETA counts them per character (also across a login), tells you when 3 are left, and once they are used up the button shows *Wait* with the time left.

## How a swap works now

1. Click the box to fold it out, then click **Swap**.
2. LayerETA looks up the players in your zone and sends your request straight to them, in the format LayerSwap uses, so players hosting with LayerSwap, Bulo or Simple Layer can invite you. Nothing goes into your chat or the layer channel.
3. A host invites you and LayerETA accepts.
4. **Moved?** When the game moves you to another layer it tells addons so (`SHARD_TRANSFER`). LayerETA counts one swap and leaves the group 4 seconds later.
5. **Not moved?** Hosts can't see layers either, so now and then a host on your own layer invites you. If the game hasn't moved you within 8 seconds, LayerETA leaves the group, tells you, and that swap isn't counted.

You can't pick a layer or go back to one you were on, and you can land on a layer you've been on before. That is the game's limit now, for every addon.

## Commands

- `/leta` show or hide the box
- `/leta swap` same as the Swap button
- `/leta lock` lock or unlock the position
- `/leta leave <seconds>` how long to stay in the group after the move
- `/leta debug` what the addon can see right now (swaps left, and when the game last moved you)
- `/leta da` or `/leta en` Danish or English
