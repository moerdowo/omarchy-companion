import test from "node:test"
import assert from "node:assert/strict"
import {
  existsSync,
  lstatSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
} from "node:fs"
import { spawnSync } from "node:child_process"
import { createRequire } from "node:module"
import { homedir, tmpdir } from "node:os"
import { dirname, join, relative, resolve, sep } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, "..")
const require = createRequire(import.meta.url)
const Model = require("../keystone/Model.js")
const read = (path) => readFileSync(join(root, path), "utf8")
const manifest = JSON.parse(read("manifest.json"))

const servicePath = manifest.entryPoints.service
const widgetPath = manifest.entryPoints.barWidget
const entryDir = dirname(servicePath)
const panelPath = join(entryDir, "Panel.qml")
const chiefPath = join(entryDir, "Chief.qml")

const service = read(servicePath)
const widget = read(widgetPath)
const panel = read(panelPath)

function filesUnder(dir) {
  const out = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".git") continue
    const path = join(dir, entry.name)
    out.push(path)
    if (entry.isDirectory()) out.push(...filesUnder(path))
  }
  return out
}

function publicFunctions(source) {
  return new Set([...source.matchAll(/\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/g)].map((m) => m[1]))
}

function rgba(path) {
  const dimensions = spawnSync("magick", ["identify", "-format", "%w %h", path], { encoding: "utf8" })
  assert.equal(dimensions.status, 0, dimensions.stderr)
  const [width, height] = dimensions.stdout.trim().split(/\s+/).map(Number)
  const pixels = spawnSync("magick", [path, "-depth", "8", "rgba:-"], {
    encoding: null,
    maxBuffer: 16 * 1024 * 1024,
  })
  assert.equal(pixels.status, 0, pixels.stderr?.toString())
  assert.equal(pixels.stdout.length, width * height * 4)
  return { width, height, pixels: pixels.stdout }
}

function hsl(r, g, b) {
  const hi = Math.max(r, g, b), lo = Math.min(r, g, b)
  const light = (hi + lo) / 2
  const delta = hi - lo
  if (delta === 0) return { hue: 0, saturation: 0, light }
  let hue
  if (hi === r) hue = ((g - b) / delta) % 6
  else if (hi === g) hue = (b - r) / delta + 2
  else hue = (r - g) / delta + 4
  hue = (hue * 60 + 360) % 360
  return { hue, saturation: delta / (1 - Math.abs(2 * light - 1)), light }
}

function luminance([r, g, b]) {
  const linear = (value) => value <= 0.04045
    ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

function rgb(hex) {
  const value = hex.replace(/^#/, "")
  return [0, 2, 4].map((start) => Number.parseInt(value.slice(start, start + 2), 16) / 255)
}

function ratio(a, b) {
  const [la, lb] = [luminance(a), luminance(b)]
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

function themeSamples() {
  const samples = new Map([
    ["everforest", ["#7fbbb3", "#2d353b"]],
    ["nord", ["#81a1c1", "#2e3440"]],
    ["vantablack", ["#8d8d8d", "#000000"]],
    ["white", ["#6e6e6e", "#ffffff"]],
    ["catppuccin-latte", ["#1e66f5", "#eff1f5"]],
  ])
  for (const themesRoot of [
    "/usr/share/omarchy/themes",
    join(homedir(), ".local/share/omarchy/themes"),
  ]) if (existsSync(themesRoot)) for (const name of readdirSync(themesRoot)) {
      const colors = join(themesRoot, name, "colors.toml")
      if (!existsSync(colors)) continue
      const source = readFileSync(colors, "utf8")
      const accent = source.match(/^accent\s*=\s*"(#[0-9a-f]{6})"/mi)
      const background = source.match(/^background\s*=\s*"(#[0-9a-f]{6})"/mi)
      if (accent && background) samples.set(name, [accent[1], background[1]])
    }
  return samples
}

function weightedPercentile(points, percentile) {
  points.sort((a, b) => a.value - b.value)
  const total = points.reduce((sum, point) => sum + point.weight, 0)
  const wanted = total * percentile
  let seen = 0
  for (const point of points) {
    seen += point.weight
    if (seen >= wanted) return point.value
  }
  return points.length > 0 ? points.at(-1).value : 0
}

test("manifest exposes exactly one service and one bar widget", () => {
  assert.equal(manifest.schemaVersion, 1)
  assert.deepEqual(manifest.kinds, ["service", "bar-widget"])
  assert.deepEqual(Object.keys(manifest.entryPoints).sort(), ["barWidget", "service"])
  for (const path of [servicePath, widgetPath, panelPath, chiefPath]) {
    assert.ok(path && !path.startsWith("/") && !path.includes(".."), `unsafe path: ${path}`)
    assert.ok(existsSync(join(root, path)), `missing architecture file: ${path}`)
  }
  assert.equal(existsSync(join(root, entryDir, "ChiefPanel.qml")), false,
    "the pre-service panel entry point must not return")
})

test("bar and popout are views over the resident service", () => {
  assert.match(service, /\bItem\s*\{/, "service entry must be a headless Item")
  assert.match(widget, /\bBarWidget\s*\{/, "widget must use Omarchy's BarWidget base")
  assert.match(panel, /\bPanel\s*\{/, "popout must use Omarchy's Panel base")
  assert.match(widget, /serviceFor\s*\(\s*moduleName\s*\)/,
    "every monitor must obtain the singleton through shell.serviceFor")
  assert.match(panel, /property\s+var\s+service\s*:/,
    "the popout needs direct service injection")
  assert.match(panel, /manageIpc\s*:\s*false/,
    "the per-monitor popout must not register the resident IPC target")

  for (const [name, source] of [["bar widget", widget], ["popout", panel]]) {
    assert.doesNotMatch(source, /\bFileView\s*\{/,
      `${name} must not poll or mirror the service through files`)
    assert.doesNotMatch(source, /\bProcess\s*\{/,
      `${name} must not shell out for service actions`)
    assert.doesNotMatch(source, /omarchy-shell\s+grokchief/,
      `${name} must call the service directly`)
  }

  const ipcTargets = [...service.matchAll(/\bIpcHandler\s*\{[\s\S]*?\btarget\s*:\s*"([^"]+)"/g)]
    .map((m) => m[1])
  assert.deepEqual(ipcTargets, ["grokchief"], "only the service may own Grok Chief IPC")
})

test("overview keeps only actions that add something", () => {
  assert.doesNotMatch(panel, /text:\s*"Home"/,
    "returning to a saved position is not a meaningful overview button")
  assert.doesNotMatch(panel, /Ask Grok Chief/,
    "the companion itself is already the ask affordance")
  assert.match(panel, /showPrimaryAction:\s*!ready\s*\|\|\s*!hasAgent\s*\|\|\s*working/,
    "agent setup and stopping a turn must remain reachable")
  assert.match(panel, /cellWidth:\s*\(width - spacing\) \/ 2/,
    "Console and Tuck should share the freed row evenly")
})

test("drag, tuck, and scrolling keep their visual chrome out of the way", () => {
  const chief = read(chiefPath)
  assert.doesNotMatch(chief, /pointerFocused/,
    "pointer interaction must not masquerade as keyboard focus")
  assert.match(chief,
    /onPressed:\s*function\(mouse\)\s*\{[\s\S]*?grabX\s*=/,
    "the pet must still initialise its pointer gesture")
  assert.doesNotMatch(chief.match(/onPressed:\s*function\(mouse\)\s*\{[\s\S]*?grabX\s*=/)[0],
    /forceActiveFocus/,
    "a pointer press must not paint the keyboard focus ring around the pet")
  assert.match(chief,
    /readonly property bool peeking:[\s\S]*?promptOpen\s*\|\|\s*sayMode\s*!==\s*""/,
    "a tucked pet must stay raised while its prompt or reply is visible")
  assert.match(chief, /pet\.peeking \? 0\.70 : 1/,
    "a bottom-tucked pet should rise a little farther for interaction")
  assert.match(chief, /pet\.peeking \? 0\.75 : 1/,
    "a side-tucked pet should slide a little farther out for interaction")
  assert.match(chief,
    /function focusPrompt\(\)[\s\S]*?forceActiveFocus\(\)[\s\S]*?cursorVisible:\s*visible\s*&&\s*activeFocus/,
    "an open prompt must claim focus and show its insertion caret")
  assert.match(chief,
    /cursorDelegate:\s*Rectangle\s*\{[\s\S]*?color:\s*Color\.popups\.text[\s\S]*?Qt\.styleHints\.cursorFlashTime/,
    "the prompt caret must stay visible against every popup theme")
  assert.match(chief,
    /onVisibleChanged:[\s\S]*?Qt\.callLater\(function\(\)\s*\{\s*pet\.focusPrompt\(\)\s*\}\)/,
    "prompt focus must be claimed as soon as the field is laid out")
  assert.match(chief,
    /id:\s*promptShield[\s\S]*?z:\s*0[\s\S]*?reach:\s*Style\.space\(16\)[\s\S]*?Math\.min\(ask\.x,\s*hit\.x\)[\s\S]*?enabled:\s*pet\.promptOpen[\s\S]*?acceptedButtons:\s*Qt\.AllButtons[\s\S]*?onClicked:\s*pet\.promptDismissed\(\)/,
    "the open prompt must shield a padded route from focus-following windows below")
  assert.match(chief,
    /Region\s*\{\s*item:\s*promptShield\.enabled\s*\?\s*promptShield\s*:\s*null\s*\}/,
    "the prompt shield must participate in the layer-shell input mask")
  assert.match(read(servicePath),
    /win\.focusPrimed\s*=\s*true[\s\S]*?chiefLoader\.item\.focusPrompt\(\)/,
    "prompt focus must be confirmed after the layer-shell handoff")
  assert.match(panel,
    /rightPadding:\s*root\.view\s*===\s*"settings"\s*\?\s*Style\.space\(10\)\s*:\s*0/,
    "the settings scrollbar needs a rail beside, not over, the content")
})

test("every guarded panel action exists on the service", () => {
  const methods = publicFunctions(service)
  const requested = new Set()
  for (const source of [widget, panel]) {
    for (const match of source.matchAll(/typeof\s+(?:root\.)?service\.([A-Za-z_][A-Za-z0-9_]*)\s*===\s*"function"/g))
      requested.add(match[1])
  }
  assert.ok(requested.size >= 10, `only found ${requested.size} service actions`)
  for (const name of requested)
    assert.ok(methods.has(name), `the UI calls service.${name}(), but Service.qml does not provide it`)
})

test("every setting exposed by the popout is accepted by the service", () => {
  const exposed = new Set([...panel.matchAll(/setSetting\s*\(\s*"([^"]+)"/g)].map((m) => m[1]))
  const keyBlock = service.match(/readonly\s+property\s+var\s+settingKeys\s*:\s*\[([\s\S]*?)\]/)
  assert.ok(keyBlock, "Service.qml has no explicit setting allow-list")
  const allowed = new Set([...keyBlock[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]))
  assert.ok(exposed.size >= 8, `only found ${exposed.size} settings in the popout`)
  for (const key of exposed)
    assert.ok(allowed.has(key), `the popout writes "${key}", but the service rejects it`)
})

test("removed invasive and obsolete features stay removed", () => {
  const runtime = `${service}\n${widget}\n${panel}`
  assert.doesNotMatch(runtime, /grokchief-hooks?|hooksInstalled|hookSet/,
    "Grok Chief must not install or manage another agent's hooks")
  assert.doesNotMatch(runtime, /cfgConsoleAt|consoleAt\s*\(/,
    "the non-native near-creature console mode must not return")
  assert.doesNotMatch(runtime, /shouldRetryTalk|talkRetry|talkRetried/,
    "an agent turn must never be retried implicitly")
  assert.doesNotMatch(runtime, /timerSeconds|timerEndsAt|cfgReadout|timerWords|timerCompact/,
    "the removed clock/timer product must not return")
  assert.match(service, /if\s*\(p\s*!==\s*"bloub"\)\s*out\.push\(pluginDir\s*\+\s*"\/pets\/bloub"\)/,
    "a missing configured pet must end at the bundled Bloub fallback")
})

test("agent work is guarded across Stop, reload, and plugin removal", () => {
  assert.match(service,
    /recolorProc\.command\s*=\s*\["bash",\s*"-lc",[\s\S]*?Model\.buildGuardedRunner/,
    "the recolour subprocess tree must have an owner-death guardian")
  assert.match(service,
    /talkProc\.command\s*=\s*\["bash",\s*"-lc",\s*Model\.buildGuardedRunner/,
    "the agent subprocess tree must have an owner-death guardian")
})

test("OpenCode waits for its authoritative process exit", () => {
  assert.doesNotMatch(service, /quietEnd|kind\s*===\s*"maybe_end"/,
    "a multi-step OpenCode turn must not be ended by a silence heuristic")
})

test("travel keeps the latest ask and focus target", () => {
  assert.match(service,
    /property string pendingAskMonitor:\s*""/,
    "an ask arriving mid-travel needs its monitor, not only a boolean")
  assert.match(service,
    /function finishTravel\(\)[\s\S]*?root\.askOn\(askTarget\)[\s\S]*?root\.armFollow\(\)/,
    "arrival must resume a queued ask and recheck focus")
  assert.match(service,
    /onCfgReduceMotionChanged:[\s\S]*?root\.finishTravelNow\(\)/,
    "enabling reduced motion must immediately finish an active trip")
  assert.match(service,
    /function canFollowNow\(\)[\s\S]*?root\.cfgHideFullscreen[\s\S]*?root\.fullscreenMonitors\.indexOf\(root\.focusedMonName\)/,
    "fullscreen may block the arrival recheck only when that setting is enabled")
  assert.match(service,
    /onFullscreenMonitorsChanged:\s*\{\s*root\.armDodge\(\);\s*root\.armFollow\(\)\s*\}/,
    "leaving fullscreen must retry follow without waiting for another focus event")
})

test("an early drag or travel merges with home.json instead of replacing it", () => {
  assert.match(service,
    /property var pendingHome:\s*null/,
    "home writes need a transaction while the first FileView read is pending")
  assert.match(service,
    /onLoaded:[\s\S]*?homeLoaded = true[\s\S]*?applyPendingHome\(\)[\s\S]*?commitLoadedHome\(\)/,
    "disk homes must load before queued user placement is merged")
  assert.match(service,
    /function recordHome\([\s\S]*?if \(!root\.homeLoaded\)\s*\{\s*root\.queueHome/,
    "drag and travel must never write the pre-load empty map")
  assert.match(service,
    /function writeHome\(\)\s*\{\s*if \(!root\.homeLoaded\) return/,
    "the low-level writer must enforce the load gate too")
  assert.match(service,
    /function commitLoadedHome\(\)[\s\S]*?root\.spawnLocalX = x[\s\S]*?root\.activeChief\.px = x/,
    "the first async load must update an already-seeded Chief on the same monitor")
  assert.match(service,
    /useHome:\s*useHome[\s\S]*?trip\.useHome && root\.homeLoaded\s*\?\s*root\.homeOn\(trip\.mon\)/,
    "a destination without an explicit coordinate must resolve its saved home after loading")
  for (const block of [
    /function commitLoadedHome\(\)[\s\S]*?root\.spawnLocalX = x\s*\n\s*root\.worldMonitor = remembered/,
    /onSegmentsChanged:[\s\S]*?spawnLocalX = homeOn\(wanted\)\s*\n\s*worldMonitor = wanted/,
    /onFocusedMonNameChanged:[\s\S]*?spawnLocalX = root\.homeOn\(target\)\s*\n\s*root\.worldMonitor = target/,
    /onCfgScreenChanged:[\s\S]*?spawnLocalX = homeOn\(cfgScreen\)\s*\n\s*worldMonitor = cfgScreen/,
  ]) assert.match(service, block,
    "a target position must be ready before changing monitor creates its Chief")
})

test("pinning retires both phases of an older monitor trip", () => {
  assert.match(service,
    /onCfgScreenChanged:[\s\S]*?followTimer\.stop\(\)[\s\S]*?diveTimer\.stop\(\)[\s\S]*?undergroundTimer\.stop\(\)[\s\S]*?pendingTravel = null/,
    "a stale underground timer must never finish a newer trip")
})

test("console handoff remains owned by the agent that launched it", () => {
  assert.match(service, /property string consoleHandoffAgent:\s*""/)
  assert.match(service,
    /function confirmConsoleLaunch\(\)[\s\S]*?handoffAgent = root\.consoleHandoffAgent[\s\S]*?root\.forgetSession\(handoffAgent\)[\s\S]*?root\.agentId === handoffAgent/,
    "switching the picker mid-launch must retire the handed-off agent's session only")
  assert.match(service,
    /function summonConsole\(monitor\)[\s\S]*?if \(!root\.sessionsLoaded\) return "still starting"[\s\S]*?buildConsoleResume/,
    "a cold-start summon must wait until resumable sessions are hydrated")
  assert.match(service,
    /function orderToConsole\(text, monitor\)[\s\S]*?if \(!root\.sessionsLoaded\) return "still starting"/,
    "every console order path must share the hydration gate")
})

test("fresh and console actions cannot outrun session hydration", () => {
  assert.match(service,
    /function freshConversation\(\)[\s\S]*?if \(!root\.sessionsLoaded \|\| root\.talkBusy/,
    "Fresh must not be overwritten by a later sessions.json load")
  assert.match(service,
    /function fresh\(\): string\s*\{\s*if \(!root\.sessionsLoaded\) return "still starting"/,
    "the IPC response must explain the startup gate")
})

test("panel keyboard focus is revealed before it moves or activates", () => {
  assert.match(panel,
    /function revealCursor\(\)[\s\S]*?if \(cursorActive\) return false[\s\S]*?cursorActive = true/,
    "the first arrow must reveal the primary action rather than skip it")
  assert.match(panel,
    /function moveCursor\(delta\)[\s\S]*?if \(revealCursor\(\)\) return/)
  assert.match(panel,
    /function moveHorizontal\(delta\)[\s\S]*?if \(revealCursor\(\)\) return/,
    "left or right must reveal the same cursor as up or down")
  assert.match(panel,
    /function activateCursor\(\)\s*\{\s*if \(!cursorActive\) return/,
    "Enter must not trigger an invisible cursor")
})

test("the activity action follows the Chief's exact ability to perform", () => {
  const chief = read(chiefPath)
  assert.match(chief,
    /function activityAllowed\(rested\)[\s\S]*?activity !== null[\s\S]*?Model\.mayPlayActivity[\s\S]*?readonly property bool canPlayActivity: activityAllowed\(true\)/,
    "the Chief must expose the same full guard its play action executes")
  assert.match(service,
    /readonly property bool canPlayActivity:[\s\S]*?activeChief\.canPlayActivity === true/,
    "the service must forward live stage eligibility")
  assert.match(panel,
    /readonly property bool hasActivities:\s*ready && service\.canPlayActivity === true/,
    "the panel must not reconstruct only part of the Chief's guard")
  assert.match(panel,
    /readonly property bool inConversation:[\s\S]*?!working[\s\S]*?service\.consoleLaunchPending !== true/,
    "a running turn or console handoff must not advertise a disabled reset")
  assert.match(panel, /property string utilityAction:\s*"play"/)
  assert.match(panel,
    /function currentUtilityAction\(\)[\s\S]*?actions\.indexOf\(utilityAction\)[\s\S]*?function syncUtilityAction/,
    "dynamic utility actions must retain their meaning, not merely their old index")
  assert.doesNotMatch(panel, /utilityCursor/,
    "an index cannot preserve Fresh when Play is inserted before it")
  assert.match(panel, /onHasActivitiesChanged:[\s\S]*?syncGroupCursor/)
  assert.match(panel, /onInConversationChanged:[\s\S]*?syncGroupCursor/,
    "dynamic utility actions must leave the keyboard cursor on a real button")
})

test("same-mode bubble changes and unavailable configured agents stay visible", () => {
  assert.match(service,
    /onSayTextChanged:\s*\{\s*root\.scheduleBubble\(\);\s*statusWrite\.restart\(\)\s*\}/,
    "changing one error message into another must refresh status.json")
  assert.match(panel,
    /Unavailable · ["']?\s*\+\s*agentName\(configuredAgent\)/,
    "the agent picker must represent an installed agent it cannot safely launch")
  assert.match(panel,
    /foundPinned[\s\S]*?Missing · ["']?\s*\+\s*cleanLabel\(pinnedScreen/,
    "an unplugged pinned monitor must remain visible and reversible")
  assert.match(panel,
    /function heroMeta\(\)[\s\S]*?chiefMonitor/,
    "the overview must name the creature's monitor, not merely the bar's")
})

test("agent discovery never installs a picker entry and every override is runnable", () => {
  assert.match(service,
    /order='pi omp opencode ori claude codex grok agy gemini copilot crush'/,
    "the fallback must cover both Omarchy 4.0 and the post-4.0 agent matrix")
  assert.match(service,
    /grep -q 'mise use -g'[\s\S]*?grep -q 'exec mise x'[\s\S]*?! mise which[\s\S]*?continue/,
    "an Omarchy lazy-install shim must not be presented as already installed")
  assert.match(service,
    /agentAvailable:[\s\S]*?agentIsDefault \|\| Model\.canTalkTo\(agentId\) \|\| Model\.canOpenConsole\(agentId\)/,
    "an explicit override must have a real bubble or console adapter")
  assert.match(service,
    /cfgAgent === "gemini"[\s\S]*?!hasAgent\("gemini"\)[\s\S]*?hasAgent\("agy"\)[\s\S]*?\? "agy"/,
    "a 4.0 Gemini preference must follow Omarchy's Antigravity alias only when Gemini disappeared")
  assert.match(panel,
    /id !== "" && Model\.canOpenConsole\(id\)/,
    "the picker must never advertise a console-only override it cannot launch")
})

test("only windows inside the native console influence the parked mood", () => {
  assert.match(service, /Model\.resolveMood\(\{[\s\S]*?consoleWindows:\s*consoleWindows/)
  assert.doesNotMatch(service, /agentWindows:\s*agentWindows/,
    "ordinary tiled Omarchy agent windows are not a parked Quake console")
})

test("persisted agent and legacy conversation settings keep their JSON types", () => {
  assert.match(service,
    /cfgAgent:\s*typeof cfg\.agent === "string"\s*&&\s*Model\.safeId\(cfg\.agent\)/,
    "a numeric JSON value must not become an agent id")
  assert.match(service,
    /if \(v === 1\) return -1[\s\S]*?return Math\.round\(v\)/,
    "only the exact legacy value 1 means one ask; nearby malformed values must not")
  assert.match(service,
    /function armSessionIdle\(\)[\s\S]*?cfgSessionIdleMin < 0[\s\S]*?sessionId = ""/,
    "switching an ongoing conversation to one ask must make the next order fresh")
  assert.match(service,
    /if \(value !== true && value !== false\)[\s\S]*?setting needs a boolean/,
    "a malformed direct settings call must not silently mean false")
})

test("turning theme dressing off restores the original sheet immediately", () => {
  const chief = read(chiefPath)
  assert.match(chief,
    /function cancelRepaint\(\)[\s\S]*?repaintRise\.stop\(\)[\s\S]*?repaintFrom = ""[\s\S]*?repaintTint = 0[\s\S]*?repaintFill = 1/,
    "the presentation must be able to remove an old coat synchronously")
  assert.match(service,
    /onCfgThemeChanged:[\s\S]*?if \(cfgTheme\)[\s\S]*?root\.beginRedress\(\)[\s\S]*?redressGiveUp\.stop\(\)[\s\S]*?themeRequestSerial\+\+[\s\S]*?redressing = false[\s\S]*?wornBefore = ""[\s\S]*?activeChief\.cancelRepaint\(\)[\s\S]*?root\.syncSpriteSource\(\)[\s\S]*?root\.rememberCurrentCoat\(\)/,
    "Theme off must not keep the previous themed sheet during an in-flight redraw")
  assert.match(service,
    /function resetPetState\(\)[\s\S]*?activeChief\.cancelRepaint\(\)[\s\S]*?settledCoat = ""[\s\S]*?themeRequestSerial\+\+/,
    "changing companion must not overlay the previous companion's paint")
})

test("legacy settings are sealed after their one-time migration", () => {
  assert.match(service, /migrationMarker\s*:\s*"_grokchiefConfigVersion"/)
  assert.match(service, /migrationMarked\(before\)\s*\?\s*\(\{\}\)\s*:\s*fileCfg/,
    "a marked canonical entry must never merge the retired settings file again")
  assert.match(service, /next\[root\.migrationMarker\]\s*=\s*root\.configVersion/,
    "normal settings writes must preserve the migration marker")
  assert.match(service,
    /else if \(top\)[\s\S]*?next\.bar\.layout\.right\.push\(canonicalTop\)[\s\S]*?next\.plugins = next\.plugins\.filter/,
    "a top-level-only legacy install must gain the bar view that owns its service")
})

test("console workspace follows Omarchy's qconsole contract with a 4.0 fallback", () => {
  assert.match(service,
    /qconsoleOmarchyRoot:[^\n]*OMARCHY_PATH[^\n]*\/usr\/share\/omarchy/,
    "the installed Omarchy tree, not a plugin-owned workspace name, is authoritative")
  assert.match(service,
    /path:\s*root\.qconsoleOmarchyRoot \+ "\/default\/hypr\/qconsole\.lua"[\s\S]*?watchChanges:\s*true/)
  assert.match(service,
    /function workspaceFromQconsole\(source\)[\s\S]*?special:\(\[A-Za-z0-9\][\s\S]*?Model\.safeId\(match\[1\]\)[\s\S]*?return "scratchpad"/,
    "a future native console name must be accepted only from safe qconsole syntax")
  assert.match(service, /onLoadFailed:\s*root\.qconsoleWorkspace = "scratchpad"/,
    "Omarchy 4.0 has no qconsole.lua and must retain its scratchpad")
  assert.match(service, /wantedConsoleWs:\s*qconsoleWorkspace/)
})

test("console handoff maps one identified agent before focusing or revealing", () => {
  assert.doesNotMatch(service, /consoleLaunchAgentBaseline|onAgentWindowsChanged\s*:\s*root\.confirmConsoleLaunch/,
    "an unrelated global agent window must not confirm the console handoff")
  assert.match(service,
    /function agentWindowKeys\(workspace\)[\s\S]*?topWorkspace !== expectedWorkspace[\s\S]*?appId !== "org\.omarchy\.agent"[\s\S]*?top\.address[\s\S]*?ipc\.pid/,
    "the baseline must identify exact agent toplevels inside the native console workspace")
  assert.match(service,
    /id:\s*consoleLaunchVerify[\s\S]*?\.workspace\.name == \$ws[\s\S]*?rtrimstr\(\\"\*\\"\) == \$tag[\s\S]*?consoleLaunchVerifiedKey = key/,
    "Hyprland itself must prove the one-use tag before Quickshell accepts the address")
  assert.match(service,
    /function newConsoleWindowKey\(\)[\s\S]*?consoleLaunchVerifiedKey[\s\S]*?consoleLaunchWindowBaseline\[verified\][\s\S]*?keys\.indexOf\(verified\) !== -1/)
  assert.match(service,
    /function probeConsoleLaunch\(\)[\s\S]*?newConsoleWindowKey\(\)[\s\S]*?consoleLaunchCandidate = candidate[\s\S]*?consoleLaunchConfirm\.restart\(\)/)
  assert.match(service, /id:\s*consoleLaunchConfirm[\s\S]*?interval:\s*3[0-9]{2}/,
    "the scratchpad window must survive a debounce before context is handed off")
  assert.match(service,
    /function consoleCandidateMapped\(\)[\s\S]*?indexOf\(key\) !== -1/)

  const launchStart = service.indexOf("function launchInConsole")
  const launchEnd = service.indexOf("// A session belongs", launchStart)
  const launchFlow = service.slice(launchStart, launchEnd)
  assert.match(launchFlow, /root\.dispatch\(Model\.dispatchExec[\s\S]*?consoleRule\(workspace, launchTag\)/)
  assert.doesNotMatch(launchFlow, /dispatchOn|dispatchFocusMonitor|dispatchToggleSpecial/,
    "launching must not create an empty visible workspace for qconsole's auto-seed")

  const confirmStart = service.indexOf("function confirmConsoleLaunch")
  const confirmEnd = service.indexOf("function beginConsoleLaunch", confirmStart)
  const confirmFlow = service.slice(confirmStart, confirmEnd)
  const proof = confirmFlow.indexOf("consoleCandidateMapped()")
  const reveal = confirmFlow.indexOf("dispatchToggleSpecial(workspace)")
  const handoff = confirmFlow.indexOf("forgetSession(handoffAgent)")
  assert.ok(proof >= 0 && reveal > proof && handoff > reveal,
    "only a stable new requested window may reveal the console and consume its bubble session")

  const beginStart = service.indexOf("function beginConsoleLaunch")
  const beginEnd = service.indexOf("id: consoleLaunchTimeout", beginStart)
  const beginFlow = service.slice(beginStart, beginEnd)
  assert.match(beginFlow,
    /consoleLaunchTag = "grokchief-launch-"[\s\S]*?consoleLaunchWorkspace = workspace[\s\S]*?consoleLaunchMonitor = root\.actionMonitor\(monitor\)/,
    "the requested toplevel gets a unique launch-only Hyprland tag")
  assert.doesNotMatch(beginFlow, /dispatchFocusMonitor|dispatchToggleSpecial/,
    "the requested monitor is remembered but must not be focused before the window maps")
})

test("theme repaint starts on Omarchy's reveal and never double-tints a cached coat", () => {
  assert.match(service, /redrawCovered:\s*themedUsable\s*\n/)
  assert.doesNotMatch(service, /holdingThemedSheet/,
    "the previous coat must not delay the current palette's live preview")
  assert.doesNotMatch(service, /redrawCovered:\s*canRedraw/,
    "ImageMagick availability does not describe the sheet currently on screen")
  assert.match(service, /property bool canRedraw:\s*false/,
    "the first frame must not assume the optional redraw tool exists")
  assert.match(service, /onCanRedrawChanged:\s*if \(canRedraw\) redressTimer\.restart\(\)/)
  const chief = read(chiefPath)
  assert.doesNotMatch(chief, /\bid:\s*sheetFrom\b|\bsource:\s*sheetFrom\b|\bid:\s*dissolve\b|\bvp\.mix\b/,
    "authored sprite poses must snap cleanly instead of ghosting or popping")
  assert.match(chief,
    /MultiEffect\s*\{\s*visible:\s*pet\.tintStrength > 0\s*\n\s*source:\s*sheet[\s\S]*?opacity:\s*vp\.bodyOpacity/,
    "MultiEffect ignores the source Image opacity, so sleeping opacity belongs on the effect")
  assert.match(service,
    /function beginRedress\(\)[\s\S]*?previous = String\(settledCoat\)[\s\S]*?syncSpriteSource\(\)[\s\S]*?activeChief\.repaint\(previous, previousTint, previousRgb, previousBrightness\)[\s\S]*?rememberCurrentCoat\(\)/,
    "the old rendered coat must cover an immediate preview, not block on ImageMagick")
  assert.match(service,
    /var next = themedUsable \?[^\n]*\n\s*: spriteBaseSource/,
    "a cache miss must show the current palette through the raw sheet immediately")
  assert.match(service,
    /onAccentHexChanged:\s*\{ backgroundRedress\.stop\(\); root\.beginRedress\(\) \}/,
    "the pet reveal must start inside Omarchy's own synchronous Color update")
  assert.doesNotMatch(chief, /visible:\s*paintOver\.visible/,
    "the mask must remain inside the artwork's transparent silhouette")
  assert.match(chief,
    /id:\s*repaintRise[\s\S]*?duration:\s*420[\s\S]*?easing\.type:\s*Easing\.InOutCubic/,
    "duration and curve must match Omarchy's built-in background reveal")
  assert.match(chief,
    /id:\s*repaintMask[\s\S]*?slant:\s*-0\.18[\s\S]*?screenY:[^\n]*pet\.fullScreenHeight - pet\.height[\s\S]*?desiredTop:[\s\S]*?pet\.width \/ 2[\s\S]*?pet\.mirrored \? width - desiredTop : desiredTop[\s\S]*?reach:[\s\S]*?pet\.width \/ 2[\s\S]*?pet\.fullScreenHeight \/ 2 \+ 4[\s\S]*?spread:\s*reach \* pet\.repaintFill/,
    "the reveal must use the exact global slice of Omarchy's slanted centre-out band")
  assert.match(service, /fullScreenHeight:\s*modelData\.height/,
    "each pet window must provide its output height to the global reveal mask")
  assert.match(chief,
    /id:\s*paintOver[\s\S]*?opacity:\s*vp\.bodyOpacity[\s\S]*?maskSource:\s*repaintMask[\s\S]*?maskInverted:\s*true/,
    "a sleeping pet must not brighten while the old coat is lifted")
  assert.match(chief,
    /id:\s*oldSheet[\s\S]*?visible:\s*pet\.repaintTint <= 0[\s\S]*?visible:\s*pet\.repaintTint > 0[\s\S]*?source:\s*oldSheet/,
    "an old live-tinted coat must retain its exact rendered colour")
  assert.match(service,
    /var current = root\.recolorSerial === root\.themeRequestSerial[\s\S]*?root\.recolorTarget === root\.themedSheet[\s\S]*?if \(code === 0 && current\)[\s\S]*?else if \(code !== 0 && current\)/,
    "a stale recolor result must never publish or clear a newer theme")
  assert.match(service,
    /function rememberCurrentCoat\(\)[\s\S]*?var strength = cfgTheme \? Model\.tintFor\(spriteThemeable, lossless, petTint\) : 0[\s\S]*?settledCoatTint = strength/,
    "the remembered coat must not depend on a QML tint binding settling first")
  assert.match(chief, /id:\s*brain[\s\S]*?running:[\s\S]*?pet\.activity === null/,
    "ambient motion must not interrupt a performance already on stage")
})

test("orders are bounded before they become one shell argument", () => {
  assert.match(service, /readonly property int orderMax:\s*8000/)
  assert.match(service, /if \(t\.length > root\.orderMax\) return "order exceeds 8000 characters"/)
  assert.match(read("keystone/Chief.qml"), /maximumLength:\s*pet\.orderMax/)
})

test("bundled pets are safe, complete, and uniquely identified", () => {
  const petRoot = join(root, "pets")
  const ids = new Set()
  for (const dirent of readdirSync(petRoot, { withFileTypes: true })) {
    if (!dirent.isDirectory()) continue
    const id = dirent.name
    assert.match(id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/, `unsafe pet folder id: ${id}`)
    assert.ok(!["__proto__", "prototype", "constructor"].includes(id),
      `reserved pet folder id: ${id}`)
    assert.equal(ids.has(id), false, `duplicate pet id: ${id}`)
    ids.add(id)

    const dir = join(petRoot, id)
    const specPath = join(dir, "pet.json")
    assert.ok(existsSync(specPath), `${id} has no pet.json`)
    const spec = JSON.parse(readFileSync(specPath, "utf8"))
    assert.equal(typeof spec.displayName, "string", `${id} has no human-readable displayName`)
    assert.ok(spec.displayName.trim(), `${id} has an empty displayName`)
    assert.ok(existsSync(join(dir, "NOTICE")), `${id} has no artwork NOTICE`)

    // A pet may be DRAWN instead of blitted: it names a renderer and ships no
    // artwork at all, so every check below about sheets and cells would be
    // asking after something that does not exist. What it must still satisfy
    // is that the renderer is one this plugin actually has.
    if (spec.render !== undefined) {
      assert.equal(spec.render, "bloub", `${id} names an unknown renderer`)
      assert.equal(spec.spritesheetPath, undefined, `${id} is drawn but names a sheet`)
      assert.match(read("keystone/Service.qml"),
        /String\(pet\.render \|\| ""\) === "bloub"/,
        "the service must recognise the renderer the drawn pet names")
      assert.ok(existsSync(join(root, "keystone/Bloub.js")), "the drawn pet has no renderer")
      continue
    }

    assert.ok(Number.isInteger(spec.rows) && spec.rows > 0 && spec.rows <= 64,
      `${id} has invalid rows`)
    const columns = spec.columns ?? 8
    assert.ok(Number.isInteger(columns) && columns > 0 && columns <= 64,
      `${id} has invalid columns`)
    assert.equal(typeof spec.spritesheetPath, "string", `${id} has no spritesheetPath`)
    assert.ok(spec.spritesheetPath && !spec.spritesheetPath.startsWith("/")
      && !spec.spritesheetPath.split(/[\\/]+/).includes(".."),
    `${id} has an unsafe spritesheetPath`)
    const sheet = resolve(dir, spec.spritesheetPath)
    assert.equal(relative(dir, sheet).startsWith(`..${sep}`), false,
      `${id} spritesheet escapes its folder`)
    assert.ok(existsSync(sheet), `${id} is missing ${spec.spritesheetPath}`)
    assert.ok(lstatSync(sheet).isFile() && lstatSync(sheet).size > 0,
      `${id} spritesheet is empty`)

    for (const [mood, cell] of Object.entries(spec.faces ?? {})) {
      assert.ok(Array.isArray(cell) && cell.length === 2,
        `${id} face ${mood} is not [row, column]`)
      assert.ok(Number.isInteger(cell[0]) && cell[0] >= 0 && cell[0] < spec.rows,
        `${id} face ${mood} has an invalid row`)
      assert.ok(Number.isInteger(cell[1]) && cell[1] >= 0 && cell[1] < columns,
        `${id} face ${mood} has an invalid column`)
    }
  }
  assert.deepEqual([...ids].sort(), ["bloub", "gritty", "gritty-front", "quattro"])
  const gritty = rgba(join(root, "pets/gritty/gritty-faces.webp"))
  const brandPixel = (70 * gritty.width + 120) * 4
  assert.deepEqual([...gritty.pixels.slice(brandPixel, brandPixel + 3)], [158, 206, 106],
    "Gritty's unthemed reference midtone must be Omarchy green #9ece6a")
  assert.ok(gritty.pixels[brandPixel + 3] >= 250,
    "the branded reference must be a visible shell pixel")
  assert.equal(JSON.parse(read("pets/quattro/pet.json")).mirror, true,
    "Quattro must turn on the right so its flipped release cell always faces inward")
  const quattro = rgba(join(root, "pets/quattro/quattro.webp"))
  let alphaWeight = 0, alphaMomentX = 0
  for (let i = 0; i < quattro.pixels.length; i += 4) {
    const alpha = quattro.pixels[i + 3] / 255
    alphaWeight += alpha
    alphaMomentX += (i / 4 % quattro.width) * alpha
  }
  assert.ok(alphaWeight > 0 && alphaMomentX / alphaWeight < quattro.width / 2 - 2,
    "Quattro's canonical cell must keep its flipped right-facing orientation")
  assert.match(read("tools/source/README.md"), /-extent 333x208 -flop/,
    "the documented Quattro rebuild must preserve its canonical orientation")
  const front = JSON.parse(read("pets/gritty-front/pet.json"))
  assert.equal(front.displayName, "Gritty, head on")
  assert.equal(front.mirror, true,
    "the head-on cable must turn with the body on the right half of a screen")
  assert.match(service,
    /priority = \{'bloub': 0, 'gritty': 1, 'quattro': 2, 'gritty-front': 3, 'glitchcat': 4\}/,
    "the picker must keep the curated companions ahead of arbitrary local ids")
})

test("pet discovery never flashes the procedural emergency body", () => {
  assert.match(service,
    /property bool petResolved:\s*false[\s\S]*?function resetPetState\(\)[\s\S]*?root\.petResolved = false/)
  assert.match(service,
    /function rejectPet\(message\)[\s\S]*?root\.petResolved = false[\s\S]*?if \(root\.petDirIndex < root\.petDirCandidates\.length - 1\) root\.petDirIndex\+\+[\s\S]*?else root\.petResolved = true/,
    "the fallback becomes visible only after all artwork candidates fail")
  assert.match(service,
    /root\.spriteOk = true\s*\n\s*root\.petResolved = true/,
    "valid artwork resolves the hidden loading state")
  assert.match(service,
    /active:\s*win\.visible && root\.petResolved\s*\n\s*visible:\s*root\.petResolved/,
    "the Chief must neither render nor animate during manifest lookup")
})

test("theme repainting clears its floor without touching unmasked artwork", () => {
  const version = spawnSync("magick", ["-version"], { encoding: "utf8" })
  assert.equal(version.status, 0, "ImageMagick 7's magick command is required")
  assert.match(version.stdout, /^Version: ImageMagick 7\./m)
  assert.match(read("tools/grokchief-recolor"),
    /-define webp:lossless=true -define webp:method=0/,
    "theme caches must finish inside Omarchy's reveal instead of optimizing ephemeral bytes")
  const work = mkdtempSync(join(tmpdir(), "grokchief-recolor-"))
  try {
    const sourcePath = join(root, "pets/gritty/gritty-faces.webp")
    const basePath = join(work, "base.webp")
    const finalPath = join(work, "final.webp")
    const tool = join(root, "tools/grokchief-recolor")
    for (const args of [
      [sourcePath, finalPath, "red"],
      [sourcePath, finalPath, "#999900", "361", "100", "12"],
      [sourcePath, finalPath, "#999900", "175", "40", "12"],
      [sourcePath, finalPath, "#999900", "40", "175", "101"],
      [sourcePath, finalPath, "#999900", "40", "175", "12", "#fff", "extra"],
    ]) {
      const rejected = spawnSync(tool, args, { encoding: "utf8" })
      assert.equal(rejected.status, 2, rejected.stderr || rejected.stdout)
      assert.match(rejected.stderr, /^grokchief-recolor:/)
    }
    const directoryOutput = mkdtempSync(join(work, "outdir-"))
    const rejectedDirectory = spawnSync(tool,
      [sourcePath, directoryOutput, "#999900", "40", "175", "12"],
      { encoding: "utf8" })
    assert.equal(rejectedDirectory.status, 2,
      rejectedDirectory.stderr || rejectedDirectory.stdout)
    assert.match(rejectedDirectory.stderr, /output must name a file/)
    assert.deepEqual(readdirSync(directoryOutput), [],
      "a directory target must not receive a randomly named cache file")
    for (const args of [
      [sourcePath, basePath, "#999900", "40", "175", "12"],
      [sourcePath, finalPath, "#999900", "40", "175", "12", "#999900"],
    ]) {
      const result = spawnSync(tool, args, { encoding: "utf8" })
      assert.equal(result.status, 0, result.stderr || result.stdout)
    }

    const source = rgba(sourcePath)
    const base = rgba(basePath)
    const final = rgba(finalPath)
    assert.deepEqual([base.width, base.height], [source.width, source.height])
    assert.deepEqual([final.width, final.height], [source.width, source.height])

    let weightSum = 0
    const rgbSum = [0, 0, 0]
    let outsideChanged = 0
    for (let i = 0; i < source.pixels.length; i += 4) {
      const sr = source.pixels[i] / 255
      const sg = source.pixels[i + 1] / 255
      const sb = source.pixels[i + 2] / 255
      const sourceHsl = hsl(sr, sg, sb)
      const skin = sourceHsl.hue >= 40 && sourceHsl.hue <= 175 && sourceHsl.saturation >= 0.12
      if (source.pixels[i + 3] >= 128 && !skin
          && (source.pixels[i] !== final.pixels[i]
            || source.pixels[i + 1] !== final.pixels[i + 1]
            || source.pixels[i + 2] !== final.pixels[i + 2])) outsideChanged++
      if (!skin) continue

      const br = base.pixels[i] / 255
      const bg = base.pixels[i + 1] / 255
      const bb = base.pixels[i + 2] / 255
      if ((Math.max(br, bg, bb) + Math.min(br, bg, bb)) / 2 < 0.25) continue
      const weight = base.pixels[i + 3] / 255
      weightSum += weight
      rgbSum[0] += final.pixels[i] / 255 * weight
      rgbSum[1] += final.pixels[i + 1] / 255 * weight
      rgbSum[2] += final.pixels[i + 2] / 255 * weight
    }
    assert.equal(outsideChanged, 0, "cables, servos, eyes, and rust must remain byte-exact")
    assert.ok(weightSum > 0, "Gritty's themeable body mask is empty")
    const body = rgbSum.map((sum) => sum / weightSum)
    const bodyLum = luminance(body)
    const backgroundLum = luminance([0.6, 0.6, 0])
    const ratio = (Math.max(bodyLum, backgroundLum) + 0.05)
      / (Math.min(bodyLum, backgroundLum) + 0.05)
    assert.ok(ratio >= 4.5, `repainted body only reached ${ratio.toFixed(3)}:1`)
  } finally {
    rmSync(work, { recursive: true, force: true })
  }
})

test("the real Qt live-tint shader keeps bundled bodies legible and shaded", () => {
  const clamp = (value) => Math.max(0, Math.min(1, value))
  for (const id of ["gritty", "quattro", "gritty-front"]) {
    const spec = JSON.parse(read(`pets/${id}/pet.json`))
    const source = rgba(join(root, "pets", id, spec.spritesheetPath))
    const skin = spec.themeable
    for (const [theme, [accentHex, backgroundHex]] of themeSamples()) {
      const accent = rgb(accentHex), background = rgb(backgroundHex)
      const targetObject = Model.liveTintColor(
        { r: accent[0], g: accent[1], b: accent[2] },
        { r: background[0], g: background[1], b: background[2] })
      const target = [targetObject.r, targetObject.g, targetObject.b]
      const strength = Model.tintFor(skin, false,
        Model.tintStrength(spec.themeTint, 0))
      const brightness = Model.liveTintBrightness(
        { r: background[0], g: background[1], b: background[2] }, strength)
      const sum = [0, 0, 0]
      let weight = 0
      let clipped = 0
      let sourceLumaSum = 0
      let sourceLumaSquared = 0
      let displayedLumaSum = 0
      let displayedLumaSquared = 0
      const sourceLumas = []
      const displayedLumas = []

      for (let i = 0; i < source.pixels.length; i += 4) {
        const original = [source.pixels[i], source.pixels[i + 1], source.pixels[i + 2]]
          .map((value) => value / 255)
        const alpha = source.pixels[i + 3] / 255
        if (alpha < 0.5) continue
        const tone = hsl(...original)
        if (tone.hue < skin.hueMin || tone.hue > skin.hueMax
            || tone.saturation < skin.satMin / 100) continue

        // Qt MultiEffect 6.11: premultiplied source, brightness, grayscale,
        // then colorization. Composite the result over the theme background.
        const lit = original.map((value) => value * alpha + brightness * alpha)
        const gray = 0.299 * lit[0] + 0.587 * lit[1] + 0.114 * lit[2]
        const displayed = lit.map((value, channel) => clamp(
          gray * target[channel] * strength + value * (1 - strength)
            + background[channel] * (1 - alpha)))
        const sourceLuma = 0.299 * original[0] + 0.587 * original[1] + 0.114 * original[2]
        const displayedLuma = 0.299 * displayed[0] + 0.587 * displayed[1] + 0.114 * displayed[2]
        if (displayedLuma < 0.01 || displayedLuma > 0.99) clipped += alpha
        sourceLumaSum += sourceLuma * alpha
        sourceLumaSquared += sourceLuma * sourceLuma * alpha
        displayedLumaSum += displayedLuma * alpha
        displayedLumaSquared += displayedLuma * displayedLuma * alpha
        sourceLumas.push({ value: sourceLuma, weight: alpha })
        displayedLumas.push({ value: displayedLuma, weight: alpha })
        for (let channel = 0; channel < 3; channel++) sum[channel] += displayed[channel] * alpha
        weight += alpha
      }

      assert.ok(weight > 0, `${id} has no themeable body pixels`)
      const body = sum.map((value) => value / weight)
      const contrast = ratio(body, background)
      assert.ok(contrast >= 4.5,
        `${id} live tint reaches only ${contrast.toFixed(3)}:1 on ${theme}`)
      assert.ok(clipped / weight <= 0.12,
        `${id} live tint clips ${(100 * clipped / weight).toFixed(2)}% of its body on ${theme}`)

      const sourceMean = sourceLumaSum / weight
      const displayedMean = displayedLumaSum / weight
      const sourceStd = Math.sqrt(Math.max(0, sourceLumaSquared / weight - sourceMean ** 2))
      const displayedStd = Math.sqrt(Math.max(0,
        displayedLumaSquared / weight - displayedMean ** 2))
      assert.ok(sourceStd === 0 || displayedStd / sourceStd >= 0.4,
        `${id} live tint retains only ${(100 * displayedStd / sourceStd).toFixed(1)}% luma spread on ${theme}`)

      const sourceRange = weightedPercentile(sourceLumas, 0.95)
        - weightedPercentile(sourceLumas, 0.05)
      const displayedRange = weightedPercentile(displayedLumas, 0.95)
        - weightedPercentile(displayedLumas, 0.05)
      assert.ok(sourceRange === 0 || displayedRange / sourceRange >= 0.4,
        `${id} live tint retains only ${(100 * displayedRange / sourceRange).toFixed(1)}% luma range on ${theme}`)
    }
  }
})

test("release tree contains no generated caches or hook installer", () => {
  const paths = filesUnder(root).map((path) => relative(root, path).split(sep).join("/"))
  for (const path of paths) {
    assert.doesNotMatch(path, /(^|\/)__pycache__(\/|$)|\.py[co]$/,
      `generated Python cache in release tree: ${path}`)
    assert.doesNotMatch(path, /^tools\/grokchief-hooks?$/,
      `removed hook installer remains: ${path}`)
  }
})

test("documentation does not instruct users to create duplicate plugin entries", () => {
  const readme = read("README.md")
  assert.match(readme, /That is the entire setup\./)
  assert.doesNotMatch(readme, /bar\s*→\s*layout|hooks\s+(?:on|off)/i)
  assert.doesNotMatch(readme, /consoleAt|over the creature/i)
})

test("every local documentation link resolves", () => {
  const markdown = filesUnder(root).filter((path) => path.endsWith(".md"))
  for (const path of markdown) {
    const source = readFileSync(path, "utf8")
    for (const match of source.matchAll(/!?\[[^\]]*\]\(([^)]+)\)/g)) {
      const target = match[1].trim().split(/\s+["']/)[0]
      if (!target || target.startsWith("#") || /^[a-z][a-z0-9+.-]*:/i.test(target)) continue
      const local = decodeURI(target.split("#")[0])
      assert.ok(existsSync(resolve(dirname(path), local)),
        `${relative(root, path)} links to missing ${target}`)
    }
  }
})

test("cold-start harness isolates user configuration and asserts bundled art", () => {
  const source = read("tools/coldstart-check")
  for (const name of ["HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME"])
    assert.match(source, new RegExp(`\\b${name}=`), `${name} is not isolated`)
  assert.match(source, /PluginRegistry/)
  assert.match(source, /source: bundled/)
  // Both kinds of body, from inside the isolated install. The default is drawn,
  // and a check that only proved that would leave the whole spritesheet path —
  // discovery, the sheet, the grid — untested by the one test that runs a real
  // shell.
  assert.match(source, /pets\/bloub/)
  assert.match(source, /pets\/gritty/)
  assert.match(source, /drawn pet: bloub source: bundled/)
  assert.match(source, /sprite pet: gritty source: bundled/)
  assert.match(source, /legacy duplicates -> one bar entry/)
  assert.match(source, /retired file remains sealed on restart/)
  assert.match(source, /missing custom pet -> bundled bloub/)
  assert.match(source, /extreme config -> safe defaults/)
})
