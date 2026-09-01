# What these are

The renders the shipped spritesheets are built from, so the sheets can be
rebuilt, corrected, or drawn over by somebody who is not me.

**They are not in this clone.** Nothing loads them at runtime, so carrying
them in every installation would add weight without changing the creature
on screen. They are attached to each release instead, as
`grokchief-artwork-sources.tar.gz`. The archive includes its own licence and
provenance notice; download it at the version in `manifest.json` and extract it
at the repository root:

```bash
version=$(jq -r .version manifest.json)
gh release download "v$version" --repo moerdowo/grok-chief \
  --pattern 'grokchief-artwork-sources.tar.gz' --output - | tar xz
```

That asset has to be built and attached first — `tools/build-source-archive`
makes it — and no Grok Chief release carries one yet. Until then the renders
are on Omarchief's releases, which is where this artwork comes from:

```bash
gh release download --repo daventhedude/omarchief \
  --pattern 'omarchief-artwork-sources.tar.gz' --output - | tar xz
```

The drawn companion has no renders and appears in neither archive: it has no
artwork to rebuild.

The table is what is in that archive.

| File | Feeds | How |
|---|---|---|
| `gritty-faces.png` | the nine drawn moods | a 3×3 grid of renders |
| `gritty-blink.png` | the resting face with its eyes closed | one render, fitted to the resting face |
| `gritty-tongue.png` | the tongue-out expression | one render, fitted the same way |
| `gritty-faces12.png` | `pets/gritty/gritty-faces.webp` | the twelve cells above, montaged 6×2 |
| `gritty-front.png` | `pets/gritty-front/gritty-front.webp` | high-resolution head-on portrait in its canonical cable orientation |
| `quattro.png` | `pets/quattro/quattro.webp` | high-resolution cutout of the approved Omarchy-derived still; see `NOTICE` |
| `NOTICE` | the source archive itself | copyright, licence, provenance, and marks notice; always included |

Build the release archive with the repository helper. It carries an explicit
member list, normalizes tar ownership, permissions, ordering, and timestamps,
and removes gzip's filename and time fields. This keeps retired studies and
local renders out, makes the notice impossible to forget, and produces the
same bytes from the same audited inputs and release commit:

```bash
asset="${TMPDIR:-/tmp}/grokchief-artwork-sources.tar.gz"
tools/build-source-archive "$asset"
tools/build-source-archive --check "$asset"
tar -tzf "$asset"
```

The builder uses the release commit time unless `SOURCE_DATE_EPOCH` is set
explicitly, and prints the archive's SHA-256. Record that checksum in the
release notes and attach the archive to the matching `v<manifest version>`
release. Neither the high-resolution PNG inputs nor the resulting tarball may
appear in `git ls-files`; every plugin installation should contain only the
optimized runtime spritesheets.

The face sheet is assembled with:

```bash
tools/build-faces.py pets/gritty/gritty-faces.webp tools/source/gritty-faces12.png 6 2 \
  idle,error,tired,working,blush,success,waiting,sleeping,love,blink,tongue,spare \
  --height 208 \
  --borrow-body idle:blink,tongue --panel 116,108,68,68,-0.5
```

This produces twelve 242 × 208 cells. The body finder gives every drawing its
own cell and drops disconnected antialiasing dust instead of carrying a piece
of its neighbour across the grid. The last two options make the blink and
tongue deterministic even though their renders came from a different sitting:
both keep the aligned `idle` body and borrow only their 68 × 68 face panel.
See [docs/pets.md](../../docs/pets.md).

The archived `gritty-faces12.png` already carries Omarchy's `#9ece6a` green
as the unthemed shell's reference midtone. Light, shadow, wear, and transparent
edge pixels remain part of the painting; the build must preserve them rather
than flattening the body to one literal colour. Runtime theme dressing starts
from that branded source and `Theme` off returns to it byte-for-byte.

## Gritty's head-on release cell

The head-on portrait is a deliberately separate still companion, not a face
spliced into the profile atlas. Its release cell is 249 × 208 with the visible
drawing seated at `239x198+5+5`; the archived source is already horizontally
oriented as the canonical release cell. `mirror: true` performs the only
runtime turn, keeping its asymmetric cable on the inward side of the screen.
Rebuilding it is an art-directed downsample: preserve the source transparency,
Omarchy-green midtone, red cable, five-pixel safe edge, and inspect it at the
actual 150 px default before replacing the audited runtime WebP.

## The blink and the tongue borrow the body

They came from a different sitting than the other nine, and two renders of
the same object are never quite the same object: the outline differed by a
pixel here and there across the whole cube, which the eye reads as a flinch
at an eighth of a second.

So the shipped sheet does not use their bodies at all. `--borrow-body` rebuilds
the blink and tongue cells from the resting cell, then takes only the sheared
panel declared by `--panel 116,108,68,68,-0.5` from each target. The edge is
feathered by the builder; the silhouette stays identical by construction and
only the expression changes.

## Quattro's release cell

Quattro has one still cell rather than a content-aware builder. The fixed crop
below turns the archived high-resolution cutout into a 333 × 208 lossless
release candidate with the drawing seated at the same +5,+5 bounds as the
shipped sheet:

```bash
magick tools/source/quattro.png -filter Lanczos -resize 335x \
  -crop 333x208+3+22 +repage -background none -gravity northwest \
  -extent 333x208 -flop -define webp:lossless=true pets/quattro/quattro.webp
magick pets/quattro/quattro.webp -alpha extract -threshold 1 -trim \
  -format '%wx%h%O\n' info:
```

The final `-flop` makes the release cell face right; `mirror: true` turns it
left when it stands on the right half of a screen, so the car always points
inward. The geometry check must print `323x198+5+5`. ImageMagick's resampler
can change individual pixels between versions, so a source change still
requires the normal-scale alpha, decal-legibility, and light/dark-theme review in
[docs/development.md](../../docs/development.md); matching dimensions alone do
not approve an image.
