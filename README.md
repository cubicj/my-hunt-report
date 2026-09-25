# My Hunt Report

A post-quest combat report for Monster Hunter Wilds, built on [REFramework](https://github.com/praydog/REFramework). It records only your own hunter and opens the report when the quest ends. Other hunters are never tracked or shown.

## What the report shows

- **Damage breakdown** as shares of your total: physical, elemental, fixed, and status.
- **Stat tiles**: combat DPS (damage over the time you were actually fighting), crit and negative-crit rate, average hitzone, and one average elemental hitzone tile per element you used.
- **Skill uptime**: how much of your damage each equipped skill was active for, weighted by motion value and hitzone. Burst is split into its stages and Weakness Exploit gets a separate row for hits on wounds.
- **Damage by motion**: every move by name, including shells, ammo and coatings, kinsect hits, slinger shots, mounted attacks, Hunting Horn melodies and echo bubbles, and status procs (blast, poison, Flayer, Element Convert). Set-bonus damage such as Violent Strike, Mirror Blade, Incandescent Torrent, Rathalos's Flare, Lagiacrus's Fury, and Dark Knight is listed separately.
- **Monsters** with tempered, arch-tempered, and frenzied variants named.
- **History** of every finished quest, opened from the report window. Training-area sessions produce a report too but are not saved.

Works in solo and multiplayer.

## Controls and settings

Settings live in the REFramework menu under **My Hunt Report**.

- **F7** toggles the report window (rebindable).
- Show the report automatically when a quest ends, and close it when the next quest starts.
- Font size, and language (automatic, English, or Korean).
- Delete all history, with a confirmation step.
- Developer Mode, which adds diagnostic lines to the report and the REFramework log.

Data is stored under `reframework/data/MyHuntReport/` in the game folder: `settings.json` and `history.jsonl`.

## Installation

1. Install [REFramework](https://www.nexusmods.com/monsterhunterwilds/mods/93).
2. Install with Fluffy Mod Manager, or extract the archive into the game folder so that `reframework/autorun/my_hunt_report.lua` exists.

## Development

The Lua modules are under `reframework/autorun/MyHuntReport/`. Unit tests run without the game:

```
lua5.4 tests/run.lua
```

## Credits

Inspired by [Skill Uptime Tracker](https://www.nexusmods.com/monsterhunterwilds/mods/3249) by JuIianMH. This mod was written from scratch and reuses no code from other projects.

The report window uses the [Pretendard](https://github.com/orioncactus/pretendard) font by Kil Hyung-jin, licensed under the SIL Open Font License 1.1 (see `reframework/fonts/MyHuntReport/LICENSE-Pretendard.txt`).

## License

MIT. See [LICENSE](LICENSE).
