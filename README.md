# My Hunt Report

A post-quest combat report for Monster Hunter Wilds, built on [REFramework](https://github.com/praydog/REFramework). It records only your own hunter and opens the report when the quest ends. Other hunters are never tracked or shown.

## What the report shows

- **Damage breakdown** as shares of your total: physical, elemental, fixed, and status.
- **Stat tiles**: combat DPS (damage over the time you were actually fighting), crit rate, negative-crit rate (shown only when a negative crit happened), average attack (your attack power at the moment each hit landed, with skills and buffs applied), average hitzone, and one average elemental hitzone tile per element you used.
- **Skill uptime**: how much of your damage each equipped skill was active for, weighted by motion value and hitzone. Burst is split into its stages and Weakness Exploit gets a separate row for hits on wounds. Hunting Horn melodies and weapon buffs (Dual Blades Demon Boost, Long Sword red Spirit Gauge, Switch Axe Amped State and Power Axe, Charge Blade Sword Boost, Element Boost and Power Axe, Insect Glaive Triple Up) get rows too; buffs that only work in one weapon mode are measured against the hits of that mode.
- **Damage by motion**: every move by name, including shells, ammo and coatings, slinger shots, mounted attacks, Hunting Horn melodies and echo bubbles, and wound break damage. Kinsect damage is counted in the row of the move that sent the kinsect.
- **Skill damage**: the share of your damage that came from Flayer, Element Convert, blast, poison, and set bonuses such as Violent Strike, Mirror Blade, Incandescent Torrent, Rathalos's Flare, Lagiacrus's Fury, and Dark Knight. Your own Palico's share of the damage is shown at the end of the line; other players' Palicos are never counted.
- **Monsters** with tempered, arch-tempered, and frenzied variants named.
- **History** of every finished quest, opened from the report window. A filter window narrows the list by weapon, quest level, monster, and variant (normal, tempered, arch-tempered, frenzied); several values can be picked at once, and each active filter shows as a chip that removes it when clicked. Training-area sessions produce a report too but are not saved.

Works in solo and multiplayer.

## Controls and settings

Settings live in the REFramework menu under **My Hunt Report**.

- **F7** toggles the report window (rebindable).
- The mouse side buttons go back and forward between the live report, the history list, and a past report, like a browser. They act only while the mouse is over the report or filter window.
- Show the report automatically when a quest ends, and close it when the next quest starts or when the quest result screen closes.
- Show the Windows mouse cursor while the mouse is over the report or filter window, so the buttons are easy to click with the REFramework menu closed (can be turned off).
- Font size, and language (automatic, English, or Korean).
- HDR color correction (automatic, on, or off), so the report colors look the same with HDR on as in SDR.
- Record Flayer, Element Convert, wound-break, and poison damage, which can be turned off (turning it off needs a game restart).
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

The report window uses the [Pretendard](https://github.com/orioncactus/pretendard) font by Kil Hyung-jin, licensed under the SIL Open Font License 1.1 (see `reframework/fonts/MyHuntReport/LICENSE-Pretendard.txt`). For game languages that font cannot draw, such as Chinese or Japanese, the report uses REFramework's default font instead.

## License

MIT. See [LICENSE](LICENSE).
