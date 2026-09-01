import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "Model.js" as Model
import "Bloub.js" as Bloub

// Omarchy Companion — your desktop's chief of staff.
//
// Resident service and stage. One click-through strip per monitor makes the
// whole arrangement a single walkable world: the chief lives on exactly one
// screen at a time, dives under the bottom edge to travel, and rises on the
// target screen. Orders are spoken — a typed wish runs the default agent
// headless and the reply lands in the chief's speech bubble; the same
// session escalates into the Quake console when a job deserves one.
//
// Safety by construction: an order runs the same agent, with the same
// trust, as Omarchy's own agent keybinding. Every other data source is
// read-only (theme colors, the usage records the first-party Agents widget
// reads, the OmaPets-compatible hook status file, and window/workspace
// metadata). No network of its own, no telemetry.
Item {
  id: root

  // The shell hands panels their manifest; __sourceDir is how the plugin
  // finds the tools it ships with.
  property var manifest: ({})
  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  property bool stateReady: false
  property bool stateInitDone: false
  Process {
    id: stateInit
    command: ["bash", "-c",
      "umask 077; mkdir -p -- \"$1\" \"$2\"; chmod 700 -- \"$1\" \"$2\"; "
      + "find \"$1\" -maxdepth 1 -type f -exec chmod 600 -- {} +",
      "companion-state", root.statusDir, root.themedDir]
    onExited: function(code) {
      root.stateReady = code === 0
      root.stateInitDone = true
      statusWrite.restart()
    }
  }

  function protectStateFile(path) {
    Quickshell.execDetached(["chmod", "600", "--", String(path || "")])
  }

  // ------------------------------------------------------------ user config

  // Settings live inline on this plugin's own entry in shell.json. Versions
  // before 4.0 also asked people to add a top-level plugin entry and kept a
  // second JSON file; migrate both once, then use the bar entry as the single
  // source of truth.
  property var shell: null
  readonly property string entryId: manifest && manifest.id ? String(manifest.id)
                                                            : "io.github.moerdowo.omarchycompanion"
  readonly property var entrySettings: {
    if (!shell || !shell.shellConfig) return null
    var c = shell.shellConfig
    var sections = ["left", "center", "right"]
    var lay = c.bar && c.bar.layout ? c.bar.layout : ({})
    for (var s = 0; s < sections.length; s++) {
      var arr = lay[sections[s]]
      for (var i = 0; arr && i < arr.length; i++)
        if (arr[i] && String(arr[i].id) === entryId) return arr[i]
    }
    var ps = Array.isArray(c.plugins) ? c.plugins : []
    for (var j = 0; j < ps.length; j++)
      if (ps[j] && String(ps[j].id) === entryId) return ps[j]
    return null
  }
  property var fileCfg: ({})
  property bool legacyLoaded: false
  property bool configMigrated: false
  readonly property string migrationMarker: "_companionConfigVersion"
  readonly property int configVersion: 1

  function migrationMarked(config) {
    if (!config || typeof config !== "object") return false
    var sections = ["left", "center", "right"]
    var layout = config.bar && config.bar.layout ? config.bar.layout : ({})
    for (var s = 0; s < sections.length; s++) {
      var entries = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
      for (var i = 0; i < entries.length; i++)
        if (entries[i] && String(entries[i].id) === entryId
            && Number(entries[i][migrationMarker]) >= configVersion) return true
    }
    var plugins = Array.isArray(config.plugins) ? config.plugins : []
    for (var p = 0; p < plugins.length; p++)
      if (plugins[p] && String(plugins[p].id) === entryId
          && Number(plugins[p][migrationMarker]) >= configVersion) return true
    return false
  }

  readonly property bool legacyMigrationDone:
    shell && shell.shellConfig ? migrationMarked(shell.shellConfig) : false
  readonly property var cfg: {
    var out = ({})
    if (!configMigrated && !legacyMigrationDone) for (var k in fileCfg)
      if (root.allowedSetting(k)) out[k] = fileCfg[k]
    var e = entrySettings
    if (e) for (var j in e) if (root.allowedSetting(j)) out[j] = e[j]
    return out
  }
  readonly property string configFile: root.home + "/.config/omarchy/companion.json"
  readonly property var settingKeys: [
    "activity", "activityChance", "activityRestSec", "agent", "color",
    "edgeGap", "expression", "expressionChance", "expressions", "followFocus",
    "frameIntervalMs", "hideOnFullscreen", "patienceSec", "pet",
    "promptPreamble", "reduceMotion", "roam", "screen", "sessionIdleMin",
    "shape", "size", "speakMax", "talk", "theme", "themeTint",
    "turnTimeoutSec", "workdir"
  ]

  function allowedSetting(key) {
    return root.settingKeys.indexOf(String(key || "")) !== -1
  }

  function mergeSettings(base, extra) {
    var out = ({})
    for (var a in base) if (root.allowedSetting(a)) out[a] = base[a]
    for (var b in extra) if (root.allowedSetting(b)) out[b] = extra[b]
    return out
  }

  function migrateConfig() {
    if (configMigrated || !legacyLoaded || !shell || !shell.shellConfig
        || typeof shell.persistShellConfig !== "function") return

    var before = shell.shellConfig
    var next = JSON.parse(JSON.stringify(before))
    if (!next.bar || typeof next.bar !== "object") next.bar = ({})
    if (!next.bar.layout || typeof next.bar.layout !== "object")
      next.bar.layout = ({ left: [], center: [], right: [] })
    if (!Array.isArray(next.plugins)) next.plugins = []

    // Once a canonical entry carries the marker, the retired file is inert.
    // This matters after a person removes a migrated key: a later restart
    // must not resurrect the old value from ~/.config/omarchy/companion.json.
    var merged = root.mergeSettings(({}), root.migrationMarked(before) ? ({}) : fileCfg)
    var top = null
    for (var p = 0; p < next.plugins.length; p++) {
      if (next.plugins[p] && String(next.plugins[p].id) === entryId) {
        if (!top) top = next.plugins[p]
        merged = root.mergeSettings(merged, next.plugins[p])
      }
    }

    var sections = ["left", "center", "right"]
    var foundBar = false
    for (var s = 0; s < sections.length; s++) {
      var arr = Array.isArray(next.bar.layout[sections[s]]) ? next.bar.layout[sections[s]] : []
      for (var i = 0; i < arr.length; i++)
        if (arr[i] && String(arr[i].id) === entryId)
          merged = root.mergeSettings(merged, arr[i])
    }
    if (Number(merged.sessionIdleMin) === 1) merged.sessionIdleMin = -1

    // Keep one canonical bar entry. A duplicate top-level entry can keep a
    // disabled plugin alive, and duplicate bar entries can create several
    // widget instances despite allowMultiple:false.
    var keptBar = false
    for (var ss = 0; ss < sections.length; ss++) {
      var old = Array.isArray(next.bar.layout[sections[ss]]) ? next.bar.layout[sections[ss]] : []
      var clean = []
      for (var j = 0; j < old.length; j++) {
        if (!old[j] || String(old[j].id) !== entryId) { clean.push(old[j]); continue }
        foundBar = true
        if (!keptBar) {
          var canonical = ({ id: entryId })
          for (var key in merged) canonical[key] = merged[key]
          canonical[root.migrationMarker] = root.configVersion
          clean.push(canonical)
          keptBar = true
        }
      }
      next.bar.layout[sections[ss]] = clean
    }

    if (foundBar) {
      next.plugins = next.plugins.filter(function(entry) {
        return !entry || String(entry.id) !== entryId
      })
    } else if (top) {
      // A hybrid service + bar-widget is enabled by its one bar entry. A
      // legacy top-level entry would keep the service alive but leave no bar
      // view at all, so move it to the manifest's default section.
      var canonicalTop = ({ id: entryId })
      for (var setting in merged) canonicalTop[setting] = merged[setting]
      canonicalTop[root.migrationMarker] = root.configVersion
      next.bar.layout.right.push(canonicalTop)
      next.plugins = next.plugins.filter(function(entry) {
        return !entry || String(entry.id) !== entryId
      })
    }

    root.configMigrated = true
    if (JSON.stringify(next) !== JSON.stringify(before)) shell.persistShellConfig(next)
  }
  Timer { id: configMigration; interval: 0; onTriggered: root.migrateConfig() }
  onShellChanged: configMigration.restart()

  // Which pets are installed, so the bar widget can offer them rather than
  // making somebody edit a file to try one on. Names come from each
  // pet.json; a folder without one is not a pet.
  property var installedPets: []
  function scanPets() {
    if (root.pluginDir !== "" && !petScan.running) petScan.running = true
  }
  onPluginDirChanged: if (pluginDir !== "") petScanStart.restart()
  Timer { id: petScanStart; interval: 0; onTriggered: root.scanPets() }
  readonly property string petScanScript:
    "import json, os, re, sys\n" +
    "safe = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')\n" +
    "reserved = {'__proto__', 'prototype', 'constructor'}\n" +
    "seen, out = set(), []\n" +
    "for base in sys.argv[1:]:\n" +
    "  if not base or not os.path.isdir(base): continue\n" +
    "  for ident in sorted(os.listdir(base), key=str.casefold):\n" +
    "    if ident in seen or ident in reserved or not safe.fullmatch(ident): continue\n" +
    "    path = os.path.join(base, ident, 'pet.json')\n" +
    "    try:\n" +
    "      with open(path, encoding='utf-8') as handle: data = json.load(handle)\n" +
    "    except (OSError, ValueError): continue\n" +
    "    if not isinstance(data, dict): continue\n" +
    "    seen.add(ident)\n" +
    "    name = ' '.join(str(data.get('displayName') or data.get('name') or ident).split())[:48] or ident\n" +
    "    out.append({'id': ident, 'name': name, 'dir': os.path.join(base, ident)})\n" +
    "priority = {'bloub': 0}\n" +
    "out.sort(key=lambda pet: (priority.get(pet['id'], 4), pet['name'].casefold(), pet['id'].casefold()))\n" +
    "print(json.dumps(out, ensure_ascii=False))\n"
  Process {
    id: petScan
    command: ["python3", "-c", root.petScanScript,
      root.home + "/.config/omarchy-companion/pets",
      root.home + "/.config/omapets/pets",
      root.pluginDir + "/pets"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "[]"))
          root.installedPets = Array.isArray(parsed) ? parsed : []
          petPromotion.restart()
        } catch (e) { root.installedPets = [] }
      }
    }
  }
  // A desired pet can appear after the fallback has already taken the stage
  // (installation, repair, or a higher-priority user override). Discovery is
  // authoritative about precedence, so retry only when it found a better
  // concrete directory than the body currently being worn.
  Timer { id: petPromotion; interval: 0; onTriggered: root.retryPreferredPet() }
  FileView {
    path: root.configFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.fileCfg = JSON.parse(String(text() || "")) || {} }
      catch (e) { console.warn("companion: ignoring bad companion.json:", e) }
      root.legacyLoaded = true
      configMigration.restart()
    }
    onLoadFailed: {
      root.fileCfg = ({})
      root.legacyLoaded = true
      configMigration.restart()
    }
  }

  readonly property int petSize: Model.resolvePetSize(cfg.size, spritePreferredSize)
  // Whether the creature is repainted in your theme at all. A pet with no
  // hue window keeps its own colours regardless; this is for the ones that
  // could be repainted and whose owner would rather they were not.
  readonly property bool cfgTheme: Model.boolValue(cfg.theme, true)
  // Whether a resting creature changes its expression on its own.
  readonly property bool cfgExpressions: Model.boolValue(cfg.expressions, true)
  readonly property real cfgGlanceChance: {
    var v = Number(cfg.expressionChance)
    return isFinite(v) && v >= 0 && v <= 1 ? v : 0.25
  }
  readonly property int cfgSessionIdleMin: {
    var v = Number(cfg.sessionIdleMin)
    // -1 means exactly one request, 0 lasts until reset, positive values are
    // idle minutes. Version 3 labelled 1 minute as "each order"; preserve
    // what that UI promised when reading an old value.
    if (!isFinite(v) || v < -1 || v > 1440) return 0
    if (v === 1) return -1
    return Math.round(v)
  }
  readonly property bool cfgFollow: Model.boolValue(cfg.followFocus, true) && !stillPet
  readonly property bool cfgHideFullscreen: Model.boolValue(cfg.hideOnFullscreen, true)
  readonly property real cfgActivity: {
    var v = Number(cfg.activity)
    return isFinite(v) && v > 0 && v <= 10 ? v : 1
  }
  readonly property string cfgScreen: typeof cfg.screen === "string" && Model.safeId(cfg.screen)
    ? cfg.screen : ""
  // A fresh install wears the pet it ships with. Invalid or missing ids fall
  // back to it too, so a broken preference never leaves an empty stage.
  readonly property string cfgPet: typeof cfg.pet === "string" && Model.safeId(cfg.pet)
    ? cfg.pet : "bloub"
  // What a drawn companion is wearing. Each falls back to its own default
  // rather than to nothing, because these come out of shell.json and a value
  // somebody typed by hand must never leave the stage empty.
  readonly property string cfgShape: Bloub.shapeId(cfg.shape)
  readonly property string cfgColor: Bloub.colorId(cfg.color)
  readonly property string cfgExpression: Bloub.expressionId(cfg.expression)
  // A creature that stays where you put it is a companion; one that paces
  // the screen is a screensaver. Roaming is opt-in.
  // How often the creature finds something to do, and how long it rests
  // afterwards. Rare and slow by default: a surprise stops being one when
  // it arrives on a schedule.
  readonly property real cfgActivityChance: {
    var v = Number(cfg.activityChance)
    return isFinite(v) && v >= 0 && v <= 1 ? v : 0.4
  }
  readonly property int cfgActivityRestSec: {
    var v = Number(cfg.activityRestSec)
    return isFinite(v) && v >= 0 && v <= 3600 ? Math.round(v) : 90
  }
  readonly property bool cfgRoam: Model.boolValue(cfg.roam, false)
  readonly property bool cfgTalk: Model.boolValue(cfg.talk, true)
  readonly property bool cfgReduceMotion: Model.boolValue(cfg.reduceMotion, false)
  // How long a silent agent gets before the chief admits it is still going.
  readonly property int cfgPatience: {
    var v = Number(cfg.patienceSec)
    return isFinite(v) && v >= 5 && v <= 600 ? Math.round(v) : 25
  }
  readonly property int cfgTurnTimeout: {
    var v = Number(cfg.turnTimeoutSec)
    return isFinite(v) && v >= 60 && v <= 3600 ? Math.round(v) : 600
  }
  readonly property int cfgSpeakMax: {
    var v = Number(cfg.speakMax)
    return isFinite(v) && v >= 40 && v <= 1000 ? Math.round(v) : 260
  }
  readonly property int cfgFrameMs: {
    var v = Number(cfg.frameIntervalMs)
    return isFinite(v) && v >= 60 && v <= 500 ? Math.round(v) : 140
  }

  // Keep the resident contract concise; runtime facts ride on every turn.
  readonly property string defaultPreamble: "You are Omarchy Companion, the resident chief of staff of this Omarchy Linux desktop. Carry out the user's order unattended. Prefer the desktop's supported `omarchy`, `omarchy-shell`, and Hyprland controls so its state stays coherent and actions remain undoable. Never install software or make an irreversible change unless the order expressly asks for it. If ambiguity could materially change the result, ask one short question.\n\nYour reply appears in a compact speech bubble: answer in the user's language, plain text, no markdown, in at most two short sentences. Do the work before reporting it. When a result needs to be seen, open it in the user's configured browser, editor, file manager, or terminal instead of printing it.\n\nYour standing notes are at " + root.notesPath + ". Read them only when prior context matters and append only durable preferences or facts."
  readonly property int preambleMax: 8000
  readonly property int orderMax: 8000
  readonly property string preamble:
    typeof cfg.promptPreamble === "string" && cfg.promptPreamble.length <= preambleMax
      ? cfg.promptPreamble : defaultPreamble

  // Where the body actually stands is a runtime fact, not an instruction, so
  // it is appended rather than baked into the preamble the user may edit.
  // Without it the agent opens windows wherever focus happened to be, which
  // is regularly a screen the user is not looking at.
  readonly property string standingOn: {
    if (worldMonitor === "") return ""
    var t = "Runtime context: your body is on monitor " + worldMonitor
      + ". Before opening a new window for this request, focus it with `hyprctl dispatch "
      + Model.luaStr(Model.dispatchFocusMonitor(worldMonitor)) + "`."
      + " Existing application windows may keep new tabs on their current monitor; say where the result appeared if that happens."
    if (cfgScreen !== "") t += " You have been kept to this monitor in your settings, so travelling elsewhere is refused: work from here."
    return t
  }

  // ------------------------------------------------------------ default agent

  // The agent the desktop as a whole prefers.
  property string defaultAgentId: ""
  FileView {
    path: root.home + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var id = String(text() || "").trim()
      root.defaultAgentId = Model.safeId(id) ? id : ""
      root.scanAgents()
    }
    onLoadFailed: root.defaultAgentId = ""
  }

  // The one the creature uses. Following the desktop's choice is the
  // sensible default and stays the default; picking one here is for when
  // you want the chief on something other than what you type into a
  // terminal all day.
  readonly property string cfgAgent: typeof cfg.agent === "string" && Model.safeId(cfg.agent)
    ? String(cfg.agent) : ""
  // Omarchy 4.1 accepts the old `gemini` spelling as an Antigravity alias.
  // Preserve real Gemini on 4.0, but follow that migration at runtime when
  // only the new executable is installed. The user's config is not rewritten.
  readonly property string agentId: cfgAgent === "gemini" && agentsScanned
      && !hasAgent("gemini") && hasAgent("agy") ? "agy"
    : cfgAgent !== "" ? cfgAgent : defaultAgentId
  readonly property bool agentIsDefault: cfgAgent === ""

  // Which agents are actually installed, so the bar offers what can be run.
  // Both the candidates and their proper names come from Omarchy's own
  // omarchy-default-agent: the `omarchy:args` header is the same line that
  // `omarchy commands` reads, and the case block below it is where "omp"
  // learns it is called Oh My Pi. Copying either into this file would mean
  // going quietly out of date the day Omarchy learns a tenth agent, so the
  // list here is only the fallback for a desktop that has moved the script.
  property var installedAgents: []
  property bool agentsScanned: false
  function scanAgents() { if (!agentScan.running) agentScan.running = true }
  function refreshChoices() { root.scanPets(); root.scanAgents() }
  function agentName(id) {
    for (var i = 0; i < installedAgents.length; i++)
      if (installedAgents[i].id === id) return String(installedAgents[i].name || id)
    return String(id || "")
  }
  function hasAgent(id) {
    for (var i = 0; i < installedAgents.length; i++)
      if (installedAgents[i].id === id) return true
    return false
  }
  readonly property bool agentAvailable: agentId !== ""
    && (!agentsScanned || hasAgent(agentId))
    && (agentIsDefault || Model.canTalkTo(agentId) || Model.canOpenConsole(agentId))
  Process {
    id: agentScan
    running: true
    command: ["bash", "-lc", "src=$(command -v omarchy-default-agent 2>/dev/null)\norder=\n[ -n \"$src\" ] && order=$(sed -n 's/^# omarchy:args=\\[\\(.*\\)\\]$/\\1/p' \"$src\" | head -1 | tr '|' ' ')\n[ -n \"$order\" ] || order='pi omp opencode ori claude codex grok agy gemini copilot crush'\nfor a in $order; do\n  p=$(command -v \"$a\" 2>/dev/null) || continue\n  # Omarchy may leave a tiny ~/.local/bin shim for an optional agent. Running\n  # that shim installs the tool through mise, which discovery must never do.\n  if [ -f \"$p\" ] && grep -q 'mise use -g' \"$p\" 2>/dev/null && grep -q 'exec mise x' \"$p\" 2>/dev/null && ! mise which \"$a\" >/dev/null 2>&1; then\n    continue\n  fi\n  n=\n  [ -n \"$src\" ] && n=$(sed -n 's/.*agent=\"'\"$a\"'\";[[:space:]]*name=\"\\([^\"]*\\)\".*/\\1/p' \"$src\" | head -1)\n  printf '%s\\t%s\\n' \"$a\" \"${n:-$a}\"\ndone"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length < 2 || parts[0].trim() === "") continue
          var id = parts[0].trim()
          if (Model.safeId(id)) out.push({ id: id, name: parts[1].trim() || id })
        }
        root.installedAgents = out
        root.agentsScanned = true
      }
    }
    onExited: function(code) { if (code !== 0) root.agentsScanned = true }
  }
  // A conversation belongs to one agent. Switching agents cancels an active
  // turn and selects that agent's own saved session; an id from Claude is
  // never handed to Codex or vice versa.
  onAgentIdChanged: {
    root.cancelTurn("agent changed", false)
    root.sessionId = root.sessions[root.agentId] ? root.sessions[root.agentId] : ""
    root.agentSilent = false
    root.armSessionIdle()
    root.dismissBubble()
    statusWrite.restart()
  }

  // ------------------------------------------------------------ energy

  property var usageRecord: null
  FileView {
    path: root.agentId !== "" ? root.stateHome + "/omarchy/agents/usage/" + root.agentId + ".json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.usageRecord = JSON.parse(String(text() || "")) }
      catch (e) { root.usageRecord = null }
    }
    onLoadFailed: root.usageRecord = null
  }
  readonly property real energy: Model.energyFromRecord(usageRecord)

  // ------------------------------------------------------------ agent hooks
  //
  // OmaPets-compatible: agents with hooks installed report session/prompt/
  // tool/permission/stop/error transitions into one JSON file. If it exists
  // the chief gets precise working/waiting/success/error states; if not,
  // the window heuristics below still carry the day.

  property var hookRecord: null
  FileView {
    path: root.stateHome + "/omarchy/omapets/status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.hookRecord = JSON.parse(String(text() || "")) }
      catch (e) { root.hookRecord = null }
    }
    onLoadFailed: root.hookRecord = null
  }
  property double nowEpoch: 0
  Timer {
    interval: 5000
    repeat: true
    running: root.hookRecord !== null && root.shown
    triggeredOnStart: true
    onTriggered: root.nowEpoch = Date.now() / 1000
  }

  // ------------------------------------------------------------ the gap
  //
  // Hyprland leaves a gap between a window and the edge of the screen. The
  // creature uses the same one, so it stands in line with the windows above
  // it instead of at some margin of its own invention.

  property var gaps: ({ top: 0, right: 0, bottom: 0, left: 0 })
  readonly property int cfgEdgeGap: {
    var v = Number(cfg.edgeGap)
    return cfg.edgeGap !== undefined && isFinite(v) && v >= 0 && v <= 3600
      ? Math.round(v) : -1
  }
  readonly property real gapBottom: cfgEdgeGap >= 0 ? cfgEdgeGap : Number(gaps.bottom || 0)
  readonly property real gapRight: cfgEdgeGap >= 0 ? cfgEdgeGap : Number(gaps.right || 0)

  Process {
    id: gapsProc
    running: true
    command: ["hyprctl", "-j", "getoption", "general:gaps_out"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          root.gaps = Model.parseGapsCss(d.css !== undefined ? d.css : d.custom)
        } catch (e) {
          // Without hyprctl the creature simply stands on the screen edge.
          root.gaps = ({ top: 0, right: 0, bottom: 0, left: 0 })
        }
      }
    }
  }

  // ------------------------------------------------------------ home
  //
  // The creature starts in the bottom-right corner of the active screen and
  // lives wherever it is dragged after that. The spot is remembered next to
  // the rest of our state rather than in the user's config, because it is a
  // placement, not a preference.

  readonly property string homeFile: stateHome + "/omarchy/companion/home.json"
  property var homes: ({})
  // A drag or travel can beat the asynchronous first read. Keep every new
  // position and the last chosen monitor until the disk state is available,
  // then merge once; writing an empty map first would erase other monitors.
  property var pendingHome: null
  readonly property var worldSegment: Model.segmentByName(segments, worldMonitor)
  readonly property real worldWidth: worldSegment ? worldSegment.w : 0
  readonly property real effectiveHomeX: Model.homeFor(
    homes, worldMonitor, worldWidth, petSize, gapRight,
    spriteCellAspect, spriteContent, spriteMirror)

  function refreshDefaultHome() {
    if (root.worldMonitor === "" || root.pendingTravel !== null) return
    var stored = root.homes && root.homes[root.worldMonitor]
    if (isFinite(Number(stored))) return
    root.spawnLocalX = root.effectiveHomeX
    if (root.activeChief)
      Qt.callLater(function() {
        if (root.activeChief && root.pendingTravel === null)
          root.activeChief.px = root.activeChief.boundedX(root.effectiveHomeX)
      })
  }
  onEffectiveHomeXChanged: root.refreshDefaultHome()


  FileView {
    id: homeStore
    path: root.homeFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var firstLoad = !root.homeLoaded
      try {
        var parsed = JSON.parse(String(text() || ""))
        root.homes = Model.readHomes(parsed)
        root.homeMon = String(parsed && parsed.monitor ? parsed.monitor : "")
      } catch (e) { root.homes = ({}); root.homeMon = "" }
      root.homeLoaded = true
      var merged = root.applyPendingHome()
      if (firstLoad) root.commitLoadedHome()
      if (merged) root.writeHome()
    }
    onLoadFailed: {
      var firstLoad = !root.homeLoaded
      root.homes = ({})
      root.homeMon = ""
      root.homeLoaded = true
      var merged = root.applyPendingHome()
      if (firstLoad) root.commitLoadedHome()
      if (merged) root.writeHome()
    }
    onSaved: root.protectStateFile(root.homeFile)
  }

  function queueHome(monitor, x, hasPosition) {
    var name = String(monitor || "")
    if (name === "" || !Model.safeMapKey(name)) return
    var positions = ({})
    var prior = root.pendingHome && root.pendingHome.monitors
      ? root.pendingHome.monitors : ({})
    for (var old in prior) if (Model.safeMapKey(old)) positions[old] = prior[old]
    if (hasPosition) positions[name] = Math.round(Number(x))
    root.pendingHome = { monitors: positions, monitor: name }
  }

  function applyPendingHome() {
    var pending = root.pendingHome
    if (!pending) return false
    var next = ({})
    for (var name in homes) next[name] = homes[name]
    var positions = pending.monitors || ({})
    for (var queued in positions)
      if (Model.safeMapKey(queued) && isFinite(Number(positions[queued])))
        next[queued] = Math.round(Number(positions[queued]))
    root.homes = next
    root.homeMon = String(pending.monitor || "")
    root.pendingHome = null
    return true
  }

  // `initialPx` is consumed when a Chief first gains a width. The state file
  // arrives asynchronously, so changing that property afterwards is not
  // enough: commit the first loaded answer to the already-visible instance as
  // well. A pin wins over the last free monitor; queued drags and journeys have
  // already been merged into `homeMon` and `homes` at this point.
  function commitLoadedHome() {
    var pinned = Model.segmentByName(root.segments, root.cfgScreen) !== null
      ? root.cfgScreen : ""
    var remembered = pinned !== "" ? pinned
      : Model.homeMonitor({ monitor: root.homeMon }, root.segments)
    if (remembered === "" && Model.segmentByName(root.segments, root.worldMonitor) !== null)
      remembered = root.worldMonitor
    if (remembered === "") return
    var sameMonitor = remembered === root.worldMonitor
    var x = root.homeOn(remembered)
    root.spawnLocalX = x
    root.worldMonitor = remembered
    if (sameMonitor && root.activeChief) root.activeChief.px = x
  }

  function recordHome(monitor, x, hasPosition) {
    var name = String(monitor || "")
    if (name === "" || !Model.safeMapKey(name)) return
    if (hasPosition && isFinite(Number(x))) {
      root.spawnLocalX = Math.round(Number(x))
    }
    if (!root.homeLoaded) { root.queueHome(name, x, hasPosition); return }
    var next = ({})
    for (var old in homes) next[old] = homes[old]
    if (hasPosition && isFinite(Number(x))) next[name] = Math.round(Number(x))
    root.homes = next
    root.homeMon = name
    root.writeHome()
  }

  function rememberHome(x) {
    root.recordHome(root.worldMonitor, x, true)
  }

  // The screen it lives on is remembered too, so a restart puts it back where
  // you left it rather than wherever the focus happened to be.
  property string homeMon: ""
  function writeHome() {
    if (!root.homeLoaded) return
    homeStore.setText(JSON.stringify({ monitors: homes, monitor: homeMon }) + "\n")
  }

  // Arriving on a screen means standing where the creature stands there.
  function homeOn(monitor) {
    var seg = Model.segmentByName(segments, monitor)
    return Model.homeFor(homes, monitor, seg ? seg.w : 0, petSize, gapRight,
                         spriteCellAspect, spriteContent, spriteMirror)
  }

  // ------------------------------------------------------------ the world
  //
  // Monitors in virtual coordinates, left to right. The chief occupies one
  // of them; travel dives under the edge, crosses the distance out of
  // sight, and rises on the target.

  readonly property var segments: {
    var out = []
    var scr = Quickshell.screens
    for (var i = 0; i < scr.length; i++)
      out.push({ name: scr[i].name, x: scr[i].x, y: scr[i].y,
                 width: scr[i].width, height: scr[i].height })
    return Model.worldSegments(out)
  }

  // Monitors come and go. If the ground under the chief vanishes, it does
  // not wait for someone to plug the screen back in — it surfaces on the
  // focused monitor, or the first one still standing.
  onSegmentsChanged: {
    if (segments.length === 0) return
    var pinned = Model.segmentByName(segments, cfgScreen) !== null ? cfgScreen : ""
    var back = Model.homeMonitor({ monitor: homeMon }, segments)
    var wanted = pinned !== "" ? pinned : (displaced ? back : "")
    if (wanted !== "" && wanted !== worldMonitor) {
      diveTimer.stop()
      undergroundTimer.stop()
      pendingTravel = null
      pendingAsk = false
      pendingAskMonitor = ""
      submerged = false
      displaced = false
      spawnLocalX = homeOn(wanted)
      worldMonitor = wanted
      return
    }
    if (Model.segmentByName(segments, worldMonitor) !== null) {
      if (displaced && worldMonitor === back) displaced = false
      return
    }
    diveTimer.stop()
    undergroundTimer.stop()
    pendingTravel = null
    pendingAsk = false
    pendingAskMonitor = ""
    submerged = false
    // The screen it lives on may come back; standing somewhere else in the
    // meantime is not the same as moving house. Never having stood anywhere
    // is not displacement either — that is just arriving.
    var hadGround = worldMonitor !== ""
    if (hadGround) displaced = true
    var fallback = Model.preferredMonitor(segments, pinned, back, focusedMonName)
    // Only a disappearing monitor needs an emergency first-screen fallback.
    // On a fresh multi-monitor start, wait for the focused monitor instead
    // of mistaking virtual left-to-right order for the user's main display.
    if (fallback === "" && hadGround) fallback = segments[0].name
    if (fallback === "") return
    spawnLocalX = homeOn(fallback)
    worldMonitor = fallback
  }

  property string worldMonitor: ""
  // Whether it is standing somewhere only because its own screen went away.
  property bool displaced: false
  // Whether the remembered home has been read yet. Recording where the
  // creature settles must wait for it: the file takes a moment to arrive,
  // and writing first would overwrite the very answer being waited for.
  property bool homeLoaded: false

  // Wherever it comes to rest is where it lives. Without this, a creature
  // that is never dragged nor sent anywhere never records a home at all, and
  // every restart guesses again.
  Timer {
    id: settleHome
    interval: 1200
    onTriggered: {
      if (!root.homeLoaded) { settleHome.restart(); return }
      if (root.worldMonitor === "" || root.homeMon === root.worldMonitor) return
      root.recordHome(root.worldMonitor, 0, false)
    }
  }
  property real lastLocalX: -1
  property real spawnLocalX: -1
  property bool submerged: false
  property var pendingTravel: null
  onPendingTravelChanged: root.armDodge()
  property bool pendingAsk: false
  property string pendingAskMonitor: ""
  property var activeChief: null
  onActiveChiefChanged: if (activeChief) root.refreshDefaultHome()
  readonly property bool canPlayActivity: activeChief !== null
    && activeChief.canPlayActivity === true

  // A performance is worth publishing: anything watching the status file
  // can see what the creature is up to, and so can a test.
  Connections {
    target: root.activeChief
    function onActivityChanged() { statusWrite.restart() }
    function onGlanceChanged() { statusWrite.restart() }
    function onTurned() { statusWrite.restart() }
  }

  function travelTo(mon, frac) {
    if (root.talkBusy) return "finish the current order first"
    var target = String(mon || "")
    var seg = Model.segmentByName(segments, target)
    if (seg === null) return "unknown monitor: " + target
    // Told to live on one screen, it does not leave, whoever asks.
    if (cfgScreen !== "" && target !== cfgScreen) return "kept to " + cfgScreen
    if (pendingTravel !== null)
      return "already traveling to " + String(pendingTravel.mon || worldMonitor)
    if (target === worldMonitor) return "already there"
    // Unless a spot was asked for, the creature surfaces where it lives on
    // that screen rather than in the middle of it.
    var useHome = frac === undefined || frac === null
    if (useHome) frac = homeOn(target) / Math.max(1, seg.w)
    var plan = Model.travelPlan(segments, worldMonitor, lastLocalX, target, frac)
    if (!plan) return "no route"
    pendingTravel = {
      mon: target,
      local: plan.targetLocal,
      underground: plan.undergroundMs,
      useHome: useHome
    }
    root.promptOpen = false
    if (cfgReduceMotion) {
      root.finishTravelNow()
      return "moved to " + target
    }
    submerged = true
    diveTimer.restart()
    return "traveling to " + target
  }

  function placeTravelTarget() {
    if (!root.pendingTravel) return
    var trip = root.pendingTravel
    var local = trip.useHome && root.homeLoaded ? root.homeOn(trip.mon) : trip.local
    root.spawnLocalX = local
    root.worldMonitor = trip.mon
    root.recordHome(trip.mon, local, !trip.useHome)
  }

  function finishTravel() {
    root.submerged = false
    root.pendingTravel = null

    if (root.pendingAsk) {
      var askTarget = root.pendingAskMonitor
      root.pendingAsk = false
      root.pendingAskMonitor = ""
      root.askOn(askTarget)
      return
    }

    // Focus may have changed while the chief was underground. The scheduled
    // attempt cannot replace an in-flight trip, so arm it again on arrival.
    root.armFollow()
  }

  function finishTravelNow() {
    if (!root.pendingTravel) return
    diveTimer.stop()
    undergroundTimer.stop()
    root.placeTravelTarget()
    root.finishTravel()
  }

  onCfgReduceMotionChanged: {
    if (root.cfgReduceMotion && root.pendingTravel !== null)
      root.finishTravelNow()
  }

  // Dive fully out of sight, then move house while nobody watches, wait
  // out the distance, and surface.
  Timer {
    id: diveTimer
    interval: root.cfgReduceMotion ? 1 : 340
    onTriggered: {
      if (!root.pendingTravel) return
      root.placeTravelTarget()
      undergroundTimer.interval = root.pendingTravel.underground
      undergroundTimer.restart()
    }
  }
  Timer {
    id: undergroundTimer
    onTriggered: root.finishTravel()
  }

  readonly property string focusedMonName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  Timer {
    id: followTimer
    interval: 1500
    onTriggered: if (root.canFollowNow()) root.travelTo(root.focusedMonName)
  }
  function canFollowNow() {
    return root.cfgFollow && root.cfgScreen === "" && !root.promptOpen
      && !root.talkBusy && root.pendingTravel === null
      && root.focusedMonName !== "" && root.focusedMonName !== root.worldMonitor
      && !(root.cfgHideFullscreen
        && root.fullscreenMonitors.indexOf(root.focusedMonName) !== -1)
  }
  function armFollow() {
    followTimer.stop()
    if (root.canFollowNow()) followTimer.restart()
  }
  onFocusedMonNameChanged: {
    if (root.worldMonitor !== "") {
      root.armFollow()
      return
    }
    // Where it was left beats where the focus happens to be: a still pet
    // cannot walk back, and a walking one would rather not be made to.
    var remembered = Model.homeMonitor({ monitor: root.homeMon }, root.segments)
    var target = Model.preferredMonitor(root.segments, root.cfgScreen,
                                        remembered, root.focusedMonName)
    if (target === "") return
    root.spawnLocalX = root.homeOn(target)
    root.worldMonitor = target
  }
  onCfgFollowChanged: root.armFollow()
  onCfgScreenChanged: {
    if (cfgScreen === "" || Model.segmentByName(segments, cfgScreen) === null) {
      root.armDodge()
      root.armFollow()
      return
    }
    followTimer.stop()
    dodgeTimer.stop()
    // Pinning is a teleport. Retire both phases of an older trip before its
    // stale timer can finish a later one.
    diveTimer.stop()
    undergroundTimer.stop()
    spawnLocalX = homeOn(cfgScreen)
    worldMonitor = cfgScreen
    pendingTravel = null
    pendingAsk = false
    pendingAskMonitor = ""
    submerged = false
  }

  // Quickshell already mirrors Hyprland's monitors and workspaces. Derived
  // bindings stay current without subprocesses, JSON snapshots or debounce
  // races between two independent queries.
  readonly property var hyprlandMonitors: Hyprland.monitors.values
  readonly property var hyprlandWorkspaces: Hyprland.workspaces.values
  // `omarchyPath` is injected by the shell into plugin services. Keep the
  // fallback under a private name so the shell never tries to assign a
  // read-only property during activation.
  readonly property string qconsoleOmarchyRoot: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property string qconsoleWorkspace: "scratchpad"

  // Omarchy 4.0 calls its native drawer `scratchpad`. Newer releases keep the
  // name in qconsole.lua, beside the rule that owns it. Read that authority
  // instead of pinning a plugin forever to today's spelling; a missing or
  // temporarily half-written file safely retains the 4.0 convention.
  function workspaceFromQconsole(source) {
    var text = String(source || "")
    var patterns = [
      /workspace\s*=\s*["']special:([A-Za-z0-9][A-Za-z0-9._-]*)["']/,
      /\[\s*workspace\s+special:([A-Za-z0-9][A-Za-z0-9._-]*)\s+silent\s*\]/
    ]
    for (var i = 0; i < patterns.length; i++) {
      var match = patterns[i].exec(text)
      if (match && Model.safeId(match[1])) return String(match[1])
    }
    return "scratchpad"
  }

  FileView {
    path: root.qconsoleOmarchyRoot + "/default/hypr/qconsole.lua"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.qconsoleWorkspace = root.workspaceFromQconsole(text())
    onLoadFailed: root.qconsoleWorkspace = "scratchpad"
  }

  readonly property string wantedConsoleWs: qconsoleWorkspace
  function workspaceObject(workspace) {
    var expected = "special:" + String(workspace || "")
    for (var i = 0; i < hyprlandWorkspaces.length; i++)
      if (hyprlandWorkspaces[i] && String(hyprlandWorkspaces[i].name) === expected)
        return hyprlandWorkspaces[i]
    return null
  }
  readonly property var consoleWorkspaceObject: root.workspaceObject(wantedConsoleWs)
  property var shownSpecialWorkspaces: []
  readonly property bool consoleWorkspaceOpen:
    shownSpecialWorkspaces.indexOf("special:" + wantedConsoleWs) !== -1
  function scanSpecialWorkspaces() {
    if (!consoleStateScan.running) consoleStateScan.running = true
  }
  Process {
    id: consoleStateScan
    running: true
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var shown = []
        try {
          var monitors = JSON.parse(String(text || "[]"))
          for (var i = 0; i < monitors.length; i++) {
            var special = monitors[i] && monitors[i].specialWorkspace
              ? String(monitors[i].specialWorkspace.name || "") : ""
            if (special !== "" && shown.indexOf(special) === -1) shown.push(special)
          }
        } catch (e) {}
        root.shownSpecialWorkspaces = shown
      }
    }
  }
  Timer {
    id: consoleStateRefresh
    interval: 60
    onTriggered: root.scanSpecialWorkspaces()
  }

  function agentWindowKeys(workspace) {
    var expectedWorkspace = "special:" + String(workspace || "")
    var tops = []
    try { tops = Hyprland.toplevels.values }
    catch (e) { return [] }
    var keys = []
    for (var i = 0; i < tops.length; i++) {
      var top = tops[i]
      if (!top) continue
      var ipc = top.lastIpcObject && typeof top.lastIpcObject === "object"
        ? top.lastIpcObject : ({})
      var topWorkspace = top.workspace && top.workspace.name
        ? String(top.workspace.name)
        : ipc.workspace && ipc.workspace.name ? String(ipc.workspace.name) : ""
      if (topWorkspace !== expectedWorkspace) continue
      var appId = top.wayland && top.wayland.appId
        ? String(top.wayland.appId)
        : String(ipc["class"] || ipc.initialClass || "")
      if (appId !== "org.omarchy.agent") continue
      // Hyprland's address is the durable identity of this exact toplevel.
      // PID covers older IPC snapshots; QObject identity is the final fallback
      // so a count change alone can never hand off somebody else's session.
      var address = String(top.address || ipc.address || "")
      if (address !== "" && address.indexOf("0x") !== 0) address = "0x" + address
      var key = address !== "" ? "address:" + address : ""
      if (key === "" && Number(ipc.pid) > 0) key = "pid:" + String(ipc.pid)
      if (key === "") key = "object:" + String(top)
      if (key === "object:") key = "slot:" + String(i)
      keys.push(key)
    }
    return keys
  }
  readonly property var consoleWindowKeys: root.agentWindowKeys(wantedConsoleWs)
  readonly property int consoleWindows: consoleWindowKeys.length
  // The scratchpad is shared by Omarchy. It is our console only when an
  // Omarchy agent window is actually in it; a visible music player or other
  // scratchpad resident must never be toggled by Omarchy Companion's console button.
  readonly property bool consoleOpen: consoleWorkspaceOpen && consoleWindows > 0
  onConsoleWindowKeysChanged: root.probeConsoleLaunch()
  readonly property var fullscreenMonitors: {
    var busy = []
    for (var i = 0; i < hyprlandMonitors.length; i++) {
      var mon = hyprlandMonitors[i]
      if (mon && mon.activeWorkspace && mon.activeWorkspace.hasFullscreen)
        busy.push(String(mon.name))
    }
    return busy
  }
  readonly property bool fullscreenOnPetMonitor: fullscreenMonitors.indexOf(worldMonitor) !== -1
  onFullscreenOnPetMonitorChanged: root.armDodge()
  onFullscreenMonitorsChanged: { root.armDodge(); root.armFollow() }
  onCfgHideFullscreenChanged: { root.armDodge(); root.armFollow() }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = String(event && event.name ? event.name : "")
      // A config reload can change the gaps the creature stands in.
      if (n === "configreloaded") gapsProc.running = true
      if (n === "activespecial" || n === "monitoradded" || n === "monitorremoved")
        consoleStateRefresh.restart()
    }
  }

  // A fullscreen window is somebody working or playing, and the chief gets
  // out of the way — but stepping onto a free screen beats disappearing, so
  // it only hides when every screen is busy.
  function armDodge() {
    dodgeTimer.stop()
    if (root.cfgHideFullscreen && root.fullscreenOnPetMonitor
        && !root.talkBusy && !root.promptOpen && root.cfgScreen === ""
        && root.pendingTravel === null)
      dodgeTimer.restart()
  }
  Timer {
    id: dodgeTimer
    interval: 900
    onTriggered: {
      if (!root.cfgHideFullscreen || !root.fullscreenOnPetMonitor
          || root.talkBusy || root.promptOpen) return
      if (root.cfgScreen !== "" || root.pendingTravel !== null) return
      for (var i = 0; i < root.segments.length; i++) {
        var name = root.segments[i].name
        if (root.fullscreenMonitors.indexOf(name) === -1) { root.travelTo(name); return }
      }
    }
  }
  Component.onCompleted: {
    stateInit.running = true
  }

  // ------------------------------------------------------------ mood

  readonly property string mood: sayMode === "error" ? "error"
    : agentSilent ? "waiting"
    : talkBusy ? "working" : Model.resolveMood({
    energy: energy,
    consoleWindows: consoleWindows,
    consoleOpen: consoleOpen,
    hookState: hookRecord && hookRecord.state ? String(hookRecord.state) : "",
    hookAgeSec: hookRecord && hookRecord.updatedAtEpoch ? nowEpoch - Number(hookRecord.updatedAtEpoch) : -1,
    hookAgent: hookRecord && hookRecord.agent ? String(hookRecord.agent) : "",
    defaultAgent: agentId
  })
  onMoodChanged: statusWrite.restart()
  onEnergyChanged: statusWrite.restart()
  onBloubPetChanged: statusWrite.restart()
  onConsoleOpenChanged: {
    if (consoleOpen && activeChief) activeChief.cheer()
    statusWrite.restart()
  }

  // ------------------------------------------------------------ pet body
  //
  // User pets override ecosystem pets, which override the bundled fallback.
  // Lookup and picker use the same order so the name shown is the body worn.

  readonly property var petDirCandidates: {
    // The shell creates a service before injecting its manifest. Starting a
    // fallback walk against `/pets/...` and resetting it mid-read can strand
    // FileView on the second candidate, so discovery begins only once the
    // bundled root is real.
    if (pluginDir === "") return []
    var p = cfgPet
    if (p === "") return []
    var out = [home + "/.config/omarchy-companion/pets/" + p,
               home + "/.config/omapets/pets/" + p,
               pluginDir + "/pets/" + p]
    if (p !== "bloub") out.push(pluginDir + "/pets/bloub")
    return out
  }
  property int petDirIndex: 0
  property int failedPetIndex: -1
  onPetDirCandidatesChanged: root.resetPetState()

  property bool spriteOk: false
  // Manifest lookup is asynchronous. Until it either resolves a real sheet
  // or exhausts every candidate, render nothing; otherwise the procedural
  // emergency body flashes for a frame on every shell start.
  property bool petResolved: false
  property url spriteSource: ""
  property int spriteRows: 9
  // Two ways to wear a theme, one intent. A pet that names its own hue
  // window is redrawn properly, keeping its shading and its details; the
  // live tint is what is left when that is impossible — no ImageMagick, or
  // a pet that never said which of its colours are skin.
  property real petTint: 0
  readonly property real spriteTint: cfgTheme
    ? Model.tintFor(spriteThemeable, redrawCovered, petTint) : 0
  readonly property var spriteTintRgb: Model.liveTintColor(
    { r: Color.accent.r, g: Color.accent.g, b: Color.accent.b },
    { r: Color.background.r, g: Color.background.g, b: Color.background.b })
  readonly property real spriteTintBrightness: Model.liveTintBrightness(
    { r: Color.background.r, g: Color.background.g, b: Color.background.b }, spriteTint)
  property int spriteSleepRow: -1
  property int spriteWalkFrames: 0
  // A pet that declares which of its hues are "skin" can be dressed in the
  // theme's own colour without losing its cables, servos or shading.
  property var spriteThemeable: null
  property var spriteActivities: []
  property var spriteStillRows: []
  property int spriteColumns: 8
  property bool spriteMirror: false
  // A pet made of expressions rather than animations: it never moves on its
  // own, so following the focus and wandering are off for it whatever the
  // configuration says. A hand is the only thing that shifts it.
  property var spriteFaces: null
  property var spriteIdleFaces: null
  property var spriteBlink: null
  property var spriteContent: null
  // A companion with no artwork at all: the body is computed every frame from
  // Bloub.js, so none of the sheet machinery above applies to it.
  property bool bloubPet: false
  // Align the visible drawing, not its transparent atlas cell, with the
  // screen edge. Qt shares this decode with the on-screen Image.
  Image {
    id: spriteGeometry
    visible: false
    asynchronous: true
    cache: true
    source: root.spriteBaseSource
  }
  readonly property real spriteCellAspect: Model.cellAspect(
    spriteGeometry.implicitWidth, spriteGeometry.implicitHeight,
    spriteRows, spriteColumns)
  // Neither a still sprite pet nor the drawn one walks: following the focus
  // and roaming are the creature moving on its own, and neither has legs.
  readonly property bool stillPet: spriteFaces !== null || bloubPet
  property int spritePreferredSize: 0
  property bool spritePixelArt: false
  property string spritePetId: ""
  property string spritePetDir: ""
  property url spriteBaseSource: ""

  // Changing bodies is one transaction. Clear every manifest-derived field,
  // presentation remnant and in-flight fallback before candidate zero is
  // allowed to load; no expression, activity or old coat may leak between
  // two pets.
  function resetPetState() {
    petFallback.stop()
    redressTimer.stop()
    redressGiveUp.stop()
    backgroundRedress.stop()
    root.failedPetIndex = -1
    if (root.activeChief) {
      root.activeChief.activity = null
      if (root.activeChief.cancelRepaint) root.activeChief.cancelRepaint()
    }
    root.redressing = false
    root.wornBefore = ""
    root.settledCoat = ""
    root.settledCoatTint = 0
    root.settledCoatTintRgb = ({ r: 1, g: 1, b: 1 })
    root.settledCoatBrightness = 0
    root.redressQueued = false
    root.themeRequestSerial++
    root.spriteOk = false
    root.petResolved = false
    root.spriteSource = ""
    root.spriteBaseSource = ""
    root.spritePetId = ""
    root.spritePetDir = ""
    root.spriteRows = 9
    root.petTint = 0
    root.spriteSleepRow = -1
    root.spriteWalkFrames = 0
    root.spriteThemeable = null
    root.spriteActivities = []
    root.spriteStillRows = []
    root.spriteColumns = 8
    root.spriteMirror = false
    root.spriteFaces = null
    root.spriteIdleFaces = null
    root.spriteBlink = null
    root.spriteContent = null
    root.bloubPet = false
    root.spritePreferredSize = 0
    root.spritePixelArt = false
    root.themedRevision = 0
    root.themedAccent = ""
    root.petDirIndex = 0
  }

  function retryPreferredPet() {
    if (root.cfgPet === "") return
    for (var i = 0; i < root.installedPets.length; i++) {
      var pet = root.installedPets[i]
      if (pet && String(pet.id || "") === root.cfgPet) {
        var preferredDir = String(pet.dir || "")
        if (preferredDir !== "" && preferredDir !== root.spritePetDir
            && (root.spriteOk || root.petDirIndex > 0
                || root.failedPetIndex === root.petDirIndex))
          root.resetPetState()
        return
      }
    }
  }

  // FileView drops a new read started synchronously from onLoadFailed. Queue
  // fallback traversal into the next event turn and guard it against a pet
  // choice that changed while the failure was being delivered.
  function rejectPet(message) {
    if (message) console.warn("companion:", message)
    root.spriteOk = false
    root.petResolved = false
    root.failedPetIndex = root.petDirIndex
    petFallback.restart()
  }
  Timer {
    id: petFallback
    interval: 0
    onTriggered: {
      if (root.failedPetIndex !== root.petDirIndex) return
      if (root.petDirIndex < root.petDirCandidates.length - 1) root.petDirIndex++
      else root.petResolved = true
    }
  }

  FileView {
    path: root.petDirIndex < root.petDirCandidates.length
      ? root.petDirCandidates[root.petDirIndex] + "/pet.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var pet = JSON.parse(String(text() || ""))
        var dir = root.petDirCandidates[root.petDirIndex]
        // A pet may be DRAWN rather than blitted. It ships no spritesheet, so
        // none of the atlas reading below means anything for it: the character
        // is code, and its shape, colour and expression are settings. Only the
        // two fields that are about placing a body on a desktop are read.
        if (String(pet.render || "") === "bloub") {
          root.spritePetId = dir.slice(dir.lastIndexOf("/") + 1)
          root.spritePetDir = dir
          root.spriteContent = pet.content && typeof pet.content === "object" ? pet.content : null
          root.spritePreferredSize = isFinite(Number(pet.size)) && Number(pet.size) >= 32
            && Number(pet.size) <= 240 ? Math.round(Number(pet.size)) : 0
          // Its performances are code, not rows, so they come from the
          // renderer rather than from the manifest — but they are the same
          // tracks, so everything that schedules an activity keeps working.
          root.spriteActivities = Bloub.performanceTracks()
          root.bloubPet = true
          root.petResolved = true
          return
        }
        var sheet = String(pet.spritesheetPath || "spritesheet.webp")
        if (!Model.safeRelativePath(sheet)) throw new Error("spritesheetPath must stay inside the pet folder")
        // A pet may simply say how many rows it has; the standard version
        // number only ever meant nine or eleven.
        root.spriteRows = isFinite(Number(pet.rows)) && Number(pet.rows) > 0 && Number(pet.rows) <= 64
          ? Math.floor(Number(pet.rows)) : Model.atlasRowCount(pet.spriteVersionNumber)
        // companion.json wins over the pet's own preference, so a user can
        // dress or undress any pet without editing artwork they downloaded.
        root.petTint = Model.tintStrength(root.cfg.themeTint !== undefined ? root.cfg.themeTint : pet.themeTint, 0)
        root.spriteSleepRow = isFinite(Number(pet.sleepRow)) && Number(pet.sleepRow) >= 0
          && Number(pet.sleepRow) < root.spriteRows ? Math.floor(Number(pet.sleepRow)) : -1
        root.spriteWalkFrames = isFinite(Number(pet.walkFrames)) && Number(pet.walkFrames) >= 1
          && Number(pet.walkFrames) <= 64 ? Math.floor(Number(pet.walkFrames)) : 0
        root.spriteActivities = Model.readActivities(pet.activities, root.spriteRows)
        root.spriteStillRows = Model.readStillRows(pet.stillRows, root.spriteRows)
        root.spriteColumns = Model.spriteColumns(pet.columns)
        root.spriteFaces = Model.readFaces(pet.faces, root.spriteRows, root.spriteColumns)
        root.spriteMirror = pet.mirror === true
        root.spriteIdleFaces = Array.isArray(pet.idleFaces) ? pet.idleFaces : null
        var blink = Model.readFaceList([pet.blink], root.spriteRows, root.spriteColumns)
        root.spriteBlink = blink.length > 0 ? blink[0] : null
        root.spriteContent = pet.content && typeof pet.content === "object" ? pet.content : null
        root.spritePreferredSize = isFinite(Number(pet.size)) && Number(pet.size) >= 32
          && Number(pet.size) <= 240 ? Math.round(Number(pet.size)) : 0
        root.spritePixelArt = pet.pixelArt === true
        // The containing folder is the lookup identity. A manifest id is
        // catalogue metadata and must not make the picker report a body the
        // loader did not actually open (notably after bundled fallback).
        root.spritePetId = dir.slice(dir.lastIndexOf("/") + 1)
        root.spritePetDir = dir
        root.spriteThemeable = pet.themeable === true ? ({}) : (Model.isThemeableSpec(pet.themeable) ? pet.themeable : null)
        root.spriteBaseSource = Util.fileUrl(dir + "/" + sheet)
        root.spriteOk = true
        root.petResolved = true
        themeStamp.reload()
      } catch (e) {
        root.rejectPet("ignoring bad pet.json: " + e)
      }
    }
    onLoadFailed: root.rejectPet("")
  }

  // ------------------------------------------------------------ theme dressing
  //
  // A themeable pet is redrawn in the theme's accent whenever the theme
  // changes: the shipped tool replaces the hue of the pet's declared skin
  // window and leaves everything else — cables, servos, the artist's
  // shading — exactly as drawn. The result is cached with the rest of our
  // state, and a stamp file records which accent it was made for, so a
  // shell restart does not redo work that is already done.

  readonly property string themedDir: stateHome + "/omarchy/companion/themed"
  // One themed sheet per accent, named for it. Redrawing takes a second;
  // switching between themes the creature has already worn should not. The
  // sheet for the old accent stays on disk, so switching back is a stat and
  // a stamp write, nothing more.
  // Cache geometry is release geometry. Including the plugin version keeps
  // an older orientation or atlas layout from ever becoming a transition
  // frame after an upgrade.
  readonly property string themeCacheVersion: String(manifest.version || "0")
    .replace(/[^A-Za-z0-9._-]/g, "_")
  readonly property string themedSheet: themedDir + "/" + spritePetId + "-"
    + themeCacheVersion + "-"
    + accentHex.replace("#", "").toLowerCase() + "-"
    + backgroundHex.replace("#", "").toLowerCase() + ".webp"
  readonly property string accentHex: String(Color.accent)
  // The desktop behind the creature. The redraw lifts the artwork until it
  // clears the contrast floor against this, so both belong in the name of
  // the sheet and in the stamp: two themes can share an accent and stand on
  // very different ground.
  readonly property string backgroundHex: String(Color.background)
  property int themedRevision: 0
  property string themedAccent: ""

  FileView {
    id: themeStamp
    path: root.spritePetId !== "" ? root.themedSheet + ".stamp" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.themedAccent = String(text() || "").trim(); root.themedRevision++ }
    onLoadFailed: root.themedAccent = ""
  }

  // What the creature actually wears: the themed copy once it matches the
  // accent on screen, the artwork as drawn otherwise. The revision in the
  // URL is what makes Qt re-read a file it has already cached.
  readonly property bool themedUsable: cfgTheme && spriteThemeable !== null && Model.themeStampMatches(themedAccent, accentHex, backgroundHex)
  // This describes what is on screen, not whether ImageMagick happens to be
  // installed. Until the new lossless sheet exists, the original is tinted
  // live so the visible change can share Omarchy's wallpaper beat.
  readonly property bool redrawCovered: themedUsable
  onSpriteBaseSourceChanged: {
    root.syncSpriteSource()
    root.rememberCurrentCoat()
    redressTimer.restart()
  }
  onThemedUsableChanged: { root.syncSpriteSource(); statusWrite.restart() }
  onThemedRevisionChanged: root.syncSpriteSource()
  // `wornBefore` is only the visual source held over the immediate live
  // preview during Omarchy's 420 ms reveal. `settledCoat` remembers the whole
  // rendered look, including a fallback tint, so a later theme change never
  // flashes the raw artist colours.
  property bool redressing: false
  property url wornBefore: ""
  property url settledCoat: ""
  property real settledCoatTint: 0
  property var settledCoatTintRgb: ({ r: 1, g: 1, b: 1 })
  property real settledCoatBrightness: 0
  function rememberCurrentCoat() {
    if (String(spriteSource) === "") return
    // Read the intended rendering directly. QML bindings are allowed to
    // settle after this JavaScript handler returns; copying `spriteTint`
    // here could therefore remember the raw sheet for one transition even
    // though the frame already displayed its live tint.
    var lossless = themedUsable
      && String(spriteSource).indexOf(Util.fileUrl(themedSheet)) === 0
    var strength = cfgTheme ? Model.tintFor(spriteThemeable, lossless, petTint) : 0
    var accent = { r: Color.accent.r, g: Color.accent.g, b: Color.accent.b }
    var background = { r: Color.background.r, g: Color.background.g, b: Color.background.b }
    var c = Model.liveTintColor(accent, background)
    settledCoat = spriteSource
    settledCoatTint = strength
    settledCoatTintRgb = { r: Number(c.r), g: Number(c.g), b: Number(c.b) }
    settledCoatBrightness = Model.liveTintBrightness(background, strength)
  }
  Timer {
    id: redressGiveUp
    interval: 8000
    onTriggered: {
      root.redressing = false
      root.wornBefore = ""
      root.syncSpriteSource()
      root.rememberCurrentCoat()
    }
  }

  function syncSpriteSource() {
    var next = themedUsable ? Util.fileUrl(themedSheet) + "?v=" + themedRevision
      : spriteBaseSource
    spriteSource = next
    if (themedUsable) {
      if (redressing) {
        redressing = false
        redressGiveUp.stop()
      }
      wornBefore = ""
      rememberCurrentCoat()
    }
  }

  // Redrawing a sheet needs ImageMagick; a system without it still gets a
  // themed creature, just the live kind.
  property bool canRedraw: false
  onCanRedrawChanged: if (canRedraw) redressTimer.restart()
  property bool redressQueued: false
  property int themeRequestSerial: 0
  property int recolorSerial: -1
  property string recolorTarget: ""
  Process {
    id: magickProbe
    running: true
    command: ["bash", "-c", "command -v magick"]
    onExited: function(code) { root.canRedraw = code === 0 }
  }

  Process {
    id: recolorProc
    onExited: function(code) {
      var current = root.recolorSerial === root.themeRequestSerial
        && root.recolorTarget === root.themedSheet
        && root.cfgTheme && root.spriteThemeable !== null
      if (code === 0 && current) themeStamp.reload()
      else if (code !== 0 && current) {
        root.redressing = false
        root.wornBefore = ""
        root.syncSpriteSource()
        root.rememberCurrentCoat()
      }
      if (root.redressQueued) {
        root.redressQueued = false
        redressTimer.restart()
      }
    }
  }

  // A themed sheet that will not load is a cache miss, not a broken pet:
  // forget the stamp, wear the artwork as drawn, and redraw it.
  function themedSheetMissing() {
    if (spriteThemeable !== null && themedAccent !== ""
        && String(spriteSource).indexOf(Util.fileUrl(themedSheet)) === 0) {
      themedAccent = ""
      syncSpriteSource()
      rememberCurrentCoat()
      // The sheet itself goes too: a file that exists but will not load
      // would satisfy the worn-before fast path forever.
      Quickshell.execDetached(["rm", "-f", themedSheet + ".stamp", themedSheet])
      redressTimer.restart()
      return
    }
    // The artwork itself will not load. Rather than leave nothing standing
    // there, hand the stage back to the creature we can always draw.
    root.rejectPet("cannot load " + root.spriteSource)
    root.spriteSource = ""
    root.spriteBaseSource = ""
  }

  function redressPet() {
    if (!cfgTheme || !canRedraw || spriteThemeable === null || String(spriteBaseSource) === "" || pluginDir === "") return
    if (recolorProc.running) { root.redressQueued = true; return }
    var spec = spriteThemeable || {}
    var source = String(spriteBaseSource).replace(/^file:\/\//, "").replace(/\?.*$/, "")
    try { source = decodeURIComponent(source) } catch (e) {
      console.warn("companion: could not decode pet artwork path:", e)
    }
    var tool = pluginDir + "/tools/companion-recolor"
    // One stamp per sheet, beside it: what it was drawn for and which
    // artwork it came from. A theme worn before is then a single comparison,
    // with nothing to sweep and no way to delete the sheet just written.
    var targetSheet = themedSheet
    var stampFile = targetSheet + ".stamp"
    // The stamp names the accent and the artwork's size and age, so a new
    // sheet from an update is redrawn too — not only a new theme. An
    // unchanged stamp costs one stat and no redraw.
    var signature = accentHex + " " + backgroundHex + " "
      + String(manifest.version || "0") + " "
      + String(spec.hueMin !== undefined ? spec.hueMin : 40) + " "
      + String(spec.hueMax !== undefined ? spec.hueMax : 100) + " "
      + String(spec.satMin !== undefined ? spec.satMin : 15)
    var cmd = "stamp=" + shq(signature)
      + "; stamp=\"$stamp $(stat -c %s.%Y " + shq(source) + " 2>/dev/null)"
      + " $(stat -c %s.%Y " + shq(tool) + " 2>/dev/null)\""
      + "; [ \"$(cat " + shq(stampFile) + " 2>/dev/null)\" = \"$stamp\" ] && [ -f " + shq(targetSheet) + " ] && exit 0"
      + "; mkdir -p " + shq(themedDir)
      // Sheets for themes not worn in a month, and the scraps of a redraw
      // that was killed mid-write, are not worth the disk.
      + "; find " + shq(themedDir) + " -maxdepth 1 -name " + shq(spritePetId + "-*")
      + " -mtime +30 -delete 2>/dev/null"
      + "; find " + shq(themedDir) + " -maxdepth 1 -name " + shq(spritePetId + "-*.webp.??????")
      + " -mmin +5 -delete 2>/dev/null"
      + "; " + shq(tool)
      + " " + shq(source) + " " + shq(targetSheet) + " " + shq(accentHex)
      + " " + shq(String(spec.hueMin !== undefined ? spec.hueMin : 40))
      + " " + shq(String(spec.hueMax !== undefined ? spec.hueMax : 100))
      + " " + shq(String(spec.satMin !== undefined ? spec.satMin : 15))
      + " " + shq(backgroundHex)
      + " && stamp_tmp=$(mktemp " + shq(stampFile + ".XXXXXX") + ")"
      + " && trap 'rm -f \"$stamp_tmp\"' EXIT"
      + " && printf %s \"$stamp\" > \"$stamp_tmp\""
      + " && mv -f \"$stamp_tmp\" " + shq(stampFile)
    recolorProc.command = ["bash", "-lc",
      Model.buildGuardedRunner(root.home, ["bash", "-lc", cmd])]
    recolorTarget = targetSheet
    recolorSerial = themeRequestSerial
    recolorProc.running = true
  }

  // Theme switches land as a colour change on the shared singleton; a short
  // debounce keeps a palette that arrives channel by channel to one run.
  // Small, because a theme the creature has worn before goes on instantly.
  function beginRedress() {
    if (cfgTheme && spriteThemeable !== null && spriteOk && String(spriteSource) !== "") {
      var previous = String(settledCoat) !== "" ? settledCoat : spriteSource
      var previousTint = settledCoatTint
      var previousRgb = settledCoatTintRgb
      var previousBrightness = settledCoatBrightness
      themeRequestSerial++
      wornBefore = previous
      redressing = true
      redressGiveUp.restart()
      syncSpriteSource()
      if (activeChief && activeChief.repaint)
        activeChief.repaint(previous, previousTint, previousRgb, previousBrightness)
      rememberCurrentCoat()
    }
    redressTimer.restart()
  }
  // Omarchy applies `background` before `accent`, then starts its wallpaper
  // reveal. An accent change is therefore the exact synchronous trigger. A
  // background-only palette is coalesced to the next event-loop turn.
  Timer { id: backgroundRedress; interval: 0; onTriggered: root.beginRedress() }
  onAccentHexChanged: { backgroundRedress.stop(); root.beginRedress() }
  onBackgroundHexChanged: backgroundRedress.restart()
  onSpriteThemeableChanged: redressTimer.restart()
  // Short: the palette still arrives channel by channel, but the creature
  // should be wearing the new one before you have finished looking at the
  // rest of the desktop change.
  Timer { id: redressTimer; interval: 50; onTriggered: root.redressPet() }

  // ------------------------------------------------------------ talking
  //
  // An order runs the default agent headless; assistant text streams into
  // the speech bubble as it arrives and the result closes the turn. The
  // session id carries the conversation: follow-ups resume it, and the
  // console escalation resumes it interactively. Agents without a headless
  // adapter go straight to the console, exactly like v1.

  property bool talkBusy: false
  property string turnAgent: ""
  property bool turnTerminal: false
  property bool turnCancelling: false
  property string sessionId: ""
  // Runners may announce a session before their result. It becomes durable
  // only with a successful terminal event; a half-committed failed turn is
  // never resumed after restart.
  property string pendingTurnSession: ""

  // A conversation belongs to its agent and survives ordinary shell reloads.
  property var sessions: ({})
  property bool sessionsLoaded: false
  readonly property string sessionFile: statusDir + "/sessions.json"
  FileView {
    id: sessionStore
    path: root.sessionFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.sessions = Model.readSessions(JSON.parse(String(text() || ""))) }
      catch (e) { root.sessions = ({}) }
      root.sessionsLoaded = true
      if (!root.talkBusy && root.sessionId === "" && root.agentId !== "" && root.sessions[root.agentId])
        root.sessionId = root.sessions[root.agentId]
      root.armSessionIdle()
    }
    onLoadFailed: {
      root.sessions = ({})
      root.sessionsLoaded = true
      root.armSessionIdle()
    }
    onSaved: root.protectStateFile(root.sessionFile)
  }

  function writeSessions(next) {
    root.sessions = next
    sessionStore.setText(JSON.stringify(next) + "\n")
  }

  function rememberSession() {
    if (!sessionsLoaded || agentId === "") return
    var next = ({})
    for (var a in sessions) next[a] = sessions[a]
    if (sessionId === "") delete next[agentId]
    else next[agentId] = sessionId
    root.writeSessions(next)
  }

  function forgetSession(agent) {
    var id = String(agent || "")
    if (!sessionsLoaded || id === "" || !sessions[id]) return
    var next = ({})
    for (var a in sessions) if (a !== id) next[a] = sessions[a]
    root.writeSessions(next)
  }

  property string talkBuffer: ""
  property string sayMode: ""
  property string sayText: ""
  property string talkErr: ""
  property string doing: ""
  property string lastAnswer: ""
  readonly property string notesPath: statusDir + "/notes.md"

  // Answers wait long enough to read and pause while the pointer is over the
  // chief. Errors remain until they are deliberately dismissed.
  onSayModeChanged: { root.scheduleBubble(); statusWrite.restart() }
  onSayTextChanged: { root.scheduleBubble(); statusWrite.restart() }
  function scheduleBubble() {
    sayHold.stop()
    if (root.sayMode !== "say") return
    sayHold.interval = Model.readingTimeMs(root.sayText)
    sayHold.start()
  }
  Timer {
    id: sayHold
    onTriggered: {
      if (root.activeChief && root.activeChief.hitbox.containsMouse) {
        sayHold.interval = 3000
        sayHold.start()
        return
      }
      if (root.sayMode === "say") root.dismissBubble()
    }
  }

  function answered(text) {
    root.sayMode = "say"
    root.sayText = Model.shapeBubbleText(text, root.cfgSpeakMax)
    root.lastAnswer = root.sayText
    statusWrite.restart()
  }

  function shq(s) { return Model.shellQuote(s) }

  function noteTurnProgress(text) {
    talkPatience.restart()
    talkGiveUp.restart()
    if (root.agentSilent) {
      root.agentSilent = false
      statusWrite.restart()
    }
    if (text !== undefined && String(text) !== "")
      root.doing = Model.shapeBubbleText(text, 110)
  }

  function acceptTurnSession(id) {
    var next = String(id || "")
    if (Model.safeSessionId(next) && !root.turnCancelling && root.turnAgent === root.agentId)
      root.pendingTurnSession = next
  }

  function settleTurnSession(ok) {
    sessionIdle.stop()
    if (root.turnAgent === root.agentId) {
      if (!ok || root.cfgSessionIdleMin < 0) root.sessionId = ""
      else if (root.pendingTurnSession !== "") root.sessionId = root.pendingTurnSession
    }
    root.pendingTurnSession = ""
  }

  function armSessionIdle() {
    sessionIdle.stop()
    if (root.talkBusy || root.consoleLaunchPending || root.sessionId === "") return
    // "One ask" starts fresh immediately. Changing the setting must not let
    // an older ongoing conversation leak into the next order.
    if (root.cfgSessionIdleMin < 0) {
      root.sessionId = ""
      return
    }
    if (root.cfgSessionIdleMin > 0) sessionIdle.restart()
  }

  function completeTurn(ok, text) {
    if (!root.talkBusy || root.turnCancelling || root.turnTerminal) return
    root.turnTerminal = true
    talkPatience.stop()
    talkGiveUp.stop()
    root.doing = ""
    root.settleTurnSession(ok)
    if (ok) {
      var answer = String(text || "").trim()
      root.answered(answer === "" ? "Done." : answer)
    } else {
      root.sayMode = "error"
      root.sayText = Model.shapeBubbleText(String(text || "The agent could not finish that."), root.cfgSpeakMax)
    }
    talkReap.restart()
  }

  function releaseTurn() {
    talkPatience.stop()
    talkGiveUp.stop()
    talkReap.stop()
    root.agentSilent = false
    root.talkBusy = false
    root.turnAgent = ""
    root.turnTerminal = false
    root.turnCancelling = false
    root.pendingTurnSession = ""
    root.doing = ""
    statusWrite.restart()
  }

  // A running order is never replaced. Retrying an unattended agent can run
  // its side effects twice, so failure is explicit and a second order waits
  // until the first process group has actually exited.
  function cancelTurn(reason, showBubble, asError) {
    if (!root.talkBusy || root.turnCancelling) return false
    root.turnCancelling = true
    talkPatience.stop()
    talkGiveUp.stop()
    talkReap.stop()
    root.doing = ""
    root.agentSilent = false
    root.pendingTurnSession = ""
    root.forgetSession(root.turnAgent)
    if (root.turnAgent === root.agentId) root.sessionId = ""
    if (showBubble) {
      root.sayMode = asError ? "error" : "say"
      root.sayText = Model.shapeBubbleText(String(reason || "Stopped."), root.cfgSpeakMax)
      if (!asError) root.lastAnswer = root.sayText
    } else {
      root.dismissBubble()
    }
    if (talkProc.running) talkProc.running = false
    else root.releaseTurn()
    return true
  }

  function stopOrder() {
    return root.cancelTurn("Stopped.", true, false)
  }

  function runOrder(text) {
    var t = String(text || "").trim()
    if (root.talkBusy) return "already working"
    if (root.consoleLaunchPending) return "console is opening"
    if (!root.sessionsLoaded) return "still starting"
    if (t.length > root.orderMax) return "order exceeds 8000 characters"
    if (t === "") {
      root.promptOpen = false
      root.summonConsole(root.worldMonitor)
      return "console"
    }
    if (!root.agentAvailable) {
      root.promptOpen = false
      root.chooseAgent()
      root.sayMode = "error"
      root.sayText = "Choose an agent first."
      return "no agent"
    }

    var argv = root.cfgTalk
      ? Model.buildTalkCommand(root.agentId, t, root.sessionId, root.preamble, root.standingOn)
      : null
    if (!argv) {
      root.promptOpen = false
      return root.orderToConsole(t, root.worldMonitor)
    }

    root.promptOpen = false
    root.talkBuffer = ""
    root.talkErr = ""
    root.doing = ""
    root.agentSilent = false
    root.turnAgent = root.agentId
    root.turnTerminal = false
    root.turnCancelling = false
    root.pendingTurnSession = ""
    root.sayMode = "think"
    root.sayText = ""
    root.talkBusy = true
    talkPatience.restart()
    talkGiveUp.restart()

    talkProc.command = ["bash", "-lc", Model.buildGuardedRunner(root.talkCwd(), argv)]
    talkProc.running = true
    return "ordered"
  }

  // Same convention as omarchy-agent: sessions launched from the desktop
  // live in ~/Work when it exists, unless an explicit workdir was configured.
  property bool hasWorkDir: false
  readonly property string cfgWorkdir: {
    var path = cfg.workdir !== undefined ? String(cfg.workdir).trim() : ""
    return path === "" || path.indexOf("/") === 0 || path.indexOf("~/") === 0 ? path : ""
  }
  function talkCwd() {
    if (cfgWorkdir !== "")
      return cfgWorkdir.indexOf("~/") === 0 ? home + cfgWorkdir.slice(1) : cfgWorkdir
    return root.hasWorkDir ? root.home + "/Work" : root.home
  }
  Process {
    id: workProbe
    running: true
    command: ["test", "-d", Quickshell.env("HOME") + "/Work"]
    onExited: function(code) { root.hasWorkDir = code === 0 }
  }

  Process {
    id: talkProc
    stdout: SplitParser {
      onRead: function(line) {
        if (!root.talkBusy || root.turnCancelling || root.turnTerminal) return
        var r = Model.parseTalkLine(root.turnAgent, line)
        if (!r) return

        root.noteTurnProgress(r.kind === "doing" ? r.text : "")
        if (r.kind === "doing") {
          statusWrite.restart()
          return
        }
        if (r.kind === "text") {
          var joined = root.talkBuffer === "" ? r.text : root.talkBuffer + " " + r.text
          root.talkBuffer = joined.length > 8192 ? joined.slice(joined.length - 8192) : joined
          root.doing = Model.shapeBubbleText(r.text, 110)
          statusWrite.restart()
        } else if (r.kind === "session") {
          root.acceptTurnSession(r.sessionId)
        } else if (r.kind === "result") {
          root.acceptTurnSession(r.sessionId)
          root.completeTurn(r.ok, r.text !== "" ? r.text : root.talkBuffer)
        }
      }
    }

    onExited: function(code) {
      talkPatience.stop()
      talkGiveUp.stop()
      talkReap.stop()
      if (!root.turnCancelling && !root.turnTerminal) {
        if (code === 0 && root.talkBuffer !== "") {
          root.settleTurnSession(true)
          root.answered(root.talkBuffer)
        } else {
          root.settleTurnSession(false)
          root.forgetSession(root.turnAgent)
          root.sayMode = "error"
          var reason = root.talkErr !== "" ? root.talkErr
            : root.turnAgent === "" ? "No agent is configured."
            : root.turnAgent + " ended without an answer."
          root.sayText = Model.shapeBubbleText(reason, root.cfgSpeakMax)
        }
      }
      root.releaseTurn()
    }

    stderr: SplitParser {
      onRead: function(line) {
        if (!root.talkBusy || root.turnCancelling || root.turnTerminal) return
        var value = String(line || "").trim()
        if (value !== "" && value.indexOf("mise ") !== 0)
          root.talkErr = value.slice(0, 200)
      }
    }
  }

  Timer {
    id: sessionIdle
    interval: Math.max(1000, Model.sessionLifeMs(root.cfgSessionIdleMin))
    repeat: false
    onTriggered: if (root.cfgSessionIdleMin > 0) root.sessionId = ""
  }
  onCfgSessionIdleMinChanged: {
    root.armSessionIdle()
  }

  // Result events are terminal, but a few runners keep their transport alive.
  Timer { id: talkReap; interval: 150; onTriggered: if (talkProc.running) talkProc.running = false }

  property bool agentSilent: false
  Timer {
    id: talkPatience
    interval: root.cfgPatience * 1000
    onTriggered: {
      if (!root.talkBusy || root.turnTerminal || root.turnCancelling) return
      root.agentSilent = true
      root.doing = "Still working…"
      statusWrite.restart()
    }
  }

  // This is an inactivity timeout, not a wall-clock job limit: every valid
  // progress event restarts it. It fails visibly and never retries.
  Timer {
    id: talkGiveUp
    interval: root.cfgTurnTimeout * 1000
    onTriggered: root.cancelTurn(
      (root.turnAgent || "The agent") + " stopped responding.", true, true)
  }

  function dismissBubble() { root.sayMode = ""; root.sayText = "" }

  // The whole onboarding: the very first time the chief ever stands on
  // this machine, it says what it is for. A marker file remembers that the
  // introduction happened; everything after that stays quiet.
  property bool welcomed: true
  FileView {
    id: welcomeStore
    path: root.stateHome + "/omarchy/companion/welcomed"
    atomicWrites: true
    printErrors: false
    onLoaded: root.welcomed = true
    onLoadFailed: { root.welcomed = false; welcomeTimer.restart() }
    onSaved: root.protectStateFile(path)
  }
  Timer {
    id: welcomeTimer
    interval: 2500
    onTriggered: {
      if (root.welcomed || root.talkBusy || root.sayMode !== "") return
      root.sayMode = "say"
      root.sayText = "Click me and tell your desktop what to do."
      root.welcomed = true
      welcomeStore.setText("1\n")
    }
  }

  // ------------------------------------------------------------ the console
  //
  // Escalation, not the default. The console drops on the chief's monitor —
  // wherever it traveled, that's where the work lands. With a living
  // session, the console resumes the very conversation the bubble held.

  // Omarchy 4 exposes the scratchpad as its native special workspace. The
  // chief shares that drawer instead of inventing a second window system.
  function dispatch(expression) {
    Quickshell.execDetached(["hyprctl", "dispatch", expression])
  }

  function actionMonitor(requested) {
    var want = String(requested || "")
    if (Model.segmentByName(root.segments, want) !== null) return want
    if (Model.segmentByName(root.segments, root.worldMonitor) !== null) return root.worldMonitor
    if (Model.segmentByName(root.segments, root.focusedMonName) !== null) return root.focusedMonName
    return root.segments.length > 0 ? root.segments[0].name : ""
  }

  function chooseAgent() {
    Quickshell.execDetached(["omarchy-menu", "summon", "setup.default.agent"])
  }

  function consoleRule(workspace, launchTag) {
    var rule = "workspace special:" + String(workspace || root.wantedConsoleWs) + " silent"
    if (Model.safeId(launchTag)) rule += "; tag +" + String(launchTag)
    return rule
  }

  function consoleArgvCommand(argv) {
    var quoted = []
    for (var i = 0; argv && i < argv.length; i++) quoted.push(root.shq(argv[i]))
    if (quoted.length === 0) return ""
    return "cd " + root.shq(root.talkCwd())
      + " && omarchy-launch-tui --app-id=org.omarchy.agent " + quoted.join(" ")
  }

  function dispatchOn(monitor, expressions) {
    var target = root.actionMonitor(monitor)
    var actions = []
    if (target !== "") actions.push(Model.dispatchFocusMonitor(target))
    if (Array.isArray(expressions)) {
      for (var i = 0; i < expressions.length; i++) actions.push(expressions[i])
    } else actions.push(expressions)
    if (actions.length === 1) { root.dispatch(actions[0]); return }
    var argv = ["bash", "-lc",
      "for action do hyprctl dispatch \"$action\" >/dev/null || exit; done",
      "companion-dispatch"]
    for (var j = 0; j < actions.length; j++) argv.push(String(actions[j]))
    Quickshell.execDetached(argv)
  }

  function launchInConsole(command, workspace, launchTag) {
    if (String(command || "") === "") return false
    // Map first, while the special workspace is hidden. Omarchy 4.1 seeds an
    // agent from qconsole.lua when that workspace is created *empty*. Showing
    // it in the same dispatch as this asynchronous terminal launch creates an
    // empty workspace first and races the native seed, yielding two consoles.
    // A window-mapped workspace is born non-empty, so the seed cannot compete.
    root.dispatch(Model.dispatchExec("[" + root.consoleRule(workspace, launchTag) + "] " + command))
    return true
  }

  // A session belongs to the bubble until a new agent toplevel proves that
  // the console launch succeeded. This avoids losing resumable context when
  // a terminal command, compositor dispatch or rule fails silently.
  property bool consoleLaunchPending: false
  property var consoleLaunchWindowBaseline: ({})
  property string consoleLaunchTag: ""
  property string consoleLaunchVerifiedKey: ""
  property string consoleLaunchCandidate: ""
  property string consoleLaunchWorkspace: ""
  property string consoleLaunchMonitor: ""
  property bool consoleRevealOnConfirm: false
  property string consoleHandoffAgent: ""
  property string consoleHandoffSession: ""
  property bool consoleDismissOnOpen: false

  function clearConsoleLaunch() {
    consoleLaunchTimeout.stop()
    consoleLaunchTimeout.interval = 12000
    consoleLaunchConfirm.stop()
    consoleLaunchVerifyTimer.stop()
    if (consoleLaunchVerify.running) consoleLaunchVerify.running = false
    root.consoleLaunchPending = false
    root.consoleLaunchWindowBaseline = ({})
    root.consoleLaunchTag = ""
    root.consoleLaunchVerifiedKey = ""
    root.consoleLaunchCandidate = ""
    root.consoleLaunchWorkspace = ""
    root.consoleLaunchMonitor = ""
    root.consoleRevealOnConfirm = false
    root.consoleHandoffAgent = ""
    root.consoleHandoffSession = ""
    root.consoleDismissOnOpen = false
  }

  function newConsoleWindowKey() {
    if (!root.consoleLaunchPending || root.consoleLaunchWorkspace === "") return ""
    var verified = root.consoleLaunchVerifiedKey
    if (verified === "" || root.consoleLaunchWindowBaseline[verified]) return ""
    var keys = root.agentWindowKeys(root.consoleLaunchWorkspace)
    if (keys.indexOf(verified) !== -1) return verified
    return ""
  }

  function consoleCandidateMapped() {
    var key = root.consoleLaunchCandidate
    if (!root.consoleLaunchPending || key === ""
        || root.consoleLaunchWindowBaseline[key]) return false
    return root.consoleLaunchVerifiedKey === key
      && root.agentWindowKeys(root.consoleLaunchWorkspace).indexOf(key) !== -1
  }

  // A global org.omarchy.agent window is not proof, nor is a native qconsole
  // seed racing us. The exec rule gives this launch a one-use Hyprland tag;
  // only a newly identified toplevel carrying it can pass the debounce.
  function probeConsoleLaunch() {
    if (!root.consoleLaunchPending) return
    var candidate = root.newConsoleWindowKey()
    if (candidate === "") {
      root.consoleLaunchCandidate = ""
      consoleLaunchConfirm.stop()
      return
    }
    if (candidate === root.consoleLaunchCandidate && consoleLaunchConfirm.running) return
    root.consoleLaunchCandidate = candidate
    consoleLaunchConfirm.restart()
  }

  Timer {
    id: consoleLaunchConfirm
    interval: 350
    onTriggered: root.confirmConsoleLaunch()
  }

  // A hidden Hyprland toplevel initially exposes its app id and workspace to
  // Quickshell, but not its tags. Verify the one-use launch tag against the
  // compositor before accepting an address; this cannot mistake a concurrent
  // native qconsole seed or an older agent window for our launch.
  Process {
    id: consoleLaunchVerify
    command: ["bash", "-c",
      "hyprctl clients -j 2>/dev/null | jq -r --arg ws \"$1\" --arg tag \"$2\" "
      + "'first(.[] | select((.class == \"org.omarchy.agent\" or .initialClass == \"org.omarchy.agent\") "
      + "and .workspace.name == $ws and any(.tags[]?; rtrimstr(\"*\") == $tag)) | .address) // empty'",
      "companion-console-verify", "special:" + root.consoleLaunchWorkspace,
      root.consoleLaunchTag]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.consoleLaunchPending) return
        var address = String(text || "").trim().split("\n")[0]
        if (!/^0x[0-9A-Fa-f]+$/.test(address)) return
        var key = "address:" + address
        if (root.consoleLaunchWindowBaseline[key]) return
        root.consoleLaunchVerifiedKey = key
        Hyprland.refreshToplevels()
        root.probeConsoleLaunch()
      }
    }
  }

  Timer {
    id: consoleLaunchVerifyTimer
    interval: 150
    repeat: true
    running: root.consoleLaunchPending
    onTriggered: if (!consoleLaunchVerify.running) consoleLaunchVerify.running = true
  }

  // Hyprland can publish a newly mapped hidden special-workspace window
  // without changing the JavaScript array object that backs the QML model.
  // Probe only while a launch is pending so that handoff never depends on a
  // missed collection-change signal.
  Timer {
    interval: 100
    repeat: true
    running: root.consoleLaunchPending
    onTriggered: root.probeConsoleLaunch()
  }

  function confirmConsoleLaunch() {
    if (!root.consoleLaunchPending) return false
    if (!root.consoleCandidateMapped()) return false
    var workspace = root.consoleLaunchWorkspace
    var target = root.consoleLaunchMonitor
    var reveal = root.consoleRevealOnConfirm
    var handoffAgent = root.consoleHandoffAgent
    var handoff = root.consoleHandoffSession
    var dismiss = root.consoleDismissOnOpen
    root.clearConsoleLaunch()
    // Focus moves only after our exact window is alive. This gives qconsole.lua
    // the right monitor for its dynamic half-screen fit, then reveals the
    // already-populated workspace without ever invoking on_created_empty.
    if (reveal) root.dispatchOn(target, Model.dispatchToggleSpecial(workspace))
    if (handoff !== "" && handoffAgent !== "") {
      root.forgetSession(handoffAgent)
      if (root.agentId === handoffAgent && root.sessionId === handoff)
        root.sessionId = ""
    }
    root.armSessionIdle()
    if (dismiss) root.dismissBubble()
    return true
  }

  function beginConsoleLaunch(command, monitor, reveal, handoff, dismiss) {
    if (String(command || "") === "" || root.consoleLaunchPending) return false
    var workspace = root.wantedConsoleWs
    var keys = root.agentWindowKeys(workspace)
    var baseline = ({})
    for (var i = 0; i < keys.length; i++) baseline[keys[i]] = true
    root.consoleLaunchWindowBaseline = baseline
    root.consoleLaunchTag = "companion-launch-" + Date.now().toString(36)
      + "-" + Math.floor(Math.random() * 0x1000000).toString(36)
    root.consoleLaunchVerifiedKey = ""
    root.consoleLaunchCandidate = ""
    root.consoleLaunchWorkspace = workspace
    root.consoleLaunchMonitor = root.actionMonitor(monitor)
    root.consoleRevealOnConfirm = reveal === true
    root.consoleHandoffAgent = String(handoff || "") !== "" ? root.agentId : ""
    root.consoleHandoffSession = String(handoff || "")
    root.consoleDismissOnOpen = dismiss === true
    root.consoleLaunchPending = true
    sessionIdle.stop()
    consoleLaunchTimeout.interval = 12000
    consoleLaunchTimeout.restart()
    if (!root.launchInConsole(command, workspace, root.consoleLaunchTag)) {
      root.clearConsoleLaunch()
      root.armSessionIdle()
      return false
    }
    return true
  }

  Timer {
    id: consoleLaunchTimeout
    interval: 12000
    onTriggered: {
      if (!root.consoleLaunchPending) return
      // If the window appeared on the deadline, let the stability proof run;
      // it still must survive consoleLaunchConfirm's full debounce.
      if (root.newConsoleWindowKey() !== "") {
        root.probeConsoleLaunch()
        interval = 500
        restart()
        return
      }
      var keptConversation = root.sessionId !== ""
      root.clearConsoleLaunch()
      root.armSessionIdle()
      root.sayMode = "error"
      root.sayText = keptConversation
        ? "The agent console did not open. Your conversation is still here."
        : "The agent console did not open."
    }
  }

  function summonConsole(monitor) {
    if (root.talkBusy) return "finish or stop the current order first"
    if (root.consoleLaunchPending) return "console is opening"
    if (!root.sessionsLoaded) return "still starting"
    // The prompt owns layer-shell keyboard focus. Hand that focus back before
    // opening the interactive console, whichever surface requested it.
    root.promptOpen = false

    var target = root.actionMonitor(monitor)
    if (root.consoleOpen) {
      root.dispatchOn(target, Model.dispatchToggleSpecial(root.wantedConsoleWs))
      return "console closed"
    }

    if (root.consoleWindows === 0) {
      if (!root.agentAvailable) {
        root.chooseAgent()
        return "choose an agent first"
      }

      var resume = Model.buildConsoleResume(root.agentId, root.sessionId)
      if (resume) {
        if (!root.beginConsoleLaunch(root.consoleArgvCommand(resume), target,
            !root.consoleWorkspaceOpen, root.sessionId, true)) return "could not open console"
      } else if (root.agentIsDefault) {
        if (!root.beginConsoleLaunch(
            "cd " + root.shq(root.talkCwd()) + " && omarchy-agent", target,
            !root.consoleWorkspaceOpen, "", false)) return "could not open console"
      } else {
        var command = Model.buildConsoleCommand(root.agentId, "")
        if (!command) return "unsupported agent: " + root.agentId
        if (!root.beginConsoleLaunch(root.consoleArgvCommand(command), target,
            !root.consoleWorkspaceOpen, "", false)) return "could not open console"
      }
      return "console open"
    }

    root.dispatchOn(target, Model.dispatchToggleSpecial(root.wantedConsoleWs))
    return "console open"
  }

  // Agents without a stream adapter still receive the exact order and the
  // selected agent remains selected. A prior bubble session is resumed when
  // the agent supports it.
  function orderToConsole(text, monitor) {
    var order = String(text || "").trim()
    if (root.consoleLaunchPending) return "console is opening"
    if (!root.sessionsLoaded) return "still starting"
    if (!root.agentAvailable) {
      root.chooseAgent()
      root.sayMode = "error"
      root.sayText = "Choose an agent first."
      return "no agent"
    }

    var parts = []
    if (root.preamble !== "") parts.push(root.preamble)
    if (root.standingOn !== "") parts.push(root.standingOn)
    parts.push("Order: " + order)
    var full = parts.join("\n\n")
    var command = ""
    var handoff = ""
    var resume = Model.buildConsoleResume(root.agentId, root.sessionId, full)
    if (resume) {
      command = root.consoleArgvCommand(resume)
      handoff = root.sessionId
    } else if (root.agentIsDefault) {
      command = "cd " + root.shq(root.talkCwd())
        + " && omarchy-agent-prompt " + root.shq(full)
    } else {
      command = root.consoleArgvCommand(Model.buildConsoleCommand(root.agentId, full))
    }
    if (command === "" || !root.beginConsoleLaunch(command, monitor,
        !root.consoleWorkspaceOpen, handoff, true)) {
      root.sayMode = "error"
      root.sayText = "That agent cannot be opened in the console."
      return "unsupported agent"
    }
    return "console"
  }

  // ------------------------------------------------------------ IPC
  //
  //   omarchy-shell companion ask | summon | toggle | show | hide | status
  //   omarchy-shell companion order "open spotify on DP-2"
  //   omarchy-shell companion travel DP-2

  property bool shown: true
  // Slid mostly off its edge, out of the way. A click brings it back.
  property bool tucked: false
  // Which way it was put away. Asking for it from the bar or a script sinks
  // it into the floor; shoving it against a side puts it away there.
  property string tuckSide: "down"

  property bool promptOpen: false
  onPromptOpenChanged: { root.armDodge(); root.armFollow() }

  // The chief's inner state, published as a small JSON file for scripts and
  // diagnostics. It is a read-only mirror; the bar binds to this service
  // directly and never waits for a file round-trip.
  readonly property string statusDir: stateHome + "/omarchy/companion"

  function statusJson() {
    return JSON.stringify({
      schemaVersion: 1,
      state: mood,
      energy: Math.round(energy * 100) / 100,
      agent: agentId,
      agentName: agentName(agentId),
      monitor: worldMonitor,
      shown: shown,
      tucked: tucked,
      talking: talkBusy,
      waiting: agentSilent,
      doing: doing,
      lastAnswer: lastAnswer.slice(0, 400),
      error: sayMode === "error" ? sayText.slice(0, 400) : "",
      consoleOpen: consoleOpen,
      sessionActive: sessionId !== "",
      pet: spritePetId !== "" ? spritePetId : cfgPet,
      shape: bloubPet ? cfgShape : "",
      color: bloubPet ? cfgColor : "",
      expression: bloubPet ? cfgExpression : "",
      bodyReady: spriteOk || bloubPet,
      themed: themedUsable,
      activity: activeChief && activeChief.activity
        ? String(activeChief.activity.name || "").slice(0, 64) : "",
      activityPasses: activeChief ? Number(activeChief.activityPasses || 0) : 0,
      updatedAtEpoch: Math.floor(Date.now() / 1000)
    })
  }

  onWorldMonitorChanged: {
    statusWrite.restart()
    root.armDodge()
    if (worldMonitor !== "" && !displaced) settleHome.restart()
  }
  onShownChanged: statusWrite.restart()
  onTuckedChanged: statusWrite.restart()
  onTuckSideChanged: statusWrite.restart()
  onCfgThemeChanged: {
    statusWrite.restart()
    if (cfgTheme) {
      root.beginRedress()
      return
    }
    // Off means the artist's original sheet now, even when a palette redraw
    // is still running. The completed cache remains useful if theme dressing
    // is enabled again, but it must not stay on screen during that run.
    redressTimer.stop()
    redressGiveUp.stop()
    backgroundRedress.stop()
    redressQueued = false
    themeRequestSerial++
    redressing = false
    wornBefore = ""
    if (root.activeChief && root.activeChief.cancelRepaint)
      root.activeChief.cancelRepaint()
    root.syncSpriteSource()
    root.rememberCurrentCoat()
  }
  onCfgPetChanged: { statusWrite.restart(); scanPets() }
  onSpriteOkChanged: statusWrite.restart()
  onAgentSilentChanged: statusWrite.restart()
  onDoingChanged: statusWrite.restart()
  onLastAnswerChanged: statusWrite.restart()
  onTalkBusyChanged: {
    statusWrite.restart()
    root.armSessionIdle()
    root.armDodge()
    root.armFollow()
  }
  onSessionIdChanged: {
    statusWrite.restart()
    rememberSession()
    root.armSessionIdle()
  }

  FileView {
    id: statusStore
    path: root.statusDir + "/status.json"
    atomicWrites: true
    printErrors: false
    onSaved: root.protectStateFile(path)
  }

  // The snapshot is for scripts and diagnostics. The bar binds to this
  // service directly and therefore never invents state between file writes.
  Timer {
    id: statusWrite
    interval: 400
    onTriggered: {
      if (!root.stateInitDone) { restart(); return }
      if (root.stateReady) statusStore.setText(root.statusJson() + "\n")
    }
  }

  property string settingError: ""

  // One rule for the drawn companion's three settings: report what is worn,
  // or change it. The choice is kept even while another companion is on
  // stage — it is a preference about a body, not about the desktop — so it is
  // accepted then, with a word about when it will show.
  function wearChoice(name, value) {
    var list = name === "shape" ? Bloub.SHAPES
      : name === "color" ? Bloub.COLORS : Bloub.EXPRESSIONS
    var current = name === "shape" ? root.cfgShape
      : name === "color" ? root.cfgColor : root.cfgExpression
    var want = String(value || "")
    if (want === "") return current
    if (!root.setConfig(name, want)) return root.settingError + ": " + Bloub.idsOf(list)
    return root.bloubPet ? "wearing " + want
      : want + ", for when the drawn companion is worn"
  }

  function normalizedSetting(key, value) {
    var name = String(key || "")
    if (!root.allowedSetting(name)) return { ok: false, error: "unknown setting: " + name }

    var boolKeys = ["expressions", "followFocus", "hideOnFullscreen", "reduceMotion",
                    "roam", "talk", "theme"]
    if (boolKeys.indexOf(name) !== -1) {
      if (value !== true && value !== false)
        return { ok: false, error: "setting needs a boolean" }
      return { ok: true, value: value }
    }
    if (name === "agent") {
      var agent = String(value || "")
      return agent === "" || root.hasAgent(agent)
        ? { ok: true, value: agent } : { ok: false, error: "agent is not installed" }
    }
    if (name === "pet") {
      var pet = String(value || "")
      var foundPet = false
      for (var p = 0; p < root.installedPets.length; p++)
        if (root.installedPets[p].id === pet) foundPet = true
      return foundPet ? { ok: true, value: pet }
        : { ok: false, error: "pet is not installed" }
    }
    if (name === "shape" || name === "color" || name === "expression") {
      var choice = String(value || "")
      var known = name === "shape" ? Bloub.isShapeId(choice)
        : name === "color" ? Bloub.isColorId(choice) : Bloub.isExpressionId(choice)
      return known ? { ok: true, value: choice }
        : { ok: false, error: "no such " + name }
    }
    if (name === "screen") {
      var screen = String(value || "")
      return screen === "" || Model.segmentByName(root.segments, screen) !== null
        ? { ok: true, value: screen } : { ok: false, error: "monitor is not connected" }
    }
    if (name === "workdir") {
      var path = String(value || "").trim()
      return path === "" || path.indexOf("/") === 0 || path.indexOf("~/") === 0
        ? { ok: true, value: path } : { ok: false, error: "workdir must be absolute" }
    }
    if (name === "promptPreamble") {
      if (typeof value !== "string") return { ok: false, error: "instructions need text" }
      return value.length <= root.preambleMax
        ? { ok: true, value: value }
        : { ok: false, error: "instructions exceed 8000 characters" }
    }

    var number = Number(value)
    if (!isFinite(number)) return { ok: false, error: "setting needs a number" }
    if (name === "sessionIdleMin")
      return number === -1 || (number >= 0 && number <= 1440 && Math.round(number) !== 1)
        ? { ok: true, value: Math.round(number) }
        : { ok: false, error: "conversation must be once, forever, or 2–1440 minutes" }
    if (name === "size") return number >= 32 && number <= 240
      ? { ok: true, value: Math.round(number) } : { ok: false, error: "size is outside 32–240" }
    if (name === "expressionChance" || name === "themeTint" || name === "activityChance")
      return number >= 0 && number <= 1 ? { ok: true, value: number }
        : { ok: false, error: "value is outside 0–1" }
    if (name === "frameIntervalMs") return number >= 60 && number <= 500
      ? { ok: true, value: Math.round(number) } : { ok: false, error: "frame interval is outside 60–500" }
    if (name === "turnTimeoutSec") return number >= 60 && number <= 3600
      ? { ok: true, value: Math.round(number) } : { ok: false, error: "timeout is outside 60–3600" }
    if (name === "patienceSec") return number >= 5 && number <= 600
      ? { ok: true, value: Math.round(number) } : { ok: false, error: "patience is outside 5–600" }
    if (name === "speakMax") return number >= 40 && number <= 1000
      ? { ok: true, value: Math.round(number) } : { ok: false, error: "reply length is outside 40–1000" }
    if (name === "activityRestSec" || name === "edgeGap") return number >= 0 && number <= 3600
      ? { ok: true, value: Math.round(number) } : { ok: false, error: "value is outside range" }
    if (name === "activity") return number > 0 && number <= 10
      ? { ok: true, value: number } : { ok: false, error: "activity rate is outside range" }
    return { ok: false, error: "unsupported setting: " + name }
  }

  // One resident service serializes every settings write; per-monitor bar
  // instances never race each other or maintain shadow config files.
  function setConfig(key, value) {
    var normalized = root.normalizedSetting(key, value)
    if (!normalized.ok) { root.settingError = normalized.error; return false }
    if (!shell || typeof shell.updateEntryInline !== "function") {
      root.settingError = "shell settings are not ready"
      return false
    }
    var next = ({})
    for (var k in cfg) if (root.allowedSetting(k)) next[k] = cfg[k]
    next[root.migrationMarker] = root.configVersion
    next[String(key)] = normalized.value
    root.settingError = ""
    shell.updateEntryInline(entryId, next)
    return true
  }

  function setShown(value) {
    root.shown = value === true
    if (!root.shown) root.promptOpen = false
  }

  function setTucked(value) {
    if (value === true) root.tuckSide = "down"
    root.tucked = value === true
    if (root.tucked) root.promptOpen = false
  }

  function freshConversation() {
    if (!root.sessionsLoaded || root.talkBusy || root.consoleLaunchPending) return false
    root.sessionId = ""
    root.dismissBubble()
    return true
  }

  function playActivity(name) {
    if (!root.activeChief) return "not on stage"
    var list = root.spriteActivities
    if (list.length === 0) return "this pet has no activities"
    var wanted = String(name || "").trim()
    var pick = null
    if (wanted === "") pick = list[Math.floor(Math.random() * list.length)]
    else for (var i = 0; i < list.length; i++)
      if (String(list[i].name) === wanted) pick = list[i]
    if (!pick) {
      var names = []
      for (var j = 0; j < list.length; j++) names.push(String(list[j].name || ""))
      return "no such activity; try: " + names.join(", ")
    }
    return root.activeChief.playActivity(pick) ? "playing " + pick.name : "busy right now"
  }

  function playRandom() { return root.playActivity("") }

  function goHomeOn(monitor) {
    if (root.pendingTravel !== null) return "already traveling"
    var target = root.actionMonitor(monitor)
    if (target !== "" && target !== root.worldMonitor) return root.travelTo(target)
    if (!root.activeChief) return "not on stage"
    return root.activeChief.walkHome(root.effectiveHomeX) ? "going home" : "home"
  }

  function askOn(monitor) {
    root.shown = true
    root.tucked = false
    if (root.talkBusy) return "already working"
    if (root.consoleLaunchPending) return "console is opening"
    if (root.pendingTravel !== null) {
      var requested = String(monitor || "")
      root.pendingAsk = true
      root.pendingAskMonitor = Model.segmentByName(root.segments, requested) !== null
        ? requested : String(root.pendingTravel.mon || "")
      return "will ask on " + root.pendingAskMonitor
    }
    if (!root.agentAvailable) {
      root.promptOpen = false
      root.chooseAgent()
      return "choose an agent first"
    }
    var target = root.actionMonitor(monitor)
    if (target !== "" && target !== root.worldMonitor) {
      root.pendingAsk = true
      root.pendingAskMonitor = target
      var result = root.travelTo(target)
      if (result.indexOf("traveling") === 0 || result.indexOf("moved") === 0) return result
      root.pendingAsk = false
      root.pendingAskMonitor = ""
    }
    root.promptOpen = true
    return "ready"
  }

  IpcHandler {
    target: "companion"

    function ask(): void { root.askOn("") }
    function order(text: string): string { root.shown = true; return root.runOrder(text) }
    function stop(): string { return root.stopOrder() ? "stopping" : "nothing is running" }
    function travel(monitor: string): string { return root.travelTo(monitor) }

    function screen(name: string): string {
      var want = String(name || "")
      if (want === "any") want = ""
      if (!root.setConfig("screen", want)) return root.settingError
      return want === "" ? "free to move" : "kept to " + want
    }

    function follow(on: string): string {
      if (root.stillPet) return "this one stays where you put it"
      var want = Model.flagValue(on, root.cfgFollow)
      if (want === null) return "use on or off"
      return root.setConfig("followFocus", want)
        ? (want ? "following your focus" : "staying put") : root.settingError
    }

    function tuck(on: string): string {
      var side = on === "left" || on === "right" ? on : ""
      var want = side !== "" ? true : Model.flagValue(on, root.tucked)
      if (want === null) return "use on, off, left, or right"
      if (want) root.tuckSide = side !== "" ? side : "down"
      root.tucked = want
      if (want) root.promptOpen = false
      return want ? "tucked away" : "back"
    }

    function place(x: string): string {
      if (!root.activeChief) return "not on stage"
      var want = Number(x)
      if (!isFinite(want)) return "where?"
      root.activeChief.px = Model.dragTo(want, 0, root.activeChief.width, root.petSize)
      root.rememberHome(root.activeChief.px)
      return "standing at " + Math.round(root.activeChief.px)
    }

    function agent(id: string): string {
      var want = id === "any" ? "" : String(id || "")
      if (!root.setConfig("agent", want)) return root.settingError
      return want === "" ? "following the default agent" : "using " + root.agentName(want)
    }

    function pet(id: string): string {
      if (id === "") return root.cfgPet
      return root.setConfig("pet", id) ? "wearing " + id : root.settingError
    }

    // The drawn companion's three choices. Reached by name from memory more
    // often than from the panel, so a value that is not recognised answers
    // with the ones that are rather than with a bare refusal.
    function shape(id: string): string { return root.wearChoice("shape", id) }
    function color(id: string): string { return root.wearChoice("color", id) }
    function expression(id: string): string { return root.wearChoice("expression", id) }

    function speak(on: string): string {
      var want = Model.flagValue(on, root.cfgTalk)
      if (want === null) return "use on or off"
      return root.setConfig("talk", want)
        ? (want ? "answering in the bubble" : "opening the console") : root.settingError
    }

    function conversation(minutes: string): string {
      var raw = String(minutes || "")
      var value = raw === "once" ? -1 : raw === "" ? 0 : Number(raw)
      if (!root.setConfig("sessionIdleMin", value)) return root.settingError
      if (value < 0) return "one request per conversation"
      if (value === 0) return "conversation stays open"
      return "ends after " + Math.round(value) + " quiet minutes"
    }

    function fresh(): string {
      if (!root.sessionsLoaded) return "still starting"
      return root.freshConversation() ? "starting fresh" : "stop the current order first"
    }

    function shy(on: string): string {
      var want = Model.flagValue(on, root.cfgHideFullscreen)
      if (want === null) return "use on or off"
      return root.setConfig("hideOnFullscreen", want)
        ? (want ? "hiding while fullscreen" : "staying visible") : root.settingError
    }

    function theme(on: string): string {
      var want = Model.flagValue(on, root.cfgTheme)
      if (want === null) return "use on or off"
      return root.setConfig("theme", want)
        ? (want ? "wearing your theme" : "keeping its own colours") : root.settingError
    }

    function motion(on: string): string {
      var want = Model.flagValue(on, !root.cfgReduceMotion)
      if (want === null) return "use on or off"
      return root.setConfig("reduceMotion", !want)
        ? (want ? "motion on" : "reduced motion") : root.settingError
    }

    function often(how: string): string {
      var steps = [0.1, 0.25, 0.5]
      var next = -1
      var raw = String(how || "").toLowerCase()
      for (var i = 0; i < steps.length; i++)
        if (Model.oftenName(steps[i]) === raw) next = steps[i]
      if (raw === "sometimes") next = 0.25
      if (next < 0) {
        if (raw !== "") return "use rarely, sometimes, or often"
        var here = 0
        for (var j = 0; j < steps.length; j++)
          if (Math.abs(steps[j] - root.cfgGlanceChance)
              < Math.abs(steps[here] - root.cfgGlanceChance)) here = j
        next = steps[(here + 1) % steps.length]
      }
      return root.setConfig("expressionChance", next) ? Model.oftenName(next) : root.settingError
    }

    function bigger(px: string): string {
      var steps = [96, 130, 150, 190]
      var raw = String(px || "").trim()
      var value = Number(raw)
      if (raw !== "" && (!isFinite(value) || value <= 0)) return "size needs a number"
      var next = raw !== "" ? Math.round(value) : -1
      if (next < 0) {
        var here = 0
        for (var i = 0; i < steps.length; i++)
          if (Math.abs(steps[i] - root.petSize) < Math.abs(steps[here] - root.petSize)) here = i
        next = steps[(here + 1) % steps.length]
      }
      return root.setConfig("size", next) ? "size " + next : root.settingError
    }

    function expressions(on: string): string {
      var want = Model.flagValue(on, root.cfgExpressions)
      if (want === null) return "use on or off"
      return root.setConfig("expressions", want)
        ? (want ? "expressions on" : "expressions off") : root.settingError
    }

    function play(name: string): string { return root.playActivity(name) }
    function home(): string { return root.goHomeOn(root.worldMonitor) }
    function stroll(): string {
      if (!root.activeChief) return "not on stage"
      return root.activeChief.strollNow() ? "walking" : "cannot walk right now"
    }

    function summon(): string { return root.summonConsole(root.worldMonitor) }
    function toggle(): string {
      root.setShown(!root.shown)
      return root.shown ? "shown" : "hidden"
    }
    function show(): void { root.setShown(true) }
    function hide(): void { root.setShown(false) }

    function status(): string {
      var segs = []
      for (var i = 0; i < root.segments.length; i++)
        segs.push(root.segments[i].name + "@" + root.segments[i].x + "+" + root.segments[i].w)
      return root.mood
        + " energy=" + Math.round(root.energy * 100) + "%"
        + " agent=" + (root.agentId === "" ? "none" : root.agentId)
        + " body=" + (root.spriteOk || root.bloubPet ? root.spritePetId : "fallback")
        + " monitor=" + root.worldMonitor
        + " console=" + (root.consoleLaunchPending ? "opening"
          : root.consoleOpen ? "open" : "closed")
        + " session=" + (root.sessionId === "" ? "fresh" : root.sessionId.slice(0, 8))
        + " talking=" + (root.talkBusy ? "yes" : "no")
        + (root.agentSilent ? " waiting=yes" : "")
        + " screens=[" + segs.join(",") + "]"
    }
  }

  // ------------------------------------------------------------ the windows
  //
  // One strip per monitor, mapped only while the chief is on it. Everything
  // else on that screen clicks straight through; while the order form is
  // open its padded route to the chief catches the dismissing click.

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: win
      required property var modelData
      readonly property bool chiefHere: modelData.name === root.worldMonitor

      screen: modelData
      // Asking, working, and answering are explicit attention: they map above
      // fullscreen. Passive presence still yields to it.
      visible: chiefHere && root.shown
        && !(root.cfgHideFullscreen && root.fullscreenOnPetMonitor
             && !root.promptOpen && !root.talkBusy && root.sayMode === "")
      anchors { left: true; right: true; bottom: true }
      implicitHeight: Math.max(Math.round(root.petSize * 2.4), 220)
      color: "transparent"
      aboveWindows: true
      // Reserve nothing, but respect what others reserve: on a monitor
      // with a bottom bar the chief walks on top of the bar; on a bare
      // edge it walks on the edge itself.
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: 0
      mask: chiefLoader.item ? chiefLoader.item.inputRegion : null
      WlrLayershell.namespace: "omarchy-companion"

      // Prime with Exclusive on every open, then settle on OnDemand — the
      // KeyboardPanel recipe. Hyprland focuses OnDemand when a surface
      // first maps, but not when an already-mapped strip flips from None
      // to OnDemand; without the prime, keystrokes fall through into the
      // window behind the chief.
      readonly property bool wantsKeyboard: win.visible && win.chiefHere && root.promptOpen
      property bool focusPrimed: false
      onWantsKeyboardChanged: {
        if (wantsKeyboard) { focusPrimed = false; primeTimer.restart() }
        else primeTimer.stop()
      }
      Timer {
        id: primeTimer
        interval: 90
        onTriggered: {
          win.focusPrimed = true
          // The field focused once when it appeared. Confirm it after the
          // Exclusive -> OnDemand handoff too, so timing can never leave a
          // visible prompt without a caret or keyboard input.
          Qt.callLater(function() {
            if (chiefLoader.item) chiefLoader.item.focusPrompt()
          })
        }
      }
      WlrLayershell.keyboardFocus: win.wantsKeyboard
        ? (win.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
        : WlrKeyboardFocus.None

      onVisibleChanged: if (!visible && chiefHere) root.promptOpen = false

      Loader {
        id: chiefLoader
        anchors.fill: parent
        active: win.chiefHere
        onLoaded: root.activeChief = item
        onActiveChanged: if (!active && root.activeChief && root.activeChief.parent === chiefLoader) root.activeChief = null

        sourceComponent: Chief {
          orderMax: root.orderMax
          petSize: root.petSize
          fullScreenHeight: modelData.height
          pixelArt: root.spritePixelArt
          bloub: root.bloubPet
          bloubShape: root.cfgShape
          bloubColor: root.cfgColor
          bloubExpression: root.cfgExpression
          mood: root.mood
          energy: root.energy
          activityRate: root.cfgActivity
          reduceMotion: root.cfgReduceMotion
          roam: root.cfgRoam && !root.stillPet
          faces: root.spriteFaces
          columns: root.spriteColumns
          mayMirror: root.spriteMirror
          doing: root.doing
          tucked: root.tucked
          idleFaces: root.spriteIdleFaces
          blinkFace: root.spriteBlink
          expressions: root.cfgExpressions
          glanceChance: root.cfgGlanceChance
          activities: root.spriteActivities
          stillRows: root.spriteStillRows
          activityChance: root.cfgActivityChance
          activityRestMs: root.cfgActivityRestSec * 1000
          groundOffset: Model.groundOffset(root.gapBottom, root.petSize, 4, 208)
          active: win.visible && root.petResolved
          visible: root.petResolved
          promptOpen: root.promptOpen
          submerged: root.submerged
          initialPx: root.spawnLocalX >= 0 ? root.spawnLocalX : root.effectiveHomeX
          sayMode: root.sayMode
          sayText: root.sayText
          spriteOk: root.spriteOk
          spriteSource: root.spriteSource
          spriteRows: root.spriteRows
          tintStrength: root.spriteTint
          sleepRow: root.spriteSleepRow
          walkFrames: root.spriteWalkFrames
          frameIntervalMs: root.cfgFrameMs
          // Hovering is how the two buttons nobody thinks to try get found.
          tooltipText: (root.agentId === "" ? "no agent yet" : root.agentId)
            + " · energy " + Math.round(root.energy * 100) + "%"
            + "\nclick to ask · right-click for the console · drag me anywhere"

          onPxChanged: root.lastLocalX = px
          tuckSide: root.tuckSide
          content: root.spriteContent
          onWantsOut: root.tucked = false
          onPushedAside: function(side) {
            root.promptOpen = false
            root.tuckSide = side
            root.tucked = true
          }
          onPetPressed: function(button) {
            if (button === Qt.RightButton) root.summonConsole()
            else if (button === Qt.LeftButton) {
              // A running order owns the bubble and the interaction slot.
              // Opening an input that cannot submit would discard its draft
              // and erase the visible progress state.
              if (root.talkBusy) return
              if (!root.agentAvailable) {
                root.promptOpen = false
                root.chooseAgent()
                return
              }
              // A click on the chief always clears a standing reply first —
              // the answer was read the moment you reach for the creature.
              var hadBubble = root.sayMode === "say" || root.sayMode === "error"
              root.dismissBubble()
              root.promptOpen = hadBubble ? false : !root.promptOpen
            }
          }
          onPromptSubmitted: function(text) { root.runOrder(text) }
          onPromptDismissed: root.promptOpen = false
          onBubbleDismissed: root.dismissBubble()
          onConsoleRequested: root.summonConsole()
          onSpriteLoadFailed: root.themedSheetMissing()
          onDraggedTo: function(x) { root.rememberHome(x) }
          onActivityFinished: activity = null
        }
      }
    }
  }
}
