# LayerETA

**LayerETA swaps layer with one click.**

Part of the ETA family with [LevelETA](https://github.com/Nielsen2211/LevelETA) and [GoldETA](https://github.com/Nielsen2211/GoldETA). Same look, and each works on its own. All code in LayerETA is written for LayerETA. LayerETA uses its own hidden, password protected channel and its own message format.

![LayerETA](screenshots/layereta-window.png)

## How a swap works

In WoW you change layer by joining a group whose leader stands on another layer in the same zone. The game then moves you, and you can leave again.

1. Click the box to fold it out, then click **Swap**.
2. LayerETA sends a short request in its own hidden channel. Players who run LayerETA with **Host for others** on, and stand in your zone, can invite you. It also looks up the players in your zone with /who and asks them for an invite in a hidden whisper, so players who host with other layer addons can invite you. If you have joined the public layer channel (`/join layer`), the click also writes `inv` there, so anyone hosting in that channel can invite you too.
3. LayerETA accepts the first invite and tells the other hosts it is taken.
4. **Moved?** The game tells addons when it moves you. LayerETA counts the swap and leaves the group a few seconds later.
5. **Not moved?** After 3 seconds LayerETA looks at how the game marks the host in your group. No mark means the host stands on your layer: LayerETA leaves and skips that host for 15 minutes. Marked as on another layer means the game refused to move you, usually because your 10 swaps this hour are used.

Since 20 November 2026 WoW Forever hides which layer anyone is on, so no addon can show your layer or take you to a chosen one.

## Hosting

Turn on the **Host for others** switch in the box (or `/leta host`) to help other LayerETA users. You only host while you are alone, out of combat and outside instances, at most 5 invites in 10 minutes. A guest who stays more than 40 seconds is left behind when you leave the little group. Hosting is off by default.

## 10 swaps an hour

The game moves a character at most ten times an hour. LayerETA counts them per character (also across a login), tells you when few are left, and once they are used up the button shows *Wait* with the time left.

## Commands

- `/leta` show or hide the box
- `/leta swap` same as the Swap button
- `/leta host` host for others on or off
- `/leta channel` also write `inv` in the layer channel, on or off
- `/leta others` also ask other hosts in your zone, on or off
- `/leta lock` lock or unlock the position
- `/leta leave <seconds>` how long to stay in the group after the move
- `/leta debug` what the addon sees right now
- `/leta da` or `/leta en` Danish or English

## License

Copyright (c) 2026 Rasmus. All Rights Reserved. See [LICENSE](LICENSE). The Inter fonts are under the SIL Open Font License.
