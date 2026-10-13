# ZBundle

**Every one of Xep's Z mods as one mod**, for Black Ops II and Black Ops III Zombies

by Xep

[![Support the mod on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/F6L1285ROA)
[![Support the mod on Patreon](https://img.shields.io/badge/Patreon-Xeptix-F96854?logo=patreon&logoColor=white)](https://www.patreon.com/Xeptix)
[![Join the Discord](https://img.shields.io/badge/Discord-Join-5865F2?logo=discord&logoColor=white)](https://discord.gg/RE85HRwYZZ)

| | What it does | Source |
|---|---|---|
| **ZPause** | A synced co-op pause: any player can pause, any player can unpause | [ZPause](https://github.com/Xeptix/ZPause) · [ZPauseT7](https://github.com/Xeptix/ZPauseT7) |
| **ZShare** | Trade guns, hand over points, and give away or pay for a box hit, a Pack-a-Punch or a perk | [ZShare](https://github.com/Xeptix/ZShare) · [ZShareT7](https://github.com/Xeptix/ZShareT7) |
| **ZStats** | A live stats HUD, per-round MVP callouts and a fuller game-over summary | [ZStats](https://github.com/Xeptix/ZStats) · [ZStatsT7](https://github.com/Xeptix/ZStatsT7) |
| **ZTweaks** | Match flow, loadouts, players, zombies, power-ups and characters, all configurable | [ZTweaks](https://github.com/Xeptix/ZTweaks) · [ZTweaksT7](https://github.com/Xeptix/ZTweaksT7) |

Black Ops III runs one mod at a time, and so does Plutonium's Mods menu for Black Ops II, so
running them separately means choosing one. ZBundle is all of them in one mod: pick it and
they are all in the same game.

Everything each mod's own page says applies here unchanged - the same settings, with the
same names, defaults and meanings, and the same controls. They were built to sit side by
side, so none of them can disturb another.

---

## One settings screen for all of them

The lobby button - and, on Black Ops II's mod version and Black Ops III, the row on the
game's own pause menu - opens **one screen carrying every mod**: a strip of categories across
the top with each mod's own beside the others, the settings under them in a list that
scrolls, and a panel on the right saying what each one does, what it defaults to, when a
change takes and who it is for.

- **MODS** at the front switches any of them on or off without leaving the game. It is only
  there when there is more than one mod on the screen, which in a bundle there always is.
- **CHANGED** at the end lists everything moved off its default, across all of them, with
  the mod that owns each row named in front of it.
- **RESET TAB**, **RANDOMIZE** and **RESET ALL** along the bottom, each asking first.

Each mod still keeps its own settings in its own place. The screen is a shared shell rather
than a shared store, so nothing any one of them saves can disturb another.

---

## Which one

### Black Ops III, from the Steam Workshop

**[Subscribe to ZBundle on the Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3802815997)**
-- it is in
[Xep's Black Ops III Zombies collection](https://steamcommunity.com/workshop/filedetails/?id=3802560637)
with [ZPause](https://steamcommunity.com/sharedfiles/filedetails/?id=3800204505),
[ZShare](https://steamcommunity.com/sharedfiles/filedetails/?id=3802815009),
[ZStats](https://steamcommunity.com/sharedfiles/filedetails/?id=3814909842) and
[ZTweaks](https://steamcommunity.com/sharedfiles/filedetails/?id=3814908789) -- then pick
ZBundle from the Mods menu. Nothing to copy. This carries all four.

All four settings menus are in every language the game ships, each player reading their own.
The translations are made by AI and may contain mistakes. If you find one, please tell Xep
on the Discord linked at the top of this page: the mod, the language, and the line as it
reads in the game.

**Settings saved in the lobby menu belong to ZBundle.** Every Workshop mod keeps save files
of its own, so a setting saved in ZPause on its own does not carry into ZBundle, or back.

### Black Ops II, on Plutonium

`ZBundle T6`, and it carries all four. The ZPause installer in the Treyarch bundle download
offers it when you install Black Ops II - or copy the `Plutonium` folder from the zip over
yours. It lands in `storage\t6\mods\zm_zbundle`, beside `zm_pause` and `zm_share`, and does
nothing until you pick **zm_zbundle** in the in-game Mods menu. Every mod's lobby button
comes with it, in one merged menu file.

### Black Ops III, on BOIII or Ezz BOIII

`ZBundle T7 BOIII`, and it carries all four. These clients run every loose script in the
folder, so there is no mod slot to share and this is the four in one download. Copy the
`Black Ops III` folder from the zip over your game folder: the scripts go in
`boiii\custom_scripts`, and the lobby menus in `boiii\ui_scripts`. Ezz BOIII clears its
AppData folder every time it starts, so on Ezz BOIII use the game folder only; the `AppData`
folder in the zip is for the original BOIII.

Each mod's own page says what its loose version does differently from its Workshop one.

### Black Ops III, on T7x

`ZBundle T7x`, and it carries all four, for the same reason. Copy the `t7x` folder from the
zip over your game folder: the compiled scripts go in `t7x\custom_scripts`, and the lobby
menus in `t7x\ui_scripts`.

---

## Credits

- **Xep** - ZPause, ZShare, ZStats and ZTweaks
- **D3V Team** - L3akMod, which the Workshop lobby menu is built with
