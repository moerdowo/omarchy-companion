import test from "node:test"
import assert from "node:assert/strict"
import { createRequire } from "node:module"
import { execFileSync, spawn } from "node:child_process"
import { existsSync, mkdtempSync, rmSync } from "node:fs"
import { readFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const require = createRequire(import.meta.url)
const M = require("../keystone/Model.js")

test("energy inverts the most-constrained limit window", () => {
  assert.equal(M.energyFromRecord(null), 1)
  assert.equal(M.energyFromRecord({ limits: [] }), 1)
  assert.equal(M.energyFromRecord({ limits: [{ percent: 0.26 }, { percent: 0.32 }] }).toFixed(2), "0.68")
  assert.equal(M.energyFromRecord({ limits: [{ percent: 1.0 }] }), 0)
  assert.equal(M.energyFromRecord({ limits: [{ percent: "x" }] }), 1)
})

test("hook freshness follows the ecosystem's windows", () => {
  assert.equal(M.freshHookState("waiting", 100, "claude", "claude"), "waiting")
  assert.equal(M.freshHookState("waiting", 20000, "claude", "claude"), "")
  assert.equal(M.freshHookState("success", 5, "claude", "claude"), "success")
  assert.equal(M.freshHookState("success", 9, "claude", "claude"), "")
  assert.equal(M.freshHookState("error", 59, "claude", "claude"), "error")
  assert.equal(M.freshHookState("error", 61, "claude", "claude"), "")
  // a hook for another agent than the default is not our chief's state
  assert.equal(M.freshHookState("working", 10, "codex", "claude"), "")
  // hooks without an agent stamp still count
  assert.equal(M.freshHookState("working", 10, "", "claude"), "working")
  assert.equal(M.freshHookState("bogus", 1, "claude", "claude"), "")
})

const base = { energy: 1, consoleWindows: 0, consoleOpen: false, hookState: "", hookAgeSec: 0, hookAgent: "", defaultAgent: "claude" }

test("mood ladder priorities", () => {
  assert.equal(M.resolveMood({ ...base }), "idle")
  assert.equal(M.resolveMood({ ...base, energy: 0.1 }), "tired")
  assert.equal(M.resolveMood({ ...base, energy: 0 }), "sleeping")
  assert.equal(M.resolveMood({ ...base, consoleWindows: 1 }), "parked")
  assert.equal(M.resolveMood({ ...base, consoleWindows: 1, consoleOpen: true }), "working")
  assert.equal(M.resolveMood({ ...base, agentWindows: 3 }), "idle",
    "ordinary tiled agent terminals are not parked consoles")
  assert.equal(M.resolveMood({ ...base, hookState: "waiting", hookAgeSec: 10, hookAgent: "claude" }), "waiting")
  assert.equal(M.resolveMood({ ...base, hookState: "error", hookAgeSec: 10, hookAgent: "claude" }), "error")
  assert.equal(M.resolveMood({ ...base, hookState: "success", hookAgeSec: 2, hookAgent: "claude" }), "success")
  // sleeping beats even an urgent hook: rate-limited means nothing will run
  assert.equal(M.resolveMood({ ...base, energy: 0, hookState: "waiting", hookAgeSec: 5, hookAgent: "claude" }), "sleeping")
  // stale hook falls through to window heuristics
  assert.equal(M.resolveMood({ ...base, consoleWindows: 1, hookState: "success", hookAgeSec: 100, hookAgent: "claude" }), "parked")
})

test("bubbles per mood", () => {
  assert.equal(M.bubbleFor("waiting"), "!")
  // An agent session sitting in a closed console is the normal state of a
  // desktop that codes; a marker for it would simply always be there.
  assert.equal(M.bubbleFor("parked"), "")
  assert.equal(M.bubbleFor("success"), "✓")
  assert.equal(M.bubbleFor("error"), "✗")
  assert.equal(M.bubbleFor("idle"), "")
})

test("walk speed scales with mood and energy", () => {
  assert.ok(M.walkSpeed("idle", 1) > M.walkSpeed("tired", 1))
  assert.ok(M.walkSpeed("waiting", 1) > M.walkSpeed("idle", 1))
  assert.equal(M.walkSpeed("sleeping", 1), 0)
  assert.equal(M.walkSpeed("idle", 0), 34 * 0.5)
})

test("brain decisions are deterministic under a seeded rand", () => {
  assert.equal(M.decideAction(() => 0.1, "idle", 1).type, "wander")
  assert.equal(M.decideAction(() => 0.2, "idle", 1).type, "hop")
  assert.equal(M.decideAction(() => 0.9, "idle", 1).type, "sit")
  assert.equal(M.decideAction(() => 0.3, "waiting", 1).type, "hop")
  assert.equal(M.decideAction(() => 0.5, "working", 1).type, "sit")
  const a = M.decideAction(() => 0.5, "idle", 1)
  assert.ok(a.nextMs >= 12000 && a.nextMs <= 45000)
  // doubled activity halves the pause
  const slow = M.decideAction(() => 0.5, "idle", 0.5)
  assert.ok(slow.nextMs > a.nextMs)
})

test("sprite tracks: walking uses the directional rows", () => {
  assert.equal(M.spriteTrack("idle", true, 1).row, 1)
  assert.equal(M.spriteTrack("idle", true, -1).row, 2)
  assert.equal(M.spriteTrack("working", false, 1).row, 7)
  assert.equal(M.spriteTrack("waiting", false, 1).row, 6)
  assert.equal(M.spriteTrack("error", false, 1).row, 5)
  assert.equal(M.spriteTrack("success", false, 1).row, 8)
  assert.equal(M.spriteTrack("sleeping", false, 1).row, 0)
  assert.equal(M.atlasRowCount(1), 9)
  assert.equal(M.atlasRowCount(2), 11)
})

test("world segments sort by virtual x and drop invalid screens", () => {
  const segs = M.worldSegments([
    { name: "DP-2", x: 4000, y: 560, width: 2560, height: 1440 },
    { name: "HDMI-A-1", x: 0, y: 0, width: 1440, height: 2560 },
    { name: "DP-1", x: 1440, y: 560, width: 2560, height: 1440 },
    { name: "", x: 9, width: 9 }, { name: "bad", x: NaN, width: 100 }
  ])
  assert.deepEqual(segs.map(s => s.name), ["HDMI-A-1", "DP-1", "DP-2"])
  assert.deepEqual(M.segmentByName(segs, "DP-1"), {
    name: "DP-1", x: 1440, y: 560, w: 2560, h: 1440
  })
  assert.equal(M.segmentByName(segs, "nope"), null)
})

test("travel plans scale with real distance and clamp", () => {
  const segs = M.worldSegments([
    { name: "A", x: 0, width: 1440 }, { name: "B", x: 1440, width: 2560 }, { name: "C", x: 4000, width: 2560 }
  ])
  const near = M.travelPlan(segs, "B", 2000, "C", 0.1)
  const far = M.travelPlan(segs, "A", 100, "C", 0.9)
  assert.ok(near.undergroundMs < far.undergroundMs)
  assert.ok(far.undergroundMs <= 2200 && near.undergroundMs >= 350)
  assert.equal(M.travelPlan(segs, "B", 0, "nope", 0.5), null)
  // unknown origin still lands somewhere sane
  assert.ok(M.travelPlan(segs, "gone", 0, "C", 0.5).targetLocal === 1280)
})

test("talk commands: claude adapter, others fall back", () => {
  const fresh = M.buildTalkCommand("claude", "hi", "", "Be the chief.", "You stand on DP-1.")
  assert.equal(fresh[0], "claude")
  assert.ok(!fresh.includes("--resume"))
  // claude carries the standing instructions as a system prompt on every
  // call — first and resumed alike — and the order itself stays clean.
  assert.ok(fresh.includes("You stand on DP-1.\n\nOrder: hi"))
  assert.deepEqual(fresh.slice(fresh.indexOf("--permission-mode"), fresh.indexOf("--permission-mode") + 2),
    ["--permission-mode", "auto"])
  assert.equal(fresh[fresh.indexOf("--append-system-prompt") + 1], "Be the chief.")
  const resumed = M.buildTalkCommand("claude", "hi", "abc-123", "Be the chief.", "You stand on DP-2.")
  assert.ok(resumed.includes("--resume") && resumed.includes("abc-123"))
  assert.ok(resumed.indexOf("--resume") < resumed.indexOf("You stand on DP-2.\n\nOrder: hi"))
  assert.ok(resumed.includes("--append-system-prompt"))
  assert.ok(!M.buildTalkCommand("claude", "hi", "", "").includes("--append-system-prompt"))
  // agents without a system-prompt flag get it folded into the first order,
  // and only the first: a resumed session already heard it.
  const oc = M.buildTalkCommand("opencode", "hi", "", "Be the chief.", "You stand on DP-1.")
  assert.equal(oc[oc.length - 1], "Be the chief.\n\nYou stand on DP-1.\n\nOrder: hi")
  const ocRes = M.buildTalkCommand("opencode", "hi", "ses_1", "Be the chief.", "You stand on DP-2.")
  assert.equal(ocRes[ocRes.length - 1], "You stand on DP-2.\n\nOrder: hi")
  const cx = M.buildTalkCommand("codex", "hi", "", "Be the chief.")
  assert.ok(cx[cx.length - 1].startsWith("Be the chief."))
  assert.equal(M.buildTalkCommand("crush", "hi", "", ""), null)
  assert.deepEqual(M.buildConsoleResume("claude", "abc"),
    ["claude", "--permission-mode", "auto", "--resume", "abc"])
  assert.equal(M.buildConsoleResume("claude", ""), null)
})

test("talk line parsing survives shim noise and extracts events", () => {
  assert.equal(M.parseTalkLine("claude", "mise ~/.config/mise/config.toml tools: claude"), null)
  assert.equal(M.parseTalkLine("claude", '{"type":"system","subtype":"init"}'), null)
  const t = M.parseTalkLine("claude", '{"type":"assistant","message":{"content":[{"type":"text","text":"Zu Diensten."}]}}')
  assert.deepEqual(t, { kind: "text", text: "Zu Diensten." })
  const r = M.parseTalkLine("claude", '{"type":"result","subtype":"success","is_error":false,"result":"done","session_id":"s-1"}')
  assert.deepEqual(r, { kind: "result", ok: true, text: "done", sessionId: "s-1" })
  const bad = M.parseTalkLine("claude", '{"type":"result","subtype":"error_during_execution","is_error":true,"session_id":"s-1"}')
  assert.equal(bad.ok, false)
})

test("bubble text is collapsed and capped on a word boundary", () => {
  assert.equal(M.shapeBubbleText("  a\n\n b   c "), "a b c")
  const long = M.shapeBubbleText("word ".repeat(100), 50)
  assert.ok(long.length <= 50 && long.endsWith("…") && !long.includes("  "))
})

test("opencode adapter: real sampled lines", () => {
  const t = M.parseTalkLine("opencode", '{"type":"text","timestamp":1787353823764,"sessionID":"ses_fd9694ca2ffeuvzR9cc5KewVK9","part":{"id":"prt_1","messageID":"msg_1","sessionID":"ses_fd9694ca2ffeuvzR9cc5KewVK9","type":"text","text":"OK","time":{"start":1,"end":2}}}')
  assert.deepEqual(t, { kind: "text", text: "OK" })
  const syn = M.parseTalkLine("opencode", '{"type":"text","sessionID":"s","part":{"type":"text","synthetic":true,"text":"Continue if you have next steps"}}')
  assert.equal(syn, null)
  const r = M.parseTalkLine("opencode", '{"type":"step_finish","timestamp":1787353823764,"sessionID":"ses_fd9694ca2ffeuvzR9cc5KewVK9","part":{"type":"step-finish","reason":"tool-calls"}}')
  assert.deepEqual(r, { kind: "session", sessionId: "ses_fd9694ca2ffeuvzR9cc5KewVK9" })
  const finalStep = M.parseTalkLine("opencode", '{"type":"step_finish","sessionID":"ses_fd9694ca2ffeuvzR9cc5KewVK9","part":{"type":"step-finish","reason":"stop"}}')
  assert.deepEqual(finalStep, r, "the process exit, not a heuristic delay, ends the turn")
  const argv = M.buildTalkCommand("opencode", "hi", "ses_x")
  assert.deepEqual(argv, ["opencode", "run", "--auto", "--format", "json", "-s", "ses_x", "hi"])
  // The TUI takes --session; the note that said otherwise was wrong, and the
  // console opened empty because of it.
  assert.deepEqual(M.buildConsoleResume("opencode", "ses_x"), ["opencode", "--auto", "--session", "ses_x"])
})

test("codex adapter: real sampled lines", () => {
  const sid = M.parseTalkLine("codex", '{"type":"thread.started","thread_id":"01a02698-aab4-7562-8610-2835fd4f8cb1"}')
  assert.deepEqual(sid, { kind: "session", sessionId: "01a02698-aab4-7562-8610-2835fd4f8cb1" })
  const t = M.parseTalkLine("codex", '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}')
  assert.deepEqual(t, { kind: "text", text: "OK" })
  const done = M.parseTalkLine("codex", '{"type":"turn.completed","usage":{"input_tokens":13846}}')
  assert.equal(done.ok, true)
  const fail = M.parseTalkLine("codex", '{"type":"turn.failed","error":{"message":"boom"}}')
  assert.deepEqual(fail, { kind: "result", ok: false, text: "boom", sessionId: "" })
  const fresh = M.buildTalkCommand("codex", "hi", "")
  assert.deepEqual(fresh, ["codex", "exec", "--approve-for-me", "--skip-git-repo-check", "--json", "hi"])
  const res = M.buildTalkCommand("codex", "hi", "t-1")
  assert.deepEqual(res,
    ["codex", "exec", "--approve-for-me", "--skip-git-repo-check", "--json", "resume", "t-1", "hi"])
  assert.deepEqual(M.buildConsoleResume("codex", "t-1"), ["codex", "resume", "t-1", "--approve-for-me"])
})

test("sleepRow routes the sleeping mood to a custom atlas row", () => {
  assert.deepEqual(M.spriteTrack("sleeping", false, 1, 3), { row: 3, frames: 6 })
  assert.equal(M.spriteTrack("sleeping", false, 1, -1).row, 0)
  assert.equal(M.spriteTrack("sleeping", false, 1, undefined).row, 0)
  assert.equal(M.spriteTrack("idle", true, 1, 3).row, 1)
})

test("walkFrames shortens the gait without touching other rows", () => {
  assert.deepEqual(M.spriteTrack("idle", true, 1, -1, 5), { row: 1, frames: 5 })
  assert.deepEqual(M.spriteTrack("idle", true, -1, -1, 5), { row: 2, frames: 5 })
  assert.equal(M.spriteTrack("idle", true, 1, -1, 0).frames, 8)
  assert.equal(M.spriteTrack("idle", true, 1, -1, 99).frames, 8)
  assert.equal(M.spriteTrack("idle", true, 1, -1, undefined).frames, 8)
  assert.equal(M.spriteTrack("working", false, 1, -1, 5).row, 7)
})

test("contrastSafe lifts a tint until it clears the floor", () => {
  const black = { r: 0, g: 0, b: 0 }
  const white = { r: 1, g: 1, b: 1 }
  // vantablack's grey accent already clears the floor on pure black; a
  // theme with a genuinely dark accent is what the lift exists for.
  const vantaAccent = { r: 0x8d / 255, g: 0x8d / 255, b: 0x8d / 255 }
  assert.ok(M.contrastRatio(vantaAccent, black) > 4.5)
  const darkAccent = { r: 0x2a / 255, g: 0x2a / 255, b: 0x2a / 255 }
  assert.ok(M.contrastRatio(darkAccent, black) < 4.5)
  const lifted = M.contrastSafe(darkAccent, black, 4.5)
  assert.ok(M.contrastRatio(lifted, black) >= 4.5)
  assert.ok(lifted.r > darkAccent.r)
  // already legible: left alone
  const bright = { r: 0.9, g: 0.9, b: 0.2 }
  assert.deepEqual(M.contrastSafe(bright, black, 4.5), bright)
  // light desktop pushes the other way
  const darkened = M.contrastSafe({ r: 0.85, g: 0.85, b: 0.85 }, white, 4.5)
  assert.ok(darkened.r < 0.85)
  // A perceptual mid-tone needs black, not white. A 50% luminance split
  // chose the wrong endpoint here and stopped below its own contrast floor.
  const mid = { r: 0x77 / 255, g: 0x77 / 255, b: 0x77 / 255 }
  assert.ok(M.contrastRatio(white, mid) < 4.5)
  assert.ok(M.contrastRatio(black, mid) >= 4.5)
  const corrected = M.contrastSafe(mid, mid, 4.5)
  assert.ok(corrected.r < mid.r)
  assert.ok(M.contrastRatio(corrected, mid) >= 4.5)
  for (let level = 0; level <= 1; level += 0.05) {
    const background = { r: level, g: level, b: level }
    for (const tint of [
      { r: level, g: level, b: level },
      { r: 0.72, g: 0.18, b: 0.12 },
      { r: 0.1, g: 0.55, b: 0.8 },
    ]) {
      const before = M.contrastRatio(tint, background)
      const result = M.contrastSafe(tint, background, 4.5)
      if (before >= 4.5) assert.deepEqual(result, tint, "an already-safe tint is unchanged")
      else assert.ok(M.contrastRatio(result, background) >= 4.5 - 1e-9,
        `contrast floor missed at grey ${level.toFixed(2)}`)
    }
  }
  assert.deepEqual(M.contrastSafe(mid, mid, 7), black,
    "an unreachable floor returns the better endpoint")
  assert.equal(M.contrastRatio(white, black).toFixed(0), "21")
})

test("the live tint compensates for Qt's grayscale colorization", () => {
  const dark = { r: 0.18, g: 0.20, b: 0.24 }
  const light = { r: 1, g: 1, b: 1 }
  const accent = { r: 0.5, g: 0.63, b: 0.76 }
  assert.ok(M.contrastRatio(M.liveTintColor(accent, dark), dark) >= 12 - 1e-9)
  assert.ok(M.liveTintBrightness(dark, 0.7) > 0)
  assert.equal(M.liveTintBrightness(light, 0.7), 0,
    "blackward tinting must not crush the source shadows")
  assert.equal(M.liveTintBrightness(dark, 0), 0)
  assert.equal(M.liveTintBrightness(dark, "nope"), 0)
})

test("tintStrength reads true/false/number the same everywhere", () => {
  assert.equal(M.tintStrength(true), 0.7)
  assert.equal(M.tintStrength(false), 0)
  assert.equal(M.tintStrength(undefined, 0.4), 0.4)
  assert.equal(M.tintStrength(0.35), 0.35)
  assert.equal(M.tintStrength(2), 1)
  assert.equal(M.tintStrength("nope"), 0)
})

test("isThemeableSpec accepts a window object and rejects nonsense", () => {
  assert.equal(M.isThemeableSpec({ hueMin: 40, hueMax: 100, satMin: 15 }), true)
  assert.equal(M.isThemeableSpec({}), true)
  assert.equal(M.isThemeableSpec({ hueMin: "x" }), false)
  assert.equal(M.isThemeableSpec({ hueMin: -5 }), false)
  assert.equal(M.isThemeableSpec({ hueMin: 40, hueMax: 361 }), false)
  assert.equal(M.isThemeableSpec({ hueMin: 180, hueMax: 40 }), false)
  assert.equal(M.isThemeableSpec({ satMin: 101 }), false)
  assert.equal(M.isThemeableSpec([]), false)
  assert.equal(M.isThemeableSpec(true), false)
  assert.equal(M.isThemeableSpec(null), false)
})

test("opencode: a finished step keeps the session but is not a verdict", () => {
  const m = M.parseTalkLine("opencode", '{"type":"step_finish","sessionID":"ses_1"}')
  assert.deepEqual(m, { kind: "session", sessionId: "ses_1" })
  const s = M.parseTalkLine("opencode", '{"type":"step_start","sessionID":"ses_1","part":{"type":"step-start"}}')
  assert.deepEqual(s, { kind: "session", sessionId: "ses_1" })
})

test("lua strings survive quotes, backslashes and newlines", () => {
  assert.equal(M.luaStr("plain"), '"plain"')
  assert.equal(M.luaStr('say "hi"'), '"say \\"hi\\""')
  assert.equal(M.luaStr("back\\slash"), '"back\\\\slash"')
  assert.equal(M.luaStr("two\nlines"), '"two\\nlines"')
  assert.equal(M.luaStr(undefined), '""')
})

test("dispatchers are dispatcher expressions, not bare words", () => {
  assert.equal(M.dispatchToggleSpecial("scratchpad"), 'hl.dsp.workspace.toggle_special("scratchpad")')
  assert.equal(M.dispatchFocusMonitor("DP-1"), 'hl.dsp.focus({monitor="DP-1"})')
  assert.equal(M.dispatchExec("[workspace special:scratchpad silent] foo"),
    'hl.dsp.exec_cmd("[workspace special:scratchpad silent] foo")')
})

test("activities are read defensively and picked at odds", () => {
  const raw = [{ name: "lunch", row: 10, frames: 6 }, { row: 99, frames: 6 }, { name: "x", row: 11, frames: 0 }]
  const acts = M.readActivities(raw, 15)
  assert.deepEqual(acts, [{ name: "lunch", row: 10, frames: 6, holds: null }])
  assert.deepEqual(M.readActivities(null, 15), [])
  assert.equal(M.pickActivity(() => 0.9, acts, 0.4), null)
  assert.deepEqual(M.pickActivity(() => 0.1, acts, 0.4), acts[0])
  assert.equal(M.pickActivity(() => 0.1, [], 0.4), null)
})

test("home defaults to the bottom-right and aligns visible artwork", () => {
  // An ordinary atlas cell uses the ecosystem's fallback aspect.
  assert.equal(M.defaultHomeX(1440, 150, 10), 1361)
  // Quattro is wide: its actual cell and content bounds keep the whole car
  // inside the same right-hand gap after it turns to face inward.
  assert.equal(M.defaultHomeX(2560, 130, 10, 333 / 208,
    { left: 0.021, right: 0.979 }, true), 2450)
  // A nonsense size falls back to the default creature rather than to zero.
  assert.equal(M.defaultHomeX(1440, 0), 1414)
  assert.equal(M.defaultHomeX(1440, "not-a-size"), 1414)
  assert.equal(M.defaultHomeX(1440, 10), 1435)
})

test("hyprland gap shorthand parses like CSS", () => {
  assert.deepEqual(M.parseGapsCss("10 10 10 10"), { top: 10, right: 10, bottom: 10, left: 10 })
  assert.deepEqual(M.parseGapsCss("8"), { top: 8, right: 8, bottom: 8, left: 8 })
  assert.deepEqual(M.parseGapsCss("4 12"), { top: 4, right: 12, bottom: 4, left: 12 })
  assert.deepEqual(M.parseGapsCss("1 2 3"), { top: 1, right: 2, bottom: 3, left: 2 })
  assert.deepEqual(M.parseGapsCss(""), { top: 0, right: 0, bottom: 0, left: 0 })
})

test("the creature lands on the same line a window's edge does", () => {
  // The cell keeps four pixels of air under the feet, scaled with the pet.
  assert.equal(M.groundOffset(10, 150, 4, 208), 7)
  assert.equal(M.groundOffset(10, 56, 4, 208), 9)
  assert.equal(M.groundOffset(0, 150, 4, 208), 0)
})

test("home aligns the creature's visible right edge with a window's", () => {
  assert.equal(M.defaultHomeX(1440, 150, 10), 1361)
  assert.equal(M.defaultHomeX(1440, 150), 1371)
})

test("activity holds come from the build, with a steady fallback", () => {
  const a = { holds: [533, 369, 546, 488, 443, 983] }
  assert.equal(M.activityHold(a, 0), 533)
  assert.equal(M.activityHold(a, 5), 983)
  assert.equal(M.activityHold(a, 9, 400), 400)
  assert.equal(M.activityHold({ row: 9 }, 0, 400), 400)
  assert.equal(M.activityHold(null, 0), 560)
})

test("an activity does not repeat itself back to back", () => {
  const acts = [{ name: "lunch" }, { name: "garden" }, { name: "cat" }]
  const picks = new Set()
  for (const r of [0.0, 0.34, 0.67, 0.99]) picks.add(M.pickActivity(() => r, acts, 1, "lunch")?.name)
  assert.ok(!picks.has("lunch"), "the one just played is skipped")
  // A pet that only knows one trick may still perform it.
  assert.equal(M.pickActivity(() => 0.1, [{ name: "solo" }], 1, "solo").name, "solo")
  assert.equal(M.pickActivity(() => 0.99, acts, 0.4, ""), null)
})

test("activity duration adds up its own frame holds", () => {
  assert.equal(M.activityDuration({ frames: 6, holds: [533, 369, 546, 488, 443, 983] }), 3362)
  assert.equal(M.activityDuration({ frames: 4 }, 500), 2000)
  assert.equal(M.activityDuration(null), 0)
})

test("homes are stored per monitor and read defensively", () => {
  assert.deepEqual(M.readHomes({ monitors: { "DP-1": 400, "DP-2": 80 } }), { "DP-1": 400, "DP-2": 80 })
  assert.deepEqual(M.readHomes({ "DP-1": 12 }), { "DP-1": 12 })
  // The first version of the file held one position and its monitor; an
  // upgrade must not throw somebody's placement away.
  assert.deepEqual(M.readHomes({ x: 45, monitor: "DP-1" }), { "DP-1": 45 })
  assert.deepEqual(M.readHomes({ x: 45, monitor: "" }), {})
  assert.deepEqual(M.readHomes({ "DP-1": -5, "": 10, "DP-2": "x" }), {})
  assert.deepEqual(M.readHomes(null), {})
})

test("a home clamps onto whatever screen it lands on", () => {
  const homes = { "DP-1": 2400 }
  // Same wide screen: kept exactly.
  assert.equal(M.homeFor(homes, "DP-1", 2560, 150, 10), 2400)
  // A narrower screen pulls it inside the edge instead of off the end.
  assert.equal(M.homeFor(homes, "DP-1", 1440, 150, 10), 1395)
  // An unknown monitor falls back to the right corner of its own screen.
  assert.equal(M.homeFor(homes, "HDMI-A-1", 1440, 150, 10), 1361)
  assert.equal(M.homeFor({}, "DP-1", 2560, 150, 10), 2481)
})

test("still rows are read defensively and recognised", () => {
  assert.deepEqual(M.readStillRows([0, 3, 4, 5, 6, 7, 8, 15], 16), [0, 3, 4, 5, 6, 7, 8, 15])
  assert.deepEqual(M.readStillRows([0, 99, -1, "x"], 16), [0])
  assert.deepEqual(M.readStillRows(null, 16), [])
  assert.equal(M.isStillRow([0, 5], 5), true)
  assert.equal(M.isStillRow([0, 5], 1), false)
  assert.equal(M.isStillRow(null, 0), false)
})

test("the better theming path wins, and something always applies", () => {
  const window = { hueMin: 40, hueMax: 175, satMin: 12 }
  // A pet that named its colours is redrawn rather than tinted.
  assert.equal(M.tintFor(window, true, 0), 0)
  // Without ImageMagick the redraw cannot run, so the live tint steps in
  // rather than the pet going untreated.
  assert.equal(M.tintFor(window, false, 0), 0.7)
  // A pet that never said which colours are skin keeps its artwork.
  assert.equal(M.tintFor(null, true, 0), 0)
  // An explicit wish is honoured when no redraw is possible.
  assert.equal(M.tintFor(null, true, 0.5), 0.5)
  assert.equal(M.tintFor(window, false, 0.35), 0.35)
  // …and never overrides the better path.
  assert.equal(M.tintFor(window, true, 0.5), 0)
})

test("a short press is a click, a longer one carries the creature", () => {
  assert.equal(M.isDrag(0), false)
  assert.equal(M.isDrag(3), false)
  assert.equal(M.isDrag(-3), false)
  assert.equal(M.isDrag(4), true)
  assert.equal(M.isDrag(-40), true)
})

test("a drag stays on the screen it started on", () => {
  assert.equal(M.dragTo(200, 300, 2560, 150), 500)
  // Dragged off the side: stopped where the creature can still stand. Going
  // further is a shove, and a shove puts it away rather than moving it.
  assert.equal(M.dragTo(200, -400, 2560, 150), 45)
  assert.equal(M.dragTo(2400, 400, 2560, 150), 2515)
})

test("an activity waits for a moment that is actually quiet", () => {
  const quiet = { onStage: true, promptOpen: false, walking: false, dragging: false, mood: "idle", rested: true }
  assert.equal(M.mayPlayActivity(quiet), true)
  assert.equal(M.mayPlayActivity({ ...quiet, rested: false }), false)
  assert.equal(M.mayPlayActivity({ ...quiet, promptOpen: true }), false)
  assert.equal(M.mayPlayActivity({ ...quiet, walking: true }), false)
  assert.equal(M.mayPlayActivity({ ...quiet, dragging: true }), false)
  assert.equal(M.mayPlayActivity({ ...quiet, onStage: false }), false)
  // A desktop that codes nearly always has an agent window open, and a
  // creature whose limits are nearly spent has less to do rather than more:
  // both are quiet moments. Demanding a bare "idle" meant the performances
  // never ran on a real machine at all.
  for (const mood of ["idle", "parked", "success", "tired"])
    assert.equal(M.mayPlayActivity({ ...quiet, mood }), true, `${mood} is a quiet moment`)
  for (const mood of ["working", "waiting", "error", "sleeping"])
    assert.equal(M.mayPlayActivity({ ...quiet, mood }), false, `${mood} is not a quiet moment`)
})

test("the cell shape comes from the sheet, not from an assumption", () => {
  // The ecosystem's usual sheet: eight columns of 192x208.
  assert.equal(M.cellAspect(1536, 3328, 16).toFixed(4), (192 / 208).toFixed(4))
  // A pet drawn on square cells is rendered square.
  assert.equal(M.cellAspect(800, 900, 9), (100 / 100).toFixed(0) * 1)
  // Nothing loaded yet, or nonsense: fall back rather than divide by zero.
  assert.equal(M.cellAspect(0, 0, 0), M.ATLAS.frameAspect)
  assert.equal(M.cellAspect(1536, 3328, 0), M.ATLAS.frameAspect)
})

test("an order cannot break out of the shell it is quoted into", () => {
  // Orders are typed by a person, land in a bash command line, and may
  // contain anything at all. Each of these is run the way the plugin runs
  // one — a single argument to bash -lc, with no second quoting layer —
  // and must come back out as the literal text that went in.
  const attacks = [
    "; rm -rf /tmp/omarchief-escape",
    "$(touch /tmp/omarchief-escape)",
    "`touch /tmp/omarchief-escape`",
    "'; touch /tmp/omarchief-escape; '",
    "&& touch /tmp/omarchief-escape",
    "| touch /tmp/omarchief-escape",
    "a'b",
    "$HOME && echo x",
    "line one\nline two",
    'quote" and $var',
  ]
  for (const attack of attacks) {
    const out = execFileSync("bash", ["-lc", "printf %s " + M.shellQuote(attack)], { encoding: "utf8" })
    assert.equal(out, attack, `escaped: ${JSON.stringify(attack)}`)
  }
  assert.equal(existsSync("/tmp/omarchief-escape"), false, "nothing was executed")
  assert.equal(M.shellQuote(undefined), "''")
})

test("a monitor name cannot break out of a Lua dispatcher", () => {
  assert.equal(M.luaStr('"); os.execute("touch /tmp/x'), '"\\"); os.execute(\\"touch /tmp/x"')
  assert.equal(M.dispatchFocusMonitor('DP-1"; evil'), 'hl.dsp.focus({monitor="DP-1\\"; evil"})')
})


test("a short performance is repeated so it lasts long enough to notice", () => {
  // Three and a half seconds in the corner of a screen is a performance
  // nobody ever catches. Short rows go round more than once.
  assert.equal(M.activityRepeats(9000, 3400), 3)
  assert.equal(M.activityRepeats(9000, 7000), 2, "a short row clears the target instead of rounding down")
  assert.equal(M.activityRepeats(9000, 9000), 1)
  assert.equal(M.activityRepeats(9000, 30000), 1, "a long row is never cut short")
  assert.equal(M.activityRepeats(9000, 100), 4, "and never repeats forever")
  assert.equal(M.activityRepeats(9000, 0), 1)
})

test("markdown the agent sends anyway becomes prose", () => {
  const spoken = M.plainSpeech("## Done\n\nI **switched** to `tokyo-night`:\n- moved *Spotify*\n- see [the docs](https://x.y)")
  assert.equal(spoken.includes("*"), false, "no asterisks survive")
  assert.equal(spoken.includes("#"), false, "no hashes survive")
  assert.equal(spoken.includes("`"), false, "no backticks survive")
  assert.equal(spoken.includes("]("), false, "no link syntax survives")
  assert.ok(spoken.startsWith("Done."), "a heading becomes a sentence")
  assert.ok(spoken.includes("switched"), "the words themselves stay")
  assert.ok(spoken.includes("the docs"), "a link keeps its text")
  assert.equal(M.plainSpeech("```bash\nls -la\n```"), "ls -la", "a fenced block keeps its body")
  assert.equal(M.plainSpeech("2 * 3 * 4"), "2 * 3 * 4", "arithmetic is not emphasis")
  assert.equal(M.plainSpeech("snake_case_name"), "snake_case_name", "underscores in a word are not emphasis")
  assert.equal(M.plainSpeech(null), "")
})

test("an answer stays up for as long as it takes to read", () => {
  assert.equal(M.readingTimeMs(""), 4000, "even an empty answer gets a glance")
  assert.ok(M.readingTimeMs("x".repeat(200)) > M.readingTimeMs("x".repeat(50)), "longer text, longer stay")
  assert.equal(M.readingTimeMs("x".repeat(100000)), 45000, "but never forever")
})

test("a themed sheet is redrawn when the artwork changes, not only the theme", () => {
  assert.equal(M.themeStampMatches("#f38d70 2311088.1787400000", "#f38d70"), true)
  assert.equal(M.themeStampMatches("#000000 2311088.1787400000", "#f38d70"), false, "a new theme redraws")
  assert.equal(M.themeStampMatches("", "#f38d70"), false, "no stamp, no cache")
  assert.equal(M.themeStampMatches("   ", "#f38d70"), false)
  // The sheet is lifted against the desktop behind it, so a theme that keeps
  // the accent and changes the ground is a different sheet.
  const both = "#f38d70 #2c2525 2311088.1787400000"
  assert.equal(M.themeStampMatches(both, "#f38d70", "#2c2525"), true)
  assert.equal(M.themeStampMatches(both, "#f38d70", "#101315"), false, "new ground, new lift")
  assert.equal(M.themeStampMatches(both, "#f38d70"), true, "asking only about the accent still works")
  assert.equal(M.themeStampMatches("#f38d70 2311088.1787400000", "#f38d70", "#2c2525"), false,
    "a stamp from before the lift is out of date")
})

test("the artist may recommend a size, the person overrules it", () => {
  assert.equal(M.resolvePetSize(undefined, 150), 150, "the artist's recommendation")
  assert.equal(M.resolvePetSize(90, 150), 90, "the person's setting wins")
  assert.equal(M.resolvePetSize(undefined, undefined), 56, "OmaPets' default when neither spoke")
  assert.equal(M.resolvePetSize(9999, 0), 240, "kept inside what a desktop can show")
  assert.equal(M.resolvePetSize(1, 0), 32)
})

test("a performance long enough on its own is told once, not looped", () => {
  // The repeat exists for pets whose rows are too short to notice. Once a
  // row lasts ten seconds by itself, telling it three times over is worse
  // than telling it once.
  assert.equal(M.activityRepeats(9000, 10500), 1)
  assert.equal(M.activityRepeats(9000, 3400), 3, "and still helps a short one")
})

test("a performance keeps the hold times it was measured with", () => {
  // These were being dropped at the parsing step: every frame fell back to
  // the same default, so six carefully measured beats all ran at one speed
  // and the balloon drifting away got no more time than the setup did.
  const [a] = M.readActivities([{ name: "balloon", row: 9, frames: 6, holds: [1639, 1520, 1788, 1594, 1345, 2614] }], 16)
  assert.deepEqual(a.holds, [1639, 1520, 1788, 1594, 1345, 2614])
  assert.equal(M.activityDuration(a, 560), 10500)
  assert.equal(M.activityRepeats(9000, M.activityDuration(a, 560)), 1, "long enough to tell once")

  // A pet that names no holds still works, one frame at a time.
  const [b] = M.readActivities([{ name: "x", row: 9, frames: 4 }], 16)
  assert.equal(b.holds, null)
  assert.equal(M.activityHold(b, 0, 560), 560)

  // Nonsense falls back per frame rather than poisoning the row, and no
  // single frame can wedge the creature for a minute.
  const [c] = M.readActivities([{ name: "x", row: 9, frames: 3, holds: [500, "nope", -3] }], 16)
  assert.deepEqual(c.holds, [500, 0, 0])
  assert.equal(M.activityHold(c, 1, 560), 560)
  const [d] = M.readActivities([{ name: "x", row: 9, frames: 1, holds: [999999] }], 16)
  assert.deepEqual(d.holds, [10000])
})

test("a pet may be a grid of faces instead of a strip of frames", () => {
  const faces = M.readFaces({
    idle: [0, 0], error: [0, 1], tired: [0, 2],
    working: [1, 0], parked: [1, 1], success: [1, 2],
    waiting: [2, 0], sleeping: [2, 1], love: [2, 2],
  }, 3, 3)
  assert.deepEqual(faces.idle, [0, 0])
  assert.deepEqual(faces.love, [2, 2])

  // Eight columns is the ecosystem's walk-cycle width, not a law.
  assert.equal(M.spriteColumns(3), 3)
  assert.equal(M.spriteColumns(undefined), 8)
  assert.equal(M.spriteColumns(0), 8)
  assert.equal(M.spriteColumns(500), 8)
  assert.equal(M.cellAspect(795, 624, 3, 3).toFixed(4), (265 / 208).toFixed(4))

  // Anything that is not a cell on this sheet is ignored rather than
  // trusted: a pet file is someone else's data.
  assert.deepEqual(M.readFaces({ a: [0, 0], b: "x", c: [9, 9], d: [0], e: [-1, 0] }, 3, 3), { a: [0, 0] })
  assert.equal(M.readFaces({}, 3, 3), null)
  assert.equal(M.readFaces(null, 3, 3), null)
  assert.equal(M.readFaces([1, 2], 3, 3), null, "an array is not a face map")
})

test("a mood wears the nearest face the pet actually has", () => {
  const full = M.readFaces({
    idle: [0, 0], error: [0, 1], tired: [0, 2], working: [1, 0],
    parked: [1, 1], success: [1, 2], waiting: [2, 0], sleeping: [2, 1], love: [2, 2],
  }, 3, 3)
  assert.deepEqual(M.faceFor("idle", full), [0, 0])
  assert.deepEqual(M.faceFor("waiting", full), [2, 0])
  // Being picked up is the one thing a still pet ever reacts to, and it
  // borrows the fondest face it has.
  assert.deepEqual(M.faceFor("dragged", full), [2, 2])

  // A pet that draws only a resting face still works everywhere.
  const sparse = M.readFaces({ idle: [0, 0] }, 3, 3)
  for (const mood of ["idle", "parked", "working", "waiting", "success", "error", "tired", "sleeping", "dragged"])
    assert.deepEqual(M.faceFor(mood, sparse), [0, 0], `${mood} falls back to resting`)

  // A tired pet with a sleeping face borrows it rather than looking awake.
  assert.deepEqual(M.faceFor("tired", M.readFaces({ idle: [0, 0], sleeping: [2, 1] }, 3, 3)), [2, 1])
  assert.equal(M.faceFor("idle", null), null, "a pet with no faces is not a still pet")
})

test("the creature remembers which screen it lives on", () => {
  // A pet that cannot walk has no way back across a monitor boundary, so
  // where you left it has to outlive a restart — otherwise it reappears
  // wherever the focus happened to be and only an IPC call brings it home.
  const screens = [{ name: "HDMI-A-1" }, { name: "DP-1" }, { name: "DP-2" }]
  assert.equal(M.homeMonitor({ monitor: "DP-1" }, screens), "DP-1")
  // A screen that is no longer plugged in is not a home to return to.
  assert.equal(M.homeMonitor({ monitor: "DP-9" }, screens), "")
  assert.equal(M.homeMonitor({ monitor: "" }, screens), "")
  assert.equal(M.homeMonitor({}, screens), "")
  assert.equal(M.homeMonitor(null, screens), "")
  assert.equal(M.homeMonitor({ monitor: "DP-1" }, []), "", "no screens, no home")
  assert.equal(M.homeMonitor({ monitor: "DP-1" }, null), "")

  // The position on that screen is still read the way it always was.
  assert.deepEqual(M.readHomes({ monitors: { "DP-1": 59 }, monitor: "DP-1" }), { "DP-1": 59 })
})

test("a fresh install chooses intent, not the leftmost monitor", () => {
  const screens = [{ name: "HDMI-A-1" }, { name: "DP-1" }, { name: "DP-2" }]
  assert.equal(M.preferredMonitor(screens, "DP-2", "DP-1", "HDMI-A-1"), "DP-2",
    "an explicit pin wins")
  assert.equal(M.preferredMonitor(screens, "missing", "DP-1", "HDMI-A-1"), "DP-1",
    "a connected remembered home comes next")
  assert.equal(M.preferredMonitor(screens, "", "missing", "DP-1"), "DP-1",
    "a fresh install opens on the focused display")
  assert.equal(M.preferredMonitor(screens, "", "", ""), "",
    "virtual left-to-right order is not a main-screen signal")
  assert.equal(M.preferredMonitor([{ name: "eDP-1" }], "", "", ""), "eDP-1",
    "a laptop's only display is immediately unambiguous")
  assert.equal(M.preferredMonitor([], "DP-1", "DP-1", "DP-1"), "")
})

test("a resting creature borrows only faces that carry no news", () => {
  const faces = M.readFaces({
    idle: [0, 0], error: [0, 1], tired: [0, 2], working: [1, 0],
    parked: [1, 1], success: [1, 2], waiting: [2, 0], sleeping: [2, 1], love: [2, 2],
  }, 3, 3)

  // Nothing alarming: a creature found wearing its error face for no reason
  // is a creature reporting something that did not happen.
  const pool = JSON.stringify(M.glanceFaces(faces))
  for (const worrying of [faces.error, faces.waiting, faces.tired, faces.sleeping, faces.working])
    assert.equal(pool.includes(JSON.stringify(worrying)), false, `${JSON.stringify(worrying)} is news`)
  assert.equal(pool.includes(JSON.stringify(faces.idle)), false, "resting is not a glance away from resting")
  assert.deepEqual(M.glanceFaces(faces), [[1, 1], [1, 2], [2, 2]])

  // Only while nothing is happening.
  const always = () => 0
  assert.ok(M.idleGlance(always, faces, "idle", 1))
  assert.ok(M.idleGlance(always, faces, "parked", 1))
  for (const busy of ["working", "waiting", "error", "success", "tired", "sleeping"])
    assert.equal(M.idleGlance(always, faces, busy, 1), null, `${busy} keeps its own face`)

  // Off means off, and a pet with nothing else to wear simply rests.
  assert.equal(M.idleGlance(always, faces, "idle", 0), null)
  assert.equal(M.idleGlance(always, M.readFaces({ idle: [0, 0] }, 3, 3), "idle", 1), null)
  assert.equal(M.idleGlance(always, null, "idle", 1), null)
  assert.equal(M.idleGlance(() => 0.99, faces, "idle", 0.25), null, "and it is rare")

  // A glance lasts long enough to notice and not long enough to look stuck.
  for (const r of [0, 0.5, 0.999]) {
    const ms = M.glanceMs(() => r)
    assert.ok(ms >= 2200 && ms <= 4800, `${ms} is a glance`)
  }

  // Two names for one drawing is one expression.
  const twins = M.readFaces({ idle: [0, 0], parked: [1, 1], success: [1, 1] }, 3, 3)
  assert.deepEqual(M.glanceFaces(twins), [[1, 1]])
})

test("a creature in profile turns around on the right of the screen", () => {
  // Artwork drawn in profile faces one way and trails its cable the other.
  // On the right of the screen it looks off the edge with the cable lying
  // across the room, which is backwards.
  assert.equal(M.mirroredAt(100, 2560), false, "left half: as drawn")
  assert.equal(M.mirroredAt(2400, 2560), true, "right half: turned around")
  assert.equal(M.mirroredAt(1280, 2560), false, "dead centre stays as drawn")
  assert.equal(M.mirroredAt(1281, 2560), true)
  // Nonsense never flips anything.
  assert.equal(M.mirroredAt(100, 0), false)
  assert.equal(M.mirroredAt(NaN, 2560), false)
  assert.equal(M.mirroredAt(100, NaN), false)
})

test("an artist decides what a resting creature may wear", () => {
  const faces = M.readFaces({ idle: [0, 0], success: [1, 2], love: [2, 2] }, 3, 3)

  // Said outright: exactly those, in that order, minus anything that is
  // already the resting face.
  assert.deepEqual(M.glanceFaces(faces, [[1, 1], [2, 2]], 3, 3), [[1, 1], [2, 2]])
  assert.deepEqual(M.glanceFaces(faces, [[0, 0], [1, 1]], 3, 3), [[1, 1]], "resting is not a glance")
  assert.deepEqual(M.glanceFaces(faces, [[1, 1], [1, 1]], 3, 3), [[1, 1]], "twice is once")
  assert.deepEqual(M.glanceFaces(faces, [], 3, 3), [], "said outright: none")

  // Not said: the moods that carry no news, which is a guess but a safe one.
  assert.deepEqual(M.glanceFaces(faces, null, 3, 3), [[1, 2], [2, 2]])

  // A list out of somebody else's file is read as carefully as anything else.
  assert.deepEqual(M.readFaceList([[0, 1], "x", [9, 9], [0], [-1, 0], [1, 1]], 3, 3), [[0, 1], [1, 1]])
  assert.deepEqual(M.readFaceList(null, 3, 3), [])
})

test("interactive console commands keep the selected agent", () => {
  // Union of Omarchy 4.0's visible matrix and the post-4.0 matrix. Gemini is
  // intentionally retained for 4.0; Antigravity and Ori are their own agents.
  const matrix = {
    pi:       { open: ["pi"], order: ["pi", "inspect"] },
    omp:      { open: ["omp", "--auto-approve"], order: ["omp", "--auto-approve", "--", "inspect"] },
    opencode: { open: ["opencode", "--auto"], order: ["opencode", "--auto", "--prompt", "inspect"] },
    ori:      { open: ["ori", "code"], order: ["ori", "code", "--prompt", "inspect"] },
    claude:   { open: ["claude", "--permission-mode", "auto"], order: ["claude", "--permission-mode", "auto", "--", "inspect"] },
    codex:    { open: ["codex", "--approve-for-me"], order: ["codex", "--approve-for-me", "--", "inspect"] },
    grok:     { open: ["grok", "--permission-mode", "bypassPermissions"], order: ["grok", "--permission-mode", "bypassPermissions", "--", "inspect"] },
    gemini:   { open: ["gemini", "--yolo"], order: ["gemini", "--yolo", "--prompt-interactive", "inspect"] },
    agy:      { open: ["agy", "--dangerously-skip-permissions"], order: ["agy", "--dangerously-skip-permissions", "--prompt-interactive", "inspect"] },
    copilot:  { open: ["copilot", "--allow-all"], order: ["copilot", "--allow-all", "--interactive", "inspect"] },
    crush:    { open: ["crush", "--yolo"], order: ["crush", "run", "inspect"] },
  }
  for (const [id, command] of Object.entries(matrix)) {
    assert.deepEqual(M.buildConsoleCommand(id, ""), command.open, id + " opens interactively")
    assert.deepEqual(M.buildConsoleCommand(id, "inspect"), command.order, id + " receives an order")
    assert.equal(M.canOpenConsole(id), true, id + " is a valid explicit override")
  }
  assert.equal(M.buildConsoleCommand("unknown", "inspect"), null,
    "an unsupported selection must not silently launch the desktop default")
  assert.equal(M.canOpenConsole("unknown"), false)
  assert.equal(M.canOpenConsole(""), false)
})

test("a conversation outlives the shell, and belongs to one agent", () => {
  // Nothing said means one long conversation: the session does not end on
  // its own, which is what talking to something usually means.
  assert.equal(M.sessionLifeMs(undefined), 0, "unset: it does not end on its own")
  assert.equal(M.sessionLifeMs(0), 0, "zero says the same thing out loud")
  assert.equal(M.sessionLifeMs(-5), 0)
  assert.equal(M.sessionLifeMs(30), 30 * 60000)

  // A session id belongs to one agent — claude's means nothing to codex — so
  // switching back and forth loses neither.
  assert.deepEqual(M.readSessions({ claude: "abc", codex: "def" }), { claude: "abc", codex: "def" })
  assert.deepEqual(M.readSessions({ claude: "abc", codex: "", "": "x", n: 5 }), { claude: "abc" })
  assert.deepEqual(M.readSessions({ "../claude": "abc", claude: "bad session", codex: "x".repeat(257) }), {})
  assert.equal(M.safeSessionId("ses_fd9694ca2ffeuvzR9cc5KewVK9"), true)
  assert.equal(M.safeSessionId("01a02698-aab4-7562-8610-2835fd4f8cb1"), true)
  assert.equal(M.safeSessionId("bad session"), false)
  assert.deepEqual(M.readSessions(null), {})
  assert.deepEqual(M.readSessions([1, 2]), {})
})

test("the bubble says what the agent is doing, in its words where it has them", () => {
  // Sampled verbatim from `claude -p --output-format stream-json`.
  const claudeTool = JSON.stringify({ type: "assistant", message: { content: [
    { type: "tool_use", name: "Bash", input: { command: "cat /tmp/agentprobe/notes.txt", description: "Read notes.txt" } }] } })
  assert.deepEqual(M.parseTalkLine("claude", claudeTool), { kind: "doing", text: "Read notes.txt" })
  // Without a description of its own, one is built from what matters.
  const claudeRead = JSON.stringify({ type: "assistant", message: { content: [
    { type: "tool_use", name: "Read", input: { file_path: "/home/x/projects/omarchief/keystone/Service.qml" } }] } })
  assert.deepEqual(M.parseTalkLine("claude", claudeRead), { kind: "doing", text: "Reading Service.qml" })
  // Words beat tools: a message that says something is text, not doing.
  const claudeBoth = JSON.stringify({ type: "assistant", message: { content: [
    { type: "text", text: "Done." }, { type: "tool_use", name: "Read", input: { file_path: "a" } }] } })
  assert.equal(M.parseTalkLine("claude", claudeBoth).kind, "text")

  // Sampled verbatim from `codex exec --json`.
  const codexRun = JSON.stringify({ type: "item.started", item: { id: "item_0", type: "command_execution",
    command: "/usr/bin/bash -lc 'wc -l data.txt'", aggregated_output: "", exit_code: null, status: "in_progress" } })
  assert.deepEqual(M.parseTalkLine("codex", codexRun), { kind: "doing", text: "Running wc -l data.txt" })

  // Sampled from OpenCode 1.18's `run --format json`: completed tools are
  // top-level tool_use records, not the older top-level `tool` spelling.
  const opencodeRead = JSON.stringify({ type: "tool_use", sessionID: "ses_1", part: {
    type: "tool", tool: "read", state: { status: "completed",
      input: { file_path: "/home/x/projects/omarchief/keystone/Service.qml" } } } })
  assert.deepEqual(M.parseTalkLine("opencode", opencodeRead),
    { kind: "doing", text: "Reading Service.qml" })

  // A long command is cut, not wrapped across three bubble lines.
  assert.ok(M.describeTool("Bash", { command: "x".repeat(200) }).length < 60)
  assert.equal(M.describeTool("WebFetch", { url: "https://github.com/hyprwm/Hyprland/pull/7" }), "Fetching github.com")
  assert.equal(M.describeTool("Grep", { pattern: "mirroredAt" }), "Searching for mirroredAt")
  assert.equal(M.describeTool("", {}), "", "an unnamed tool says nothing rather than 'undefined'")
})

test("a runner that refuses says why, in the bubble", () => {
  // Sampled verbatim from `opencode run --format json` once the free quota
  // was spent. Before this the bubble said the agent "ended without a word",
  // which was true and useless.
  const line = JSON.stringify({ type: "error", timestamp: 1787424427649, sessionID: "ses_fd533c",
    error: { name: "APIError", data: { message: "You have exceeded your monthly quota", statusCode: 402 } } })
  const r = M.parseTalkLine("opencode", line)
  assert.equal(r.kind, "result")
  assert.equal(r.ok, false)
  assert.equal(r.text, "You have exceeded your monthly quota")
  // An error with nothing to say still fails honestly.
  assert.equal(M.parseTalkLine("opencode", JSON.stringify({ type: "error", error: {} })).text, "the agent reported an error")
})

test("the console can resume every agent the bubble can talk to", () => {
  assert.deepEqual(M.buildConsoleResume("opencode", "ses_abc"), ["opencode", "--auto", "--session", "ses_abc"])
  assert.ok(M.buildConsoleResume("claude", "x")[0] === "claude")
  assert.ok(M.buildConsoleResume("codex", "x")[0] === "codex")
  assert.deepEqual(M.buildConsoleResume("opencode", "ses_abc", "keep going"),
    ["opencode", "--auto", "--session", "ses_abc", "--prompt", "keep going"])
  assert.deepEqual(M.buildConsoleResume("claude", "x", "keep going").slice(-2),
    ["--", "keep going"])
  assert.deepEqual(M.buildConsoleResume("codex", "x", "keep going").slice(-2),
    ["--", "keep going"])
  assert.equal(M.buildConsoleResume("opencode", ""), null, "nothing to resume")
  assert.equal(M.buildConsoleResume("gemini", "x"), null, "no adapter, no resume")
})

test("a blink only interrupts the resting face", () => {
  const faces = { idle: [0, 0], working: [0, 3], parked: [0, 0], sleeping: [1, 1] }
  assert.equal(M.mayBlink("idle", faces, [1, 3]), true)
  // parked is drawn with the resting picture, so it blinks like one
  assert.equal(M.mayBlink("parked", faces, [1, 3]), true)
  assert.equal(M.mayBlink("working", faces, [1, 3]), false, "not somebody else's mouth")
  assert.equal(M.mayBlink("sleeping", faces, [1, 3]), false)
  // tired is drawn as the sleeping picture here, so it does not blink with
  // the resting one; a mood with nothing of its own does fall back and may
  assert.equal(M.mayBlink("tired", faces, [1, 3]), false)
  assert.equal(M.mayBlink("success", faces, [1, 3]), true, "falls back to resting")
  assert.equal(M.mayBlink("idle", faces, null), false, "no drawing, no blink")
  assert.equal(M.mayBlink("idle", null, [1, 3]), false)
})

test("the state directory spelling stays stable", () => {
  const root = new URL("..", import.meta.url).pathname
  const files = ["README.md", "CHANGELOG.md", "docs/pets.md", "docs/development.md",
                 "tools/perform-check", "tools/coldstart-check"]
  const known = new Set(["omarchy", "omarchief"])
  for (const name of files) {
    let text
    try { text = readFileSync(root + name, "utf8") } catch { continue }
    const stray = [...new Set(text.match(/omar[a-z]+/g) || [])].filter(w => !known.has(w))
    assert.deepEqual(stray, [], name + " has a mangled name: " + stray)
  }
  const performance = readFileSync(root + "tools/perform-check", "utf8")
  assert.match(performance, /XDG_STATE_HOME/,
    "perform-check must honor the configured state home")
  assert.match(performance,
    /os\.path\.join\(state_home,\s*"omarchy",\s*"omarchief",\s*"status\.json"\)/,
    "perform-check must read the real status file")
})

test("command toggles never turn a typo into an action", () => {
  assert.equal(M.flagValue("", true), false)
  assert.equal(M.flagValue("on", false), true)
  assert.equal(M.flagValue("YES", false), true)
  assert.equal(M.flagValue("off", true), false)
  assert.equal(M.flagValue("0", true), false)
  assert.equal(M.flagValue("onn", true), null)
})

async function waitUntil(predicate, timeoutMs) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (predicate()) return true
    await new Promise((resolve) => setTimeout(resolve, 25))
  }
  return predicate()
}

function processAlive(pid) {
  try { process.kill(pid, 0); return true } catch { return false }
}

async function closeOf(child, timeoutMs = 6000) {
  return Promise.race([
    new Promise((resolve) => child.once("close", (code, signal) => resolve({ code, signal }))),
    new Promise((resolve) => setTimeout(() => resolve(null), timeoutMs)),
  ])
}

test("stopping an agent turn reaps even TERM-resistant descendants", async () => {
  const work = mkdtempSync(join(tmpdir(), "omarchief-runner-"))
  const pidPath = join(work, "agent.pid")
  let childPid = 0
  let runner
  try {
    const command = M.buildGuardedRunner(work, [
      "bash", "-c",
      'trap "" TERM; printf "%s" "$$" > "$1"; exec sleep 30',
      "term-resistant-agent", pidPath,
    ])
    runner = spawn("bash", ["-lc", command], { stdio: "ignore" })
    assert.equal(await waitUntil(() => existsSync(pidPath), 2000), true,
      "the isolated agent never started")
    childPid = Number(readFileSync(pidPath, "utf8"))
    assert.ok(Number.isInteger(childPid) && childPid > 1 && processAlive(childPid))
    runner.kill("SIGTERM")
    const closed = await closeOf(runner)
    assert.ok(closed, "the process-group wrapper did not stop within its grace period")
    assert.equal(closed.code, 143)
    assert.equal(await waitUntil(() => !processAlive(childPid), 1000), true,
      "a TERM-resistant descendant survived Stop")
  } finally {
    if (runner && runner.exitCode === null) runner.kill("SIGKILL")
    if (childPid > 1 && processAlive(childPid)) {
      try { process.kill(-childPid, "SIGKILL") } catch {}
    }
    rmSync(work, { recursive: true, force: true })
  }
})

test("plugin destruction reaps a turn after its direct wrapper is SIGKILLed", async () => {
  const work = mkdtempSync(join(tmpdir(), "omarchief-destructor-"))
  const pidPath = join(work, "agent.pid")
  let childPid = 0
  let runner
  try {
    const command = M.buildGuardedRunner(work, [
      "bash", "-c",
      'trap "" TERM; printf "%s" "$$" > "$1"; exec sleep 30',
      "term-resistant-agent", pidPath,
    ])
    runner = spawn("bash", ["-lc", command], { stdio: "ignore" })
    assert.equal(await waitUntil(() => existsSync(pidPath), 2000), true,
      "the isolated agent never started")
    childPid = Number(readFileSync(pidPath, "utf8"))
    assert.ok(Number.isInteger(childPid) && childPid > 1 && processAlive(childPid))

    runner.kill("SIGKILL")
    const closed = await closeOf(runner)
    assert.ok(closed, "the QProcess-owned wrapper did not die")
    assert.equal(closed.signal, "SIGKILL")
    assert.equal(await waitUntil(() => !processAlive(childPid), 4000), true,
      "the guardian left an agent alive after plugin destruction")
  } finally {
    if (runner && runner.exitCode === null) runner.kill("SIGKILL")
    if (childPid > 1 && processAlive(childPid)) {
      try { process.kill(-childPid, "SIGKILL") } catch {}
    }
    rmSync(work, { recursive: true, force: true })
  }
})

test("the process guardian preserves a natural workload exit code", async () => {
  const command = M.buildGuardedRunner(tmpdir(), ["bash", "-c", "exit 7"])
  const runner = spawn("bash", ["-lc", command], { stdio: "ignore" })
  const closed = await closeOf(runner)
  assert.ok(closed, "the process guardian did not return")
  assert.equal(closed.code, 7)
  assert.equal(closed.signal, null)
})

test("persisted booleans accept only real JSON booleans", () => {
  assert.equal(M.boolValue(true, false), true)
  assert.equal(M.boolValue(false, true), false)
  assert.equal(M.boolValue("false", true), true, "a non-empty string is not coerced to true")
  assert.equal(M.boolValue("true", false), false, "strings fall back instead of changing a setting")
  assert.equal(M.boolValue(1, false), false)
  assert.equal(M.boolValue(null, true), true)
  assert.equal(M.boolValue(undefined, false), false)
})

test("ids and pet paths stay inside their declared boundary", () => {
  assert.equal(M.safeId("side-view"), true)
  assert.equal(M.safeId("../../escape"), false)
  assert.equal(M.safeId("with space"), false)
  for (const reserved of ["__proto__", "prototype", "constructor"])
    assert.equal(M.safeId(reserved), false, `${reserved} must not become an object-map key`)
  assert.equal(M.safeRelativePath("sprites/gritty.webp"), true)
  assert.equal(M.safeRelativePath("../secret.webp"), false)
  assert.equal(M.safeRelativePath("/tmp/secret.webp"), false)
  assert.equal(M.safeRelativePath("a\\b.webp"), false)
})

test("external maps cannot replace object prototypes", () => {
  const faces = JSON.parse('{"idle":[0,0],"__proto__":[1,1]}')
  assert.deepEqual(M.readFaces(faces, 2, 2), { idle: [0, 0] })
  const homes = JSON.parse('{"monitors":{"DP-1":42,"__proto__":7,"constructor":9}}')
  assert.deepEqual(M.readHomes(homes), { "DP-1": 42 })
  const sessions = JSON.parse('{"codex":"thread-1","__proto__":"thread-2"}')
  assert.deepEqual(M.readSessions(sessions), { codex: "thread-1" })
  assert.deepEqual(M.readHomes([]), {})
  assert.deepEqual(M.readHomes({ monitors: [] }), {})
})

test("how often it looks up, said in words", () => {
  assert.equal(M.oftenName(0), "never")
  assert.equal(M.oftenName(-1), "never")
  assert.equal(M.oftenName(NaN), "never")
  assert.equal(M.oftenName(0.1), "rarely")
  assert.equal(M.oftenName(0.25), "now and then")
  assert.equal(M.oftenName(0.6), "often")
})

test("an agent that can be talked to is one an order can be built for", () => {
  // Not a list typed out twice: the answer comes from the order builder, so
  // a new adapter is speakable the moment it exists.
  for (const id of ["claude", "codex", "opencode"])
    assert.equal(M.canTalkTo(id), true, id)
  for (const id of ["crush", "", "gemini"])
    assert.equal(M.canTalkTo(id), false, id)
})

test("a pet drawn as one picture has nothing to look up with", () => {
  // Which is why the bar must not offer it a switch for expressions.
  assert.deepEqual(M.glanceFaces({ idle: [0, 0] }, null, 1, 1), [])
  assert.deepEqual(M.glanceFaces({ idle: [0, 0] }, [[0, 0]], 1, 1), [],
    "naming the resting face as an expression is not an expression")
  assert.equal(M.glanceFaces({ idle: [0, 0], love: [1, 2] }, null, 2, 6).length, 1)
  assert.deepEqual(M.glanceFaces(null, null, 2, 6), [])
})

test("what is left showing is drawing, not the margin around it", () => {
  assert.equal(M.peekHeight(190), 28)
  assert.equal(M.peekHeight(150), 22, "the default still shows a recognisable face")
  assert.equal(M.peekHeight(56), 15, "small pets keep a usable handle")
  assert.equal(M.peekHeight(0), 15)
  // gritty's resting picture stops well short of its cell on the right, so
  // the shift is measured to the drawing's own edge
  const bw = 188, right = 0.8495, left = 0.0534, W = 2560, peek = 28
  const bodyX = 63 - bw / 2
  const left_shift = M.sideTuckShift(bodyX, bw, W, peek, left, right, "left")
  assert.equal(Math.round(bodyX + left_shift + bw * right), peek,
    "the drawing's right edge lands exactly at the peek")
  const right_shift = M.sideTuckShift(bodyX, bw, W, peek, left, right, "right")
  assert.equal(Math.round(bodyX + right_shift + bw * left), W - peek)
  assert.equal(M.sideTuckShift(bodyX, bw, W, peek, left, right, "down"), 0)
  // Artwork that says nothing is assumed to fill its cell
  assert.equal(M.sideTuckShift(0, 100, 1000, 10, undefined, undefined, "left"), -90)
  // And downwards, the top of the drawing lands a peek above the edge
  const H = 240, bodyY = 50, top = 0.0433
  const drop = M.sinkShift(bodyY, 190, H, peek, top)
  assert.equal(Math.round(bodyY + drop + 190 * top), H - peek)
  assert.equal(M.sinkShift(300, 190, H, peek, top), 0, "never upwards")
})

test("shoving it against a side asks for it to be put away there", () => {
  const W = 2560, size = 190
  // An ordinary drag stops where the creature can still stand, on any screen
  assert.equal(M.dragTo(1000, -5000, W, size), 57)
  assert.equal(M.dragTo(1000, 5000, W, size), W - 57)
  // Shoving is its own test below; here, only that an ordinary drag stays
  // an ordinary drag and leaves the creature where the hand let go.
  assert.equal(M.dragTo(400, 0, W, size), 400)
  // Its place on the edge is untouched by being put away — only the picture
  // moves — so letting it out puts it back exactly where it was standing.
  assert.equal(M.dragTo(400, 0, W, size), 400)
})


test("a shove asks for the room the hand has, not a fixed distance", () => {
  const W = 2560, H = 456, size = 190, edge = size * 0.3   // 57
  const shove = (px, gx, gy, mx, my) => M.shoveProgress(px, gx, gy, mx, my, W, H, size)

  // Standing in the corner, taken hold of in the middle: the pointer has 57
  // pixels to the screen edge, and that is what the gesture asks for
  assert.equal(shove(57, 57, 350, 0, 0).progress, 0)
  assert.ok(shove(57, 57, 350, -20, 0).progress > 0, "it starts giving way at once")
  assert.equal(shove(57, 57, 350, -50, 0).progress, 1, "and gives way within reach")
  assert.equal(shove(57, 57, 350, -50, 0).side, "left")

  // Taken hold of by its right side there is more room, and it takes more
  assert.ok(shove(57, 117, 350, -50, 0).progress < 1)
  assert.equal(shove(57, 117, 350, -110, 0).progress, 1)

  // The same on the right-hand edge
  assert.equal(shove(W - 57, W - 57, 350, 50, 0).side, "right")
  assert.equal(shove(W - 57, W - 57, 350, 50, 0).progress, 1)

  // Downwards: the room is what is left between the hand and the floor
  assert.equal(shove(1000, 1000, 350, 0, 8).progress, 0, "a twitch is not a shove")
  assert.equal(shove(1000, 1000, 350, 90, 40).progress, 0,
    "a drag going mostly sideways never dips it")
  assert.equal(shove(1000, 1000, 350, 0, 80).progress, 1, "pushed to the floor")
  assert.ok(shove(1000, 1000, 300, 0, 60).progress < 1, "held higher, there is further to go")
  assert.equal(shove(1000, 1000, 440, 0, 14).progress, 1,
    "held by its feet, touching the floor is all there is")
  assert.equal(shove(1000, 1000, 350, 0, -200).progress, 0, "upwards is nothing")
})

test("a shove that has begun does not change its mind", () => {
  const W = 2560, H = 456, size = 190
  const ask = (gy, my, only) => M.shoveProgress(1000, 1000, gy, 0, my, W, H, size, only)
  // Undecided, a small downward move is not yet a shove
  assert.equal(ask(350, 8).progress, 0)
  // Once it is one, the same small move is simply a small amount of it —
  // rather than nothing, which is what made it stutter at the threshold
  assert.ok(ask(350, 8, "down").progress > 0)
  assert.equal(ask(350, -20, "down").progress, 0, "and pulling back gives it all back")
  // Latched to one side, the other side's condition is not consulted
  assert.equal(M.shoveProgress(57, 57, 350, -200, 0, W, H, size, "down").side, "down")
  assert.equal(M.shoveProgress(57, 57, 350, -200, 0, W, H, size, "left").progress, 1)
})
