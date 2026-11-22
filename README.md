# LayerETA

**LayerETA swaps layer with one click. You never host.**

Part of the ETA family with [LevelETA](https://github.com/Nielsen2211/LevelETA) and [GoldETA](https://github.com/Nielsen2211/GoldETA). Same look, and each works on its own.

![LayerETA](screenshots/layereta-window.png)

## Blizzard's change of 20 November 2026

Since a hotfix on 20 November 2026, WoW Forever hides the realm from addons: the realm name is empty, the realm ID is 0, and the realm number inside every NPC's ID is scrambled (two NPCs side by side get different numbers). That number was the only way any addon could tell one layer from another. So since that day **no layer addon can see which layer you are on**, LayerSwap included, and nobody can ask for one layer in particular.

LayerETA 3.9 works with this, and talks to LayerSwap 1.14.45 hosts the way LayerSwap itself does:

- **No layer letters, no list of layers and no "Back to A"** while the game hides layers. If Blizzard shows them again, they come back by themselves.
- **Swap still works**: it moves you to another layer than the one you stand on. You don't need to target an NPC first.
- **Your request names no layer.** A LayerSwap host can't read its own layer either, and it skips a request that names one. LayerETA 3.8 still named one (read from the scrambled IDs), so hosts skipped it: that is fixed in 3.9.
- **10 swaps an hour**: the game moves a character at most ten times an hour. LayerETA counts them per character (also across a login), tells you when 3 are left, and once they are used up the button shows *Wait* with the time left.

## How a swap works now

1. Click the box to fold it out, then click **Swap**.
2. LayerETA looks up the players in your zone (the zone's map, then one class at a time, so it finds more of them) and sends your request straight to them, in the format LayerSwap uses, so players hosting with LayerSwap, Bulo or Simple Layer can invite you. Nothing goes into your chat or the layer channel.
3. A host invites you and LayerETA accepts.
4. **Moved?** When the game moves you to another layer it tells addons so (`SHARD_TRANSFER`). LayerETA counts one swap and leaves the group 4 seconds later.
5. **Not moved?** A move comes about a second after you join. If none has come after 3 seconds, LayerETA looks at how the game marks the host in your group: no mark means the host stands on your own layer, so LayerETA leaves and the swap isn't counted. Marked as on another layer means the game refused to move you, usually because your 10 swaps this hour are used.
6. No requests in combat or the first 6 seconds after it.

You can't pick a layer or go back to one you were on, and you can land on a layer you've been on before. That is the game's limit now, for every addon.

## Commands

- `/leta` show or hide the box
- `/leta swap` same as the Swap button
- `/leta lock` lock or unlock the position
- `/leta leave <seconds>` how long to stay in the group after the move
- `/leta debug` what the addon can see right now (swaps left, and when the game last moved you)
- `/leta da` or `/leta en` Danish or English
