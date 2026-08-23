// Omarchief's pure logic: no QML, no Quickshell, testable with plain node
// (`node --test tests/`).
//
// The chief's whole inner life reduces to a handful of read-only inputs —
// how much of the default agent's rate limits remain, whether agent windows
// exist, whether the Quake console is open, and what the agent hooks last
// reported — and this file turns those into a mood and a behavior.
// Everything visual stays in the QML.

function clamp01(v) {
  return Math.max(0, Math.min(1, v))
}

// Energy is the inverse of the most-constrained rate-limit window in the
// agent's usage record (the same records the first-party Agents widget
// reads). No record means no known limits, which reads as a well-rested
// chief.
function energyFromRecord(record) {
  if (!record || !Array.isArray(record.limits) || record.limits.length === 0) return 1
  var worst = 0
  for (var i = 0; i < record.limits.length; i++) {
    var p = Number(record.limits[i] && record.limits[i].percent)
    if (isFinite(p) && p > worst) worst = p
  }
  return clamp01(1 - worst)
}

// Agent-hook status (OmaPets-compatible: session/prompt/tool/permission/
// stop/error events written to status.json). A stale report is no report;
// the freshness windows mirror the ecosystem's detect-agent rules, with a
// short fuse for the transient celebrations.
var HOOK_MAX_AGE = { success: 8, error: 60, working: 14400, waiting: 14400 }

function freshHookState(hookState, hookAgeSec, hookAgent, defaultAgent) {
  if (!hookState || !(hookState in HOOK_MAX_AGE)) return ""
  if (hookAgent && defaultAgent && hookAgent !== defaultAgent) return ""
  var age = Number(hookAgeSec)
  if (!isFinite(age) || age < 0 || age > HOOK_MAX_AGE[hookState]) return ""
  return hookState
}

// Mood ladder, top wins. "parked" means an agent session exists but the
// console is closed — the chief holds a thought bubble so you remember it.
function resolveMood(inputs) {
  var energy = clamp01(Number(inputs.energy))
  var hook = freshHookState(inputs.hookState, inputs.hookAgeSec, inputs.hookAgent, inputs.defaultAgent)

  if (energy <= 0.02) return "sleeping"
  if (hook === "error") return "error"
  if (hook === "waiting") return "waiting"
  if (hook === "success") return "success"
  if (hook === "working") return "working"
  if (inputs.agentWindows > 0 && inputs.consoleOpen) return "working"
  if (inputs.agentWindows > 0) return "parked"
  if (energy < 0.3) return "tired"
  return "idle"
}

// What the speech bubble says, if anything. Hovering shows the tooltip
// instead; that override lives in the QML.
// A marker over the creature's head is for news. An agent session sitting
// in a closed console is not news — on a desktop that codes it is the
// normal state of affairs, and a permanent bubble for it is just a bubble
// that is always there.
function bubbleFor(mood) {
  if (mood === "waiting") return "!"
  if (mood === "success") return "✓"
  if (mood === "error") return "✗"
  return ""
}

// Logical pixels per second along the strip. Tiredness slows the walk the
// same way it slows everything else.
var SPEEDS = { idle: 34, tired: 20, working: 30, parked: 30, waiting: 48, success: 36, error: 24, sleeping: 0 }

function walkSpeed(mood, energy) {
  var base = SPEEDS[mood] !== undefined ? SPEEDS[mood] : 70
  return base * (0.5 + 0.5 * clamp01(energy))
}

// One decision per brain tick: what to do and when to think again.
// `rand` is a function so tests can seed it. `activity` scales the tempo
// (2 = twice as lively, 0.5 = half).
// A companion, not a screensaver: it mostly sits, and every once in a
// long while it strolls a little. Only a waiting agent earns urgency.
function decideAction(rand, mood, activity) {
  var mul = activity > 0 ? 1 / activity : 1
  var r = rand()
  var next = (12000 + rand() * 33000) * mul

  if (mood === "working") return { type: "sit", nextMs: next }
  if (mood === "error") return { type: "sit", nextMs: next * 1.2 }
  if (mood === "waiting") {
    if (r < 0.35) return { type: "hop", nextMs: next * 0.3 }
    return r < 0.5 ? { type: "wander", nextMs: next * 0.4 } : { type: "sit", nextMs: next * 0.4 }
  }
  if (mood === "tired") {
    return r < 0.08 ? { type: "wander", nextMs: next * 1.5 } : { type: "sit", nextMs: next * 1.5 }
  }
  if (mood === "parked") {
    return r < 0.15 ? { type: "wander", nextMs: next } : { type: "sit", nextMs: next }
  }
  // idle / success
  if (r < 0.18) return { type: "wander", nextMs: next }
  if (r < 0.25) return { type: "hop", nextMs: next }
  return { type: "sit", nextMs: next }
}

// ------------------------------------------------------------ sprite atlas
//
// The Codex/Petdex pet atlas: 8 columns of 192x208 frames, 9 rows (v1) or
// 11 (v2). Row semantics are fixed across the ecosystem; Omarchief uses the
// directional walk rows for actual walking, which bar pets never get to do.
var ATLAS = {
  columns: 8,
  frameAspect: 192 / 208,
  rows: {
    idle: { row: 0, frames: 6 },
    right: { row: 1, frames: 8 },
    left: { row: 2, frames: 8 },
    error: { row: 5, frames: 8 },
    waiting: { row: 6, frames: 6 },
    working: { row: 7, frames: 6 },
    success: { row: 8, frames: 6 }
  }
}

// Which atlas animation a mood plays. Walking overrides with a direction;
// sleeping freezes on idle's first frame (the QML dims it and floats the
// z's on top, so it works with any pet).
function spriteTrack(mood, walking, dir, sleepRow, walkFrames) {
  if (mood === "sleeping" && isFinite(Number(sleepRow)) && Number(sleepRow) >= 0)
    return { row: Number(sleepRow), frames: 6 }
  if (walking) {
    var base = dir < 0 ? ATLAS.rows.left : ATLAS.rows.right
    // A pet whose walk cycle is shorter than the atlas's eight columns says
    // so; playing the empty cells would stutter the gait.
    var n = Number(walkFrames)
    if (isFinite(n) && n >= 1 && n <= ATLAS.columns) return { row: base.row, frames: Math.floor(n) }
    return base
  }
  if (mood === "working") return ATLAS.rows.working
  if (mood === "waiting") return ATLAS.rows.waiting
  if (mood === "error") return ATLAS.rows.error
  if (mood === "success") return ATLAS.rows.success
  return ATLAS.rows.idle
}

// The shape of one cell, worked out from the sheet the pet actually ships
// rather than assumed. A sheet is ATLAS.columns wide and `rows` tall, so
// its natural size says everything.
// How many cells across a sheet is. Eight is the ecosystem's walk-cycle
// width; a pet that is a grid of faces rather than a strip of frames says
// so and is read on its own grid.
function spriteColumns(value) {
  var c = Number(value)
  return isFinite(c) && c >= 1 && c <= 64 ? Math.floor(c) : ATLAS.columns
}

function cellAspect(sheetWidth, sheetHeight, rows, columns) {
  var w = Number(sheetWidth), h = Number(sheetHeight), r = Number(rows)
  var c = spriteColumns(columns)
  if (!isFinite(w) || !isFinite(h) || !isFinite(r) || w <= 0 || h <= 0 || r <= 0)
    return ATLAS.frameAspect
  return (w / c) / (h / r)
}

// A pet may be a set of expressions instead of a set of animations: one
// drawing per mood, no motion of its own. `faces` maps a mood to the cell
// that shows it.
function readFaces(value, rows, columns) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  var cols = spriteColumns(columns)
  var out = {}, any = false
  for (var key in value) {
    var at = value[key]
    if (!Array.isArray(at) || at.length < 2) continue
    var r = Number(at[0]), c = Number(at[1])
    if (!isFinite(r) || !isFinite(c) || r < 0 || c < 0) continue
    if (rows && r >= Number(rows)) continue
    if (c >= cols) continue
    out[String(key)] = [Math.floor(r), Math.floor(c)]
    any = true
  }
  return any ? out : null
}

// Which drawing a mood wears. A pet need not have one for every mood; each
// falls back through what it is most likely to have, and everything ends at
// the resting face, which every pet has.
var FACE_FALLBACK = {
  idle: ["idle"],
  parked: ["parked", "idle"],
  tired: ["tired", "sleeping", "idle"],
  working: ["working", "idle"],
  waiting: ["waiting", "working", "idle"],
  success: ["success", "idle"],
  error: ["error", "idle"],
  sleeping: ["sleeping", "tired", "idle"],
  // Being picked up deserves its own reaction: it is the one thing a still
  // pet is ever asked to respond to.
  dragged: ["dragged", "love", "success", "idle"]
}

// Faces a resting creature may drift to on its own. A mood the agent drives
// means something — you do not want it looking alarmed for no reason — so a
// glance only ever borrows an expression that carries no news.
var IDLE_GLANCES = ["parked", "success", "love", "dragged"]

// Which drawings a resting creature may wear. An artist who says so in
// `idleFaces` decides it; otherwise the moods that carry no news are
// borrowed, which is a guess but a safe one. Either way the resting face
// itself is not a glance away from resting, and one drawing under two
// names is one expression.
function glanceFaces(faces, declared, rows, columns) {
  if (!faces) return []
  var pool = []
  if (Array.isArray(declared)) {
    var cells = readFaceList(declared, rows, columns)
    for (var d = 0; d < cells.length; d++) pool.push(cells[d])
  } else {
    for (var i = 0; i < IDLE_GLANCES.length; i++)
      if (faces[IDLE_GLANCES[i]]) pool.push(faces[IDLE_GLANCES[i]])
  }
  var out = []
  for (var k = 0; k < pool.length; k++) {
    var at = pool[k]
    if (faces.idle && faces.idle[0] === at[0] && faces.idle[1] === at[1]) continue
    var seen = false
    for (var j = 0; j < out.length; j++)
      if (out[j][0] === at[0] && out[j][1] === at[1]) { seen = true; break }
    if (!seen) out.push(at)
  }
  return out
}

// A plain list of cells, read as carefully as anything else out of a file
// somebody else wrote.
function readFaceList(value, rows, columns) {
  if (!Array.isArray(value)) return []
  var cols = spriteColumns(columns)
  var out = []
  for (var i = 0; i < value.length; i++) {
    var at = value[i]
    if (!Array.isArray(at) || at.length < 2) continue
    var r = Number(at[0]), c = Number(at[1])
    if (!isFinite(r) || !isFinite(c) || r < 0 || c < 0) continue
    if (rows && r >= Number(rows)) continue
    if (c >= cols) continue
    out.push([Math.floor(r), Math.floor(c)])
  }
  return out
}

// Whether to look up from resting, and at what. Rare enough that catching it
// feels like catching something, never while anything is actually happening.
function idleGlance(rand, faces, mood, chance, declared, rows, columns) {
  if (mood !== "idle" && mood !== "parked") return null
  var pool = glanceFaces(faces, declared, rows, columns)
  if (pool.length === 0) return null
  var odds = isFinite(Number(chance)) ? Number(chance) : 0.25
  if (odds <= 0 || rand() > odds) return null
  return pool[Math.min(pool.length - 1, Math.floor(rand() * pool.length))]
}

// A blink is the resting face with its eyes closed, so it may only
// interrupt the resting face. Blinking while the creature wears a mood of
// its own would flash somebody else's mouth for an eighth of a second —
// and a pet may well draw several moods with the same picture, so what
// counts is the drawing on screen, not the name of the mood.
function mayBlink(mood, faces, blink) {
  if (!blink || !faces) return false
  var here = faceFor(mood, faces)
  var rest = faceFor("idle", faces)
  if (!here || !rest) return false
  return here[0] === rest[0] && here[1] === rest[1]
}

// ---------------------------------------------------------------- the timer
//
// A creature with a screen for a face may as well use it. "25m", "90s",
// "1h30", "10" — the last meaning minutes, because that is what a bare
// number means when somebody asks for a timer.
function parseDuration(spec) {
  var text = String(spec === undefined || spec === null ? "" : spec).trim().toLowerCase()
  if (text === "") return null
  if (text === "stop" || text === "off" || text === "cancel" || text === "0") return 0
  var total = 0, saw = false
  var re = /(\d+(?:[.,]\d+)?)\s*(h|m|s|min|sec|hours?|minutes?|seconds?)?/g
  var m, tail = text.replace(/[\s]/g, "")
  if (!/^[\d.,hms a-z]+$/.test(text)) return null
  while ((m = re.exec(text)) !== null) {
    var n = Number(String(m[1]).replace(",", "."))
    if (!isFinite(n)) return null
    var unit = m[2] || ""
    var mult = unit.charAt(0) === "h" ? 3600 : unit.charAt(0) === "s" ? 1 : 60
    total += n * mult
    saw = true
  }
  if (!saw) return null
  total = Math.round(total)
  if (total <= 0) return 0
  // A day is more than a creature standing at the edge of a screen can
  // reasonably be asked to hold in its face.
  return Math.min(total, 24 * 3600)
}

// What the face shows. Whole minutes while there is more than a minute
// left, because two big digits read across a room and "24:59" does not;
// seconds under it, where every one of them counts.
function timerFace(msLeft) {
  var left = Math.max(0, Math.ceil(Number(msLeft || 0) / 1000))
  if (left <= 0) return ""
  if (left < 60) return String(left)
  if (left < 3600) return String(Math.ceil(left / 60))
  var hours = Math.floor(left / 3600)
  var mins = Math.ceil((left - hours * 3600) / 60)
  if (mins === 60) return String(hours + 1) + "h"
  return String(hours) + ":" + (mins < 10 ? "0" : "") + String(mins)
}

// The same thing said in words, for the bar and the tooltip.
function timerWords(msLeft) {
  var left = Math.max(0, Math.ceil(Number(msLeft || 0) / 1000))
  if (left <= 0) return ""
  if (left < 60) return left + "s left"
  var mins = Math.ceil(left / 60)
  if (mins < 60) return mins + " min left"
  var hours = Math.floor(mins / 60)
  return hours + "h " + (mins - hours * 60) + "m left"
}

// How long it holds that look before going back to resting.
function glanceMs(rand) {
  return Math.round(2200 + rand() * 2600)
}

// A creature drawn in profile faces one way and trails its cable the other.
// Standing on the right of the screen it looks off the edge with its cable
// lying across the room, which is backwards. Turning it around there keeps
// the face pointed inwards and the cable running off the nearer edge.
//
// Only artwork that says it may be flipped is flipped: a front view gains
// nothing by it, and anything with writing on it would read backwards.
// Words for how often, because nobody thinks in tenths.
function oftenName(chance) {
  var c = Number(chance)
  if (!isFinite(c) || c <= 0) return "never"
  if (c < 0.18) return "rarely"
  if (c < 0.38) return "now and then"
  return "often"
}

// How long a conversation lasts before the next order starts a new one.
// Zero means it does not end on its own — you are talking to the same
// session tomorrow, which is what most people mean by talking to something.
function sessionLifeMs(minutes) {
  var m = Number(minutes)
  if (!isFinite(m) || m <= 0) return 0
  return Math.round(m) * 60000
}

// A session id belongs to one agent: claude's means nothing to codex. The
// file keeps one per agent so switching back and forth does not lose either.
function readSessions(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return ({})
  var out = ({})
  for (var agent in value) {
    var id = value[agent]
    if (typeof id === "string" && id !== "" && String(agent) !== "") out[String(agent)] = id
  }
  return out
}

// Which special workspace the console lives on.
//
// Omarchy presents one as a Quake console — dimmed, half a screen, seeded
// with your default agent the first time it drops. Which workspace that is
// has already moved once and may move again: it began as `scratchpad`, and
// there is an open proposal to give the console its own `qconsole` so the
// plain scratchpad stays plain. Rather than guess, read it out of Omarchy's
// own file, where the seed line names the workspace it pins the agent to.
function consoleWorkspace(qconsoleLua, fallback) {
  var text = String(qconsoleLua || "")
  var found = text.match(/special:([A-Za-z0-9_-]+)/)
  if (found) return found[1]
  var back = String(fallback || "")
  return back !== "" ? back : "scratchpad"
}

function mirroredAt(px, screenWidth) {
  var x = Number(px), w = Number(screenWidth)
  if (!isFinite(x) || !isFinite(w) || w <= 0) return false
  return x > w / 2
}

function faceFor(mood, faces) {
  if (!faces) return null
  var chain = FACE_FALLBACK[String(mood)] || ["idle"]
  for (var i = 0; i < chain.length; i++)
    if (faces[chain[i]]) return faces[chain[i]]
  if (faces.idle) return faces.idle
  for (var any in faces) return faces[any]
  return null
}

function atlasRowCount(spriteVersionNumber) {
  return Number(spriteVersionNumber || 1) >= 2 ? 11 : 9
}


// ------------------------------------------------------------ the world
//
// The chief treats the whole monitor arrangement as one walkable world.
// Segments are the monitors in wayland virtual coordinates, sorted left to
// right; a position is (monitor, localX), and travel between monitors is a
// dive under the bottom edge, a stretch of underground distance, and a rise
// on the target screen.

function worldSegments(screens) {
  var list = []
  for (var i = 0; i < (screens ? screens.length : 0); i++) {
    var s = screens[i]
    if (!s || !s.name) continue
    var x = Number(s.x)
    var w = Number(s.width)
    if (!isFinite(x) || !isFinite(w) || w <= 0) continue
    list.push({ name: String(s.name), x: x, w: w })
  }
  list.sort(function(a, b) { return a.x - b.x })
  return list
}

function segmentByName(segments, name) {
  for (var i = 0; i < segments.length; i++)
    if (segments[i].name === name) return segments[i]
  return null
}

// How long the underground stretch of a journey takes. Dive and rise have
// their own fixed animations; this is only the in-between, scaled by real
// distance so a hop to the neighbor feels different from a trek across
// three screens.
function travelPlan(segments, fromName, fromLocalX, toName, toLocalFrac) {
  var from = segmentByName(segments, fromName)
  var to = segmentByName(segments, toName)
  if (!to) return null
  var frac = isFinite(Number(toLocalFrac)) ? Math.max(0.05, Math.min(0.95, Number(toLocalFrac))) : 0.5
  var targetLocal = to.w * frac
  var fromWorld = from ? from.x + Number(fromLocalX || 0) : to.x
  var dist = Math.abs((to.x + targetLocal) - fromWorld)
  var underground = Math.max(350, Math.min(2200, dist / 1.6))
  return { targetLocal: targetLocal, undergroundMs: Math.round(underground) }
}

// ------------------------------------------------------------ talking
//
// The chief speaks for itself: orders run through the default agent's
// headless mode and the reply lands in a speech bubble. Sessions carry
// over — a follow-up resumes the same conversation, and escalating to the
// Quake console resumes it interactively. Agents without a headless
// adapter fall back to the console path.

// Which agents the creature can hold a conversation with. The rest still
// work — an order opens the console with them — but the speech bubble
// needs a runner that streams its answer out in a shape we can read.
function canTalkTo(agent) {
  return buildTalkCommand(String(agent || ""), "x", null) !== null
}

// The standing instructions ride differently per agent. Claude takes them as
// a true system prompt, passed on every call: they never scroll out of reach
// in a long conversation, and the console — launched without them — answers
// the same conversation at full length instead of in bubble-sized clips. The
// other two have no such flag, so there the first order of a session carries
// them inline, once.
function buildTalkCommand(agent, order, sessionId, preamble) {
  var lead = String(preamble || "")
  var prompt = sessionId || lead === "" || agent === "claude"
    ? order : lead + "\n\nOrder: " + order
  if (agent === "claude") {
    var argv = ["claude", "-p"]
    if (sessionId) argv.push("--resume", sessionId)
    argv.push(prompt, "--permission-mode", "bypassPermissions", "--output-format", "stream-json", "--verbose")
    if (lead !== "") argv.push("--append-system-prompt", lead)
    return argv
  }
  if (agent === "opencode") {
    var oc = ["opencode", "run", "--format", "json"]
    if (sessionId) oc.push("-s", sessionId)
    oc.push(prompt)
    return oc
  }
  if (agent === "codex") {
    var cx = ["codex", "exec"]
    if (sessionId) cx.push("resume", sessionId)
    cx.push("--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check", "--json", prompt)
    return cx
  }
  return null
}

function buildConsoleResume(agent, sessionId) {
  if (agent === "claude" && sessionId)
    return ["claude", "--permission-mode", "bypassPermissions", "--resume", sessionId]
  if (agent === "codex" && sessionId)
    return ["codex", "resume", sessionId, "--dangerously-bypass-approvals-and-sandbox"]
  // `opencode --session <id>` opens the TUI on that conversation; `--auto`
  // is what omarchy-agent passes so it does not stop to ask.
  if (agent === "opencode" && sessionId)
    return ["opencode", "--auto", "--session", sessionId]
  return null
}

// One NDJSON line of headless-agent output into what the bubble needs,
// dispatched per agent. Non-JSON noise (version-manager shims love stdout)
// parses to null and is dropped.
// What an agent is doing, said the way a person would say it. Agents
// narrate their work as tool calls — read this file, run that command —
// and a bubble that says "Reading ChiefPanel.qml" while the creature digs
// is worth more than three dots. Claude writes a description of its own
// for shell commands, which is better than anything derived; the rest is
// built from the tool's name and the one argument that matters.
function baseName(path) {
  var p = String(path || "")
  var i = p.lastIndexOf("/")
  return i >= 0 ? p.slice(i + 1) : p
}

function hostOf(url) {
  var m = String(url || "").match(/^[a-z]+:\/\/([^\/?#]+)/i)
  return m ? m[1] : String(url || "")
}

function shortCommand(cmd) {
  var c = String(cmd || "").replace(/^\/usr\/bin\/bash -lc '(.*)'$/, "$1")
  c = c.replace(/\s+/g, " ").trim()
  return c.length > 48 ? c.slice(0, 47) + "…" : c
}

function describeTool(name, input) {
  var n = String(name || ""), a = input && typeof input === "object" ? input : {}
  if (a.description) return String(a.description)
  switch (n) {
    case "Read": return "Reading " + baseName(a.file_path)
    case "Edit": case "MultiEdit": case "Write": case "NotebookEdit": return "Editing " + baseName(a.file_path)
    case "Grep": return "Searching for " + String(a.pattern || "")
    case "Glob": return "Looking for " + String(a.pattern || "")
    case "LS": return "Listing " + baseName(a.path || ".")
    case "WebFetch": return "Fetching " + hostOf(a.url)
    case "WebSearch": return "Searching the web"
    case "Agent": case "Task": return a.description ? String(a.description) : "Delegating"
    case "Bash": return "Running " + shortCommand(a.command)
    case "TodoWrite": return "Planning"
  }
  return n !== "" ? n : ""
}

function parseTalkLine(agent, line) {
  if (agent === "opencode") return parseOpencodeLine(line)
  if (agent === "codex") return parseCodexLine(line)
  return parseClaudeLine(line)
}

// opencode `run --format json` events. Sampled verbatim:
//   {"type":"text","sessionID":"ses_fd9694…","part":{"type":"text","text":"OK",…}}
//   {"type":"step_finish","timestamp":…,"sessionID":"ses_fd9694…",…}
// The run process lingers after step_finish (session keep-alive, even
// synthetic compaction notes), so step_finish is the turn's true end and
// the caller must reap the process itself.
function parseOpencodeLine(line) {
  var d
  try { d = JSON.parse(String(line || "")) } catch (e) { return null }
  if (!d || typeof d !== "object") return null
  if (d.type === "text" && d.part && d.part.type === "text" && d.part.text && !d.part.synthetic)
    return { kind: "text", text: String(d.part.text) }
  // A step is not a turn: a single order can run eleven of them, and the
  // run process keeps its session alive long after the last one. So a
  // finished step only means "this could be the end" — silence decides.
  if (d.type === "step_finish")
    return { kind: "maybe_end", sessionId: String(d.sessionID || "") }
  if (d.type === "step_start" && d.sessionID)
    return { kind: "session", sessionId: String(d.sessionID) }
  // A tool part carries the tool's name and its input; what it is doing is
  // the title when the runner wrote one, else derived from the input.
  if (d.type === "tool" && d.part && typeof d.part === "object") {
    var st = d.part.state && typeof d.part.state === "object" ? d.part.state : {}
    var title = st.title ? String(st.title) : describeTool(opencodeToolName(d.part.tool), st.input)
    if (title !== "") return { kind: "doing", text: title }
  }
  // The runner reports a failed request as an event of its own — a spent
  // quota, a model that does not exist — and says nothing else afterwards.
  // Sampled verbatim: {"type":"error","error":{"name":"APIError","data":{"message":"You have exceeded your monthly quota","statusCode":402}}}
  if (d.type === "error") {
    var e = d.error && typeof d.error === "object" ? d.error : {}
    var data = e.data && typeof e.data === "object" ? e.data : {}
    var msg = String(data.message || e.message || e.name || "the agent reported an error")
    return { kind: "result", ok: false, text: msg, sessionId: String(d.sessionID || "") }
  }
  return null
}

function opencodeToolName(tool) {
  var t = String(tool || "").toLowerCase()
  if (t === "read") return "Read"
  if (t === "edit" || t === "write" || t === "patch") return "Edit"
  if (t === "grep") return "Grep"
  if (t === "glob") return "Glob"
  if (t === "bash") return "Bash"
  if (t === "webfetch") return "WebFetch"
  if (t === "websearch") return "WebSearch"
  if (t === "list") return "LS"
  return tool ? String(tool) : ""
}

// codex `exec --json` events. Sampled verbatim:
//   {"type":"thread.started","thread_id":"01a02698-aab4-…"}
//   {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}
//   {"type":"turn.completed","usage":{…}}
// The thread id arrives long before the turn ends, so it travels as its
// own record; turn.failed is the documented error twin of turn.completed.
function parseCodexLine(line) {
  var d
  try { d = JSON.parse(String(line || "")) } catch (e) { return null }
  if (!d || typeof d !== "object") return null
  if (d.type === "thread.started" && d.thread_id)
    return { kind: "session", sessionId: String(d.thread_id) }
  // Sampled verbatim: {"type":"item.started","item":{"type":"command_execution","command":"/usr/bin/bash -lc 'wc -l data.txt'","status":"in_progress"}}
  if (d.type === "item.started" && d.item && typeof d.item === "object") {
    var it = d.item
    if (it.type === "command_execution") return { kind: "doing", text: "Running " + shortCommand(it.command) }
    if (it.type === "file_change") return { kind: "doing", text: "Editing files" }
    if (it.type === "web_search") return { kind: "doing", text: "Searching the web" }
    if (it.type === "reasoning") return { kind: "doing", text: "Thinking" }
  }
  if (d.type === "item.completed" && d.item && d.item.type === "agent_message" && d.item.text)
    return { kind: "text", text: String(d.item.text) }
  if (d.type === "turn.completed")
    return { kind: "result", ok: true, text: "", sessionId: "" }
  if (d.type === "turn.failed")
    return { kind: "result", ok: false, text: String((d.error && d.error.message) || ""), sessionId: "" }
  return null
}

// Claude's `--output-format stream-json --verbose` events.
function parseClaudeLine(line) {
  var d
  try { d = JSON.parse(String(line || "")) } catch (e) { return null }
  if (!d || typeof d !== "object") return null
  if (d.type === "assistant" && d.message && Array.isArray(d.message.content)) {
    var text = ""
    var doing = ""
    for (var i = 0; i < d.message.content.length; i++) {
      var c = d.message.content[i]
      if (c && c.type === "text" && c.text) text += c.text
      // Sampled verbatim: {"type":"tool_use","name":"Bash","input":{"command":"cat notes.txt","description":"Read notes.txt"}}
      if (c && c.type === "tool_use" && doing === "") doing = describeTool(c.name, c.input)
    }
    if (text !== "") return { kind: "text", text: text }
    if (doing !== "") return { kind: "doing", text: doing }
    return null
  }
  if (d.type === "result") {
    return {
      kind: "result",
      ok: d.subtype === "success" && !d.is_error,
      text: typeof d.result === "string" ? d.result : "",
      sessionId: String(d.session_id || "")
    }
  }
  return null
}

// Bubble text stays bubble-sized: collapse the whitespace, cap the length,
// and point at the console when there is more.
// Agents are asked for plain prose, but markdown is a habit, and a bubble
// full of asterisks and pound signs reads as a bug. The habit is undone
// here rather than trusted away. Structure survives as punctuation: a
// heading becomes a sentence of its own, a list a run of clauses.
function plainSpeech(text) {
  var t = String(text === undefined || text === null ? "" : text).replace(/\r\n?/g, "\n")
  t = t.replace(/```[a-zA-Z0-9_-]*\n?([\s\S]*?)```/g, "$1")
  t = t.replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
  t = t.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
  t = t.replace(/^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$/gm, "$1.")
  t = t.replace(/^\s{0,3}>\s?/gm, "")
  t = t.replace(/^\s*([-*+]|\d+[.)])\s+/gm, "\u00b7 ")
  t = t.replace(/^\s*([-*_]\s*){3,}$/gm, "")
  t = t.replace(/(\*\*|__)(?=\S)([\s\S]*?\S)\1/g, "$2")
  t = t.replace(/(^|[^\w*])\*(?=\S)([^*\n]*?\S)\*(?![\w*])/g, "$1$2")
  t = t.replace(/(^|[^\w_])_(?=\S)([^_\n]*?\S)_(?![\w_])/g, "$1$2")
  t = t.replace(/`([^`\n]*)`/g, "$1")
  t = t.replace(/<\/?[a-zA-Z][^>]*>/g, "")
  return t.trim()
}

function shapeBubbleText(text, maxChars) {
  var t = plainSpeech(text).replace(/\s+/g, " ").trim()
  var cap = isFinite(Number(maxChars)) && Number(maxChars) > 20 ? Number(maxChars) : 260
  if (t.length <= cap) return t
  return t.slice(0, cap - 1).replace(/\s+\S*$/, "") + "…"
}


// How long an answer stays up: long enough to read at an easy pace, never
// so long that a bubble looks stuck. A person reads about a thousand
// characters a minute; the floor covers a glance back from another window.
function readingTimeMs(text) {
  var n = String(text || "").length
  return Math.max(4000, Math.min(45000, 3500 + n * 60))
}

// A runner that exits at once without a word has not refused the order, it
// has stumbled: a dropped connection, a model that returned nothing. One
// more try costs a second and catches most of those. Anything that said
// something, or took its time, was a real turn and is not repeated.
function shouldRetryTalk(elapsedMs, sawOutput, retried) {
  var t = Number(elapsedMs)
  return !retried && !sawOutput && isFinite(t) && t >= 0 && t < 4000
}

// The stamp left beside a themed sheet names the accent it was drawn for,
// then the size and age of the artwork it came from. Only the accent is
// judged here; the shell compares the rest before deciding to redraw.
function themeStampMatches(stamp, accent, background) {
  var parts = String(stamp || "").trim().split(/\s+/)
  if (parts[0] === "" || parts[0] !== String(accent || "")) return false
  // The desktop the sheet was lifted against counts too, and old stamps
  // that never named one are simply out of date.
  var want = String(background || "")
  return want === "" || parts[1] === want
}

// How tall the creature stands: the person's word first, the artist's
// recommendation second, OmaPets' 56 pixels when neither spoke.
function resolvePetSize(configured, recommended) {
  var c = Number(configured), r = Number(recommended)
  var v = isFinite(c) && c > 0 ? c : (isFinite(r) && r > 0 ? r : 56)
  return Math.max(32, Math.min(240, Math.round(v)))
}

// A press becomes a drag once it has travelled far enough that it cannot
// have been meant as a click. Anything shorter is a click, however long
// the finger rested.
var DRAG_THRESHOLD = 4

function isDrag(movedPx) {
  return Math.abs(Number(movedPx) || 0) >= DRAG_THRESHOLD
}

// Where a press lands the creature, kept inside the screen's own edges.
// How much of a tucked creature is still on screen. It sinks into the edge
// it stands on rather than sliding along it: the point is to read what is
// behind it, and a creature that travels the width of the screen to hide
// has left the place you put it. What stays up is the top of its head —
// a share of its height, but never fewer pixels than a person can hit.
function peekHeight(petSize) {
  var size = Number(petSize)
  if (!isFinite(size) || size <= 0) size = 56
  return Math.max(14, Math.round(size * 0.13))
}



// How far a drag may carry it. Not to the edge and no further: pushing it
// hard against a side is how you park it there, so the travel goes on until
// only a peek of it would be left on screen.
function dragTo(startX, movedPx, width, petSize) {
  var edge = (Number(petSize) || 56) * 0.3
  var x = Number(startX || 0) + Number(movedPx || 0)
  return Math.round(Math.max(edge, Math.min((Number(width) || 0) - edge, x)))
}

// Pushing it past where it can go is how you ask for it to be put away
// there, and how far you have got comes back as a fraction so the creature
// can follow your hand rather than snapping when an invisible line is
// crossed.
//
// What counts is never a fixed distance. The creature stops; the hand keeps
// going; and how much further the hand *can* go is decided by where it took
// hold and how close that is to the edge of the screen. A creature standing
// in the corner has barely any room at all — asking for a fixed eighty-five
// pixels there made the gesture impossible, which is exactly where it is
// most wanted. So the distance asked for is the distance available.
//
// A double-click would have been the obvious gesture and is the wrong one:
// the first of the two clicks already opens the order form or clears a
// standing reply, so by the time the second arrives the scene has changed
// under it and the gesture only works sometimes.
function shoveProgress(grabPx, grabX, grabY, movedX, movedY, width, height, petSize, only) {
  var size = Number(petSize) || 56
  var edge = size * 0.3
  var margin = size * 0.15
  var least = 12
  var w = Number(width) || 0
  var h = Number(height) || 0
  var px = Number(grabPx) || 0
  var gy = Number(grabY) || 0
  var hold = (Number(grabX) || 0) - px   // where on the creature it was taken hold of
  var raw = px + (Number(movedX) || 0)   // where it would stand if nothing stopped it
  var down = Number(movedY) || 0
  var across = Math.abs(Number(movedX) || 0)

  function toLeft() {
    if (raw >= edge) return 0
    return Math.min(1, (edge - raw) / Math.max(least, edge + hold - margin))
  }
  function toRight() {
    if (raw <= w - edge) return 0
    return Math.min(1, (raw - (w - edge)) / Math.max(least, edge - hold - margin))
  }
  // `settled` means a downward shove is already under way, so the hand may
  // wander back without the gesture being called off — it simply gives back
  // what it has taken. Deciding afresh on every mouse move made the creature
  // stutter around the threshold, animation snapping on and off with it.
  function toFloor(settled) {
    if (down <= 0) return 0
    if (!settled && (down < least || across > down)) return 0
    if (gy + down >= h - 6) return 1
    return Math.min(1, down / Math.max(least, h - gy - margin))
  }

  if (only === "left") return { side: "left", progress: toLeft() }
  if (only === "right") return { side: "right", progress: toRight() }
  if (only === "down") return { side: "down", progress: toFloor(true) }

  var l = toLeft()
  if (l > 0) return { side: "left", progress: l }
  var r = toRight()
  if (r > 0) return { side: "right", progress: r }
  var d = toFloor(false)
  if (d > 0) return { side: "down", progress: d }
  return { side: "", progress: 0 }
}

// Where a creature put away against a side or into the floor is drawn.
//
// Measured against what is actually drawn, not against the cell it is drawn
// in. A sprite cell has margins — gritty's resting picture stops thirty
// pixels short of its own right edge — so leaving "a cell's worth of peek"
// showing left nothing but transparency at the screen edge, and the
// creature vanished completely.
function sideTuckShift(bodyX, bodyWidth, screenWidth, peek, contentLeft, contentRight, side) {
  var x = Number(bodyX) || 0
  var bw = Number(bodyWidth) || 0
  var l = isFinite(Number(contentLeft)) ? Number(contentLeft) : 0
  var r = isFinite(Number(contentRight)) ? Number(contentRight) : 1
  var p = Number(peek) || 0
  if (side === "left") return Math.round(p - (x + bw * r))
  if (side === "right") return Math.round((Number(screenWidth) || 0) - p - (x + bw * l))
  return 0
}

// The same, downwards: enough that only the top of its head is above the
// edge it stands on.
function sinkShift(bodyY, bodyHeight, screenHeight, peek, contentTop) {
  var y = Number(bodyY) || 0
  var bh = Number(bodyHeight) || 0
  var t = isFinite(Number(contentTop)) ? Number(contentTop) : 0
  var drawnTop = y + bh * t
  return Math.max(0, Math.round((Number(screenHeight) || 0) - (Number(peek) || 0) - drawnTop))
}





// Whether an activity may begin. It is a small surprise, not an
// interruption: it waits for a rested creature that is idle, standing
// still, with nothing asked of it.
// The moods in which the creature has nothing pressing to do. An agent
// window merely being open is one of them: that is a desk with someone
// sitting at it, not a job in progress — and since a coding desktop nearly
// always has one open, requiring a bare "idle" meant the performances
// never ran at all.
var CALM_MOODS = ["idle", "parked", "success", "tired"]

function isCalmMood(mood) {
  return CALM_MOODS.indexOf(String(mood)) !== -1
}

function mayPlayActivity(state) {
  if (!state || !state.onStage || state.promptOpen || state.walking || state.dragging) return false
  if (!isCalmMood(state.mood)) return false
  return state.rested !== false
}

// ------------------------------------------------------------ theme tinting
//
// Colorizing a sprite with the theme's accent is only kind to the artwork
// when the accent can actually be seen: vantablack's accent is a mid grey on
// pure black, which turns a bright pet into a dim smudge. These helpers lift
// the tint until it clears a contrast floor against the theme background,
// following the WCAG relative-luminance definition.

function srgbToLinear(v) {
  return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}

function relLuminance(c) {
  return 0.2126 * srgbToLinear(c.r) + 0.7152 * srgbToLinear(c.g) + 0.0722 * srgbToLinear(c.b)
}

function contrastRatio(a, b) {
  var la = relLuminance(a), lb = relLuminance(b)
  var hi = Math.max(la, lb), lo = Math.min(la, lb)
  return (hi + 0.05) / (lo + 0.05)
}

function mix(c, target, t) {
  return { r: c.r + (target.r - c.r) * t, g: c.g + (target.g - c.g) * t, b: c.b + (target.b - c.b) * t }
}

// Walk the tint toward white (on a dark desktop) or black (on a light one)
// until it clears `minRatio`, then stop — the least change that is legible.
function contrastSafe(color, background, minRatio) {
  var floor = isFinite(Number(minRatio)) && Number(minRatio) > 1 ? Number(minRatio) : 4.5
  var target = relLuminance(background) < 0.5 ? { r: 1, g: 1, b: 1 } : { r: 0, g: 0, b: 0 }
  var out = { r: color.r, g: color.g, b: color.b }
  for (var i = 0; i < 20; i++) {
    if (contrastRatio(out, background) >= floor) return out
    out = mix(out, target, 0.12)
  }
  return out
}

// pet.json and omarchief.json both spell tinting as true/false/0..1; this is
// the one place that decides what a value means.
// Which of the two theming paths applies. A pet that named its own hue
// window is redrawn properly when that is possible; the live tint is what
// remains when it is not, or what an explicit setting asked for.
function tintFor(themeable, canRedraw, requested) {
  if (themeable !== null && themeable !== undefined && canRedraw) return 0
  var asked = Number(requested)
  if (isFinite(asked) && asked > 0) return asked
  return themeable !== null && themeable !== undefined ? 0.7 : 0
}

function tintStrength(value, fallback) {
  if (value === true) return 0.7
  if (value === false || value === null || value === undefined) return isFinite(Number(fallback)) ? Number(fallback) : 0
  var n = Number(value)
  if (!isFinite(n)) return 0
  return Math.max(0, Math.min(1, n))
}


// pet.json may spell `themeable` as true or as a window object; this keeps
// the two spellings honest in one place.
function isThemeableSpec(value) {
  if (!value || typeof value !== "object") return false
  var keys = ["hueMin", "hueMax", "satMin"]
  for (var i = 0; i < keys.length; i++) {
    if (value[keys[i]] === undefined) continue
    var n = Number(value[keys[i]])
    if (!isFinite(n) || n < 0) return false
  }
  return true
}


// Text on its way into a shell. Orders are written by a person and can
// contain anything a person types; single quotes are the only character a
// POSIX shell will not reinterpret inside them, so the string is wrapped in
// them and its own quotes are broken out and escaped.
function shellQuote(value) {
  return "'" + String(value === undefined || value === null ? "" : value).replace(/'/g, "'\\''") + "'"
}

// Hyprland's dispatcher takes Lua now, so anything handed to it has to be a
// Lua string literal rather than a bare word.
function luaStr(value) {
  return '"' + String(value === undefined || value === null ? "" : value)
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "") + '"'
}

function dispatchExec(command) { return "hl.dsp.exec_cmd(" + luaStr(command) + ")" }
function dispatchToggleSpecial(name) { return "hl.dsp.workspace.toggle_special(" + luaStr(name) + ")" }
function dispatchFocusMonitor(name) { return "hl.dsp.focus({monitor=" + luaStr(name) + "})" }


// Where a window should open so it sits above the creature rather than
// wherever the compositor felt like putting it. Coordinates are virtual
// desktop pixels; the window is kept fully on its own screen.
function consolePlacement(segment, localX, screenHeight, size, margin) {
  if (!segment) return null
  var w = Math.max(200, Math.round(size && size.width ? size.width : 1000))
  var h = Math.max(150, Math.round(size && size.height ? size.height : 560))
  var gap = isFinite(Number(margin)) ? Number(margin) : 24
  var x = segment.x + Math.round(Number(localX || segment.w / 2)) - Math.round(w / 2)
  x = Math.max(segment.x + gap, Math.min(segment.x + segment.w - w - gap, x))
  var y = Math.max(gap, Math.round(Number(screenHeight || 0) - h - gap))
  return { x: Math.round(x), y: y, width: w, height: h }
}

function placementRule(placement) {
  if (!placement) return ""
  return "float; size " + placement.width + " " + placement.height
    + "; move " + placement.x + " " + placement.y + "; "
}


// Idle activities live in rows past the standard atlas and are named by
// pet.json. A pet without them simply never has one to pick.
// Rows whose frames are all the same picture. Animating one repaints
// identical pixels for as long as the desktop is on.
function readStillRows(value, rows) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var r = Number(value[i])
    if (isFinite(r) && r >= 0 && (!rows || r < rows)) out.push(Math.floor(r))
  }
  return out
}

function isStillRow(stillRows, row) {
  return Array.isArray(stillRows) && stillRows.indexOf(Number(row)) !== -1
}

function readActivities(value, rows) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var a = value[i] || {}
    var row = Number(a.row), frames = Number(a.frames)
    if (!isFinite(row) || row < 0 || (rows && row >= rows)) continue
    if (!isFinite(frames) || frames < 1 || frames > ATLAS.columns) continue
    frames = Math.floor(frames)
    // The hold times are the whole reason a performance reads as a story
    // rather than a flip-book, and they were being dropped on the floor
    // here: every frame fell back to the same default, so six carefully
    // measured beats all ran at exactly the same speed. A hold of zero or
    // nonsense still falls back, one frame at a time.
    var holds = null
    if (Array.isArray(a.holds)) {
      holds = []
      for (var f = 0; f < frames; f++) {
        var h = Number(a.holds[f])
        holds.push(isFinite(h) && h > 0 ? Math.min(10000, Math.round(h)) : 0)
      }
    }
    out.push({ name: String(a.name || ("row" + row)), row: Math.floor(row), frames: frames, holds: holds })
  }
  return out
}

// Pick something to do — but not the same thing twice in a row, and not
// so often that it stops being a surprise. `recent` is what was played
// last; it is skipped unless it is the only thing this pet knows.
function pickActivity(rand, activities, chance, recent) {
  if (!Array.isArray(activities) || activities.length === 0) return null
  var odds = isFinite(Number(chance)) ? Number(chance) : 0.4
  if (rand() > odds) return null
  var pool = activities
  if (recent && activities.length > 1)
    pool = activities.filter(function(a) { return a.name !== recent })
  if (pool.length === 0) return null
  return pool[Math.min(pool.length - 1, Math.floor(rand() * pool.length))]
}

// How long an activity takes from first frame to last, so the creature can
// wait a decent while before doing anything else.
// A performance of three seconds in the corner of a screen is one nobody
// ever sees. Short rows are played more than once so the whole thing lasts
// long enough to be noticed and understood, without slowing the drawing
// down into a slideshow.
// Six drawn poses with hard cuts between them is a slideshow, however
// slowly it runs. A dissolve makes them read as one continuous motion —
// but only where there is time for one: a walk cycle changes frames every
// seventh of a second, and smearing those together turns a gait into mush.
// So the dissolve is a fraction of the hold, and below a quarter second
// there is none at all.
function crossfadeMs(holdMs) {
  var h = Number(holdMs)
  if (!isFinite(h) || h < 250) return 0
  return Math.max(60, Math.min(260, Math.round(h * 0.22)))
}

function activityRepeats(activity, targetMs, onePassMs) {
  var one = Number(onePassMs)
  if (!isFinite(one) || one <= 0) return 1
  var target = isFinite(Number(targetMs)) && Number(targetMs) > 0 ? Number(targetMs) : 9000
  return Math.max(1, Math.min(4, Math.round(target / one)))
}

function activityDuration(activity, fallback) {
  var base = isFinite(Number(fallback)) && Number(fallback) > 0 ? Number(fallback) : 560
  if (!activity) return 0
  var frames = Number(activity.frames) || 0
  if (!Array.isArray(activity.holds)) return frames * base
  var total = 0
  for (var i = 0; i < frames; i++) total += activityHold(activity, i, base)
  return total
}

// Where the creature stands when nobody has moved it: down in the left
// corner, far enough out that the cable it trails runs off the screen.
// Where the creature stands on each screen. Homes are stored per monitor,
// because a spot chosen on a wide screen means nothing on a narrow one, and
// a monitor that has since been unplugged should not drag the creature to a
// position that no longer exists.
// Which screen the creature lives on. A pet that cannot walk has no way to
// cross to another one, so where you left it has to survive a restart —
// otherwise it comes back wherever the focus happened to be and there is no
// way to send it home but an IPC call.
function homeMonitor(value, segments) {
  if (!value || typeof value !== "object") return ""
  var name = String(value.monitor || "")
  if (name === "" || !Array.isArray(segments)) return ""
  for (var i = 0; i < segments.length; i++)
    if (segments[i] && segments[i].name === name) return name
  return ""
}

function readHomes(value) {
  if (!value || typeof value !== "object") return {}
  var out = {}
  // The first version of this file held one position and the monitor it was
  // chosen on. Read it as what it meant rather than discarding somebody's
  // placement on an upgrade.
  if (typeof value.monitor === "string" && isFinite(Number(value.x))) {
    if (value.monitor !== "" && Number(value.x) >= 0) out[value.monitor] = Number(value.x)
    return out
  }
  var source = value.monitors && typeof value.monitors === "object" ? value.monitors : value
  for (var name in source) {
    var x = Number(source[name])
    if (String(name) !== "" && isFinite(x) && x >= 0) out[String(name)] = x
  }
  return out
}

// The home for one screen, clamped so a position saved on a wider monitor
// still lands somewhere sensible on a narrower one.
function homeFor(homes, monitor, screenWidth, petSize, gapLeft) {
  var edge = Number(petSize || 56) * 0.3
  var width = Number(screenWidth || 0)
  var stored = homes && homes[monitor]
  var x = isFinite(Number(stored)) ? Number(stored) : defaultHomeX(petSize, gapLeft)
  if (width > 2 * edge) x = Math.max(edge, Math.min(width - edge, x))
  return Math.round(x)
}

function defaultHomeX(petSize, gapLeft) {
  var size = Number(petSize || 56)
  var gap = isFinite(Number(gapLeft)) ? Number(gapLeft) : 0
  // Line the creature's own left edge up with where a window's edge would
  // be; the cable it trails then runs on into the gap, which is exactly
  // where a cable belongs.
  return Math.round(Math.max(8, gap + size * 0.46))
}

// Hyprland reports its gaps as CSS shorthand: one, two or four numbers in
// the order top, right, bottom, left.
function parseGapsCss(css) {
  var parts = String(css || "").trim().split(/\s+/).map(Number).filter(function(n) { return isFinite(n) })
  if (parts.length === 0) return { top: 0, right: 0, bottom: 0, left: 0 }
  if (parts.length === 1) return { top: parts[0], right: parts[0], bottom: parts[0], left: parts[0] }
  if (parts.length === 2) return { top: parts[0], right: parts[1], bottom: parts[0], left: parts[1] }
  if (parts.length === 3) return { top: parts[0], right: parts[1], bottom: parts[2], left: parts[1] }
  return { top: parts[0], right: parts[1], bottom: parts[2], left: parts[3] }
}

// How far the creature has to be lifted so its feet land on the same line a
// window's edge does. The atlas already leaves a little air under the feet,
// and that air scales with the creature, so it comes off the gap.
function groundOffset(gapBottom, petSize, cellAir, cellHeight) {
  var air = Number(cellAir || 4) * Number(petSize || 56) / Number(cellHeight || 208)
  return Math.max(0, Math.round(Number(gapBottom || 0) - air))
}

// The frame timing an activity was built with, falling back to a steady
// pace for a pet that did not measure its own.
function activityHold(activity, frame, fallback) {
  var base = isFinite(Number(fallback)) && Number(fallback) > 0 ? Number(fallback) : 560
  if (!activity || !Array.isArray(activity.holds)) return base
  var v = Number(activity.holds[frame])
  return isFinite(v) && v > 0 ? v : base
}

if (typeof module !== "undefined") {
  module.exports = {
    clamp01: clamp01,
    energyFromRecord: energyFromRecord,
    freshHookState: freshHookState,
    resolveMood: resolveMood,
    bubbleFor: bubbleFor,
    walkSpeed: walkSpeed,
    decideAction: decideAction,
    ATLAS: ATLAS,
    spriteTrack: spriteTrack,
    atlasRowCount: atlasRowCount,
    cellAspect: cellAspect,
    spriteColumns: spriteColumns,
    readFaces: readFaces,
    faceFor: faceFor,
    mirroredAt: mirroredAt,
    consoleWorkspace: consoleWorkspace,
    sessionLifeMs: sessionLifeMs,
    readSessions: readSessions,
    oftenName: oftenName,
    glanceFaces: glanceFaces,
    readFaceList: readFaceList,
    // Exported is what the QML or the tests actually call. The per-agent
    // line parsers, the mood test and the luminance maths are reached
    // through the functions above them; an export nobody consumes is a
    // promise nobody asked for.
    idleGlance: idleGlance,
    parseDuration: parseDuration,
    timerFace: timerFace,
    timerWords: timerWords,
    mayBlink: mayBlink,
    glanceMs: glanceMs,
    contrastRatio: contrastRatio,
    contrastSafe: contrastSafe,
    tintStrength: tintStrength,
    tintFor: tintFor,
    isDrag: isDrag,
    dragTo: dragTo,
    shoveProgress: shoveProgress,
    sideTuckShift: sideTuckShift,
    sinkShift: sinkShift,
    peekHeight: peekHeight,
    mayPlayActivity: mayPlayActivity,
    isThemeableSpec: isThemeableSpec,
    readActivities: readActivities,
    readStillRows: readStillRows,
    isStillRow: isStillRow,
    pickActivity: pickActivity,
    activityDuration: activityDuration,
    defaultHomeX: defaultHomeX,
    readHomes: readHomes,
    homeFor: homeFor,
    homeMonitor: homeMonitor,
    parseGapsCss: parseGapsCss,
    groundOffset: groundOffset,
    activityHold: activityHold,
    luaStr: luaStr,
    shellQuote: shellQuote,
    dispatchExec: dispatchExec,
    consolePlacement: consolePlacement,
    placementRule: placementRule,
    dispatchToggleSpecial: dispatchToggleSpecial,
    dispatchFocusMonitor: dispatchFocusMonitor,
    worldSegments: worldSegments,
    segmentByName: segmentByName,
    travelPlan: travelPlan,
    buildTalkCommand: buildTalkCommand,
    canTalkTo: canTalkTo,
    buildConsoleResume: buildConsoleResume,
    parseTalkLine: parseTalkLine,
    describeTool: describeTool,
    shapeBubbleText: shapeBubbleText,
    activityRepeats: activityRepeats,
    crossfadeMs: crossfadeMs,
    plainSpeech: plainSpeech,
    readingTimeMs: readingTimeMs,
    shouldRetryTalk: shouldRetryTalk,
    themeStampMatches: themeStampMatches,
    resolvePetSize: resolvePetSize
  }
}
