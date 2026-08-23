# Making a pet for Omarchief

A pet is a folder with a `pet.json` and one spritesheet. Drop it into
`~/.config/omarchief/pets/<id>/` and it appears under **Who stands there**
in the bar menu. To name it without the menu:

```bash
omarchy-shell omarchief pet <id>
```

which writes `pet` onto this plugin's entry in
`~/.config/omarchy/shell.json`, where the shell keeps every plugin's
settings. `~/.config/omarchy/omarchief.json` is still read for the same
keys, so an older setup keeps working.

Pets from the Codex/Petdex ecosystem work as they are — the first nine
rows mean what they mean everywhere. Everything past row eight is
Omarchief's own, and a reader that does not know about it still finds
what it expects.

## The sheet

A grid of cells, eight columns wide. Every cell is the same size, and the
sheet is as tall as it has rows. Omarchief works out the cell size from
the sheet and the row count, so any cell size will do as long as the
proportions match the shipped pets (192 × 208 is the ecosystem's).

| Row | Meaning | Frames |
|---|---|---|
| 0 | idle | up to 8 |
| 1 | walking right | up to 8 |
| 2 | walking left | up to 8 |
| 3 | wave | up to 8 |
| 4 | jump | up to 8 |
| 5 | error | up to 8 |
| 6 | waiting for you | up to 8 |
| 7 | working | up to 8 |
| 8 | finished | up to 8 |
| 9+ | activities, one row each | declared in `pet.json` |

Rows the pet does not use should repeat its resting pose rather than be
left blank, so a reader that plays them shows something sensible.

## pet.json

```json
{
  "id": "gritty",
  "displayName": "Gritty",
  "description": "One sentence, shown wherever pets are listed.",
  "spritesheetPath": "gritty-v10.webp",

  "rows": 16,
  "walkFrames": 6,
  "sleepRow": 15,
  "themeable": { "hueMin": 40, "hueMax": 175, "satMin": 12 },
  "activities": [
    { "name": "garden", "row": 14, "frames": 6,
      "holds": [554, 472, 411, 446, 481, 996] }
  ]
}
```

| Field | Meaning |
|---|---|
| `spritesheetPath` | The sheet, relative to `pet.json` |
| `columns` | How many cells across the sheet is. Eight — the walk-cycle width — unless you say otherwise |
| `faces` | A mood to the cell that shows it: `{ "idle": [0, 0], "error": [0, 1] }`. A pet with faces is a still pet — see below |
| `blink` | One cell, the resting face with its eyes closed. Shown for a moment every few seconds — see below |
| `display` | Where the pet has a screen on it, if it does: `{ "x", "y", "w", "h", "slope" }` — see below |
| `content` | Where the drawing sits inside its cell: `{ "left", "right", "top", "bottom" }` as fractions — see below |
| `mirror` | `true` if the drawing may be flipped when the creature stands on the right of the screen. See below |
| `rows` | How many rows the sheet has. Without it, nine are assumed (eleven for `spriteVersionNumber` 2) |
| `walkFrames` | How long the walk cycle is. A cycle shorter than eight columns stutters through the empty cells without this |
| `sleepRow` | A row holding a real sleeping pose. Without it, the resting pose is simply dimmed |
| `themeable` | The hue window that counts as the pet's skin — see below |
| `activities` | Idle performances, one row each. Each carries the milliseconds its frames are held; `tools/build-atlas.py` measures them, and you are welcome to tune them by hand afterwards |
| `themeTint` | `true`, `false` or a strength between 0 and 1: the live fallback tint. `themeable` is the better path; this is what runs when a redraw cannot |

### Activities

Each entry names a row and how many frames it uses. `holds` is optional
and gives each frame its own time on screen in milliseconds; without it
every frame is held equally.

Hold times matter more than they sound. Animators hold the poses that
carry meaning and pass quickly through the in-betweens: a screen reading
`LUNCH.exe` needs time to be read, two frames of chewing do not. The
builder measures this — each frame is held in proportion to how much the
picture changes after it, and the closing frame is held longest, because
nothing follows it.

### Wearing the theme

```json
"themeable": { "hueMin": 40, "hueMax": 175, "satMin": 12 }
```

Those are degrees on the colour wheel. Every pixel whose hue falls inside
the window and which is saturated enough to be paint rather than shadow
is redrawn in the theme's accent when the theme changes. Lightness is
left alone — that is where your modelling lives — and everything outside
the window stays exactly as you drew it.

**How a theme is worn.** The hue comes from the theme's accent. The
artist's vividness does not: scaling it by the accent's own saturation
is the obvious reading of "wear the theme" and it is wrong, because most
themes accent with a muted mid-tone, and a pet recoloured that way turns
grey — in the same washed hue as the desktop it stands on. Vividness is
kept whole for any accent with colour in it, and surrendered only as the
accent approaches grey, where a vivid pet would misrepresent the theme
and the hue has no meaning left anyway.

Lightness is then fitted, as a gamma so nothing clips and black stays
black and white stays white — lifted on a dark desktop, deepened on a
pale one, since a wan creature on cream is exactly as hard to see as a
dim one on black. The body is what is measured — outlines and dark
screens are meant to stay dark, and averaging them in only bleaches the
artwork chasing a number.

How far it goes depends on what else separates the pet from its desktop.
Figure and ground are told apart by hue, by colour, or by lightness, and
where the first two are present the 3:1 that WCAG asks of graphics is
enough. But a surprising number of themes accent with a brighter shade of
their own wallpaper — it is part of what makes a palette feel of a piece
— and there the pet is painted in the wallpaper's own hue, with nothing
but lightness left to tell it apart. Those get 4.5:1 instead. A desktop
that is a neutral is exempt: hue was never going to separate anything
there, and the pet's own colour already does.

Set `OMARCHIEF_CONTRAST_FLOOR` to override the whole judgement.

**What this asks of the artwork:** keep the surfaces you want recoloured
inside one hue family, and paint them with the full range from shadow to
highlight. Anything that should stay itself — cables, metal, eyes, rust —
simply lives outside that window. Gritty's shell is yellow-green, and its
red cables, white servos and brown boots survive every theme.

## Drawing the frames

Three rules decide whether the creature walks or limps:

**Draw on a grid and keep to it.** Frames are cut on the sheet's own
grid. Cutting each pose to its own outline instead would re-centre every
one of them and make the body jitter as it walks.

**Anchor the head, not the feet.** Across a walk cycle the head stays at
one height while the feet move. The builder keeps the head where you put
it and seats each frame on its own lowest pixel, so the feet always land.

**Keep the creature the same size everywhere.** If idle, walking and the
activities come from separate renders, each will have its own scale. The
builder measures the plain standing cube in the first column of every
source and scales all of them so that cube is identical — but it can only
do that if every source has one.

Save with transparency. Never key a background out by colour afterwards:
that also takes your dark outline, which is invisible against a dark
desktop and shows up as a bright halo the moment the creature walks over
a white window.

## A pet that does not move

A creature does not have to animate to be alive. A pet may be a grid of
expressions instead — one drawing per mood, no walking, no performances,
nothing moving of its own accord. It sits where you put it and tells you
how the day is going with its face; the only thing that ever shifts it
across the screen is your hand.

```json
{
  "name": "Gritty",
  "spritesheetPath": "gritty-faces.webp",
  "rows": 3, "columns": 3, "size": 150,
  "faces": {
    "idle":    [0, 0], "error":   [0, 1], "tired":   [0, 2],
    "working": [1, 0], "parked":  [1, 1], "success": [1, 2],
    "waiting": [2, 0], "sleeping":[2, 1], "love":    [2, 2]
  }
}
```

The moods are the same ones an animated pet answers to. You need not draw
all of them: each falls back through what you are most likely to have and
ends at `idle`, which every pet must have. `dragged` is the one extra —
what the creature does while you are holding it — and it borrows `love`,
then `success`, then `idle` if you did not draw one.

A still pet ignores `followFocus` and `roam` whatever the person's
settings say, because both of them are the creature moving on its own.
Expressions dissolve into one another rather than snapping.

Resting is not the same as being frozen. Every so often the creature
looks up wearing another of its faces for a few seconds and then settles
back. It only ever borrows an expression that carries no news — `parked`,
`success`, `love`, `dragged` — so a pet is never found looking alarmed
for no reason, and it never happens while the agent is doing something.
Draw those faces and you get it for free; draw only `idle` and the
creature simply rests, which is also fine. The person can switch it off
from the bar popout.

### A screen to show things on

```json
"display": { "x": 0.5146, "y": 0.4615, "w": 0.2233, "h": 0.2212, "slope": -0.5 }
```

A pet with a panel on it — a screen, a gauge, a window — can be asked to
show something there. `x`, `y`, `w` and `h` are fractions of the cell, so
they hold at any size, and `slope` is the rise of the panel's top edge in
the drawing: `0` for a flat one, `-0.5` for the two-to-one isometric that
most pixel-art cubes are drawn in. The rectangle is sheared by it, and
what is drawn inside is sheared with it, which is what makes the digits
sit on the panel rather than float in front of it.

Measure it from the artwork with a grid: the anchor is the panel's
top-left corner, and the width and height are its unsheared extent. Keep
it inside the panel's frame — a screen that overlaps its own bezel looks
like a sticker.

Omit it and the pet simply has nothing to show things on; the timer then
lives in the bar and the speech bubble instead.

### Where the drawing sits in its cell

```json
"content": { "left": 0.0534, "right": 0.8495, "top": 0.0433, "bottom": 0.7981 }
```

A cell is rarely filled to its edges. Gritty's resting picture stops
thirty pixels short of its own right edge and forty short of the bottom,
which is fine until something has to be measured against the creature
rather than against the cell — putting it away at an edge, where what
should stay showing is a peek of the pet and not a strip of transparency.
Say where the drawing is and those measurements land on it.

Take it from the resting cell, as fractions of the cell's width and
height. Leave it out and the cell is assumed to be full, which is what
every pet did before this existed and is right for artwork drawn edge to
edge.

### Blinking

```json
"blink": [1, 3]
```

Draw the resting face once more with the eyes closed, name its cell, and
the creature blinks: a snap to that cell for about an eighth of a second,
every few seconds, sometimes twice in a row the way a real blink comes.
It is the cheapest sign of life a still drawing can have, and the only
one that never stops — except while it is being carried, while it is
already wearing an expression, and while it sleeps.

A blink does not dissolve. Every other change of face fades across a
quarter of a second; a blink you can watch fade is not a blink.

**What this asks of the artwork:** the same drawing, from the same
distance, in the same colours — only the eyes change. Anything else and
the creature appears to flinch. `tools/build-faces.py` will align the
cell for you, but it cannot know that a render came out four percent
larger or a shade brighter, and both are plainly visible at a tenth of a
second. If the blink comes from a separate render, match it to the
resting face before building the sheet.

`tools/build-faces.py` assembles the sheet from a grid of renders:

```bash
tools/build-faces.py pets/gritty/gritty-faces.webp renders.png 6 2 \
  idle,error,tired,working,blush,success,waiting,sleeping,love,blink,tongue,spare
```

The grid is however many columns by however many rows your renders came
in, and the names are read across it in that order. Names it does not
recognise as moods — `blush`, `tongue` — are still cut and aligned like
any other cell; what makes them expressions rather than moods is that
`idleFaces` names them and `faces` does not. `spare` here is the twelfth
cell of a sheet with eleven drawings in it: a grid has to be full, and a
duplicate of the resting face is the cheapest thing to fill it with.

The one thing it takes seriously is that the body lands in exactly the
same place in every cell — a face that shifts two pixels when the mood
changes reads as a glitch rather than a feeling. Renders are never
pixel-aligned, and decorations fuse to the body, so it finds the body by
eroding those attachments away, cuts each cell relative to the body's own
footing, and then slides every cell against the first until they match.
It reports the cell size and the ground line it settled on.

## Turning to face you

A creature drawn in profile faces one way and trails its cable the other.
Stand it on the right of the screen and it looks off the edge with its
cable lying across the room, which is backwards. `mirror: true` lets it
turn around there — it pivots on the spot rather than snapping — so the
face stays pointed inwards and the cable runs off the nearer edge.

Say `mirror: true` only if the drawing can take it. A front view gains
nothing by being flipped, and anything with writing on it — a number
plate, a sponsor's name — reads backwards the moment you do. The rally
car that ships with this plugin says `false` for exactly that reason.

## A pet may be one picture

Nothing says a sheet needs more than one cell. `rows: 1`, `columns: 1`
and `faces: { "idle": [0, 0] }` is a complete pet: it rests, it wears
your theme if it has a hue window, it can be dragged, and that is all.
Two of the three that ship here are built that way.

```bash
tools/build-faces.py pets/quattro/quattro.webp render.png 1 1 idle
```

## Building an animated sheet

`tools/build-atlas.py` does all of the above. The renders it reads from
`tools/source/` are not in the clone — they are attached to each release,
and [tools/source/README.md](../tools/source/README.md) has the one command
that puts them back:

```bash
tools/build-atlas.py pets/gritty/gritty-v10.webp \
  --walk tools/source/gritty-walk.png 6 \
  --idle tools/source/gritty-idle.png \
  --activities tools/source/gritty-activities.png 6 6 \
      balloon,lunch,treasure,painting,cat,garden \
  --poses working=2:4,success=2:5,error=3:2,waiting=0:3,sleep=4:5
```

It prints the `pet.json` fields it produced, including the measured hold
times. `--poses` lifts single cells out of the activity sheet to fill the
standard rows: `working=2:4` means row 2, column 4 of that sheet becomes
the working pose.

It needs ImageMagick, which Omarchy already installs.
