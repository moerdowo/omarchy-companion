# What these are

The renders the shipped spritesheets are built from, so the sheets can be
rebuilt, corrected, or drawn over by somebody who is not me.

**They are not in this clone.** Nothing loads them at runtime, and they are
twelve megabytes against the plugin's own three hundred kilobytes: every
installation would carry them forever to run a creature that never opens
them. They are attached to each release instead, as
`omarchief-artwork-sources.tar.gz` — download it into this folder and every
command below works as written:

```bash
gh release download --repo daventhedude/omarchief \
  --pattern 'omarchief-artwork-sources.tar.gz' --output - | tar xz
```

The table is what is in that archive.

| File | Feeds | How |
|---|---|---|
| `gritty-faces.png` | the nine drawn moods | a 3×3 grid of renders |
| `gritty-blink.png` | the resting face with its eyes closed | one render, fitted to the resting face |
| `gritty-tongue.png` | the tongue-out expression | one render, fitted the same way |
| `gritty-faces12.png` | `pets/gritty/gritty-faces.webp` | the twelve cells above, montaged 6×2 |
| `gritty-front.png` | `pets/gritty-front/` | one render, head on |
| `quattro.png` | `pets/quattro/` | cut from an Omarchy wallpaper — see that folder's NOTICE |
| `gritty-idle.png`, `gritty-walk.png`, `gritty-activities.png` | an animated atlas | rows of frames, for `build-atlas.py` |

The face sheet is assembled with:

```bash
tools/build-faces.py pets/gritty/gritty-faces.webp tools/source/gritty-faces12.png 6 2 \
  idle,error,tired,working,blush,success,waiting,sleeping,love,blink,tongue,spare \
  --height 208
```

A render that came from a different sitting than the rest — the blink and
the tongue did — has to be matched to the resting face first, in size and
in colour, or the creature appears to flinch when it wears it. See
[docs/pets.md](../../docs/pets.md).

## The blink and the tongue borrow the body

They came from a different sitting than the other nine, and two renders of
the same object are never quite the same object: the outline differed by a
pixel here and there across the whole cube, which the eye reads as a flinch
at an eighth of a second.

So the shipped sheet does not use their bodies at all. After
`build-faces.py` has aligned every cell, the blink and tongue cells are
rebuilt as the resting cell with only the face panel taken from theirs — a
parallelogram at (100, 90), 56 by 56, sloped -0.5, softened two pixels at
its edge. The silhouette is then identical by construction, and the only
thing that changes when the creature blinks is its face.
