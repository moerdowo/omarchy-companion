import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { createRequire } from "node:module"
import { runInNewContext } from "node:vm"

const require = createRequire(import.meta.url)
const M = require("../keystone/Model.js")

// Bloub.js and BloubFit.js are QML JavaScript libraries: `.pragma library` and
// `.import` are directives the QML engine reads, not JavaScript, so Node cannot
// require them the way it requires Model.js. Stripping those two lines and
// wiring the one import by hand is the whole difference — everything below this
// point is the same code the shell runs.
function loadQmlJs(path, extra = {}) {
  const source = readFileSync(new URL(path, import.meta.url), "utf8")
    .split("\n")
    .map((line) => (/^\s*\.(pragma|import)\b/.test(line) ? "" : line))
    .join("\n")
  const context = { Math, JSON, isFinite, parseInt, String, Number, Array, Object, ...extra }
  runInNewContext(source, context, { filename: path })
  return context
}

const Fit = loadQmlJs("../keystone/BloubFit.js")
const B = loadQmlJs("../keystone/Bloub.js", { BloubFit: { offset: Fit.offset } })

// Both libraries were evaluated in their own realm, so everything they return
// carries that realm's Object prototype and `deepStrictEqual` rejects it on
// identity alone. Comparing the JSON is comparing what the values are, which is
// what these tests are about.
const same = (actual, expected, message) =>
  assert.equal(JSON.stringify(actual), JSON.stringify(expected), message)

const R = 100

/* ----------------------------------------------------------- the catalogue */

test("the catalogue is what the customiser offered, plus a desktop's two", () => {
  same(B.SHAPES.map((s) => s.id),
    ["cercle", "galet", "squircle", "capsule", "triangle", "hexagone", "nuage", "goutte"])
  // twelve from the original palette, plus a plain white and the theme accent
  assert.equal(B.COLORS.length, 14)
  assert.equal(B.EXPRESSIONS.length, 16)
  assert.equal(B.STATES.length, 15)
})

test("every entry has a unique id and a name worth showing", () => {
  for (const list of [B.SHAPES, B.COLORS, B.EXPRESSIONS]) {
    const ids = list.map((e) => e.id)
    assert.equal(new Set(ids).size, ids.length)
    for (const entry of list) {
      assert.match(entry.id, /^[a-z]+$/)
      assert.ok(entry.name.length > 0 && entry.name.length <= 20, entry.id)
    }
  }
})

test("a fresh install is a white circle wearing nothing in particular", () => {
  assert.equal(B.DEFAULT_SHAPE, "cercle")
  assert.equal(B.DEFAULT_COLOR, "blanc")
  assert.equal(B.DEFAULT_EXPRESSION, "neutre")
  assert.equal(B.COLOR_BY_ID[B.DEFAULT_COLOR].hex, "#ffffff")
  // and a circle is a true circle, which is the one thing about this character
  // that reads as a mistake and is not
  const radii = B.SHAPE_BY_ID.cercle.radii
  assert.ok(radii.every((r) => r === 1))
})

/* ------------------------------------------------------------- validation */

test("a value out of shell.json never leaves the stage empty", () => {
  for (const bad of ["", "nope", "__proto__", null, undefined, 7, {}, "CERCLE"]) {
    assert.equal(B.shapeId(bad), "cercle", String(bad))
    assert.equal(B.colorId(bad), "blanc", String(bad))
    assert.equal(B.expressionId(bad), "neutre", String(bad))
  }
  assert.equal(B.shapeId("goutte"), "goutte")
  assert.equal(B.colorId("encre"), "encre")
  assert.equal(B.expressionId("somnolent"), "somnolent")
})

test("the settings layer only claims to know its own values", () => {
  assert.equal(B.isShapeId("nuage"), true)
  assert.equal(B.isShapeId("encre"), false)
  assert.equal(B.isColorId("encre"), true)
  assert.equal(B.isColorId("nuage"), false)
  assert.equal(B.isExpressionId("fier"), true)
  assert.equal(B.isExpressionId("constructor"), false)
})

test("the theme accent is the one colour the renderer has to resolve", () => {
  assert.equal(B.inkFor("rouge", "#123456"), "#e8483f")
  assert.equal(B.inkFor("theme", "#123456"), "#123456")
  assert.equal(B.inkFor("nonsense", "#123456"), "#ffffff")
})

test("the panel is handed value/label pairs, which is what its pickers read", () => {
  for (const options of [B.panelOptions(B.SHAPES), B.panelOptions(B.COLORS),
                         B.panelOptions(B.EXPRESSIONS)]) {
    for (const option of options) {
      assert.equal(typeof option.value, "string")
      assert.equal(typeof option.label, "string")
    }
  }
  assert.match(B.idsOf(B.SHAPES), /cercle/)
})

/* ------------------------------------------------------------------ moods */

test("every mood the plugin can be in has a state to show it as", () => {
  // the ladder in Model.resolveMood, plus the two the Chief adds by hand
  const moods = ["idle", "tired", "working", "parked", "waiting", "success",
                 "error", "sleeping", "love", "dragged"]
  for (const mood of moods) {
    const id = B.stateForMood(mood)
    assert.ok(B.STATE_BY_ID[id], `${mood} -> ${id}`)
  }
  assert.equal(B.stateForMood("working"), "thinking")
  assert.equal(B.stateForMood("error"), "alert")
  assert.equal(B.stateForMood("success"), "burst")
  assert.equal(B.stateForMood("sleeping"), "sleep")
  assert.equal(B.stateForMood("dragged"), "wide")
  // an unknown mood rests rather than disappearing
  assert.equal(B.stateForMood("nonsense"), "idle")
})

test("a mood may impose an expression; otherwise the person's choice stands", () => {
  assert.equal(B.expressionForMood("tired", "fier"), "somnolent")
  assert.equal(B.expressionForMood("love", "fier"), "heureux")
  assert.equal(B.expressionForMood("idle", "fier"), "fier")
  assert.equal(B.expressionForMood("working", "nonsense"), "neutre")
})

test("an idle glance never carries news, and never repeats what is worn", () => {
  const alarming = ["triste", "colere", "effraye", "mefiant", "confus", "somnolent"]
  for (const id of B.IDLE_EXPRESSIONS) {
    assert.ok(B.EXPRESSION_BY_ID[id], id)
    assert.ok(!alarming.includes(id), `${id} has news in it`)
  }
  // Assert what it IS, not only what it is not. Checking `notEqual(worn)` alone
  // passed while the function was returning `undefined` for every call, because
  // undefined is indeed not the expression being worn.
  const known = new Set(B.EXPRESSIONS.map((e) => e.id))
  for (const worn of B.IDLE_EXPRESSIONS) {
    for (const roll of [0, 0.25, 0.5, 0.99, 1]) {
      const picked = B.idleExpression(() => roll, worn)
      assert.ok(known.has(picked), `picked ${picked} for roll ${roll}`)
      assert.notEqual(picked, worn)
    }
  }
  // Every idle expression must be reachable, or the pool is smaller than it looks.
  const seen = new Set()
  for (let i = 0; i < 200; i++) seen.add(B.idleExpression(Math.random, ""))
  assert.equal(seen.size, B.IDLE_EXPRESSIONS.length)
})

/* ----------------------------------------------------- standby performances */

test("a performance is a real state held for a sane length of time", () => {
  assert.ok(B.PERFORMANCES.length >= 6)
  const names = B.PERFORMANCES.map((p) => p.name)
  assert.equal(new Set(names).size, names.length)
  for (const performance of B.PERFORMANCES) {
    const state = B.STATE_BY_ID[performance.state]
    assert.ok(state, `${performance.name} names no state`)
    assert.match(performance.name, /^[a-z]+$/)
    // Cut before it resolves and the animation is a fragment: the "!" never
    // comes back, the body stays burst. Those lengths are read off the state's
    // own constants, so this is a real floor and not a preference.
    if (state.minDuration !== undefined) {
      assert.ok(performance.seconds >= state.minDuration,
        `${performance.name} is ${performance.seconds}s, under ${state.minDuration}s`)
    }
    assert.ok(performance.seconds >= 1.2 && performance.seconds <= 20, performance.name)
  }
})

test("a performance never says something is happening", () => {
  // These four states are how the plugin reports work, waiting, failure and
  // success. A creature that played one for its own amusement would be crying
  // wolf, and the next real one would not be believed.
  const news = new Set(["thinking", "notify", "alert", "burst", "exclaim"])
  for (const performance of B.PERFORMANCES) {
    assert.ok(!news.has(performance.state), `${performance.name} performs the news`)
  }
  // and every mood that has news maps to one of exactly those
  for (const mood of ["working", "waiting", "error", "success"]) {
    assert.ok(news.has(B.stateForMood(mood)), mood)
  }
})

test("the repertoire covers looking up, sleeping, and changing shape", () => {
  const byName = Object.fromEntries(B.PERFORMANCES.map((p) => [p.name, p]))
  // looking at whoever is at the desk keeps the resting body and face, so the
  // chosen shape and expression survive it
  assert.equal(byName.notice.state, "idle")
  assert.equal(B.STATE_BY_ID.idle.baseBody, true)
  assert.equal(B.STATE_BY_ID.idle.baseFace, true)
  // sleeping is the one whose point is that nothing happens, so it is the
  // longest by a clear margin rather than a blink that reads as a glitch
  assert.equal(byName.doze.state, "sleep")
  const others = B.PERFORMANCES.filter((p) => p.name !== "doze").map((p) => p.seconds)
  assert.ok(byName.doze.seconds >= Math.max(...others) * 2)
  // and there is more than one thing to do besides those two
  assert.ok(B.PERFORMANCES.length - 2 >= 4)
})

test("performances are handed over as the activity tracks the plugin schedules", () => {
  const tracks = B.performanceTracks()
  assert.equal(tracks.length, B.PERFORMANCES.length)
  for (const track of tracks) {
    // Model.activityDuration multiplies frames by holds, so one frame held for
    // the whole performance is how a drawn one states its length to code that
    // was written for spritesheets.
    assert.equal(track.frames, 1)
    assert.equal(track.holds.length, 1)
    assert.equal(M.activityDuration(track, 560), track.holds[0])
    assert.equal(M.activityDuration(track, 560) / 1000, B.performanceSeconds(track.name))
  }
  // and the scheduler can actually pick one, without repeating the last
  const picked = M.pickActivity(() => 0, tracks, 1, tracks[0].name)
  assert.ok(picked && picked.name !== tracks[0].name)
})

test("an unknown performance rests rather than throwing", () => {
  assert.equal(B.performanceState("nonsense"), "idle")
  assert.equal(B.performanceState("constructor"), "idle")
  assert.equal(B.performanceState(""), "idle")
  assert.equal(B.performanceSeconds("nonsense"), 0)
})

test("looking up at you starts and ends holding nothing", () => {
  const seconds = B.performanceSeconds("notice")
  // The rule that makes a gaze script maintenance-free: it must finish at
  // mix 0, so there is never a last slide of the eyes after everything should
  // have settled.
  assert.equal(B.noticeLook(0, seconds, true).mix, 0)
  assert.equal(B.noticeLook(seconds, seconds, true).mix, 0)
  assert.equal(B.noticeLook(seconds + 5, seconds, true).mix, 0)

  let peak = 0
  for (let t = 0; t <= seconds; t += 0.02) {
    const look = B.noticeLook(t, seconds, true)
    peak = Math.max(peak, look.mix)
    assert.ok(look.mix >= 0 && look.mix <= 1, `mix ${look.mix} at ${t}`)
    // the automatic drift comes back exactly as the look lets go
    assert.ok(Math.abs(look.wander - (1 - look.mix)) < 1e-9)
    assert.ok(isFinite(look.yaw + look.pitch + look.spin))
  }
  assert.ok(peak > 0.99, `only reached ${peak}`)

  // A whole turn is the same angle as none, so it lands where it aims however
  // far round it went; it is spent by the time the look is holding.
  assert.equal(B.noticeLook(0, seconds, true).spin, 360)
  assert.equal(B.noticeLook(1.2, seconds, true).spin, 0)
  // On a shape that is not a circle the eyes are re-seated to the outline, so
  // travelling round it makes them hop along the profile. There they slide.
  for (let t = 0; t <= seconds; t += 0.1) {
    assert.equal(B.noticeLook(t, seconds, false).spin, 0)
  }
})

test("looking up actually moves the eyes, and gives them back", () => {
  const seconds = B.performanceSeconds("notice")
  const engine = B.createEngine(R, "idle", "cercle", "neutre")

  // Driven every frame, the way the renderer drives it. Setting the target
  // once and sampling at that same instant proves nothing: the engine's
  // catch-up starts from where the gaze already was, so it would still be
  // there — which is exactly the inertia that makes the tracking read as
  // looking rather than as snapping.
  const play = (until) => {
    let frame = null
    for (let t = 0; t <= until + 1e-9; t += 1 / 30) {
      engine.setLook(B.noticeLook(t, seconds, true), t, 0.05)
      frame = engine.sample(t)
    }
    return frame
  }

  const restingAt = (t) => B.createEngine(R, "idle", "cercle", "neutre").sample(t)
  const held = play(1.7)
  const resting = restingAt(1.7)
  const moved = Math.hypot(held.eyes[0].m[4] - resting.eyes[0].m[4],
                           held.eyes[0].m[5] - resting.eyes[0].m[5])
  assert.ok(moved > 20, `eyes only moved ${moved.toFixed(1)}`)

  // and by the end they are back where the pose alone would have put them
  const after = play(seconds + 1)
  const back = restingAt(seconds + 1)
  const gap = Math.hypot(after.eyes[0].m[4] - back.eyes[0].m[4],
                         after.eyes[0].m[5] - back.eyes[0].m[5])
  assert.ok(gap < 1, `eyes ended ${gap.toFixed(2)} away from resting`)
})

/* ----------------------------------------------------------------- engine */

const sig = (frame) => JSON.stringify([
  frame.bodyPts, frame.eyes, frame.dots, frame.arcs.map((a) => [a.front, a.back]),
  frame.notif, frame.bodyAlpha, frame.dotsBehind])

test("sampling is a pure function of time, forwards and backwards", () => {
  const engine = B.createEngine(R, "idle", "galet", "curieux")
  engine.setState("thinking", 0.4)
  engine.setState("idle", 0.9)
  const dates = [0, 0.2, 0.41, 0.6, 0.95, 1.4, 2.2]
  const first = dates.map((t) => sig(engine.sample(t)))
  // read again in the same order, then backwards: an engine that quietly kept
  // state would disagree with itself here
  assert.deepEqual(dates.map((t) => sig(engine.sample(t))), first)
  assert.deepEqual(dates.slice().reverse().map((t) => sig(engine.sample(t))),
                   first.slice().reverse())
})

test("a shape change morphs, and lands exactly on the shape asked for", () => {
  const engine = B.createEngine(R, "idle", "cercle", "neutre")
  const before = engine.sample(0).bodyPts.map((p) => ({ ...p }))
  engine.setShape("triangle", 0)
  const mid = engine.sample(0.2).bodyPts
  // partway there: neither where it was nor where it is going
  assert.notDeepEqual(mid.map((p) => Math.round(p.x)), before.map((p) => Math.round(p.x)))
  const after = engine.sample(5).bodyPts
  const target = B.createEngine(R, "idle", "triangle", "neutre").sample(5).bodyPts
  for (let i = 0; i < after.length; i++) {
    assert.ok(Math.abs(after[i].x - target[i].x) < 1e-9)
    assert.ok(Math.abs(after[i].y - target[i].y) < 1e-9)
  }
})

test("a state change arriving mid-fade does not make the body jump", () => {
  // The engine keeps one slot of history, so a change during a fade used to
  // blend from the full pose of the state being left rather than from the
  // frame actually on screen. Measured on this exact chain at the time: a
  // 35.9 px jump against 8.0 px of normal movement.
  const engine = B.createEngine(R, "idle", "cercle", "neutre")
  engine.setState("wide", 0.5)
  engine.setState("idle", 0.6)
  let previous = engine.sample(0.6).bodyPts.map((p) => ({ ...p }))
  let worst = 0
  for (let t = 0.61; t < 1.2; t += 0.01) {
    const now = engine.sample(t).bodyPts
    for (let i = 0; i < now.length; i++) {
      worst = Math.max(worst, Math.hypot(now[i].x - previous[i].x, now[i].y - previous[i].y))
    }
    previous = now.map((p) => ({ ...p }))
  }
  assert.ok(worst < 4, `largest step between frames was ${worst.toFixed(2)} px`)
})

test("a non-finite gaze target is refused rather than poisoning every frame", () => {
  const engine = B.createEngine(R, "idle", "cercle", "neutre")
  engine.setLook(B.lookAt(0.5, -0.5, 1), 0)
  const good = sig(engine.sample(1))
  engine.setLook({ yaw: NaN, pitch: 0, mix: 1, spin: 0, wander: 0 }, 1)
  assert.equal(sig(engine.sample(1)), good)
  for (const point of engine.sample(1).bodyPts) {
    assert.ok(isFinite(point.x) && isFinite(point.y))
  }
})

test("looking at a pointer stays inside the angles the head can hold", () => {
  for (const [nx, ny] of [[0, 0], [1, 1], [-1, -1], [4, -9]]) {
    const look = B.lookAt(nx, ny, 1)
    assert.ok(Math.abs(look.yaw) <= 16 + 1e-9, `yaw ${look.yaw}`)
    assert.ok(look.pitch >= 10 - 13 - 1e-9 && look.pitch <= 10 + 13 + 1e-9)
    // with a pointer to follow, the automatic drift stands down
    assert.equal(look.wander, 0)
  }
  assert.equal(B.lookAt(0, 0, 0).wander, 1)
})

/* --------------------------------------------------------------- geometry */

function inside(polygon, x, y) {
  let hit = false
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[i]
    const b = polygon[j]
    if ((a.y > y) !== (b.y > y)
        && x < ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x) hit = !hit
  }
  return hit
}

/** The outline of an eye, in the same frame as the body points. */
function eyeOutline(eye) {
  const hw = eye.w / 2
  const hh = eye.h / 2
  const r = Math.min(hw, hh)
  const points = []
  for (let i = 0; i < 48; i++) {
    const a = (i / 48) * Math.PI * 2
    // the capsule is a segment thickened by a disc, so its boundary is the
    // disc swept between the two end centres
    const end = Math.cos(a) * (hw - r) >= 0 ? 1 : -1
    const cx = hw > hh ? end * (hw - r) : 0
    const cy = hw > hh ? 0 : end * (hh - r)
    const px = cx + Math.cos(a) * r
    const py = cy + Math.sin(a) * r
    points.push({
      x: eye.m[0] * px + eye.m[2] * py + eye.m[4],
      y: eye.m[1] * px + eye.m[3] * py + eye.m[5]
    })
  }
  return points
}

test("the eyes stay inside every body shape, in every expression", () => {
  // This is what BloubFit.js is for. Re-seating the eyes pro rata to the local
  // radius places their CENTRE correctly, but an eye has a size, and on a
  // narrow silhouette that pushed the capsule through the outline — visible as
  // the body opening outwards around a notch. The table is the fix, so the
  // table is what this checks, across the whole resting drift.
  const escapes = []
  for (const shape of B.SHAPES) {
    for (const expression of B.EXPRESSIONS) {
      const engine = B.createEngine(R, "idle", shape.id, expression.id)
      for (let t = 0; t < 12; t += 0.37) {
        const frame = engine.sample(t)
        for (const eye of frame.eyes) {
          if (eye.alpha < 0.5) continue
          for (const point of eyeOutline(eye)) {
            if (!inside(frame.bodyPts, point.x, point.y)) {
              escapes.push(`${shape.id}/${expression.id} at t=${t.toFixed(2)}`)
            }
          }
        }
      }
    }
  }
  assert.deepEqual(escapes.slice(0, 8), [], `${escapes.length} escapes`)
})

test("the creature itself always fits the frame the canvas reserves", () => {
  // Chief.qml inflates the canvas by OVERFLOW on each side and lowers the
  // ground line by the same amount, so this is what that number has to cover.
  //
  // The CREATURE is what must fit: its body, the dots it becomes, the pip and
  // its notch. The orbit and swoosh arcs may run past it, and do — the sweep in
  // `play` reaches about 1.66 radii — but the original clips them at exactly
  // this frame too, because that is its SVG view box. Reserving more than the
  // original drew would not be more faithful, it would be a different picture.
  const limit = R * (1 + B.OVERFLOW * 2)
  let reach = 0
  let worst = ""
  for (const state of B.STATES) {
    // The chosen shape only replaces the body on the resting states; elsewhere
    // the silhouette IS the animation, so one pass covers those.
    const shapes = state.baseBody ? B.SHAPES.map((s) => s.id) : ["cercle"]
    for (const shape of shapes) {
      const engine = B.createEngine(R, state.id, shape, "surpris")
      for (let t = 0; t <= 4; t += 0.1) {
        const frame = engine.sample(t)
        const bump = (value, what) => {
          if (value > reach) { reach = value; worst = `${state.id}/${shape} ${what}` }
        }
        for (const point of frame.bodyPts) bump(Math.max(Math.abs(point.x), Math.abs(point.y)), "body")
        for (const dot of frame.dots) {
          bump(Math.max(Math.abs(dot.x), Math.abs(dot.y)) + dot.r, "dot")
        }
        for (const eye of frame.eyes) {
          for (const point of eyeOutline(eye)) {
            bump(Math.max(Math.abs(point.x), Math.abs(point.y)), "eye")
          }
        }
        if (frame.notch) bump(Math.max(Math.abs(frame.notch.x), Math.abs(frame.notch.y)) + frame.notch.r, "pip")
      }
    }
  }
  assert.ok(reach <= limit, `reached ${reach.toFixed(1)} of ${limit.toFixed(1)} at ${worst}`)
})

test("the eye-fit table covers every shape the picker offers", () => {
  for (const shape of B.SHAPES) {
    // a resting body with a resting face: one entry per expression
    for (const expression of B.EXPRESSIONS) {
      const value = Fit.offset(shape.id, "idle", expression.id)
      assert.equal(typeof value.x, "number", `${shape.id}/${expression.id}`)
      assert.ok(isFinite(value.x) && isFinite(value.y))
    }
    // a resting body wearing the video's own face: one entry whatever is chosen
    same(Fit.offset(shape.id, "wink", "colere"), Fit.offset(shape.id, "wink", null))
  }
  // the circle is the shape the character was measured on, so it never moves
  for (const expression of B.EXPRESSIONS) {
    same(Fit.offset("cercle", "idle", expression.id), { x: 0, y: 0 }, expression.id)
  }
  // an unknown shape corrects nothing rather than throwing, and `constructor`
  // is not a shape however truthy a plain object says it is
  same(Fit.offset("nonsense", "idle", "neutre"), { x: 0, y: 0 })
  same(Fit.offset(null, "idle", null), { x: 0, y: 0 })
  same(Fit.offset("constructor", "idle", "neutre"), { x: 0, y: 0 })
  same(Fit.offset("cercle", "idle", "__proto__"), { x: 0, y: 0 })
})

/* ------------------------------------------------------------------ paint */

/** A Canvas context that records what it was asked to do. */
function recordingContext() {
  const calls = []
  const handler = {
    get(target, name) {
      if (name === "calls") return calls
      if (name === "createLinearGradient") {
        return () => ({ addColorStop() {} })
      }
      if (typeof name !== "string") return undefined
      return (...args) => { calls.push([name, ...args]) }
    },
    set(target, name, value) { calls.push(["=" + name, value]); return true }
  }
  return new Proxy({}, handler)
}

test("painting fills a body, then cuts the eyes out of it", () => {
  const engine = B.createEngine(R, "idle", "goutte", "curieux")
  const ctx = recordingContext()
  B.paint(ctx, engine.sample(1), "#ffffff", "#101010")
  const names = ctx.calls.map((c) => c[0])
  assert.ok(names.includes("bezierCurveTo"), "the outline is drawn as curves")
  assert.ok(names.includes("clip"), "the eyes are clipped to the body")
  // The eyes are holes, so what they show is the ground, never white paint.
  const fills = ctx.calls.filter((c) => c[0] === "=fillStyle").map((c) => c[1])
  assert.ok(fills.includes("#ffffff"), "the body wears the chosen colour")
  assert.ok(fills.includes("#101010"), "the eyes show the ground")
  // Nothing is ever filled before a path has been opened. Filling twice over
  // one path is deliberate — the body is laid down in the ground colour and
  // then in its own — so a fill does not close the path, only beginPath does.
  let opened = false
  for (const [name] of ctx.calls) {
    if (name === "beginPath") opened = true
    if (name === "fill" || name === "stroke") assert.ok(opened, "a fill without a path")
  }
  // and the clip is released again, or the rest of the frame is cropped
  assert.equal(names.filter((n) => n === "save").length,
               names.filter((n) => n === "restore").length)
})

test("the decorated states paint their rings on both sides of the body", () => {
  for (const id of ["orbit", "comet", "burst", "alert", "notify"]) {
    const ctx = recordingContext()
    B.paint(ctx, B.createEngine(R, id, "cercle", "neutre").sample(1), "#ffffff", "#101010")
    assert.ok(ctx.calls.length > 0, id)
  }
})

/* --------------------------------------------------------- the plugin's own */

test("a drawn pet declares a renderer instead of a spritesheet", () => {
  const manifest = JSON.parse(readFileSync(new URL("../pets/bloub/pet.json", import.meta.url), "utf8"))
  assert.equal(manifest.render, "bloub")
  assert.equal(manifest.spritesheetPath, undefined)
  assert.equal(M.resolvePetSize(undefined, manifest.size), manifest.size)
})
