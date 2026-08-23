# Working on Omarchief

Omarchief follows Omarchy 4's regular plugin contract. The manifest exposes
one resident `service` and one `bar-widget`:

- `keystone/Service.qml` owns the creature, agent turn, state, and IPC.
- `keystone/BarWidget.qml` is a thin bar control that obtains that singleton
  through `shell.serviceFor(moduleName)`.
- `keystone/Panel.qml` contains the widget's overview and settings popout.
- `keystone/Chief.qml` is presentation and interaction only.
- `keystone/Model.js` contains pure logic covered by Node tests.

Keeping state in the service matters. Omarchy creates a bar widget on every
monitor, but there must only ever be one conversation, creature, and IPC
target.

## Local checks

Run these before testing the live desktop:

```bash
omarchy plugin validate .
node --test tests/*.test.mjs
/usr/lib/qt6/bin/qmllint --ignore-settings -W 0 \
  -i /usr/share/omarchy/shell/Commons/qmldir \
  -i /usr/share/omarchy/shell/Ui/qmldir \
  --missing-property disable \
  --signal-handler-parameters disable \
  --unqualified disable \
  keystone/Chief.qml keystone/Service.qml \
  keystone/BarWidget.qml keystone/Panel.qml
tools/coldstart-check
```

The Node suite checks the model, manifest-to-entry-point contract, bundled
pet metadata, repository hygiene, and the service/widget boundary. The
cold-start check is the integration test: it creates an empty HOME and XDG
environment, installs this checkout there with a real `manifest.json` and
`shell.json`, starts a fresh Quickshell process, and requires the bundled
Gritty sheet to load. It does not read the developer's installed pets or
plugin settings.

Use Qt 6's `qmllint`; `/usr/bin/qmllint` can still be Qt 5 on Omarchy and
silently rejects QML 6 syntax. The three disabled categories are false
positives for shell-injected objects, loader properties, and incomplete
Quickshell qmltypes. `-W 0` turns every other warning into a failure. The
cold-start check remains mandatory because only a real shell process can
exercise manifest injection, plugin discovery, asynchronous file loading,
and the first-render lifecycle.

## Live iteration

Install the committed checkout into a disposable desktop or test account.
`plugin add` clones it into Omarchy's user-owned plugin directory; edit that
installed clone for live iteration:

```bash
omarchy plugin add file:///absolute/path/to/omarchief --enable
cd ~/.config/omarchy/plugins/io.github.daventhedude.omarchief
$EDITOR .
journalctl --user -t omarchy-shell -f
```

Omarchy 4 watches installed plugin files, clears the QML component cache,
rescans the manifest, and reloads the affected service and widget. A shell
restart should not be part of the normal edit loop.

The service writes its public snapshot to
`$XDG_STATE_HOME/omarchy/omarchief/status.json` (normally
`~/.local/state/omarchy/omarchief/status.json`). For the running version:

```bash
omarchy-shell omarchief status
```

The status command and the journal are more reliable than assuming the copy
being edited is the copy currently loaded.

## Visual review

Test at least one narrow and one wide bar, keyboard-only navigation, mouse
navigation, a long agent name, an empty agent list, an invalid custom pet,
reduced motion, an interrupted agent turn, and a multi-monitor layout with a
non-zero monitor origin. Verify both light and dark themes.

Release screenshots must render the real plugin components at normal scale,
either from an installed copy or from a clean capture harness that loads the
unmodified `Service.qml`, `BarWidget.qml`, `Panel.qml`, and `Chief.qml`. A
harness may supply shell and bar state to stage a reproducible scene, but it
must not redraw or mock the plugin UI. Do not use debug overlays. Check the
chief, order field, answer bubble, overview, and settings panel independently;
a polished hero screenshot cannot hide a broken state.

## Pet work

`tools/build-faces.py` builds expression grids and `tools/build-atlas.py`
builds animated sheets. `tools/omarchief-recolor` is the same deterministic
recolouring path used at runtime. Original Gritty renders are distributed as
a separate release asset; [tools/source/README.md](../tools/source/README.md)
documents their names and build commands.

The complete schema and drawing rules are in [pets.md](pets.md). A release
must include each `pet.json`, the exact spritesheet it names, and its NOTICE.
Build the separate, reproducible source asset with:

```bash
asset="${TMPDIR:-/tmp}/omarchief-artwork-sources.tar.gz"
tools/build-source-archive "$asset"
tools/build-source-archive --check "$asset"
```

The helper fixes archive order, ownership, permissions, timestamps, and gzip
metadata. It prints the SHA-256 to record in the release notes. The ignored
high-resolution inputs and the resulting archive are release material, never
part of the installed plugin checkout.

## Release gate

A green development checkout is not a release. The marketplace validates one
public commit, and that exact commit must also be the one tested out of the box.
Before publishing or preparing a marketplace submission:

1. Finish the release commit, then require an empty `git status`. Record
   `release_sha=$(git rev-parse HEAD)` and confirm that the repository's public
   default-branch HEAD resolves to that full 40-character SHA. Never submit a
   dirty working tree, a local-only commit, or a moving commit that was not the
   one reviewed.
2. Clone that public repository into a new temporary directory. Run every
   local check above from the clone, not from the development checkout. Confirm
   `manifest.json`, the changelog version/date, current screenshots, notices,
   and every intended deletion are present in the clone.
3. On a disposable Omarchy 4 user with no Omarchief config, pets, state,
   or prior scratchpad, install with the README command. Accept the normal
   warning and placement prompt. Require one service, one widget, bundled
   Gritty on first paint, and exactly `gritty` plus `quattro` in the picker.
4. Exercise every visible action once and every setting twice, including the
   return path, keyboard-only use, a narrow and wide bar, multiple monitors,
   fullscreen avoidance, reduced motion, light/dark theme changes, theme off
   and back on, and the ImageMagick-missing fallback.
5. Test no default agent, the desktop default, and every agent Omarchy exposes.
   Bubble-capable agents must stream one turn only. Console-only and explicitly
   selected agents must open the selected CLI, never a stale alias. On the very
   first Quake-console open, require exactly one new
   `org.omarchy.agent` window in `special:scratchpad`; repeat while hidden,
   visible, resumed, and on another monitor.
6. Confirm cancellation, timeout, non-zero exit, agent switching, shell reload,
   and plugin disable leave no descendant process or stale callback capable of
   affecting a later turn. Verify the trust copy against the actual command
   line of each supported CLI version.
7. Upgrade a clean v3.38.0 install through the public update path. Require one
   canonical bar entry, no top-level duplicate, preserved supported settings,
   no resurrected legacy values, and a working service/widget after the live
   reload.
8. Remove through the README command both while idle and while an agent is
   running. Require the service, widget, and child process tree to disappear;
   no hook or external application setting may remain. Only the documented
   state/history directory may survive.
9. Build and byte-check `omarchief-artwork-sources.tar.gz` with the helper
   above. Inspect its seven exact members, record the printed SHA-256, and
   attach that file to release `v$(jq -r .version manifest.json)`. Confirm the
   archive itself and `tools/source/*.png` are absent from `git ls-files`.
10. Require the GitHub checks for `release_sha` to pass. After submission,
    require marketplace compatibility validation and the Automated Security
    Baseline to refer to that same SHA before approval. Re-run the process for
    any changed commit; old evidence does not approve new code.

For the marketplace listing, use category `Productivity` and the tags `ai`,
`bar`, and `quickshell`. Review all five submission checkboxes against the
exact release commit, including ownership or permission for the plugin and
preview assets, before explicitly authorizing the issue.

Publishing, release creation, and marketplace submission are separate,
explicit steps. These checks never commit, push, tag, publish, or submit
anything themselves.
