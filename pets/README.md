# Bundled pets

One ships with the plugin, and it is drawn rather than blitted.

| Id | What it is | Drawn at |
|---|---|---|
| `bloub` | One filled shape that morphs between states, with two capsule eyes cut out of it. Computed every frame, so its shape, colour and resting expression are settings. | 48 px |

Its folder holds no artwork at all — see [../docs/pets.md](../docs/pets.md) for
what a pet with a `render` field is, and the top-level README for its shapes,
colours, expressions and idle performances. It wears the theme by being told
to: `Theme accent` is one of the colours it offers, and the eyes, being holes,
show the theme's background whatever the body is painted.

It sits where you put it. There is no walk cycle, so *Follow my focus* has
nothing to offer it and the menu leaves it out.

## Your own

The spritesheet engine is still here, so a pet made for this ecosystem works.
Drop a folder with a `pet.json` and its sheet into

```
~/.config/omarchy-companion/pets/<id>/
```

and it appears in the picker beside the bundled one. `~/.config/omapets/pets/<id>/`
is read as well. The format and coordinate system are in
[../docs/pets.md](../docs/pets.md), and
[`../tools/build-atlas.py`](../tools/build-atlas.py) assembles an animated
atlas from your own renders, scaling every source to one shared reference pose
so the creature does not shrink in the rows where something tall rises above
it. A pet that declares a `themeable` hue window is repainted in your theme's
accent by [`../tools/companion-recolor`](../tools/companion-recolor).

Nothing bundled exercises those paths any more, so
[`../tools/coldstart-check`](../tools/coldstart-check) plants a spritesheet pet
in an isolated `HOME` and loads it in a real shell, which is a better test of
the path your pet actually arrives by than bundled artwork was.
