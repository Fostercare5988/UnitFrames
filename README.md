# UnitFrames

Blizzard's player, target and pet frames, made better for World of Warcraft
1.12.1: auras, cast bars and energy ticks.

## Features

- **Class colours** behind your, your target's and your party's names.
- **Exact numbers:** health and mana on the player and target frames.
- **Target cast bar** under the target frame, grey when it cannot be interrupted;
  your own cast bar moves with Ctrl+Shift.
- **Target of target** redrawn only when what it shows changes.
- **Raid marks** on the target's portrait, solo marks too.
- **Energy ticks** and the five-second mana rule on your power bar.
- **Buffs and debuffs** under the player and target frames, with sweeps,
  countdowns and dispel colours.
- **The top-right buffs, debuffs and weapon enchants**, each area moved with
  Ctrl+Shift; the poison on each weapon, main hand left; the time left counts
  down on the icon.
- **Borders** on buffs, debuffs and weapon enchants.

Every feature has a switch on its page in AddOn Options; `/ffr` opens it.
Ctrl+Shift shows a handle on every frame it places. The watched auras are their
own addon, [Auras](https://github.com/Fostercare5988/Auras): with it, a watched
aura leaves the rows and the top right.

## Requirements

WoW 1.12.1 (build 5875) with **[ClassicAPI](https://github.com/brues-code/ClassicAPI)**, **SuperWoW** and **NamPower**
loaded. The energy ticks leave out power that comes from spells (NamPower's
`SPELL_ENERGIZE_ON_SELF`).

## Installation

Download `UnitFrames.zip` from the
[latest release](https://github.com/Fostercare5988/UnitFrames/releases/latest),
extract it into `Interface/AddOns` and enable it in the game's AddOns list. The
folder must contain `Interface/AddOns/UnitFrames/UnitFrames.toc`.
It replaces the unit-frame features of Tweaks before 1.0.0.
