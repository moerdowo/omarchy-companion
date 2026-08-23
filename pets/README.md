# Bundled pets

`gritty` is Omarchief's own body: a weathered machine cube that rests as a
plain cube and walks a six-step gait in both directions. Install it with

```bash
cp -r pets/gritty ~/.config/omarchief/pets/
```

and set `{ "pet": "gritty" }` in `~/.config/omarchy/omarchief.json`.

It declares a `themeable` hue window, so Omarchief redraws it in your
theme's accent whenever the theme changes — cables, servos and the
artist's shading stay exactly as drawn. See the main README.

The sheet was assembled from the renders in `../tools/source/` with
`../tools/build-pet.py`, which measures rather than trusts: frames are cut
on the sheet's own grid through one shared vertical window (the artist
anchors the head, so bottom-aligning would bounce it), and the playback
order is the closed cycle with the smallest frame-to-frame difference.

```bash
tools/build-pet.py tools/source/gritty-walk.png tools/source/gritty-idle.png \
  pets/gritty/gritty-v5.webp 6
```
