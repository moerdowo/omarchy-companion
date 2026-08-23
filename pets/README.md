# Bundled pets

Three ship with the plugin. Pick one from **Companion** in the bar
menu, or with `omarchy-shell omarchief pet <id>` — nothing needs copying,
they are already here.

| Id | What it is | Drawn at |
|---|---|---|
| `gritty` | A weathered machine cube on a cable, in profile. Eight moods, four idle expressions, and a blink. The default. | 150 px |
| `quattro` | The rally car from Omarchy's Tokyo Night wallpaper, cut out as one still pose and covered by its upstream MIT licence. | 130 px |
| `gritty-front` | Gritty facing you, with one uncompromising expression. | 150 px |

All three sit where you put them: none has a walk cycle, so *Follow my
focus* has nothing to offer them and the menu leaves it out. All three
declare a `themeable` hue window, so they are repainted in your theme's
accent whenever it changes, with the artist's shading and the cables left
exactly as drawn. The profile drawings face into the screen: their release
cells look right on the left-hand side, and `mirror` turns them left on the
right-hand side. Head-on Gritty turns too, keeping its asymmetric cable on the
inward side.

## Your own

Drop a folder with a `pet.json` and its spritesheet into

```
~/.config/omarchief/pets/<id>/
```

and it appears in the picker beside these. `~/.config/omapets/pets/<id>/`
is read as well. The format and coordinate system are in
[../docs/pets.md](../docs/pets.md).

## How these sheets were made

`gritty`'s twelve cells are montaged and aligned by
[`../tools/build-faces.py`](../tools/build-faces.py); a pet with an
animated atlas is assembled by
[`../tools/build-atlas.py`](../tools/build-atlas.py), which scales every
source to one shared reference pose so the creature does not shrink in the
rows where something tall rises above it.

The separate release-source archive contains only the inputs for Gritty's
face sheet and head-on portrait plus the high-resolution Quattro cutout; they extract into
`../tools/source/`. See
[../tools/source/README.md](../tools/source/README.md) for its exact contents,
download command, and bundled-art build steps. `build-atlas.py` is a BYO-pet
tool instead: pass it your own walk, idle, and activity renders as documented
in [../docs/pets.md](../docs/pets.md).
