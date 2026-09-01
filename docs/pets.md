# Making a pet for Omarchy Companion

A pet is a folder with a `pet.json` and one spritesheet. Drop it into
`~/.config/omarchy-companion/pets/<id>/` and it appears under **Companion** in the
bar widget's settings. To name it without the panel:

```bash
omarchy-shell companion pet <id>
```

which writes `pet` onto this plugin's entry in
`~/.config/omarchy/shell.json`, where the shell keeps every plugin's
settings. A pre-4.0 `~/.config/omarchy/companion.json` is read once and
migrated there, so an older setup keeps working without creating two sources
of truth.

Codex/Petdex v1 and v2 pets work as they are. Rows 0–8 keep their standard
meaning. A v2 manifest sets `spriteVersionNumber` to `2` and reserves rows
9–10 for its sixteen look directions; Omarchy Companion leaves those rows intact.
Optional Omarchy Companion activities are explicitly declared and belong after the
standard atlas: row 9 onward for v1, row 11 onward for v2.

## A pet that has no artwork

Before any of the below: a pet does not have to be a sheet at all. One that
names a renderer is DRAWN — its body is computed every frame — and none of the
grid, cell, atlas or theme-repaint machinery in this document applies to it.

```json
{
  "id": "bloub",
  "displayName": "Bloub",
  "description": "One sentence, shown wherever pets are listed.",
  "render": "bloub",
  "size": 130
}
```

`render` is the only field that makes it one, and `bloub` is the only renderer
this plugin ships. `size` and `content` are read, because they are about
placing a body on a desktop rather than about artwork; everything else is
ignored. There is no `spritesheetPath`, no `rows`, no `faces`, no `themeable`.

A drawn pet is still, in the sense the last section of this document means: it
never moves across the screen on its own, so following the focus and roaming
are off for it whatever the settings say. What it does instead of holding a
pose is animate — the whole character is a silhouette that morphs, and its
moods are animations rather than cells.

Still does not mean idle, though, and the two were worth separating: a body
with no legs cannot cross the room but can still do something with itself. A
drawn pet declares its idle performances in code rather than as atlas rows, and
they are scheduled by exactly the machinery on this page — the same *how often*
and *how long it rests*, the same Play button, the same `play <name>`.

Adding a second renderer would mean a second `keystone/<Name>Body.qml` and a
branch beside `bloub` in `Service.qml` and `Chief.qml`. The pet format has
room for it; nothing else here needs to change.

## The sheet

Every sheet is a regular grid of equal-size cells. A Codex/Petdex animated
atlas uses the ecosystem's eight columns of 192 × 208 frames. An expression
grid may declare another `columns` value and may use rectangular cells of any
proportion; Omarchy Companion measures their aspect ratio from the loaded sheet.
Keep the sheet width evenly divisible by `columns` and its height evenly
divisible by `rows`, so filtering never samples across a cell boundary.

The row meanings below apply to an animated Codex/Petdex atlas. A still
expression grid names cells directly with `faces` instead.

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
| 9–10 | v2 look directions | eight each; absent in v1 |
| 9+ (v1), 11+ (v2) | optional activities | declared in `pet.json` |

Rows the pet does not use should repeat its resting pose rather than be
left blank, so a reader that plays them shows something sensible.

## pet.json

```json
{
  "id": "example-animated",
  "displayName": "Example Animated Pet",
  "description": "One sentence, shown wherever pets are listed.",
  "spritesheetPath": "example-animated.webp",

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
| `id` | Optional stable id. The containing folder name remains the lookup key |
| `displayName` | Codex/Petdex human-readable name shown in the companion picker (`name` is accepted as a legacy alias) |
| `description` | One-sentence description for catalogues and future surfaces |
| `spritesheetPath` | The sheet, relative to `pet.json` |
| `size` | The artist's preferred on-screen height in pixels, rounded and accepted from 32 through 240. A user-selected size wins; without either preference the runtime uses 56 px |
| `spriteVersionNumber` | Animated-atlas version used only when `rows` is absent or invalid. A numeric value of 2 or greater selects the eleven-row layout; otherwise nine rows are assumed |
| `columns` | How many cells across the sheet is. Eight — the walk-cycle width — unless you say otherwise |
| `faces` | A mood to the cell that shows it: `{ "idle": [0, 0], "error": [0, 1] }`. A pet with faces is a still pet — see below |
| `idleFaces` | Optional list of `[row, column]` cells a resting expression pet may borrow. Invalid, duplicate, out-of-grid, and `idle` cells are discarded; when omitted, the neutral `parked`, `success`, `love`, and `dragged` faces form the pool |
| `blink` | One cell, the resting face with its eyes closed. Shown for a moment every few seconds — see below |
| `content` | Where the drawing sits inside its cell: `{ "left", "right", "top", "bottom" }` as fractions — see below |
| `mirror` | `true` if the drawing may be flipped when the creature stands on the right of the screen. See below |
| `rows` | How many rows the sheet has. Without it, nine are assumed (eleven for `spriteVersionNumber` 2) |
| `walkFrames` | How long the walk cycle is. A cycle shorter than eight columns stutters through the empty cells without this |
| `sleepRow` | A row holding a real sleeping pose. Without it, the resting pose is simply dimmed |
| `stillRows` | Optional list of animated-atlas row numbers whose cells repeat one still drawing. Valid rows are rounded down and kept between zero and `rows - 1`; their frame timer stays stopped |
| `pixelArt` | Literal `true` disables smooth filtering and mipmaps so hard pixel edges survive scaling; every other value keeps normal filtering |
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

Lightness inside that same paint window is then fitted as a gamma, so black
stays black, white stays white, and cables, metal, eyes, and rust remain
byte-for-byte as drawn. The fit heads toward whichever of black or white
contrasts more with the exact background — perceptual mid-tones cannot be
split reliably into simply “dark” and “light”. The body is what is measured;
outlines and dark screens are meant to stay dark, and averaging them in only
bleaches the artwork chasing a number.

How far it goes depends on what else separates the pet from its desktop.
Figure and ground are told apart by hue, by colour, or by lightness, and
where the first two are present the 3:1 that WCAG asks of graphics is
enough. But a surprising number of themes accent with a brighter shade of
their own wallpaper — it is part of what makes a palette feel of a piece
— and there the pet is painted in the wallpaper's own hue, with nothing
but lightness left to tell it apart. Those get 4.5:1 instead. A desktop
that is a neutral is exempt: hue was never going to separate anything
there, and the pet's own colour already does.

Set `OMARCHY_COMPANION_CONTRAST_FLOOR` to override the whole judgement.

**What this asks of the artwork:** keep the surfaces you want recoloured
inside one hue family, and paint them with the full range from shadow to
highlight. Anything that should stay itself — cables, metal, eyes, rust —
simply lives outside that window. A creature whose shell is yellow-green
keeps its red cables, white servos and brown boots through every theme.

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
  "id": "example-faces",
  "displayName": "Example Faces",
  "spritesheetPath": "example-faces.webp",
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
Expressions switch as crisp authored poses. Keep their scale and grounding
consistent so the change reads as expression rather than movement.

Resting is not the same as being frozen. Every so often the creature
looks up wearing another of its faces for a few seconds and then settles
back. It only ever borrows an expression that carries no news — `parked`,
`success`, `love`, `dragged` — so a pet is never found looking alarmed
for no reason, and it never happens while the agent is doing something.
Draw those faces and you get it for free; draw only `idle` and the
creature simply rests, which is also fine. The person can switch it off
from the bar popout.

### Where the drawing sits in its cell

```json
"content": { "left": 0.08, "right": 0.88, "top": 0.05, "bottom": 0.82 }
```

A cell is rarely filled to its edges. That is fine until something has to be
measured against the creature rather than the cell — putting it away at an
edge, for example, where what should stay showing is a peek of the drawing and
not a strip of transparency. Declare the visible bounds and those measurements
land on the pet itself.

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

The blink uses the same crisp pose change as every other expression.

**What this asks of the artwork:** the same drawing, from the same
distance, in the same colours — only the eyes change. Anything else and
the creature appears to flinch. `tools/build-faces.py` will align the
cell for you, but it cannot know that a render came out four percent
larger or a shade brighter, and both are plainly visible at a tenth of a
second. If the blink comes from a separate render, match it to the
resting face before building the sheet.

`tools/build-faces.py` assembles the sheet from a grid of renders:

```bash
tools/build-faces.py example-faces.webp renders.png 6 2 \
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
plate or a name — reads backwards the moment you do.

## A pet may be one picture

Nothing says a sheet needs more than one cell. `rows: 1`, `columns: 1`
and `faces: { "idle": [0, 0] }` is a complete pet: it rests, it wears
your theme if it has a hue window, it can be dragged, and that is all.
A single still pose, such as a vehicle or a portrait, is built that way.

## Building an animated sheet

`tools/build-atlas.py` does all of the above. Supply your own aligned renders;
the paths below are examples and are not part of Omarchy Companion's artwork-source
archive:

```bash
tools/build-atlas.py example-animated.webp \
  --walk renders/walk.png 6 \
  --idle renders/idle.png \
  --activities renders/activities.png 6 6 \
      balloon,lunch,treasure,painting,cat,garden \
  --poses working=2:4,success=2:5,error=3:2,waiting=0:3,sleep=4:5
```

It prints the `pet.json` fields it produced, including the measured hold
times. `--poses` lifts single cells out of the activity sheet to fill the
standard rows: `working=2:4` means row 2, column 4 of that sheet becomes
the working pose.

Both builders need Python 3 and ImageMagick, which Omarchy already installs;
`build-faces.py` additionally needs NumPy. The complete development dependency
list is in the root README.
