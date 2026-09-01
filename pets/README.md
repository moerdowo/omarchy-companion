# Bundled pets

Four ship with the plugin. Pick one from **Companion** in the bar
menu, or with `omarchy-shell grokchief pet <id>` — nothing needs copying,
they are already here.

| Id | What it is | Drawn at |
|---|---|---|
| `bloub` | One filled shape that morphs between states, with two capsule eyes cut out of it. Computed rather than blitted, so its shape, colour and resting expression are settings. The default. | 48 px |
| `gritty` | A weathered machine cube on a cable, in profile. Eight moods, four idle expressions, and a blink. | 150 px |
| `quattro` | The rally car from Omarchy's Tokyo Night wallpaper, cut out as one still pose and covered by its upstream MIT licence. | 130 px |
| `gritty-front` | Gritty facing you, with one uncompromising expression. | 150 px |

All four sit where you put them: none has a walk cycle, so *Follow my focus*
has nothing to offer them and the menu leaves it out.

`bloub` has no artwork in its folder at all — see
[../docs/pets.md](../docs/pets.md) for what a pet with a `render` field is,
and the README for its shapes, colours and expressions. It wears the theme by
being told to: `Theme accent` is one of the colours it offers, and the eyes,
being holes, show the theme's background whatever the body is painted.

The three spritesheet pets declare a `themeable` hue window instead, so they
are repainted in your theme's accent whenever it changes, with the artist's
shading and the cables left exactly as drawn. The profile drawings face into
the screen: their release cells look right on the left-hand side, and `mirror`
turns them left on the right-hand side. Head-on Gritty turns too, keeping its
asymmetric cable on the inward side.

## Your own

Drop a folder with a `pet.json` and its spritesheet into

```
~/.config/grokchief/pets/<id>/
```

and it appears in the picker beside these. `~/.config/omapets/pets/<id>/`
is read as well. The format and coordinate system are in
[../docs/pets.md](../docs/pets.md).

## How these were made

`bloub` was not made, it was ported: see `../tools/build-eyefit`,
`../tools/verify-bloub-port`, and `pets/bloub/NOTICE`.

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
