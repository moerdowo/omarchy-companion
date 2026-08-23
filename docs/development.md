# Working on Omarchief

The plugin runs inside `omarchy-shell`, the long-lived Quickshell process
that also draws the bar. That is convenient — the creature costs one
process, not two — and it has one consequence worth knowing before it
costs you an afternoon.

## The shell caches components by URL

Saving a file under `~/.config/omarchy/plugins/` makes the shell log
`Local plugin changed, reloading`, and for data — `shell.json`, a pet's
`pet.json`, our own config — that reload is real. For **QML and
JavaScript it is not**: the engine re-mounts the component it already
compiled for that URL. Directory listings are cached too, so a file you
add to a directory the shell has already read comes back as
`File name case mismatch` rather than as your new file.

So while you are changing QML, one of these is true:

- **Restart the shell** (`omarchy restart shell`) — honest, and fine when
  nobody is working on that desktop.
- **Give the entry point a URL the session has never compiled** — a new
  directory name, updated in `manifest.json`, followed by
  `omarchy-shell shell rescanPlugins`.

The second trick is what makes it possible to iterate on a desktop
somebody is using. It also means this repository's history contains a
long line of directory renames that carry no meaning: they were cache
busts, and `keystone/` is where the code lives now.

## Iterate outside the live plugin

The shell watches the whole plugin directory, including documentation.
An agent or an editor that saves often will reload the plugin on every
keystroke — eighty-four reloads in three minutes, in one measured case,
each one tearing the creature down and putting it back up. Work in a
clone and pull:

```bash
git clone ~/.config/omarchy/plugins/io.github.daventhedude.omarchief /tmp/omarchief
# … change, test, commit there …
cd ~/.config/omarchy/plugins/io.github.daventhedude.omarchief
git pull /tmp/omarchief master     # one reload, not fifty
```

## Checking your work

```bash
node --test tests/model.test.mjs                 # the pure logic
qmllint -I /usr/share/omarchy/shell keystone/Chief.qml
omarchy-shell omarchief status                   # what the creature thinks
journalctl --user -t omarchy-shell -f            # what the shell thinks
```

`qmllint` cannot parse the typed IPC handler functions Quickshell
requires (`function ask(): void`) and exits 255 without a word on files
that contain them. That is a false negative: lint `Chief.qml` and
`BarWidget.qml`, and read the journal for `ChiefPanel.qml`.

Two QML mistakes cost real time here and produce no useful error:
declaring two handlers for the same signal on one object, and putting a
`Behavior` on a `readonly property`. Both take the whole panel down; the
journal names the line.

## The cache, and how it lies to you

Edit a `.qml` file, run `rescanPlugins`, and the running shell will
cheerfully keep running the version it compiled the first time.
**Neither `rescanPlugins` nor `reloadConfig` drops it**, and there is no
warning: your change simply does nothing, which sends you hunting for a
bug in code that never ran.

It is worth knowing where this actually comes from, because the obvious
guess is wrong. Qt is not the culprit — a plain Quickshell process
watching a `file://` URL reloads it properly, which is easy to confirm
with a fifteen-line probe. It is the shell's own bookkeeping: it keeps
the component it compiled for a plugin, keyed by the entry-point URL
(`loadPluginWidget` in `shell.qml`), and a URL it has already seen is a
component it already has. Everything the entry point pulled in at compile
time — `Chief.qml`, `Model.js` — is inside that component and just as
stale.

Two ways out:

- `omarchy restart shell` — the honest one, and the one that interrupts
  whoever is using the desktop.
- `tools/rename-entry <old> <new>` — rename the directory the entry points
  live in and update `manifest.json` with it. A new URL is a new
  component, which is why the history of this repo carries rather a lot of
  those renames. Use the tool rather than a search-and-replace: `chief/`
  also lives inside `omarchief/`, and rewriting it by hand once pointed
  every documented path, and one of the checking tools, at a state
  directory that does not exist. The tool anchors the replacement to a
  path segment, and the tests fail if the spelling drifts anyway.

This is a development problem, not a shipped one: a fresh install
compiles what is on disk. But it will hide your work for as long as you
let it, so when a change appears to do nothing, check that the running
code is the code you wrote before you look anywhere else. The status
file is the cheapest way to ask — publish a field from the new code and
see whether it appears.

## Proving it works from cold

Everything you test in a running shell is tested in a process that has
already loaded the plugin many times, which says nothing about a machine
starting it for the first time. `tools/coldstart-check` answers that
without restarting anybody's desktop: it launches a second Quickshell —
one that has compiled nothing — points it at the plugin with the windows
suppressed, and asks the panel what it managed to read.

```bash
tools/coldstart-check
# COLDSTART body: sprite rows: 16 activities: 6 still: 8 walk: 6
# COLDSTART world: DP-1 screens: 3 gap: 10 home: 45 agent: claude
# coldstart-check: ok
```

A compile failure and a panel that mounts but reads nothing both come
back as a non-zero exit.

## Showing every face at once

`tools/face-parade` drives the creature through every mood it has a face
for — writing the same hook file the agent writes and the same usage
record the rate limits live in — waits for it to notice each one, and
photographs it. What comes out is a contact sheet of the pet's whole
range, taken off the screen rather than cut out of the sheet:

```bash
tools/face-parade faces.png
#   asked for  mood became
#   idle       idle         ok
#   working    working      ok
#   ...
```

Both files are put back exactly as they were found. It waits for each
mood to arrive rather than sleeping a fixed spell — a file watcher, a
reload and a re-evaluation take a moment, and how long is not ours to
guess. Sleeping instead of waiting is what made this flaky the first
three times.

## Catching a glance

A resting creature looks up wearing another face every twenty seconds or
so, for three. That is hard to catch on purpose and easy to fool yourself
about, so the status file publishes the decision — `glancing` holds the
cell it is wearing, or an empty string — separately from the pixels.
Watch that rather than the screen, and turn the odds up while you do by
turning the odds up while you do — `omarchy-shell omarchief often often`,
or `expressionChance` on this plugin's `shell.json` entry.

A word of warning about comparing the creature on screen against the
sheet: the pixels that tell two faces apart are often *outside* the body —
a heart, sparkles, a zZz — so a naive match ends up comparing wallpaper
and confidently reporting the wrong face. A tool that did exactly that
was written, believed for an hour, and deleted.

## Proving the performances still play

`tools/perform-check` asks the installed plugin to play each of its
performances and times them through the status file, which is the one
thing that cannot lie about what is on screen:

```bash
tools/perform-check        # two rounds
#   performance     ran for  passes
#   balloon           10.1s  x3  ok
#   ...
#   perform-check: ok
```

Two rounds matter: the bug this was written for let the first
performance run its full length and cut every one after it short, so a
single round would have passed. A walk to another screen cutting one
short is reported as an interruption rather than a fault, because that
is the creature behaving correctly.

## Displays

Sizes are logical pixels, so the creature is the same size on a scaled
output as on an unscaled one, and its sheet is drawn with nearest-neighbour
sampling — pixel art upscaled on a HiDPI screen stays crisp rather than
going soft. Rotation is handled by working from the screen's reported
geometry rather than the compositor's pre-transform numbers; a portrait
monitor is simply a narrow screen. Both were exercised on a rotated
1440×2560 output; fractional scaling has been reasoned about but not run,
because setting it up means changing somebody's display configuration.
