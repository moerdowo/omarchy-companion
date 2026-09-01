# Changelog

## 2.0.0 — 2026-09-01

Renamed, and reduced to one companion. Both are breaking: the plugin id
changed, so this installs beside the old one rather than updating it, and the
bundled spritesheet pets are gone.

- Renamed to **Omarchy Companion**: id `io.github.moerdowo.omarchycompanion`,
  `omarchy-shell companion ...`, user pets in `~/.config/omarchy-companion/`,
  state in `$XDG_STATE_HOME/omarchy/companion/`. Nothing carries over from the
  previous id; settings are re-entered once.
- Removed the bundled Gritty, Gritty head-on and Quattro artwork. The
  spritesheet engine stays, so a pet made for this ecosystem still works, and
  so do `tools/build-atlas.py`, `tools/build-faces.py` and
  `tools/companion-recolor`. With one companion bundled the **Companion**
  picker has nothing to choose between and is left out.
- Kept those paths tested without shipping artwork to test them with.
  `tools/coldstart-check` now plants a spritesheet pet in its isolated `HOME`
  and loads it in a real shell — which proves the route a person's own pet
  actually arrives by, something bundled artwork never did — and the two
  theming tests generate a themeable sheet with ImageMagick. Generated art is
  the better fixture: a known hue, an even lightness range, and an exactly
  known set of pixels that must not move.
- **Stopped turning into a progress bar while working.** An agent turn used
  the catalogue's `thinking` state, which dissolves the body into three pulsing
  dots. That is faithful — it is one of the fourteen states measured off the
  video — but on a desktop three pulsing dots are a loading indicator, and a
  companion that vanishes into one the moment you ask it something is the
  opposite of the point. A turn now keeps the body and the face and puts the
  thought in the eyes: a tilted head, and a slow sweep that replaces the
  resting drift rather than adding to it, so it reads as thoughtful instead of
  agitated. `thinking` stays in the catalogue; nothing maps to it.

## 1.2.0 — 2026-09-01

- Gave the drawn companion something to do while nothing is happening. Left
  alone it now performs: `notice` looks up at whoever is at the desk, `doze`
  falls asleep for a while, and `wink`, `stretch`, `egg`, `hexagon`, `tumble`,
  `orbit` and `comet` are the rest of the repertoire.
- Made `notice` a gaze rather than a pose. The eyes travel round the sphere
  they live on — behind the body and back the other side — and land facing
  you, because a whole turn is the same angle as none and so arrives exactly
  where it aimed. On a shape that is not a circle they slide instead: the eyes
  are re-seated to the real outline, so turning them round a triangle would
  make them hop along its profile. A real pointer outranks the script, since
  the creature should look at the person rather than through them.
- Kept the performances neutral, which is a rule and not a preference. The
  state catalogue also holds `thinking`, `notify`, `alert` and `burst`, and
  those four are how the plugin says something has happened; a creature that
  played one for its own amusement would be crying wolf. A test enforces it.
- Reused the existing activity machinery rather than building a second one, so
  the *how often* and *how long it rests* settings, the Play button and
  `play <name>` all work on the drawn companion exactly as they do on a
  spritesheet one.
- Separated walking from performing. They were one flag, and bundling them had
  quietly cost the drawn companion every idle performance it has: it is still,
  because it has no legs, and *still* was also being read as *has nothing to
  do with itself*.

## 1.1.1 — 2026-09-01

- Fixed idle expressions never happening. `idleExpression` used its random
  source as a number where it is a function, so the index was `NaN` and the
  expression `undefined`, which QML refused to assign — costing the whole
  feature while failing nowhere near the mistake. Its test asserted only that
  the result was not the expression already worn, which `undefined` satisfies;
  it now asserts what was returned is a real expression and that every one in
  the pool is reachable.
- Reported a drawn companion as a body in `status`. The one-line status and
  the JSON snapshot both read "has a spritesheet" as "has a body", so a
  perfectly healthy drawn creature described itself as the fallback. The
  snapshot also refreshes when the drawn pet resolves, which it previously did
  not, leaving the file stale until something unrelated happened to change.

## 1.1.0 — 2026-09-01

- Brought the whole size scale down: S/M/L/XL are now 48, 64, 88 and 120
  pixels, against 96, 130, 150 and 190. The old numbers were chosen for the
  spritesheet companions, whose drawn faces need pixels to read at all. The
  drawn companion is two capsules on a shape and stays legible far smaller, so
  the smallest option can be genuinely small rather than merely the smallest of
  four large ones.
- Made the drawn companion recommend 48 rather than 130, so a fresh install is
  small. A size chosen by hand still wins, and the bundled spritesheet pets
  keep their own recommendations — 150 for Gritty is what its face needs, and
  the picker offers it as a custom value.

## 1.0.0 — 2026-09-01

Omarchy Companion forks [Omarchief](https://github.com/daventhedude/omarchief) 4.0.0
and replaces its character. Everything about the desktop is Omarchief's; the
entries below are what this fork changed. It carries its own plugin id, so it
installs beside Omarchief rather than over it, and shares none of its settings
or state.

- Added **bloub** as the default companion, and a third kind of pet to support
  it: one that declares a renderer instead of a spritesheet and is drawn every
  frame from a radial profile. `keystone/Bloub.js` is a port of
  [bloub](https://github.com/jeremy-prt/bloub) — an SVG recreation of the x.ai
  bot avatar whose fourteen states, silhouettes, easings and eye geometry were
  measured off the reference video. Only the output changed: points and
  matrices for a QML Canvas where the original emits SVG path strings.
- Added the customiser the drawn body makes possible: **eight shapes**, **the
  original twelve colours** plus a plain white and the desktop's own accent,
  and **sixteen resting expressions** — all three in the bar popout, in
  `shell.json`, and on the command line. Every change morphs rather than cuts,
  because all the shapes are sampled at the same angles.
- Mapped the plugin's moods onto the character's states rather than onto a
  grid of drawings: working thinks in three dots, waiting grows a
  notification pip, an error becomes an exclamation mark that runs across the
  screen, finishing bursts and reassembles, sleeping curls into a bouncing
  dot, and being carried widens the eyes. Tired and affectionate moods change
  the resting face instead.
- Made the drawn companion watch the pointer while it is over it, and keep
  Omarchief's idle-expression cadence, so a person who changes companion does
  not also change how lively their desktop is.
- Added `keystone/BloubFit.js`, generated by `tools/build-eyefit` from the
  upstream eye-fit solver: where the face has to sit so that neither capsule
  crosses the outline of a shape that is not a circle. A test checks the
  result geometrically, for every shape against every expression, across the
  whole resting drift.
- Added `tools/verify-bloub-port`, which samples both engines over every
  state, shape, expression and a set of awkward dates and compares about
  seventy thousand values against the project the port came from. It is a
  release check, not a unit test: it needs the network.
- Added `tools/build-preview`, which redraws `preview.png` and
  `docs/expressions.png` from the shipped renderer, so the pictures in the
  documentation cannot drift from the character.
- Renamed everything the plugin owns: id `io.github.moerdowo.omarchycompanion`,
  command `omarchy-shell companion ...`, user pets in `~/.config/omarchy-companion/`,
  state in `$XDG_STATE_HOME/omarchy/companion/`. OmaPets-compatible discovery
  and status reading are unchanged.
- Kept the three spritesheet companions, the atlas and face builders, and the
  theme-recolour tool. Bloub is only the default.
- **Removed** `docs/settings.png`: it showed the previous name and a companion
  that is no longer the default. `docs/expressions.png` replaces it in the
  README; a fresh settings capture needs a running session.

## 4.0.0 — 2026-08-23

- Rebuilt on Omarchy 4's service plus bar-widget architecture. The resident
  service owns the creature, conversation, IPC, and state; every bar
  renders a lightweight control onto that one source of truth.
- Replaced the status-file-driven menu with a native overview and settings
  panel that talks to the service directly, stays open while choices change,
  and supports keyboard navigation.
- Made agent turns explicit and at-most-once: no silent retry, no replacement
  of a running order, a real Stop action, and no stale timeout or cleanup that
  can terminate a later turn.
- Fixed clean installs so bundled Gritty is discovered without a pet copied
  into the user's config, starts at size L, and appears at the bottom-right of
  the active screen. Legacy settings and duplicate shell entries migrate into
  one canonical bar entry.
- Matched the companion's theme repaint to Omarchy's own 420 ms, centre-out
  wallpaper reveal. Cached and live-tinted coats now transition without raw
  colour flashes or a visible Quattro orientation change.
- Tightened click-versus-drag handling, prompt focus, tucked-edge reachability,
  speech placement, panel scrolling, and input shielding across one- and
  multi-monitor layouts.
- Followed Omarchy 4.1's native Quake-console workspace contract when present,
  with the Omarchy 4.0 scratchpad retained as a safe compatibility fallback.
- Removed the Claude hook installer and its edits to external settings.
  Existing OmaPets-compatible state remains an optional, passive input.
- Restored the approved Quattro artwork with complete upstream Omarchy MIT
  attribution, made the car face inward on either side of a screen, and
  restored the deliberately stark head-on Gritty portrait. Python caches and
  other local build artefacts are excluded from releases and checked in CI.
- Added an isolated HOME/XDG cold-start gate, service/widget contract tests,
  strict pet schema checks, pinned CI actions, and least-privilege workflow
  permissions.

## 3.38.0 — 2026-08-23

- Last release of the original panel plus status-file bar architecture.
- Added multi-monitor placement, bubble conversations, Quake-console
  escalation, persistent state, theme-aware pets, idle expressions, and
  agent/rate-limit mood states across the 2.x–3.x series.
- Added inline `shell.json` settings and discovery of Omarchy's configured
  agents and compatible pet folders.

Version 4 migrates supported 3.x settings automatically. The Git history
retains the detailed development log for the earlier experimental releases.
