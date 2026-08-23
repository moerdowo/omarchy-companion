import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "Model.js" as Model

// Omarchief — your desktop's chief of staff.
//
// This file is the plumbing. One click-through strip per monitor makes the
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

  // ------------------------------------------------------------ user config
  //
  // ~/.config/omarchy/omarchief.json, hot-reloaded on save. All keys
  // optional:
  //   { "size": 56, "followFocus": true, "hideOnFullscreen": true,
  //     "activity": 1.0, "screen": "", "pet": "", "frameIntervalMs": 140,
  //     "talk": true, "speakMax": 260, "promptPreamble": "", "sessionIdleMin": 0,
  //     "expressions": true, "expressionChance": 0.25 }

  // Settings live inline on this plugin's own entry in shell.json, which is
  // where the shell keeps every plugin's — "no separate per-plugin settings
  // file" is its rule, and a file of our own was ours to keep in step. The
  // shell hands a panel plugin its own object when it loads it, so the entry
  // is readable and writable without the bar widget having to exist.
  property var shell: null
  readonly property string entryId: manifest && manifest.id ? String(manifest.id)
                                                            : "io.github.daventhedude.omarchief"
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
  // The file is what earlier versions wrote to, and is still read so nobody
  // loses their settings on an update; the entry wins wherever both speak.
  property var fileCfg: ({})
  readonly property var cfg: {
    var out = ({})
    for (var k in fileCfg) out[k] = fileCfg[k]
    var e = entrySettings
    for (var j in e) if (j !== "id") out[j] = e[j]
    return out
  }
  readonly property string configFile: root.home + "/.config/omarchy/omarchief.json"

  // Whether the chief can see what claude does in the console. That takes
  // five hooks in ~/.claude/settings.json — somebody else's file — so it is
  // off until a person turns it on, and turning it off takes them out again.
  property bool hooksInstalled: false
  property bool hasClaude: false
  function probeHooks() { hookProbe.running = true }
  Process {
    id: hookProbe
    running: root.pluginDir !== ""
    command: ["bash", "-lc", "command -v claude >/dev/null && echo claude; "
      + shq(root.pluginDir + "/tools/omarchief-hooks") + " status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "")
        root.hasClaude = t.indexOf("claude") !== -1
        root.hooksInstalled = t.indexOf("installed") !== -1
      }
    }
  }
  Process { id: hookSet; onExited: root.probeHooks() }
  onPluginDirChanged: if (pluginDir !== "") probeHooks()

  // Which pets are installed, so the bar widget can offer them rather than
  // making somebody edit a file to try one on. Names come from each
  // pet.json; a folder without one is not a pet.
  property var installedPets: []
  function scanPets() { petScan.running = true }
  Process {
    id: petScan
    running: true
    command: ["bash", "-lc",
      "for d in ~/.config/omarchief/pets/*/ ~/.config/omapets/pets/*/; do "
      + "[ -f \"$d/pet.json\" ] || continue; "
      + "id=$(basename \"$d\"); "
      + "name=$(sed -n 's/.*\"name\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' \"$d/pet.json\" | head -1); "
      + "printf '%s\\t%s\\n' \"$id\" \"${name:-$id}\"; done | sort -u"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length < 2 || parts[0] === "") continue
          out.push({ id: parts[0], name: parts[1] })
        }
        root.installedPets = out
      }
    }
  }
  FileView {
    path: root.configFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.fileCfg = JSON.parse(String(text() || "")) || {} }
      catch (e) { console.warn("omarchief: ignoring bad omarchief.json:", e) }
    }
    onLoadFailed: root.fileCfg = ({})
  }

  readonly property int petSize: Model.resolvePetSize(cfg.size, spritePreferredSize)
  // Whether the creature is repainted in your theme at all. A pet with no
  // hue window keeps its own colours regardless; this is for the ones that
  // could be repainted and whose owner would rather they were not.
  readonly property bool cfgTheme: cfg.theme !== undefined ? !!cfg.theme : true
  // Whether a resting creature changes its expression on its own.
  readonly property bool cfgExpressions: cfg.expressions !== undefined ? !!cfg.expressions : true
  readonly property real cfgGlanceChance: {
    var v = Number(cfg.expressionChance)
    return isFinite(v) && v >= 0 && v <= 1 ? v : 0.25
  }
  readonly property int cfgSessionIdleMin: {
    var v = Number(cfg.sessionIdleMin)
    // Absent means one long conversation. A number ends it after that many
    // quiet minutes; zero says the same thing as absent, out loud.
    return isFinite(v) && v >= 0 ? Math.round(v) : 0
  }
  readonly property bool cfgFollow: (cfg.followFocus !== undefined ? !!cfg.followFocus : true) && !stillPet
  readonly property bool cfgHideFullscreen: cfg.hideOnFullscreen !== undefined ? !!cfg.hideOnFullscreen : true
  readonly property real cfgActivity: isFinite(Number(cfg.activity)) && Number(cfg.activity) > 0 ? Number(cfg.activity) : 1
  readonly property string cfgScreen: typeof cfg.screen === "string" ? cfg.screen : ""
  // A fresh install wears the pet it ships with — the one in every picture
  // of this plugin. Saying `"pet": ""` out loud still asks for the body
  // drawn from theme colours alone, and a pet that cannot be found falls
  // back to it too, so nothing is ever left standing there empty.
  readonly property string cfgPet: typeof cfg.pet === "string" ? cfg.pet : "gritty"
  // "quake" drops the console from the top of the screen; "chief" opens it
  // as a floating window standing over the creature itself.
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
    return isFinite(v) && v >= 0 ? Math.round(v) : 90
  }
  readonly property bool cfgRoam: cfg.roam === true
  readonly property string cfgConsoleAt: cfg.consoleAt === "chief" ? "chief" : "quake"
  readonly property bool cfgTalk: cfg.talk !== undefined ? !!cfg.talk : true
  // How long a silent agent gets before the chief admits it is still going.
  readonly property int cfgPatience: {
    var v = Number(cfg.patienceSec)
    return isFinite(v) && v >= 5 ? Math.round(v) : 25
  }
  readonly property int cfgSpeakMax: isFinite(Number(cfg.speakMax)) && Number(cfg.speakMax) > 40 ? Number(cfg.speakMax) : 260
  readonly property int cfgFrameMs: {
    var v = Number(cfg.frameIntervalMs)
    return isFinite(v) && v >= 60 && v <= 500 ? Math.round(v) : 140
  }

  // The preamble that makes the agent this desktop's resident. Only the
  // first order of a session carries it; resumed turns already know.
  readonly property string defaultPreamble: "You are Omarchief, the resident spirit and chief of staff of this Omarchy Linux desktop. You act on the user's behalf, unattended: do not wait for confirmation, and take irreversible steps \u2014 deleting data, closing windows, killing sessions, anything hard to undo \u2014 only when expressly ordered. If an order is genuinely ambiguous, ask in one short sentence rather than guessing; that is a question, not a confirmation.\n\nYou are not sitting in a terminal anyone is watching. Your words go into a small speech bubble beside a creature on the desktop, and nothing you print is read by anybody. So when the answer is something to be looked at, open it the way this desktop opens things: `omarchy launch browser <url>` for a page, `omarchy launch editor <path>` for a file, `xdg-open <path>` for a folder or anything else, and `omarchy launch terminal` for a terminal, which opens the one this user actually chose rather than whichever you have heard of. Never a terminal browser \u2014 no w3m, lynx, links, no curl piped into your own reply \u2014 unless the user asked what a page *says* rather than to see it. When the window is likely already open, `omarchy launch or focus <window-pattern> <launch-command>` brings it forward instead of starting a second one. If something is not installed, say so; do not install it unasked.\n\nThis desktop has a command for most things it can do to itself, and `omarchy commands` lists every one of them: reaching for that beats inventing a way. Read whatever you need with ordinary command-line tools \u2014 it is only *showing* that goes through the desktop.\n\nThe shell answers separately, on targets no CLI listing mentions, through `omarchy-shell <target> <method>`. Whatever is playing anywhere \u2014 a YouTube tab counts, and so does Spotify \u2014 is `omarchy-shell media status`, then `playPause`, `play`, `pause`, `next`, `previous`: reach for those rather than playerctl, which this machine does not have, or clicking about inside the page. Quiet is `notifications toggleDnd`, with `isDnd`, `dismissAll` and `showHistory` beside it. Keeping the screen awake through a talk is `idle disable`, and `idle enable` gives it back. There are also `nightlight toggle` and `lock lock`. Most answer `status` or `ping`, so you can look before you touch.\n\nUse the desktop's own controls rather than working around them. Where `omarchy`, `omarchy-shell` or `hyprctl` covers a job, that is the way to do it \u2014 not editing config files by hand, killing processes, restarting the shell, or driving an application through synthetic keystrokes. The official way is the one that keeps the desktop's own idea of its state true, and the one a person can undo. If there is no official way, say so rather than improvising something clever with a sharp edge on it.\n\nHyprland is `hyprctl`. Ask it things with `hyprctl -j clients`, `hyprctl -j monitors`, `hyprctl -j activewindow`. Tell it things in Lua, which this Hyprland requires and which older examples get wrong: `hyprctl dispatch \"hl.dsp.exec_cmd('<command>')\"`, `hl.dsp.focus({monitor='DP-2'})`, `hl.dsp.workspace.toggle_special('magic')`, `hl.dsp.window.close({address='0x...'})`. The plain form \u2014 `hyprctl dispatch exec <command>` \u2014 is rejected outright. Dispatchers that name no target act on whatever is focused, which is rarely what was meant: address a window by `address:0x...` from `hyprctl -j clients` instead of trusting the focus.\n\nAnswer in the language the user writes, in one or two short sentences of plain text, no markdown \u2014 anything longer is cut off mid-sentence. When the full story will not fit, do the work anyway and say that a right-click on the creature carries this same conversation into the console.\n\nThe creature on screen is your body. When your work concerns one monitor, walk there first \u2014 `omarchy-shell omarchief travel <name>` \u2014 so the user sees you arrive where the work happens; told to get out of the way, put yourself aside with `omarchy-shell omarchief tuck on`. Your standing notes live in " + root.notesPath + ": read them when an order leans on earlier context, and append anything worth keeping \u2014 a preference, a recurring task, where things live."
  readonly property string preamble: cfg.promptPreamble !== undefined ? String(cfg.promptPreamble) : defaultPreamble

  // Where the body actually stands is a runtime fact, not an instruction, so
  // it is appended rather than baked into the preamble the user may edit.
  // Without it the agent opens windows wherever focus happened to be, which
  // is regularly a screen the user is not looking at.
  readonly property string standingOn: {
    if (worldMonitor === "") return ""
    var t = "\n\nYour body is standing on the monitor called " + worldMonitor
      + ". Anything you open belongs on the screen the user is watching you from, so focus that monitor first"
      + " \u2014 hyprctl dispatch \"hl.dsp.focus({monitor='" + worldMonitor + "'})\" \u2014 and launch afterwards."
      + " A bare launch lands wherever the focus happened to be, which is regularly another screen entirely."
    t += " That places a window opened for the first time. An application already running commonly takes the page as a tab in the window it already has, and no focusing moves that window: when it lands on another screen, say where it went rather than claiming it is in front of the user."
    if (cfgScreen !== "") t += " You have been kept to this monitor in your settings, so travelling elsewhere is refused: work from here."
    return t
  }
  readonly property string fullPreamble: preamble === "" ? "" : preamble + standingOn

  // ------------------------------------------------------------ default agent

  // The agent the desktop as a whole prefers.
  property string defaultAgentId: ""
  FileView {
    path: root.home + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.defaultAgentId = String(text() || "").trim()
    onLoadFailed: root.defaultAgentId = ""
  }

  // The one the creature uses. Following the desktop's choice is the
  // sensible default and stays the default; picking one here is for when
  // you want the chief on something other than what you type into a
  // terminal all day.
  readonly property string cfgAgent: cfg.agent !== undefined ? String(cfg.agent) : ""
  readonly property string agentId: cfgAgent !== "" ? cfgAgent : defaultAgentId
  readonly property bool agentIsDefault: cfgAgent === ""

  // Which agents are actually installed, so the bar offers what can be run.
  // Both the candidates and their proper names come from Omarchy's own
  // omarchy-default-agent: the `omarchy:args` header is the same line that
  // `omarchy commands` reads, and the case block below it is where "omp"
  // learns it is called Oh My Pi. Copying either into this file would mean
  // going quietly out of date the day Omarchy learns a tenth agent, so the
  // list here is only the fallback for a desktop that has moved the script.
  property var installedAgents: []
  Process {
    id: agentScan
    running: true
    command: ["bash", "-lc", "src=$(command -v omarchy-default-agent 2>/dev/null)\norder=\n[ -n \"$src\" ] && order=$(sed -n 's/^# omarchy:args=\\[\\(.*\\)\\]$/\\1/p' \"$src\" | head -1 | tr '|' ' ')\n[ -n \"$order\" ] || order='pi omp opencode claude codex grok gemini copilot crush'\nfor a in $order; do\n  command -v \"$a\" >/dev/null 2>&1 || continue\n  n=\n  [ -n \"$src\" ] && n=$(sed -n 's/.*agent=\"'\"$a\"'\";[[:space:]]*name=\"\\([^\"]*\\)\".*/\\1/p' \"$src\" | head -1)\n  printf '%s\\t%s\\n' \"$a\" \"${n:-$a}\"\ndone"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length < 2 || parts[0].trim() === "") continue
          out.push({ id: parts[0].trim(), name: parts[1].trim() })
        }
        root.installedAgents = out
      }
    }
  }
  // A conversation belongs to one agent. Picking a different default agent
  // ends it: a claude session id means nothing to codex, and resuming it
  // after switching back would drag a stale context into a new day.
  onAgentIdChanged: {
    root.sessionId = root.sessions[root.agentId] ? root.sessions[root.agentId] : ""
    root.agentSilent = false
    sessionIdle.stop()
    if (talkProc.running) talkProc.running = false
    root.talkBusy = false
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

  // ------------------------------------------------------------ agent windows

  readonly property var wlToplevels: ToplevelManager.toplevels.values
  readonly property int agentWindows: {
    var n = 0
    for (var i = 0; i < wlToplevels.length; i++) {
      var t = wlToplevels[i]
      if (t && t.appId === "org.omarchy.agent") n++
    }
    return n
  }

  // ------------------------------------------------------------ the gap
  //
  // Hyprland leaves a gap between a window and the edge of the screen. The
  // creature uses the same one, so it stands in line with the windows above
  // it instead of at some margin of its own invention.

  property var gaps: ({ top: 0, right: 0, bottom: 0, left: 0 })
  readonly property real gapBottom: cfg.edgeGap !== undefined && isFinite(Number(cfg.edgeGap))
    ? Number(cfg.edgeGap) : Number(gaps.bottom || 0)
  readonly property real gapLeft: cfg.edgeGap !== undefined && isFinite(Number(cfg.edgeGap))
    ? Number(cfg.edgeGap) : Number(gaps.left || 0)

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
  // The creature lives somewhere: down in the left corner by default, where
  // the cable it trails runs off the screen, and wherever you drag it after
  // that. The spot is remembered next to the rest of our state rather than
  // in the user's config, because it is a placement, not a preference.

  readonly property string homeFile: stateHome + "/omarchy/omarchief/home.json"
  property var homes: ({})
  readonly property real worldWidth: worldSegment ? worldSegment.w : 0
  readonly property real effectiveHomeX: Model.homeFor(homes, worldMonitor, worldWidth, petSize, gapLeft)


  FileView {
    path: root.homeFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(String(text() || ""))
        root.homes = Model.readHomes(parsed)
        root.homeMon = String(parsed && parsed.monitor ? parsed.monitor : "")
        // Focus is known before this file is read, so the first placement is
        // usually a guess. Now that the answer is in, correct it.
        var remembered = Model.homeMonitor({ monitor: root.homeMon }, root.segments)
        if (root.placementGuessed && remembered !== "" && remembered !== root.worldMonitor) {
          root.worldMonitor = remembered
          root.spawnLocalX = root.homeOn(remembered)
        }
        if (remembered !== "") root.placementGuessed = false
      } catch (e) { root.homes = ({}) }
      root.homeLoaded = true
    }
    onLoadFailed: { root.homes = ({}); root.homeLoaded = true }
  }

  function rememberHome(x) {
    if (worldMonitor === "") return
    var next = ({})
    for (var name in homes) next[name] = homes[name]
    next[worldMonitor] = Math.round(x)
    root.homes = next
    root.homeMon = worldMonitor
    writeHome()
  }

  // The screen it lives on is remembered too, so a restart puts it back where
  // you left it rather than wherever the focus happened to be.
  property string homeMon: ""
  function writeHome() {
    Quickshell.execDetached(["bash", "-c",
      "mkdir -p " + shq(stateHome + "/omarchy/omarchief") + " && printf %s "
      + shq(JSON.stringify({ monitors: homes, monitor: homeMon })) + " > " + shq(homeFile)])
  }

  // Arriving on a screen means standing where the creature stands there.
  function homeOn(monitor) {
    var seg = Model.segmentByName(segments, monitor)
    return Model.homeFor(homes, monitor, seg ? seg.w : 0, petSize, gapLeft)
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
      out.push({ name: scr[i].name, x: scr[i].x, width: scr[i].width })
    return Model.worldSegments(out)
  }

  // Monitors come and go. If the ground under the chief vanishes, it does
  // not wait for someone to plug the screen back in — it surfaces on the
  // focused monitor, or the first one still standing.
  onSegmentsChanged: {
    if (segments.length === 0) return
    if (Model.segmentByName(segments, worldMonitor) !== null) {
      if (displaced && worldMonitor === homeMon) displaced = false
      return
    }
    // Where it lives beats where the focus is, whichever path gets here
    // first — screens and focus arrive in no fixed order.
    var back = Model.homeMonitor({ monitor: homeMon }, segments)
    if (worldMonitor === "" && back !== "") {
      worldMonitor = back
      spawnLocalX = homeOn(back)
      placementGuessed = false
      return
    }
    if (displaced && back !== "") {
      diveTimer.stop()
      undergroundTimer.stop()
      pendingTravel = null
      submerged = false
      displaced = false
      worldMonitor = back
      spawnLocalX = homeOn(back)
      return
    }
    diveTimer.stop()
    undergroundTimer.stop()
    pendingTravel = null
    submerged = false
    // The screen it lives on may come back; standing somewhere else in the
    // meantime is not the same as moving house. Never having stood anywhere
    // is not displacement either — that is just arriving.
    var hadGround = worldMonitor !== ""
    if (hadGround) displaced = true
    worldMonitor = Model.segmentByName(segments, focusedMonName) !== null
      ? focusedMonName : segments[0].name
    // Placed for want of an answer: correct it when the answer arrives.
    if (!hadGround) placementGuessed = true
  }

  property string worldMonitor: ""
  // Whether the screen it stands on was picked for it rather than remembered.
  property bool placementGuessed: false
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
      root.homeMon = root.worldMonitor
      root.writeHome()
    }
  }
  property real lastLocalX: -1
  property real spawnLocalX: -1
  property bool submerged: false
  property var pendingTravel: null
  property var activeChief: null

  // A performance is worth publishing: anything watching the status file
  // can see what the creature is up to, and so can a test.
  Connections {
    target: root.activeChief
    function onActivityChanged() { statusWrite.restart() }
    function onGlanceChanged() { statusWrite.restart() }
    function onTurned() { statusWrite.restart() }
  }

  function travelTo(mon, frac) {
    var target = String(mon || "")
    var seg = Model.segmentByName(segments, target)
    if (seg === null) return "unknown monitor: " + target
    // Told to live on one screen, it does not leave, whoever asks.
    if (cfgScreen !== "" && target !== cfgScreen) return "kept to " + cfgScreen
    if (target === worldMonitor || pendingTravel !== null) return "already there"
    // Unless a spot was asked for, the creature surfaces where it lives on
    // that screen rather than in the middle of it.
    if (frac === undefined || frac === null) frac = homeOn(target) / Math.max(1, seg.w)
    var plan = Model.travelPlan(segments, worldMonitor, lastLocalX, target, frac)
    if (!plan) return "no route"
    pendingTravel = { mon: target, local: plan.targetLocal, underground: plan.undergroundMs }
    root.promptOpen = false
    submerged = true
    diveTimer.restart()
    return "traveling to " + target
  }

  // Dive fully out of sight, then move house while nobody watches, wait
  // out the distance, and surface.
  Timer {
    id: diveTimer
    interval: 340
    onTriggered: {
      if (!root.pendingTravel) return
      root.spawnLocalX = root.pendingTravel.local
      root.worldMonitor = root.pendingTravel.mon
      root.placementGuessed = false
      root.homeMon = root.pendingTravel.mon
      root.writeHome()
      undergroundTimer.interval = root.pendingTravel.underground
      undergroundTimer.restart()
    }
  }
  Timer {
    id: undergroundTimer
    onTriggered: { root.submerged = false; root.pendingTravel = null }
  }

  readonly property string focusedMonName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  Timer {
    id: followTimer
    interval: 1500
    onTriggered: {
      if (root.cfgFollow && root.cfgScreen === "" && !root.promptOpen
          && root.focusedMonName !== "" && root.focusedMonName !== root.worldMonitor
          && !(root.cfgHideFullscreen && root.fullscreenMonitors.indexOf(root.focusedMonName) !== -1))
        root.travelTo(root.focusedMonName)
    }
  }
  onFocusedMonNameChanged: {
    if (root.worldMonitor !== "") {
      if (root.cfgFollow && root.cfgScreen === "") followTimer.restart()
      return
    }
    // Where it was left beats where the focus happens to be: a still pet
    // cannot walk back, and a walking one would rather not be made to.
    var remembered = Model.homeMonitor({ monitor: root.homeMon }, root.segments)
    root.worldMonitor = remembered !== "" ? remembered : root.focusedMonName
    root.placementGuessed = remembered === ""
  }
  onCfgScreenChanged: if (cfgScreen !== "") { worldMonitor = cfgScreen; pendingTravel = null; submerged = false }

  // Console + fullscreen state, refreshed only on Hyprland events. Two
  // small read-only queries chained: monitors for the open special
  // workspace and the chief monitor's active workspace, workspaces for its
  // fullscreen flag.

  property bool consoleOpen: false
  // How many windows the console workspace holds. Zero means a right-click
  // would drop an empty drawer, which is exactly what happened when the only
  // guard was "is there an agent window anywhere" — a terminal on another
  // screen counted, and the console stayed dark.
  property int consoleWindows: 0
  property int petActiveWsId: -1
  property bool fullscreenOnPetMonitor: false
  // Which monitors currently show something fullscreen, and which workspace
  // each one is on — enough to step aside instead of vanishing.
  property var monitorWorkspace: ({})
  property var fullscreenMonitors: []

  function refreshState() { if (!monProc.running) monProc.running = true }

  Process {
    id: monProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyMonitors(text) }
  }
  Process {
    id: wsProc
    command: ["hyprctl", "-j", "workspaces"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyWorkspaces(text) }
  }

  function applyMonitors(out) {
    try {
      var ms = JSON.parse(out)
      var open = false
      var wsId = -1
      var byMonitor = ({})
      for (var i = 0; i < ms.length; i++) {
        var m = ms[i]
        if (m.specialWorkspace && String(m.specialWorkspace.name).indexOf("special:" + root.wantedConsoleWs) === 0) open = true
        if (m.activeWorkspace) byMonitor[String(m.name)] = Number(m.activeWorkspace.id)
        if (String(m.name) === root.worldMonitor && m.activeWorkspace) wsId = Number(m.activeWorkspace.id)
      }
      root.consoleOpen = open
      root.petActiveWsId = wsId
      root.monitorWorkspace = byMonitor
      if (!wsProc.running) wsProc.running = true
    } catch (e) {
      console.warn("omarchief: monitors query failed:", e)
    }
  }

  function applyWorkspaces(out) {
    try {
      var ws = JSON.parse(out)
      var fullIds = ({})
      var inConsole = 0
      for (var i = 0; i < ws.length; i++) {
        if (ws[i].hasfullscreen) fullIds[Number(ws[i].id)] = true
        if (String(ws[i].name) === "special:" + root.wantedConsoleWs) inConsole = Number(ws[i].windows) || 0
      }
      root.consoleWindows = inConsole
      var busy = []
      for (var name in root.monitorWorkspace)
        if (fullIds[root.monitorWorkspace[name]]) busy.push(name)
      root.fullscreenMonitors = busy
      root.fullscreenOnPetMonitor = busy.indexOf(root.worldMonitor) !== -1
      if (root.cfgHideFullscreen && root.fullscreenOnPetMonitor) dodgeTimer.restart()
    } catch (e) {
      // keep last known state
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = String(event && event.name ? event.name : "")
      // A config reload can change the gaps the creature stands in.
      if (n === "configreloaded") gapsProc.running = true
      if (n.indexOf("activespecial") === 0 || n === "fullscreen"
          || n.indexOf("workspace") === 0 || n.indexOf("focusedmon") === 0
          || n === "openwindow" || n === "closewindow" || n === "monitorlayoutchanged")
        refreshTimer.restart()
    }
  }
  Timer { id: refreshTimer; interval: 150; onTriggered: root.refreshState() }

  // A fullscreen window is somebody working or playing, and the chief gets
  // out of the way — but stepping onto a free screen beats disappearing, so
  // it only hides when every screen is busy.
  Timer {
    id: dodgeTimer
    interval: 900
    onTriggered: {
      if (!root.cfgHideFullscreen || !root.fullscreenOnPetMonitor) return
      if (root.cfgScreen !== "" || root.pendingTravel !== null) return
      for (var i = 0; i < root.segments.length; i++) {
        var name = root.segments[i].name
        if (root.fullscreenMonitors.indexOf(name) === -1) { root.travelTo(name); return }
      }
    }
  }
  Component.onCompleted: {
    refreshState()
    statusWrite.restart()
  }

  // ------------------------------------------------------------ mood

  readonly property string mood: talkBusy ? "working" : Model.resolveMood({
    energy: energy,
    agentWindows: agentWindows,
    consoleOpen: consoleOpen,
    hookState: hookRecord && hookRecord.state ? String(hookRecord.state) : "",
    hookAgeSec: hookRecord && hookRecord.updatedAtEpoch ? nowEpoch - Number(hookRecord.updatedAtEpoch) : -1,
    hookAgent: hookRecord && hookRecord.agent ? String(hookRecord.agent) : "",
    defaultAgent: agentId
  })
  onMoodChanged: statusWrite.restart()
  onEnergyChanged: statusWrite.restart()
  onConsoleOpenChanged: {
    if (consoleOpen && activeChief) activeChief.cheer()
    statusWrite.restart()
  }

  // ------------------------------------------------------------ pet body
  //
  // cfg.pet may be an absolute path, ~/path, or a bare pet id looked up in
  // ~/.config/omarchief/pets/<id> and then ~/.config/omapets/pets/<id> —
  // the OmaPets install location, so a pet installed once serves both.

  readonly property var petDirCandidates: {
    var p = cfgPet
    if (p === "") return []
    if (p.indexOf("~/") === 0) p = home + p.slice(1)
    if (p.indexOf("/") === 0) return [p]
    return [home + "/.config/omarchief/pets/" + p, home + "/.config/omapets/pets/" + p]
  }
  property int petDirIndex: 0
  onPetDirCandidatesChanged: {
    petDirIndex = 0; spriteOk = false; spriteSource = ""; spriteBaseSource = ""; spriteRows = 9
    petTint = 0; spriteSleepRow = -1; spriteWalkFrames = 0; spriteThemeable = null; themedRevision = 0; spriteStillRows = []; spritePreferredSize = 0; spritePixelArt = false; spriteColumns = 8; spriteFaces = null; spriteIdleFaces = null; spriteBlink = null; spriteDisplay = null; spriteContent = null; spriteMirror = false
  }

  property bool spriteOk: false
  property url spriteSource: ""
  property int spriteRows: 9
  // Two ways to wear a theme, one intent. A pet that names its own hue
  // window is redrawn properly, keeping its shading and its details; the
  // live tint is what is left when that is impossible — no ImageMagick, or
  // a pet that never said which of its colours are skin.
  property real petTint: 0
  readonly property real spriteTint: cfgTheme ? Model.tintFor(spriteThemeable, canRedraw, petTint) : 0
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
  property var spriteDisplay: null
  property var spriteContent: null
  // The screen glows in whatever the creature is wearing, so a timer on a
  // themed pet is the theme's own light rather than a green sticker.
  // A display glows; the accent as-is is a mid tone and reads as ink on
  // paper rather than light behind glass.
  readonly property color screenInk: cfgTheme && spriteThemeable !== null
    ? Qt.lighter(Color.accent, 1.15) : "#d8ff72"
  readonly property bool stillPet: spriteFaces !== null
  property int spritePreferredSize: 0
  property bool spritePixelArt: false
  property string spritePetId: ""
  property url spriteBaseSource: ""

  FileView {
    path: root.petDirIndex < root.petDirCandidates.length
      ? root.petDirCandidates[root.petDirIndex] + "/pet.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var pet = JSON.parse(String(text() || ""))
        var sheet = String(pet.spritesheetPath || "spritesheet.webp")
        var dir = root.petDirCandidates[root.petDirIndex]
        // A pet may simply say how many rows it has; the standard version
        // number only ever meant nine or eleven.
        root.spriteRows = isFinite(Number(pet.rows)) && Number(pet.rows) > 0
          ? Math.floor(Number(pet.rows)) : Model.atlasRowCount(pet.spriteVersionNumber)
        // omarchief.json wins over the pet's own preference, so a user can
        // dress or undress any pet without editing artwork they downloaded.
        root.petTint = Model.tintStrength(root.cfg.themeTint !== undefined ? root.cfg.themeTint : pet.themeTint, 0)
        root.spriteSleepRow = isFinite(Number(pet.sleepRow)) && pet.sleepRow !== undefined ? Number(pet.sleepRow) : -1
        root.spriteWalkFrames = isFinite(Number(pet.walkFrames)) ? Number(pet.walkFrames) : 0
        root.spriteActivities = Model.readActivities(pet.activities, root.spriteRows)
        root.spriteStillRows = Model.readStillRows(pet.stillRows, root.spriteRows)
        root.spriteColumns = Model.spriteColumns(pet.columns)
        root.spriteFaces = Model.readFaces(pet.faces, root.spriteRows, root.spriteColumns)
        root.spriteMirror = pet.mirror === true
        root.spriteIdleFaces = Array.isArray(pet.idleFaces) ? pet.idleFaces : null
        root.spriteBlink = Array.isArray(pet.blink) && pet.blink.length >= 2 ? pet.blink : null
        root.spriteDisplay = pet.display && typeof pet.display === "object" ? pet.display : null
        root.spriteContent = pet.content && typeof pet.content === "object" ? pet.content : null
        root.spritePreferredSize = isFinite(Number(pet.size)) ? Number(pet.size) : 0
        root.spritePixelArt = pet.pixelArt === true
        root.spritePetId = String(pet.id || "pet")
        root.spriteThemeable = pet.themeable === true ? ({}) : (Model.isThemeableSpec(pet.themeable) ? pet.themeable : null)
        root.spriteBaseSource = "file://" + (sheet.indexOf("/") === 0 ? sheet : dir + "/" + sheet)
        root.spriteOk = true
        themeStamp.reload()
      } catch (e) {
        console.warn("omarchief: ignoring bad pet.json:", e)
        root.spriteOk = false
      }
    }
    onLoadFailed: {
      if (root.petDirIndex < root.petDirCandidates.length - 1) root.petDirIndex++
      else root.spriteOk = false
    }
  }

  // ------------------------------------------------------------ theme dressing
  //
  // A themeable pet is redrawn in the theme's accent whenever the theme
  // changes: the shipped tool replaces the hue of the pet's declared skin
  // window and leaves everything else — cables, servos, the artist's
  // shading — exactly as drawn. The result is cached with the rest of our
  // state, and a stamp file records which accent it was made for, so a
  // shell restart does not redo work that is already done.

  readonly property string themedDir: stateHome + "/omarchy/omarchief/themed"
  // One themed sheet per accent, named for it. Redrawing takes a second;
  // switching between themes the creature has already worn should not. The
  // sheet for the old accent stays on disk, so switching back is a stat and
  // a stamp write, nothing more.
  readonly property string themedSheet: themedDir + "/" + spritePetId + "-"
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
  onSpriteBaseSourceChanged: { root.syncSpriteSource(); redressTimer.restart() }
  onThemedUsableChanged: root.syncSpriteSource()
  onThemedRevisionChanged: root.syncSpriteSource()
  // Between a theme changing and its sheet being ready there is about a
  // second, and the creature used to spend it wearing the colours it was
  // drawn in — undressed, in front of everybody. It keeps the last sheet it
  // had instead, and changes straight from that to the new one.
  property bool redressing: false
  property url wornBefore: ""
  property string repaintPetId: ""
  Timer {
    id: redressGiveUp
    interval: 8000
    onTriggered: { root.redressing = false; root.wornBefore = ""; root.syncSpriteSource() }
  }

  function syncSpriteSource() {
    var was = spriteSource
    var next = themedUsable ? "file://" + themedSheet + "?v=" + themedRevision
      : (redressing && String(wornBefore) !== "" ? wornBefore : spriteBaseSource)
    spriteSource = next
    if (themedUsable && redressing) {
      redressing = false
      redressGiveUp.stop()
      // A new theme is the same creature in another colour, so the change
      // is worth watching: the new paint rises up it. A new *pet* is a
      // different creature, where rising paint would be two drawings
      // sliding past each other, so that one simply appears.
      if (String(wornBefore) !== "" && wornBefore !== next
          && spritePetId === repaintPetId && activeChief && activeChief.repaint)
        activeChief.repaint(wornBefore)
      wornBefore = ""
    }
    repaintPetId = spritePetId
  }

  // Redrawing a sheet needs ImageMagick; a system without it still gets a
  // themed creature, just the live kind.
  property bool canRedraw: true
  Process {
    id: magickProbe
    running: true
    command: ["bash", "-c", "command -v magick"]
    onExited: function(code) { root.canRedraw = code === 0 }
  }

  Process { id: recolorProc }

  // A themed sheet that will not load is a cache miss, not a broken pet:
  // forget the stamp, wear the artwork as drawn, and redraw it.
  function themedSheetMissing() {
    // A themed sheet that will not load is a cache miss: forget the stamp,
    // wear the artwork as drawn, and redraw it.
    if (spriteThemeable !== null && themedAccent !== "") {
      themedAccent = ""
      syncSpriteSource()
      // The sheet itself goes too: a file that exists but will not load
      // would satisfy the worn-before fast path forever.
      Quickshell.execDetached(["bash", "-c", "rm -f " + shq(themedSheet + ".stamp")
        + " " + shq(themedSheet)])
      redressTimer.restart()
      return
    }
    // The artwork itself will not load. Rather than leave nothing standing
    // there, hand the stage back to the creature we can always draw.
    console.warn("omarchief: cannot load", root.spriteSource, "— falling back to the drawn body")
    root.spriteOk = false
    root.spriteSource = ""
    root.spriteBaseSource = ""
  }

  function redressPet() {
    if (!cfgTheme || !canRedraw || spriteThemeable === null || String(spriteBaseSource) === "" || pluginDir === "") return
    if (recolorProc.running) { redressTimer.restart(); return }
    var spec = spriteThemeable || {}
    var source = String(spriteBaseSource).replace(/^file:\/\//, "").replace(/\?.*$/, "")
    // One stamp per sheet, beside it: what it was drawn for and which
    // artwork it came from. A theme worn before is then a single comparison,
    // with nothing to sweep and no way to delete the sheet just written.
    var stampFile = themedSheet + ".stamp"
    // The stamp names the accent and the artwork's size and age, so a new
    // sheet from an update is redrawn too — not only a new theme. An
    // unchanged stamp costs one stat and no redraw.
    var cmd = "stamp=" + shq(accentHex + " " + backgroundHex) + "\" \"$(stat -c %s.%Y " + shq(source) + " 2>/dev/null)"
      + "; [ \"$(cat " + shq(stampFile) + " 2>/dev/null)\" = \"$stamp\" ] && [ -f " + shq(themedSheet) + " ] && exit 0"
      + "; mkdir -p " + shq(themedDir)
      // Sheets for themes not worn in a month, and the scraps of a redraw
      // that was killed mid-write, are not worth the disk.
      + "; find " + shq(themedDir) + " -maxdepth 1 -name " + shq(spritePetId + "-*")
      + " -mtime +30 -delete 2>/dev/null"
      + "; find " + shq(themedDir) + " -maxdepth 1 -name " + shq(spritePetId + "-*.webp.??????")
      + " -mmin +5 -delete 2>/dev/null"
      + "; " + shq(pluginDir + "/tools/omarchief-recolor")
      + " " + shq(source) + " " + shq(themedSheet) + " " + shq(accentHex)
      + " " + shq(String(spec.hueMin !== undefined ? spec.hueMin : 40))
      + " " + shq(String(spec.hueMax !== undefined ? spec.hueMax : 100))
      + " " + shq(String(spec.satMin !== undefined ? spec.satMin : 15))
      + " " + shq(backgroundHex)
      + " && printf %s \"$stamp\" > " + shq(stampFile)
    recolorProc.command = ["bash", "-lc", cmd]
    recolorProc.running = true
  }

  // Every theme on this machine, dressed in advance and quietly, so that
  // changing theme is instant rather than a second of the creature catching
  // up with a desktop that has already changed. Omarchy hands its own
  // palette to the shell and animates the wallpaper across four tenths of a
  // second; a creature that arrives after that is a creature that arrives
  // late. One sheet per theme is a couple of hundred kilobytes, drawn once,
  // at the back of the queue and only while nothing is being asked of it.
  Timer {
    id: wardrobe
    interval: 20000
    running: root.canRedraw && root.cfgTheme && root.spriteThemeable !== null
             && root.spriteBaseSource !== "" && root.pluginDir !== ""
    onTriggered: root.fillWardrobe()
  }
  function fillWardrobe() {
    if (recolorProc.running || talkBusy || spritePetId === "") return
    var spec = spriteThemeable || {}
    var source = String(spriteBaseSource).replace(/^file:\/\//, "").replace(/\?.*$/, "")
    // Reads every theme's colours, skips the ones already drawn, and draws
    // the rest one at a time at the lowest priority the machine offers.
    wardrobeProc.command = ["bash", "-lc",
      "nice -n 19 bash -s -- " + shq(source) + " " + shq(themedDir) + " " + shq(spritePetId)
      + " " + shq(pluginDir + "/tools/omarchief-recolor")
      + " " + shq(String(spec.hueMin !== undefined ? spec.hueMin : 40))
      + " " + shq(String(spec.hueMax !== undefined ? spec.hueMax : 100))
      + " " + shq(String(spec.satMin !== undefined ? spec.satMin : 15))
      + " <<'WARDROBE'\n"
      + "src=$1; dir=$2; pet=$3; tool=$4; hmin=$5; hmax=$6; smin=$7\n"
      + "stamp=\"$(stat -c %s.%Y \"$src\" 2>/dev/null)\"\n"
      + "mkdir -p \"$dir\"\n"
      + "for t in \"$HOME/.local/share/omarchy/themes\"/*/ \"$HOME/.config/omarchy/themes\"/*/; do\n"
      + "  [ -f \"$t/colors.toml\" ] || continue\n"
      + "  acc=$(sed -nE 's/^accent[[:space:]]*=[[:space:]]*\"(#[0-9a-fA-F]{6})\".*/\\1/p' \"$t/colors.toml\" | head -1)\n"
      + "  bg=$(sed -nE 's/^background[[:space:]]*=[[:space:]]*\"(#[0-9a-fA-F]{6})\".*/\\1/p' \"$t/colors.toml\" | head -1)\n"
      + "  [ -n \"$acc\" ] && [ -n \"$bg\" ] || continue\n"
      + "  name=\"$dir/$pet-$(echo \"$acc\" | tr -d '#' | tr 'A-Z' 'a-z')-$(echo \"$bg\" | tr -d '#' | tr 'A-Z' 'a-z').webp\"\n"
      + "  [ \"$(cat \"$name.stamp\" 2>/dev/null)\" = \"$acc $bg $stamp\" ] && [ -f \"$name\" ] && continue\n"
      + "  \"$tool\" \"$src\" \"$name\" \"$acc\" \"$hmin\" \"$hmax\" \"$smin\" \"$bg\" 2>/dev/null \\\n"
      + "    && printf '%s' \"$acc $bg $stamp\" > \"$name.stamp\"\n"
      + "done\n"
      + "WARDROBE"]
    wardrobeProc.running = true
  }
  Process { id: wardrobeProc }

  // Theme switches land as a colour change on the shared singleton; a short
  // debounce keeps a palette that arrives channel by channel to one run.
  // Small, because a theme the creature has worn before goes on instantly.
  onAccentHexChanged: {
    if (cfgTheme && spriteThemeable !== null && spriteOk && String(spriteSource) !== "") {
      wornBefore = spriteSource
      redressing = true
      redressGiveUp.restart()
    }
    redressTimer.restart()
  }
  onBackgroundHexChanged: redressTimer.restart()
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
  property string sessionId: ""
  // The conversation outlives the shell. Without this, every reload — and
  // there are a lot of those — quietly started a new one, so "carry on from
  // before" only worked until something restarted.
  property var sessions: ({})
  property bool sessionsLoaded: false
  readonly property string sessionFile: statusDir + "/sessions.json"
  FileView {
    path: root.sessionFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.sessions = Model.readSessions(JSON.parse(String(text() || ""))) }
      catch (e) { root.sessions = ({}) }
      root.sessionsLoaded = true
      if (root.sessionId === "" && root.agentId !== "" && root.sessions[root.agentId])
        root.sessionId = root.sessions[root.agentId]
    }
    onLoadFailed: { root.sessions = ({}); root.sessionsLoaded = true }
  }
  function rememberSession() {
    if (!sessionsLoaded || agentId === "") return
    var next = ({})
    for (var a in sessions) next[a] = sessions[a]
    if (sessionId === "") delete next[agentId]
    else next[agentId] = sessionId
    root.sessions = next
    Quickshell.execDetached(["bash", "-c",
      "mkdir -p " + shq(statusDir) + " && printf %s " + shq(JSON.stringify(next))
      + " > " + shq(sessionFile)])
  }

  property string talkBuffer: ""
  property string sayMode: ""
  property string sayText: ""
  property string talkErr: ""
  // What the agent is doing right now, in its own words where it has them.
  property string doing: ""
  property bool talkSawOutput: false
  property bool talkRetried: false
  property real talkStartedAt: 0
  property string lastAnswer: ""
  readonly property string notesPath: statusDir + "/notes.md"

  // An answer stays up for as long as it takes to read and a little more,
  // and waits while the pointer rests on the chief. Errors stay until
  // clicked away: those are worth acting on.
  onSayModeChanged: root.scheduleBubble()
  onSayTextChanged: root.scheduleBubble()
  function scheduleBubble() {
    sayHold.stop()
    if (root.sayMode !== "say") return
    sayHold.interval = Model.readingTimeMs(root.sayText)
    sayHold.start()
  }
  Timer {
    id: sayHold
    onTriggered: {
      if (root.activeChief && root.activeChief.hitbox.containsMouse) { sayHold.interval = 3000; sayHold.start(); return }
      if (root.sayMode === "say") root.dismissBubble()
    }
  }
  function answered(text) {
    // It stays where you put it and speaks from there: being out of the way
    // is not the same as being off duty.
    root.sayMode = "say"
    root.sayText = Model.shapeBubbleText(text, root.cfgSpeakMax)
    root.lastAnswer = root.sayText
    statusWrite.restart()
  }
  Timer {
    id: talkRetry
    interval: 700
    onTriggered: { root.talkStartedAt = Date.now(); talkPatience.restart(); talkProc.running = true }
  }

  function shq(s) { return Model.shellQuote(s) }

  function runOrder(text) {
    var t = String(text).trim()
    root.promptOpen = false
    if (t === "") { root.summonConsole(); return "console" }
    var argv = root.cfgTalk ? Model.buildTalkCommand(root.agentId, t, root.sessionId, root.fullPreamble) : null
    if (!argv) { root.orderToConsole(t); return "console" }
    if (talkProc.running) talkProc.running = false
    root.talkBuffer = ""
    root.talkErr = ""
    root.doing = ""
    root.talkSawOutput = false
    root.talkRetried = false
    root.talkStartedAt = Date.now()
    root.sayMode = "think"
    root.sayText = ""
    root.talkBusy = true
    talkPatience.restart()
    talkGiveUp.restart()
    // bash -lc so the login profile finds the agent (mise & friends); its
    // stdout noise is non-JSON and parses to null.
    var quoted = []
    for (var i = 0; i < argv.length; i++) quoted.push(shq(argv[i]))
    // Run the agent in a session of its own and take that whole session down
    // when the turn ends. Some runners leave a session process behind — one
    // order at a time was quietly accumulating them — and killing only the
    // process we spawned would leave those orphans running.
    talkProc.command = ["bash", "-lc",
      "cd " + shq(root.talkCwd()) + " && setsid " + quoted.join(" ") + " & agent=$!; "
      + "trap 'kill -TERM -- -$agent 2>/dev/null' TERM EXIT; wait $agent"]
    talkProc.running = true
    return "ordered"
  }

  // Same convention as omarchy-agent: sessions started from the desktop
  // live in ~/Work when it exists, so trust prompts stay answered.
  property bool hasWorkDir: false
  // Where an order runs. ~/Work when it exists, as omarchy-agent does, so
  // trust prompts stay answered — unless you name somewhere else.
  readonly property string cfgWorkdir: cfg.workdir !== undefined ? String(cfg.workdir) : ""
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
        var r = Model.parseTalkLine(root.agentId, line)
        if (!r) return
        root.talkSawOutput = true
        if (r.kind === "doing") {
          quietEnd.stop()
          if (root.agentSilent) { root.agentSilent = false; statusWrite.restart() }
          root.doing = r.text
          statusWrite.restart()
          return
        }
        if (r.kind === "text") {
          quietEnd.stop()
          if (root.agentSilent) { root.agentSilent = false; statusWrite.restart() }
          // Agents think out loud between tools. Those are progress, not the
          // answer: the bubble shows the latest one as a single line while the
          // work goes on, and the whole of it only if nothing better closes
          // the turn.
          root.talkBuffer = root.talkBuffer === "" ? r.text : root.talkBuffer + " " + r.text
          root.doing = Model.shapeBubbleText(r.text, 110)
          if (root.sayMode !== "think") { root.sayMode = "think"; root.sayText = "" }
          statusWrite.restart()
        } else if (r.kind === "session") {
          if (r.sessionId !== "") root.sessionId = r.sessionId
        } else if (r.kind === "maybe_end") {
          // A step ended. If nothing follows it, the turn is over — the
          // runner itself will happily stay alive for minutes.
          if (r.sessionId !== "") root.sessionId = r.sessionId
          quietEnd.restart()
        } else if (r.kind === "result") {
          if (r.sessionId !== "") root.sessionId = r.sessionId
          sessionIdle.restart()
          // Some runners linger after the turn ends (opencode keeps its
          // session process alive); the turn is over, so reap shortly.
          talkReap.restart()
          if (r.ok) {
            var finalText = r.text !== "" ? r.text : root.talkBuffer
            root.answered(finalText === "" ? "Done." : finalText)
          } else {
            root.sayMode = "error"
            root.sayText = Model.shapeBubbleText(r.text !== "" ? r.text
              : root.talkBuffer !== "" ? root.talkBuffer
              : "That went sideways — right-click me and I'll open the console.", root.cfgSpeakMax)
          }
        }
      }
    }
    // A runner that exits at once without a word has stumbled, not refused.
    onExited: function(code) {
      if (Model.shouldRetryTalk(Date.now() - root.talkStartedAt, root.talkSawOutput, root.talkRetried)) {
        root.talkRetried = true
        talkRetry.restart()
        return
      }
      quietEnd.stop()
      talkPatience.stop()
      talkGiveUp.stop()
      root.talkBusy = false
      root.doing = ""
      if (root.sayMode === "think") {
        root.sayMode = "error"
        root.sayText = (root.agentId === "" ? "No default agent yet" : root.agentId + " ended without a word")
          + (root.talkErr !== "" ? " (" + root.talkErr + ")" : "")
          + " — right-click me for the console."
      } else if (root.talkBuffer !== "") {
        // It said something and then stopped: keep the words, drop the wait.
        root.answered(root.talkBuffer)
      }
    }
    // The last line on stderr is usually the reason a runner gave up: not
    // logged in, a rate limit, a model that does not exist. The login
    // profile's own chatter is skipped.
    stderr: SplitParser {
      onRead: function(line) {
        var l = String(line).trim()
        if (l !== "" && l.indexOf("mise ") !== 0) root.talkErr = l.slice(0, 160)
      }
    }
  }

  // A conversation that has gone quiet for half an hour is over; the next
  // order starts fresh instead of dragging an old context along.
  Timer {
    id: sessionIdle
    interval: Math.max(1000, Model.sessionLifeMs(root.cfgSessionIdleMin))
    repeat: false
    onTriggered: if (Model.sessionLifeMs(root.cfgSessionIdleMin) > 0) root.sessionId = ""
  }
  Timer { id: talkReap; interval: 1500; onTriggered: if (talkProc.running) talkProc.running = false }

  // Some runners go quiet for a long time before their first word — an
  // order that means real work, or simply an agent that buffers until it
  // is done. Saying so beats a bubble of dots forever, and the work keeps
  // running: if the answer arrives later, it replaces this.
  // An agent that has said nothing at all for a long time is not thinking,
  // it is stuck — and a runner left behind keeps a session open for as long
  // as it lives. Give up out loud, and let go of the process.
  Timer {
    id: talkGiveUp
    interval: root.cfgPatience * 4 * 1000
    onTriggered: {
      if (!root.talkBusy) return
      if (root.talkBuffer === "") {
        root.sayMode = "error"
        root.sayText = (root.agentId || "the agent") + " is not responding — right-click me for the console."
      } else {
        root.sayMode = "say"
        root.sayText = Model.shapeBubbleText(root.talkBuffer, root.cfgSpeakMax)
      }
      if (talkProc.running) talkProc.running = false
    }
  }

  // An agent that took the full patience window without a word, or ended a
  // turn without saying anything, is one worth mentioning: it is nearly
  // always the agent, not the desktop.
  property bool agentSilent: false

  Timer {
    id: talkPatience
    interval: root.cfgPatience * 1000
    onTriggered: {
      if (!root.talkBusy || root.sayMode !== "think") return
      root.agentSilent = true
      statusWrite.restart()
      root.sayMode = "say"
      root.sayText = "Still working on it — right-click me to watch in the console."
    }
  }

  // Silence after a finished step ends the turn: show what was said and
  // stop the runner, which has no intention of stopping by itself.
  Timer {
    id: quietEnd
    interval: 3000
    onTriggered: {
      if (!root.talkBusy) return
      root.answered(root.talkBuffer === "" ? "Done." : root.talkBuffer)
      sessionIdle.restart()
      if (talkProc.running) talkProc.running = false
    }
  }

  function dismissBubble() { root.sayMode = ""; root.sayText = "" }

  // The whole onboarding: the very first time the chief ever stands on
  // this machine, it says what it is for. A marker file remembers that the
  // introduction happened; everything after that stays quiet.
  property bool welcomed: true
  FileView {
    path: root.stateHome + "/omarchy/omarchief/welcomed"
    printErrors: false
    onLoaded: root.welcomed = true
    onLoadFailed: { root.welcomed = false; welcomeTimer.restart() }
  }
  Timer {
    id: welcomeTimer
    interval: 2500
    onTriggered: {
      if (root.welcomed || root.talkBusy || root.sayMode !== "") return
      root.sayMode = "say"
      root.sayText = "Click me and tell your desktop what to do."
      root.welcomed = true
      Quickshell.execDetached(["bash", "-c",
        "mkdir -p \"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/omarchief\" && touch \"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/omarchief/welcomed\""])
    }
  }

  // ------------------------------------------------------------ the console
  //
  // Escalation, not the default. The console drops on the chief's monitor —
  // wherever it traveled, that's where the work lands. With a living
  // session, the console resumes the very conversation the bubble held.

  property bool hasQconsole: false
  // The workspace Omarchy's own console uses, read from the file that
  // defines it. Sharing the workspace is the whole point: the chief's
  // console and the one on SUPER+grave should be the same drawer, holding
  // the same conversation, not two consoles fighting over one screen.
  property string consoleWs: "scratchpad"
  readonly property string wantedConsoleWs:
    cfg.consoleWorkspace !== undefined && String(cfg.consoleWorkspace) !== ""
      ? String(cfg.consoleWorkspace) : consoleWs
  FileView {
    path: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/default/hypr/qconsole.lua"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.hasQconsole = true
      root.consoleWs = Model.consoleWorkspace(String(text() || ""), "scratchpad")
    }
    onLoadFailed: { root.hasQconsole = false; root.consoleWs = "scratchpad" }
  }

  // Hyprland's dispatcher speaks Lua: a dispatch is an expression, not a
  // command line, and a bare word is a nil global rather than an action.
  function dispatch(expression) {
    Quickshell.execDetached(["hyprctl", "dispatch", expression])
  }

  // The chief's own screen, in virtual desktop pixels, for placing a window
  // where the creature is standing.
  readonly property var worldSegment: Model.segmentByName(segments, worldMonitor)
  readonly property int worldScreenHeight: {
    var scr = Quickshell.screens
    for (var i = 0; i < scr.length; i++)
      if (scr[i].name === worldMonitor) return scr[i].height
    return 0
  }

  function consoleRule() {
    if (cfgConsoleAt !== "chief") return "workspace special:" + wantedConsoleWs + " silent"
    var place = Model.consolePlacement(worldSegment, lastLocalX, worldScreenHeight,
      { width: Math.round(worldSegment ? Math.min(1100, worldSegment.w * 0.45) : 1000), height: 560 }, 24)
    return Model.placementRule(place) + "workspace " + (petActiveWsId > 0 ? petActiveWsId : 1) + " silent"
  }

  function summonConsole() {
    if (root.worldMonitor !== "") dispatch(Model.dispatchFocusMonitor(root.worldMonitor))
    if (!root.consoleOpen) {
      var resume = Model.buildConsoleResume(root.agentId, root.sessionId)
      if (resume) {
        var quoted = []
        for (var i = 0; i < resume.length; i++) quoted.push(root.shq(resume[i]))
        dispatch(Model.dispatchExec("[" + consoleRule() + "] omarchy-launch-tui --app-id=org.omarchy.agent "
          + quoted.join(" ")))
        root.sessionId = ""
        root.dismissBubble()
      } else if (root.consoleWindows === 0) {
        // Nothing to resume and nothing in the drawer: put the default agent
        // there, the way Omarchy's own console seeds itself — or the picker,
        // when no default has been chosen yet.
        dispatch(Model.dispatchExec("[" + consoleRule() + "] omarchy-agent"
          + (root.defaultAgentId === "" ? " --pick" : "")))
      }
    }
    if (cfgConsoleAt !== "chief") dispatch(Model.dispatchToggleSpecial(wantedConsoleWs))
  }

  // v1 fallback for agents without a headless adapter: the order goes into
  // a console session directly.
  function orderToConsole(t) {
    var full = root.fullPreamble === "" ? t : root.fullPreamble + "\n\nOrder: " + t
    dispatch(Model.dispatchExec("[" + consoleRule() + "] omarchy-agent-prompt " + root.shq(full)))
    if (root.cfgConsoleAt !== "chief" && !root.consoleOpen) dispatch(Model.dispatchToggleSpecial(root.wantedConsoleWs))
  }

  // ------------------------------------------------------------ IPC
  //
  //   omarchy-shell omarchief ask | summon | toggle | show | hide | status
  //   omarchy-shell omarchief order "open spotify on DP-2"
  //   omarchy-shell omarchief travel DP-2

  property bool shown: true
  // Slid mostly off its edge, out of the way. A click brings it back.
  property bool tucked: false
  // Which way it was put away. Asking for it from the bar or a script sinks
  // it into the floor; shoving it against a side puts it away there.
  property string tuckSide: "down"

  // ------------------------------------------------------------ the timer
  //
  // The creature has a screen for a face, so it can hold a timer for you.
  // It outlives a reload — the shell restarts often enough that a timer
  // which did not would be a timer you could not trust.
  property double timerEndsAt: 0
  property string timerText: ""
  // What the creature's own panel is for. It is its face first — a screen
  // (the config key is `readout`, not `screen`: `screen` already names the
  // monitor it stands on, and reusing it wipes that)
  // showing the time forever is a screen never showing an expression — so
  // the timer is the default and the clock is for people who want one.
  readonly property string cfgScreenShows: {
    var want = cfg.readout !== undefined ? String(cfg.readout) : "timer"
    return want === "face" || want === "clock" ? want : "timer"
  }
  property string clockText: ""
  Timer {
    interval: 10000
    repeat: true
    // Nothing to read the clock off while the creature is away.
    running: root.cfgScreenShows === "clock" && root.shown && !root.tucked
    triggeredOnStart: true
    onTriggered: {
      var now = new Date()
      var h = now.getHours(), m = now.getMinutes()
      root.clockText = (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
    }
  }
  readonly property string screenText: timerText !== "" ? timerText
    : cfgScreenShows === "clock" ? clockText : ""
  readonly property string timerFile: statusDir + "/timer"
  FileView {
    path: root.timerFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var at = Number(String(text() || "").trim())
      root.timerEndsAt = isFinite(at) && at > Date.now() ? at : 0
      root.tickTimer()
    }
    onLoadFailed: root.timerEndsAt = 0
  }
  Timer {
    id: timerTick
    interval: 1000
    repeat: true
    running: root.timerEndsAt > 0
    onTriggered: root.tickTimer()
  }
  function tickTimer() {
    if (timerEndsAt <= 0) { if (timerText !== "") { timerText = ""; statusWrite.restart() } return }
    var left = timerEndsAt - Date.now()
    if (left <= 0) {
      timerEndsAt = 0
      timerText = ""
      writeTimer(0)
      // It has been holding this for you; it should be the one to say so.
      if (activeChief) activeChief.cheer()
      answered("Time's up.")
      // A bubble on a screen you are not looking at is a timer that did not
      // go off. The desktop's own notifier is the one that reaches you.
      Quickshell.execDetached(["bash", "-lc",
        "command -v notify-send >/dev/null && notify-send -a Omarchief -u normal"
        + " -i dialog-information " + shq("Time's up") + " " + shq("The timer you set has run out.")
        + " || true"])
      statusWrite.restart()
      return
    }
    var next = Model.timerFace(left)
    if (next !== timerText) { timerText = next; statusWrite.restart() }
  }
  function writeTimer(at) {
    Quickshell.execDetached(["bash", "-c", at > 0
      ? "mkdir -p " + shq(statusDir) + " && printf %s " + shq(String(Math.round(at))) + " > " + shq(timerFile)
      : "rm -f " + shq(timerFile)])
  }
  function startTimer(spec) {
    var seconds = Model.parseDuration(spec)
    if (seconds === null) return "not a duration: " + String(spec)
    if (seconds === 0) {
      timerEndsAt = 0; timerText = ""; writeTimer(0); statusWrite.restart()
      return "timer off"
    }
    timerEndsAt = Date.now() + seconds * 1000
    writeTimer(timerEndsAt)
    tickTimer()
    if (activeChief) activeChief.cheer()
    return Model.timerWords(seconds * 1000)
  }
  property bool promptOpen: false

  // The chief's inner state, published as a small JSON file. The bar
  // widget watches it, and so can anything else on the machine — it is the
  // read-only mirror of what `omarchy-shell omarchief status` prints.
  readonly property string statusDir: stateHome + "/omarchy/omarchief"

  function statusJson() {
    return JSON.stringify({
      mood: mood, energy: Math.round(energy * 100) / 100,
      agent: agentId, monitor: worldMonitor,
      console: consoleOpen, talking: talkBusy,
      session: sessionId === "" ? "" : sessionId.slice(0, 8),
      shown: shown, agentSilent: agentSilent, lastAnswer: lastAnswer.slice(0, 400),
      tucked: tucked,
      tuckSide: tucked ? tuckSide : "",
      timer: timerEndsAt > 0 ? Math.max(0, Math.round((timerEndsAt - Date.now()) / 1000)) : 0,
      readout: cfgScreenShows,
      consoleAt: cfgConsoleAt,
      walks: !stillPet,
      follow: cfgFollow,
      screen: cfgScreen,
      hasReadout: spriteDisplay !== null,
      home: homeMon,
      expressions: cfgExpressions,
      theme: cfgTheme,
      hooks: hooksInstalled,
      canHook: hasClaude,
      talk: cfgTalk,
      conversation: cfgSessionIdleMin,
      hideFullscreen: cfgHideFullscreen,
      workdir: talkCwd(),
      canTheme: spriteThemeable !== null,
      chance: cfgGlanceChance,
      size: petSize,
      pet: cfgPet,
      agents: installedAgents,
      agentDefault: defaultAgentId,
      agentFollowsDefault: agentIsDefault,
      pets: installedPets,
      hasFaces: spriteFaces !== null,
      // Whether it has anything to look up *with*. A pet drawn as one
      // picture has faces and no expressions, and offering a switch for
      // them is offering a switch that does nothing.
      canGlance: spriteFaces !== null && Model.glanceFaces(
        spriteFaces, spriteIdleFaces, spriteRows, spriteColumns).length > 0,
      // What it is wearing right now, if that is not simply its mood — the
      // only way to tell a daydream apart from a stuck picture from outside.
      glancing: activeChief && activeChief.glance ? JSON.stringify(activeChief.glance) : "",
      doing: doing,
      x: activeChief ? Math.round(activeChief.px) : -1,
      mirrored: activeChief ? activeChief.mirrored === true : false,
      activity: activeChief && activeChief.activity ? String(activeChief.activity.name || "") : "",
      activityPasses: activeChief ? activeChief.activityPasses : 0,
      activities: spriteActivities.length,
      updatedAtEpoch: Math.floor(Date.now() / 1000)
    })
  }

  onWorldMonitorChanged: {
    statusWrite.restart()
    if (worldMonitor !== "" && !displaced) settleHome.restart()
  }
  onShownChanged: statusWrite.restart()
  onTuckedChanged: statusWrite.restart()
  onTuckSideChanged: statusWrite.restart()
  // Anything the bar widget shows has to be republished when it changes, or
  // the switch in the popout keeps reporting the setting it had at startup.
  onCfgExpressionsChanged: statusWrite.restart()
  onCfgThemeChanged: { statusWrite.restart(); if (cfgTheme) redressTimer.restart() }
  onCfgTalkChanged: statusWrite.restart()
  onHooksInstalledChanged: statusWrite.restart()
  onHasClaudeChanged: statusWrite.restart()
  onCfgHideFullscreenChanged: statusWrite.restart()
  onCfgGlanceChanceChanged: statusWrite.restart()
  onPetSizeChanged: statusWrite.restart()
  onInstalledPetsChanged: statusWrite.restart()
  onInstalledAgentsChanged: statusWrite.restart()
  onCfgAgentChanged: statusWrite.restart()
  onCfgPetChanged: { statusWrite.restart(); scanPets() }
  onSpriteFacesChanged: statusWrite.restart()
  onHomeMonChanged: statusWrite.restart()
  onSpriteActivitiesChanged: statusWrite.restart()
  onTalkBusyChanged: statusWrite.restart()
  onSessionIdChanged: { statusWrite.restart(); rememberSession() }

  // One debounced shell write per state change: mkdir keeps the first
  // write honest and printf keeps the file whole — FileView.setText
  // declined the job silently here, so the boring way wins.
  Timer {
    id: statusWrite
    interval: 400
    onTriggered: Quickshell.execDetached(["bash", "-c",
      "mkdir -p " + root.shq(root.statusDir) + " && printf '%s\\n' " + root.shq(root.statusJson())
      + " > " + root.shq(root.statusDir + "/status.json")])
  }

  // Settings the bar widget offers are written back here rather than by the
  // widget itself: there is one panel and one config file, but a widget per
  // screen, and three of them racing to rewrite the same file is a way to
  // lose it.
  function setConfig(key, value) {
    var next = ({})
    for (var k in cfg) next[k] = cfg[k]
    next[key] = value
    // The shell's own store, when the shell has handed itself to us. It
    // writes the whole entry, so everything the file used to hold moves
    // across on the first change and the file stops being consulted for it.
    if (shell && typeof shell.updateEntryInline === "function") {
      shell.updateEntryInline(entryId, next)
      return
    }
    Quickshell.execDetached(["bash", "-c",
      "mkdir -p " + shq(home + "/.config/omarchy") + " && printf %s "
      + shq(JSON.stringify(next, null, 2) + "\n") + " > " + shq(configFile)])
  }

  // What `omarchy-shell shell summon <id> <payload>` reaches. The shell
  // calls open() on a summoned panel plugin; without one it summons nothing.
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (e) { payload = ({}) }
    root.shown = true
    if (payload.order !== undefined && String(payload.order) !== "") {
      root.runOrder(String(payload.order))
      return
    }
    if (payload.tuck !== undefined) { root.tuckSide = "down"; root.tucked = !!payload.tuck; return }
    root.promptOpen = true
  }
  function close() { root.promptOpen = false }

  IpcHandler {
    target: "omarchief"
    function ask(): void { root.shown = true; root.promptOpen = true }
    function order(text: string): string { root.shown = true; return root.runOrder(text) }
    function travel(monitor: string): string { return root.travelTo(monitor) }
    // Which screen it lives on. "any" lets it move again, by focus or by order.
    function screen(name: string): string {
      var want = String(name || "")
      if (want === "" || want === "any") { root.setConfig("screen", ""); return "free to move" }
      if (Model.segmentByName(root.segments, want) === null) return "unknown monitor: " + want
      root.setConfig("screen", want)
      return "kept to " + want
    }
    function timer(spec: string): string { return root.startTimer(spec === "" ? "25m" : spec) }
    function consoleAt(where: string): string {
      var want = where === "chief" || where === "quake" ? where
        : root.cfgConsoleAt === "chief" ? "quake" : "chief"
      root.setConfig("consoleAt", want)
      return want === "chief" ? "the console opens over it" : "the console drops from the top"
    }
    function follow(on: string): string {
      if (root.stillPet) return "this one stays where you put it"
      var want = on === "" ? !root.cfgFollow : (on === "on" || on === "true" || on === "1")
      root.setConfig("followFocus", want)
      return want ? "following your focus" : "staying put"
    }
    function readout(shows: string): string {
      var want = shows === "face" || shows === "clock" || shows === "timer" ? shows
        : root.cfgScreenShows === "clock" ? "timer" : "clock"
      root.setConfig("readout", want)
      return "its screen shows " + (want === "face" ? "nothing" : want === "clock" ? "the clock" : "a timer when one runs")
    }
    function tuck(on: string): string {
      // `tuck left` and `tuck right` put it away against that side, the way
      // shoving it there does; anything else sinks it into the floor.
      var side = on === "left" || on === "right" ? on : ""
      var want = side !== "" ? true
        : on === "" ? !root.tucked
        : (on === "on" || on === "true" || on === "1")
      // Asking for it to be put away, without saying where, always means
      // down. It used to keep whichever side it had been shoved to last,
      // so the same gesture did different things depending on history.
      if (want) root.tuckSide = side !== "" ? side : "down"
      root.tucked = want
      return root.tucked ? "tucked away" : "back"
    }
    // Put the creature somewhere along the edge it stands on. Dragging does
    // the same thing with a hand; this is for scripts, and for finding out
    // whether the hand and the script agree.
    function place(x: string): string {
      if (!root.activeChief) return "not on stage"
      var want = Number(x)
      if (!isFinite(want)) return "where?"
      root.activeChief.px = Model.dragTo(want, 0, root.activeChief.width, root.petSize)
      root.rememberHome(root.activeChief.px)
      return "standing at " + Math.round(root.activeChief.px)
    }
    // Settings the bar widget offers. Kept here because the panel owns the
    // config file; a widget exists once per screen and would race itself.
    // Wear a different pet. The bar widget offers whatever is installed.
    // Which agent the creature answers with. An empty argument goes back to
    // following whatever the desktop's default is.
    function agent(id: string): string {
      // "any" is how the menu says follow the desktop's own choice, since an
      // empty argument is one the IPC layer refuses to pass at all.
      var want = id === "any" ? "" : id
      root.setConfig("agent", want)
      return want === "" ? "following the default" : "using " + want
    }
    function pet(id: string): string {
      if (id === "") return root.cfgPet
      root.setConfig("pet", id)
      return "wearing " + id
    }
    // Whether an order is answered in the bubble — which means the agent
    // runs unattended — or always handed to the console, where you watch it.
    // Let the chief see what claude does in the console — or stop.
    function hooks(on: string): string {
      if (root.pluginDir === "") return "not ready"
      var want = on === "" ? !root.hooksInstalled : (on === "on" || on === "true" || on === "1")
      hookSet.command = [root.pluginDir + "/tools/omarchief-hooks", want ? "install" : "remove", "claude"]
      hookSet.running = true
      return want ? "watching the console agent" : "no longer watching the console agent"
    }
    function speak(on: string): string {
      var want = on === "" ? !root.cfgTalk : (on === "on" || on === "true" || on === "1")
      root.setConfig("talk", want)
      return want ? "answering in the bubble" : "always opening the console"
    }
    // How long one conversation lasts. Nothing said means it does not end
    // on its own, which is what talking to something usually means.
    function conversation(minutes: string): string {
      var m = Number(minutes)
      root.setConfig("sessionIdleMin", isFinite(m) && m >= 0 ? Math.round(m) : 0)
      return isFinite(m) && m > 0 ? "ends after " + Math.round(m) + " quiet minutes"
                                  : "one long conversation"
    }
    // End it deliberately. The next order starts with a clean slate.
    function fresh(): string {
      root.sessionId = ""
      root.dismissBubble()
      return "starting fresh"
    }
    function shy(on: string): string {
      var want = on === "" ? !root.cfgHideFullscreen : (on === "on" || on === "true" || on === "1")
      root.setConfig("hideOnFullscreen", want)
      return want ? "hiding while fullscreen" : "staying put"
    }
    function theme(on: string): string {
      var want = on === "" ? !root.cfgTheme : (on === "on" || on === "true" || on === "1")
      root.setConfig("theme", want)
      return want ? "wearing your theme" : "keeping its own colours"
    }
    // How readily a resting creature looks up. Named rather than numbered,
    // because nobody thinks in tenths; no argument steps to the next one.
    function often(how: string): string {
      var steps = [0.1, 0.25, 0.5]
      var next = -1
      for (var i = 0; i < steps.length; i++)
        if (Model.oftenName(steps[i]) === how) next = steps[i]
      if (next < 0) {
        var here = 0
        for (var j = 0; j < steps.length; j++)
          if (Math.abs(steps[j] - root.cfgGlanceChance) < Math.abs(steps[here] - root.cfgGlanceChance)) here = j
        next = steps[(here + 1) % steps.length]
      }
      root.setConfig("expressionChance", next)
      return Model.oftenName(next)
    }
    function bigger(px: string): string {
      var steps = [96, 130, 150, 190]
      var want = Number(px)
      var next = isFinite(want) && want > 0 ? Math.max(32, Math.min(240, Math.round(want))) : -1
      if (next < 0) {
        var here = 0
        for (var i = 0; i < steps.length; i++)
          if (Math.abs(steps[i] - root.petSize) < Math.abs(steps[here] - root.petSize)) here = i
        next = steps[(here + 1) % steps.length]
      }
      root.setConfig("size", next)
      return "size " + next
    }
    function expressions(on: string): string {
      var want = on === "" ? !root.cfgExpressions : (on === "on" || on === "true" || on === "1")
      root.setConfig("expressions", want)
      return want ? "expressions on" : "expressions off"
    }
    // Ask for a walk now instead of waiting for the chief to feel like one:
    // handy for a demo, and the only way to see a new gait on purpose.
    // Play an activity by name, or whatever the pet feels like. Being able
    // to ask is what makes them testable, and demonstrable.
    function play(name: string): string {
      if (!root.activeChief) return "not on stage"
      var list = root.spriteActivities
      if (list.length === 0) return "this pet has no activities"
      var pick = null
      var wanted = String(name || "").trim()
      if (wanted === "") pick = list[Math.floor(Math.random() * list.length)]
      else for (var i = 0; i < list.length; i++) if (list[i].name === wanted) pick = list[i]
      if (!pick) {
        var names = []
        for (var j = 0; j < list.length; j++) names.push(list[j].name)
        return "no such activity — try: " + names.join(", ")
      }
      return root.activeChief.playActivity(pick) ? "playing " + pick.name : "busy right now"
    }

    // Put the creature back where it lives on this screen.
    function home(): string {
      if (!root.activeChief) return "not on stage"
      root.activeChief.walkHome(root.effectiveHomeX)
      return "going home"
    }

    function stroll(): string {
      if (!root.activeChief) return "not on stage"
      return root.activeChief.strollNow() ? "walking" : "cannot walk right now"
    }
    function summon(): void { root.summonConsole() }
    function toggle(): string { root.shown = !root.shown; return root.shown ? "shown" : "hidden" }
    function show(): void { root.shown = true }
    function hide(): void { root.shown = false; root.promptOpen = false }
    function status(): string {
      var segs = []
      for (var i = 0; i < root.segments.length; i++)
        segs.push(root.segments[i].name + "@" + root.segments[i].x + "+" + root.segments[i].w)
      return root.mood + " energy=" + Math.round(root.energy * 100) + "%"
        + " agent=" + (root.agentId === "" ? "none" : root.agentId)
        + " windows=" + root.agentWindows
        + " console=" + (root.consoleOpen ? "open" : "closed")
        + " body=" + (root.spriteOk ? "sprite" : "blob")
        + " acts=" + root.spriteActivities.length
        + " gap=" + Math.round(root.gapBottom)
        + " theme=" + (root.spriteTint > 0 ? "tinted"
            : root.spriteThemeable === null ? "off"
            : (root.themedUsable ? "dressed" : "pending"))
        + "/" + root.accentHex + (root.pluginDir === "" ? "/no-plugin-dir" : "")
        + " hooks=" + (root.hooksInstalled ? "yes" : "no")
        + " world=" + root.worldMonitor + (root.submerged ? "(diving)" : "")
        + (root.cfgScreen === "" ? "" : " kept=" + root.cfgScreen)
        + " session=" + (root.sessionId === "" ? "fresh" : root.sessionId.slice(0, 8))
        + " talking=" + (root.talkBusy ? "yes" : "no")
        + (root.agentSilent ? " answering=no" : "")
        + " segments=[" + segs.join(",") + "]"
    }
  }

  // ------------------------------------------------------------ the windows
  //
  // One strip per monitor, mapped only while the chief is on it. Everything
  // else on that screen clicks straight through; while the order form is
  // open the whole strip catches the dismissing click.

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: win
      required property var modelData
      readonly property bool chiefHere: modelData.name === root.worldMonitor

      screen: modelData
      visible: chiefHere && root.shown
        && !(root.cfgHideFullscreen && root.fullscreenOnPetMonitor)
      anchors { left: true; right: true; bottom: true }
      implicitHeight: Math.max(Math.round(root.petSize * 2.4), 220)
      color: "transparent"
      aboveWindows: true
      // Reserve nothing, but respect what others reserve: on a monitor
      // with a bottom bar the chief walks on top of the bar; on a bare
      // edge it walks on the edge itself.
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: 0
      mask: Region { item: chiefLoader.item ? (root.promptOpen ? chiefLoader.item : chiefLoader.item.hitbox) : null }
      WlrLayershell.namespace: "omarchief"

      // Prime with Exclusive on every open, then settle on OnDemand — the
      // KeyboardPanel recipe. Hyprland focuses OnDemand when a surface
      // first maps, but not when an already-mapped strip flips from None
      // to OnDemand; without the prime, keystrokes fall through into the
      // window behind the chief.
      readonly property bool wantsKeyboard: win.chiefHere && root.promptOpen
      property bool focusPrimed: false
      onWantsKeyboardChanged: {
        if (wantsKeyboard) { focusPrimed = false; primeTimer.restart() }
        else primeTimer.stop()
      }
      Timer { id: primeTimer; interval: 90; onTriggered: win.focusPrimed = true }
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
          petSize: root.petSize
          pixelArt: root.spritePixelArt
          mood: root.mood
          energy: root.energy
          activityRate: root.cfgActivity
          roam: root.cfgRoam && !root.stillPet
          faces: root.spriteFaces
          columns: root.spriteColumns
          mayMirror: root.spriteMirror
          doing: root.doing
          tucked: root.tucked
          display: root.spriteDisplay
          displayText: root.screenText
          screenInk: root.screenInk
          // The same monospace the shell writes everything else in.
          screenFont: Style.fontFamily
          idleFaces: root.spriteIdleFaces
          blinkFace: root.spriteBlink
          expressions: root.cfgExpressions
          glanceChance: root.cfgGlanceChance
          activities: root.spriteActivities
          stillRows: root.spriteStillRows
          activityChance: root.cfgActivityChance
          activityRestMs: root.cfgActivityRestSec * 1000
          groundOffset: Model.groundOffset(root.gapBottom, root.petSize, 4, 208)
          active: win.visible
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
            + (root.timerText !== "" ? " · " + Model.timerWords(
                 Math.max(0, root.timerEndsAt - Date.now())) : "")
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
            else if (button === Qt.MiddleButton) { root.shown = false; root.promptOpen = false }
            else {
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
