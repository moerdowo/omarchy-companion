# Bundled pets

Three ship with the plugin. Pick one from **Who stands there** in the bar
menu, or with `omarchy-shell omarchief pet <id>` — nothing needs copying,
they are already here.

| Id | What it is | Drawn at |
|---|---|---|
| `gritty` | A weathered machine cube on a cable, in profile. Nine drawn moods, a blink and a tongue, and a face plate that can carry a timer or a clock. The default. | 150 px |
| `gritty-front` | The same cube, head on rather than in profile. One expression. | 150 px |
| `quattro` | A rally car parked at the bottom of the screen, headlights on. Cut from a wallpaper Omarchy ships — see its `NOTICE`. | 130 px |

All three sit where you put them: none has a walk cycle, so *Follow my
focus* has nothing to offer them and the menu leaves it out. All three
declare a `themeable` hue window, so they are repainted in your theme's
accent whenever it changes, with the artist's shading and the cables left
exactly as drawn. `mirror` lets them face the other way when they are on
the right-hand side of a screen.

## Your own

Drop a folder with a `pet.json` and its spritesheet into

```
~/.config/omarchief/pets/<id>/
```

and it appears in the picker beside these. `~/.config/omapets/pets/<id>/`
is read as well. The format, the coordinate system, and how a face plate is
measured are in [../docs/pets.md](../docs/pets.md).

## How these sheets were made

`gritty`'s twelve cells are montaged and aligned by
[`../tools/build-faces.py`](../tools/build-faces.py); a pet with an
animated atlas is assembled by
[`../tools/build-atlas.py`](../tools/build-atlas.py), which scales every
source to one shared reference pose so the creature does not shrink in the
rows where something tall rises above it.

Both read the renders from `../tools/source/`, which are **not in this
clone** — they are attached to each release. See
[../tools/source/README.md](../tools/source/README.md) for the one command
that puts them back.
