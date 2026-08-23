# Changelog

## 3.33.0 — 2026-08-23

- Settings live inline on this plugin's entry in `shell.json`, where the
  shell keeps every plugin's. Its own rule says as much — "no separate
  per-plugin settings file" — and ours made this the one plugin on the
  machine whose configuration lived somewhere nobody would look. The old
  file is still read so nothing is lost; the entry wins, and the first
  change moves everything across.
- The panel answers `open()`, so `omarchy-shell shell summon <id>` reaches
  it — with `{"ask":true}`, `{"order":"..."}` or `{"tuck":true}`. Before,
  a summon returned ok and did nothing at all.

## 3.30.0 — 2026-08-23

- A creature that has been put away can be used where it stands. Clicking
  the peek opens the order form over whatever is showing, and the answer
  arrives there: out of the way is not off duty. Dragging the peek is how
  you have it back — the gesture that already meant that.
- It moves with your hand while you push it away, one pixel for one pixel,
  and covers the rest of the distance when you let go. It used to run at
  twice the speed of the hand pushing it, which read as sudden; and it
  decided afresh on every mouse move which way it was going, which made it
  stutter at the threshold.
- Theme changes no longer arrive late. Omarchy hands its palette to the
  shell and glides the wallpaper across four tenths of a second; the
  creature then spent three quarters of a second being redrawn before it
  could follow. Every theme on the machine is dressed in advance now —
  quietly, at the lowest priority the scheduler offers, only while nothing
  is being asked of it. Twenty-two themes, eleven seconds, three megabytes,
  once; after that a switch is a comparison and a crossfade.
- The bar has the last two settings that lived only in the config file:
  where the console opens, and whether a walking pet follows your focus.

## 3.28.0 — 2026-08-23

- Pushing it away is smooth now. Two things were holding it back: the lift
  that says "still here" when you hover a tucked creature was also applying
  while you shoved one, so it only ever sank to seven tenths of where your
  hand was and dropped the rest when you let go; and pulling a tucked
  creature back out by hand jumped rather than eased, because the animation
  was switched off for the whole of a drag rather than for the shove.
- Two settings that existed only in the config file are in the bar: where
  the console opens, and — for a pet that can walk — whether it follows
  your focus.

## 3.27.0 — 2026-08-23

- Putting it away by pushing it works from anywhere, including the corner
  it stands in by default — which is where it was least likely to work
  before. The gesture asked for a fixed distance past the stop; a creature
  in the corner has barely any room to give, so the hand ran out of screen
  before the distance was met and it sprang back. What is asked for now is
  the room the hand actually has, in all three directions.
- It follows the hand exactly while being pushed, with no animation in
  between. Easing that made the creature lag a quarter-second behind the
  gesture making it, which reads as mush rather than weight. The easing is
  for letting go: springing back, or settling into the edge.
- A drag going mostly sideways never dips it, so shuffling it along the
  bottom of the screen cannot sink it by accident.

## 3.25.0 — 2026-08-23

- Pushing it down puts it away, the same way pushing it against a side
  does: keep going after the creature has stopped, and it sinks into the
  floor it stands on. This replaces the double-click, which fought the
  single one — the first of the two clicks already opens the order form or
  clears a standing reply, so by the time the second arrived the scene had
  changed under it and the gesture only worked sometimes.
- Asking for it to be put away, without saying where, always means down.
  It used to keep whichever side it had last been shoved to.

## 3.24.0 — 2026-08-23

- It can be put away against either side as well as into the floor —
  shove it there with the mouse, or `tuck left` / `tuck right`. Its place
  on the edge does not change, only the picture moves, so nothing crosses
  to a neighbouring monitor and letting it out stands it where it was.
- What stays showing is the creature rather than the margin beside it. A
  sprite cell has transparent edges, and measuring the peek against the
  cell left a strip of nothing at the screen edge — the creature vanished
  outright. Artwork now says where the drawing sits inside its cell.
- And what is showing is what can be pressed. The hitbox was placed by
  adding an offset to a position that already carried it, which put the
  rectangle off screen and computed its width as zero: a creature that
  could be seen and not fetched back. It is now exactly the drawing that
  is visible — 25 pixels of it — and never narrower, whatever the
  arithmetic does.

## 3.22.0 — 2026-08-23

- Drag it hard against the side of your desktop and it parks there with a
  peek of itself showing; one click on that peek fetches it back. Only
  against a side that has nothing beyond it: pushing it at the seam
  between two monitors hands it to the neighbour, as it always has, and
  parking it there would leave it a sliver on a screen you are not looking
  at, which is how you lose a creature.
- Double-clicking tucks it away, and again brings it up. That one works
  wherever it stands.
- Parked or tucked, it catches clicks on exactly what is showing. The
  margins that make it comfortable to hit in the open reached out over the
  very window it had just made room for.
- The blink and the tongue borrow the resting body outright. Two renders
  of the same cube are never quite the same cube, and theirs differed
  along the whole outline — which at an eighth of a second reads as a
  flinch. The shipped cells are the resting cell with only the face panel
  taken from theirs: silhouette difference, zero.
- New colours arrive sooner: the redraw starts within fifty milliseconds
  of the theme changing, and rises up the creature in three tenths of a
  second rather than six.

## 3.20.0 — 2026-08-23

- Tucking sinks the creature into the edge it stands on rather than
  sliding it along it. A creature standing mid-edge used to travel the
  width of the screen to hide and end up somewhere other than where you
  put it; now it goes straight down, its whole footprint is freed, and the
  top of its head stays up to grab. Hovering that lifts it a little.
  Anything it has to say brings it back up on its own.
- While tucked it catches clicks on what is left showing and nothing more.
  It was still catching them over the whole area it had just got out of
  the way of, which made tucking worse than useless.
- A theme change is worth watching, so the new colours rise up it from the
  feet over about six tenths of a second, with a bright waterline at the
  edge they have reached.
- And it keeps its clothes on while they are being made: the second
  between a theme changing and its sheet being redrawn used to be spent
  wearing the colours it was drawn in.
- The rally car turns around on the right of the screen, and wears your
  theme — it is a white car, so what the theme takes is the light it
  stands in.

## 3.18.0 — 2026-08-23

- The rally car wears your theme. It is a white car; everything coloured
  about it is the light it stands in, so the theme takes that light while
  the headlights and the sponsor decals — white, and white has no hue to
  swap — stay as they are. Twenty-two themes, worst contrast 3.26:1. It
  turns around on the right of the screen now too.
- Its provenance is written down: the car is cut from the wallpaper
  Omarchy ships with tokyo-night, which is MIT with no separate terms for
  images. The file said it was drawn for this plugin. It was not.
- The bar stops offering idle expressions to a pet drawn as one picture,
  where the switch had nothing to switch.
- Every tool answers `--help`. Two of them answered it with a traceback.
- The raw renders say what they are and what each one builds, and a
  superseded ten-cell sheet is gone.
- A status line the hero replaced, and a list of labels nothing read, are
  gone from the bar widget.
- Broken configuration cannot break it: truncated JSON, an empty file, a
  size of 99999, a pet that does not exist, nulls throughout — twelve
  kinds, all loading clean and landing on sane values.

## 3.16.0 — 2026-08-23

- The bar button introduces itself on hover — who is answering, how the
  creature is, what is left on the timer, and what its other two buttons
  do, which is the only place middle-click and right-click were ever going
  to be found. While a timer runs the button shows it.
- The creature's own panel can hold the clock as well as a timer, and a
  timer running out now reaches the desktop's notifier: a bubble on a
  screen you are not looking at is a timer that did not go off.
- Removing the plugin can no longer leave a trap. The hooks it writes into
  the agent's settings are guarded, so once the files are gone they do
  nothing rather than failing on every event.
- The README says what an order actually grants — the agent runs
  unattended with its approvals bypassed — lists every dependency and what
  happens without it, and now documents every IPC command, every config
  key and every field of the status file. All three had drifted.
- The bar widget kept its own copy of two pieces of logic. One of them,
  "can this agent be spoken to", was a list of three names typed out, and
  would have gone on calling a new adapter console-only. Both now come
  from the one place that knows.
- CI runs the checks the shell and the marketplace run: manifest, id
  namespace, entry points, symlinks, and the files a listing needs.

## 3.12.0 — 2026-08-22

- A timer, on the screen the creature has for a face. Whole minutes while
  there is more than one, seconds under it — two big digits read across a
  room and 24:59 does not. It glows in whatever the creature is wearing,
  it is sheared to sit on the panel rather than float in front of it, and
  it survives a reload, because a timer you cannot trust is not a timer.
  `omarchy-shell omarchief timer 25m`, or the bar.
- Artwork says where its screen is, as a rectangle in cell fractions plus
  the slope its top edge is drawn at. A pet without one simply has nothing
  to show things on.
- Dragging a tucked creature pulls it back out.

## 3.11.0 — 2026-08-22

- The contrast fit works in both directions. It only ever lifted, on the
  reasoning that a pale desktop already had the contrast — which was true
  of the cube and not of the creature drawn head-on, who came out at
  2.8:1 on rose-pine. A gamma reads the same either way.
- How much separation to insist on now depends on what else the theme
  offers. Eight of the twenty-two accent with a brighter shade of their
  own wallpaper, which leaves the creature painted in the desktop's hue
  with only lightness to tell it apart; those ask 4.5:1 rather than the
  3:1 WCAG asks of graphics. A neutral desktop is exempt — hue was never
  separating anything there and the creature's own colour already does.
- The fitted sheet is checked at full size before it ships rather than
  trusted from the thumbnail, and the thumbnail is sampled rather than
  scaled: averaging the pixels down melts the black outlines into the
  body and reported a creature half a stop darker than the real one.
- Dragging a tucked creature pulls it back out, instead of sliding it
  along the edge still mostly out of sight.
- All three pets clear their floor on all twenty-two themes.

## 3.10.0 — 2026-08-22

- A blink only interrupts the resting face. The drawing is the resting face
  with its eyes closed, so blinking while the creature wore a mood of its
  own flashed somebody else's mouth for an eighth of a second. What counts
  is the picture on screen rather than the name of the mood, since a pet may
  draw several moods with one picture.
- The blink and the tongue are matched to the face they interrupt: the same
  colour to within a fraction of a degree of hue, inside the spread the nine
  original faces already have between them, and it survives the recolour on
  every theme.
- Renaming the entry point — which every release does, to get past the
  shell's QML cache — no longer rewrites anything it should not. "chief/"
  also lives inside "omarchief/", and a blanket replace had quietly pointed
  every documented path, and one of the checking tools, at a state directory
  that does not exist. `tools/rename-entry` anchors the replacement, and the
  spelling is now asserted by the tests.

## 3.9.0 — 2026-08-22

- The creature blinks. The resting face with its eyes closed, for an
  eighth of a second every few seconds, sometimes twice — and it snaps
  rather than fades, because a blink you can watch fade is not a blink.
  It sticks its tongue out too, now and then, among the resting faces.
- It can be tucked into the edge when it sits on something you are
  reading: it slides mostly off its nearest side and leaves a sliver.
  Click the sliver and it comes back. Tucked, it holds still.
- It reads on every theme. An audit of all twenty-two shipped themes
  found it under the 3:1 WCAG asks of graphics on five of them, and a dim
  smudge on far more: the recolour scaled the artwork's vividness by the
  accent's own, which turns a neon character into wet cardboard on the
  many themes whose accent is a muted mid-tone — and paints it the same
  washed hue as the desktop it stands on. What a theme lends is its hue;
  vividness now survives whole for any accent with colour in it and is
  given up only as the accent approaches grey. The sheet is then lifted
  until the body clears 3:1 against the desktop behind it. Worst case
  across the twenty-two is 3.04:1, and no theme lost its look.
- Wearing a theme again is instant: sheets are kept per accent and
  desktop, so switching back is a comparison and no redraw. A theme worn
  for the first time takes about three quarters of a second.
- The standing instructions are a real system prompt for Claude, passed
  on every turn instead of only the first, so they do not scroll out of
  reach in a long conversation and the console answers the same session
  at full length. They now also say what the creature may not do unasked,
  to answer in the language you write in, and that a right-click carries
  a long answer into the console.

## 3.3.0 — 2026-08-22

- The bar has the settings you change more than once: wear your theme or
  keep the colours it was drawn in, idle expressions and how often, size,
  and which of your installed pets is standing there. Everything else is
  still a config key — the bar is not the place for all nineteen of them.
- Two more creatures ship with it: Gritty head-on, and a rally car. Both
  are single drawings, because a pet may be one picture.
- A creature drawn in profile turns around on the right of the screen, so
  its face stays pointed inwards and its cable runs off the nearer edge.
  It pivots rather than snapping. Artwork says whether it may be flipped:
  the rally car is a front view whose liveries would read backwards, and
  says no.
- Decorations go to the creature they trail from. A sleeping creature's
  zZz reaches far enough right to brush the cube beside it, and the one
  being carried was wearing a stray z on its cheek.
- The status file says where the creature stands and which way it faces,
  and `place` puts it somewhere along the edge from a script.

## 3.1.0 — 2026-08-22

- A resting creature is not a frozen one: every so often it looks up
  wearing another of its faces for a few seconds, then goes back to
  resting. Only expressions that carry no news are borrowed — you should
  not find it looking alarmed for no reason — and never while the agent
  is doing anything. The bar popout has a switch for it, which is where
  a setting belongs; `expressions` and `expressionChance` are the config
  keys behind it.
- The popout tells settings from actions now: a setting is a real switch
  with a description under it, the way the rest of the desktop does it.
- It remembers which screen it lives on, not only where on that screen,
  and comes back there after a restart. Losing a monitor moves it; it
  does not move house, and it returns when the screen does.
- Releasing the mouse outside the hitbox left it wearing its
  being-carried face; it reads the button itself now.

## 3.0.0 — 2026-08-22

- A pet can be a set of expressions rather than a set of animations: one
  drawing per mood, nothing moving of its own accord, and a hand the only
  thing that ever shifts it. `faces` maps a mood to a cell, `columns`
  lets a sheet be any grid rather than the ecosystem's eight-wide strip,
  and a still pet ignores `followFocus` and `roam` whatever the settings
  say. Expressions dissolve into one another rather than snapping, and
  being picked up has a face of its own.
- Gritty is nine faces now — resting, cross, downcast, thinking, pleased,
  delighted, startled, asleep, and fond of you — and the sheet went from
  2.3 MB to 460 kB.
- `tools/build-faces.py` builds such a sheet from a grid of renders. It
  finds each body by eroding away the decorations fused to it, cuts every
  cell relative to that body's own footing, and then slides each one
  against the first until they line up: measured afterwards, all nine
  land within nothing of each other.

## 2.3.0 — 2026-08-22

- The performances are slow enough to follow and dissolve between poses
  instead of cutting. Every frame is held for at least a second and a
  third — the balloon drifting away used to flash past in under three
  tenths — and a row now lasts about ten seconds, told once through
  rather than looped three times. The dissolve is a fraction of the hold,
  so a walk cycle at a seventh of a second stays crisp while a held pose
  blends over a quarter second.

- The performances finally play. They were gated on a bare "idle" mood,
  and a desktop that codes nearly always has an agent window open, which
  reads as "parked" — so on a real machine they never ran at all, not
  once. A quiet moment now means any mood with nothing pressing in it.
  A short performance also goes round more than once, because three
  seconds in the corner of a screen is something nobody ever catches.
- An answer stays up for as long as it takes to read and then leaves on
  its own, waiting while your pointer rests on the chief; errors stay
  until clicked. The bar popout keeps what was said last.
- Markdown the agent sends anyway is turned back into prose.
- A runner that exits at once without a word is tried once more, and one
  that fails for a reason now says the reason, from its own stderr.
- The agent keeps standing notes in the plugin's state directory, named
  in its preamble, so what you told it last week outlives the
  conversation — with any agent. `sessionIdleMin` sets how long a
  conversation itself lives.
- A themed sheet is redrawn when the artwork changes, not only when the
  theme does: a pet update no longer wears last version's colours.
- Rendered art is scaled with filtering and mipmaps; a pet that is
  pixel art says `pixelArt` and keeps its hard edges. A pet may also ask
  for its own `size` — the bundled one asks for 150.
- The bar popout answers to `omarchy-shell omarchief.menu`, like every
  first-party popout does.

## 2.2.0 — 2026-08-22

- The creature has a home: the bottom-left corner by default, on
  Hyprland's own gap so its feet land where a window's edge does, drag it
  anywhere and that becomes its place, remembered per monitor. Roaming is
  opt-in now.
- Idle activities: pets can declare performances in atlas rows past the
  standard nine, timed frame by frame from how much the picture changes,
  with a rest between them and no interruptions when the agent needs you.
  Gritty brings six.
- Every agent state has its own face — digging while it works, a balloon
  held up when it needs you, X eyes on failure, a diamond when it
  finishes, asleep under a cat when the limits are spent.
- One builder assembles the whole sheet at one scale, so the creature is
  the same size and stands on the same line in every row; it also drops
  what leaks in from neighbouring cells and marks rows that never change
  so they are not repainted.
- The console can open over the creature rather than dropping from the
  top (`consoleAt`), Hyprland dispatches are spoken in Lua as 0.56
  requires, an agent session is taken down whole rather than leaving
  children behind, and a silent agent is named as such.
- Artwork that will not load hands the stage back to the drawn body
  rather than leaving nothing there.
- Wearing a theme is one story again: a pet that names its hue window is
  redrawn properly, and the live tint is the fallback when that cannot run
  rather than a second, parallel mechanism.
- The cell shape is read from the pet's own sheet instead of assumed, so a
  pet drawn on a different grid is no longer stretched.
- docs/pets.md documents the pet format, docs/development.md the shell's
  component cache and what was verified about displays.
- Store images are drawn from the artwork rather than from a screenshot of
  a working desktop, and the bundled renders carry their own licence note.

## 2.1.0 — 2026-08-22

- Pets can wear the theme: a `themeable` hue window lets Omarchief redraw a
  spritesheet in the theme's accent on every theme change, keeping
  lightness and everything outside the window exactly as drawn. Cached,
  stamped, and self-healing when the cache is cleared.
- Gritty ships with the plugin, together with its source renders and
  `tools/build-pet.py`, which cuts a rendered sheet on its own grid and
  picks the playback order by scoring every closed cycle.
- `pet.json` learns `walkFrames`; sprites no longer get a synthetic bounce
  on top of a drawn gait, and frames are normalised with one shared scale
  so the creature stops shrinking between poses.
- A `stroll` command asks for a walk on the spot.

## 2.0.0 — 2026-08-22

- The chief speaks: orders run the default agent headless — claude,
  opencode, and codex natively — and answer in a speech bubble; sessions
  survive follow-ups and escalate into the Quake console, which opens on
  the chief's monitor and resumes the very same conversation.
- One world, many screens: a strip per monitor, dive-and-rise travel that
  follows your focus, travel time scaled by real distance, hotplug
  fallback, and an agent that may send its own body ahead.
- A bar control widget (status dot, popout with ask/console/send-to-
  monitor/hide/pick-agent) fed by a published status file at
  ~/.local/state/omarchy/omarchief/status.json.
- Pets: any Codex/Petdex spritesheet walks the desktop with its real walk
  rows; pet.json learns themeTint (accent-colorized via the theme, live)
  and sleepRow (a real sleeping pose).
- First-run greeting, clickable urgent/error bubbles with a console
  escape, Style-contract scaling, keyboard-focus priming for the order
  form, and a talk session that ends when the default agent changes.

## 1.0.0 — 2026-08-21

- Initial release: theme-procedural creature, Quake-console orders via
  omarchy-agent, rate-limit energy, OmaPets hook states, Codex/Petdex
  sprite bodies.
