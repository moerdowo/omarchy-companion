// The bloub character: one filled shape that morphs between states, with two
// capsule eyes cut out of it.
//
// Ported from bloub (github.com/jeremy-prt/bloub, MIT, (c) Jérémy Perret),
// an SVG recreation of the x.ai bot avatar. The numbers here are measurements
// taken off the reference video at 10 fps, not chosen values: rounding them to
// friendlier ones breaks the resemblance, which is the only thing the original
// set out to get right. Three that read as mistakes and are not:
//
//   - the eyes lean `\\`, about 26 degrees off vertical, never `//`;
//   - the body is a true circle, radial deviation under 0.7%, not a squircle;
//   - transitions are exponential ease-outs — the body never overshoots.
//
// What changed in the port is the output, not the geometry: the original emits
// SVG path strings for a browser, this emits points and matrices for QML's
// Canvas. Every constant, easing and schedule is carried over unaltered.

.pragma library

.import "BloubFit.js" as BloubFit

/* ------------------------------------------------------- the drawing frame */

/**
 * The resting ball's radius, in view-box units. Chosen, not measured: it is the
 * working unit, and everything else in this file is expressed as a fraction of
 * it, which is what makes the measurements independent of display size.
 */
var RAYON = 100

/**
 * Half the view box. The margin past the radius is where the rings live: the
 * orbit's and the comet's swoosh reach 1.4 radii, and nothing bounds them at
 * runtime — it is the hand-tuned RINGS and SWOOSH tables that hold them under
 * 158.
 */
var DEMI_VIEWBOX = 158

/**
 * How far the drawing reaches past the creature on each side, as a fraction of
 * its diameter. The canvas is inflated by this and the ground line lowered by
 * it, so an orbit is not sliced off by the bottom of the screen.
 */
var OVERFLOW = (DEMI_VIEWBOX - RAYON) / (RAYON * 2)

/* ------------------------------------------------------------------- math */

/**
 * Reads an id out of one of the catalogues below.
 *
 * Every one of those ids arrives from shell.json or a command line, so a plain
 * `map[value]` is not a lookup: `constructor` and `prototype` are inherited
 * from Object and answer truthy, which would have `isShapeId("constructor")`
 * say yes and the engine then ask a function for its radii.
 */
function lookup(map, value) {
  var key = String(value === undefined || value === null ? "" : value)
  return Object.prototype.hasOwnProperty.call(map, key) ? map[key] : null
}

var TAU = Math.PI * 2

function clamp(v, lo, hi) {
  if (lo === undefined) lo = 0
  if (hi === undefined) hi = 1
  return v < lo ? lo : (v > hi ? hi : v)
}

function lerp(a, b, t) { return a + (b - a) * t }

// Measured on the video: transitions are exponential ease-outs with no body
// overshoot. The only springs are local — the notification pip popping in, and
// the eyes opening — and those are written into the states that own them.
var easings = {
  easeOutCubic: function(t) { return 1 - Math.pow(1 - t, 3) },
  easeInOutCubic: function(t) {
    return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2
  },
  easeOutQuint: function(t) { return 1 - Math.pow(1 - t, 5) }
}

// Periodic 1D noise: loops seamlessly over `period`, which is what keeps the
// gaze drifting without ever visibly repeating.
function loopNoise(t, period, seed) {
  if (seed === undefined) seed = 0
  var p = (t / period) * TAU
  return 0.55 * Math.sin(p + seed)
    + 0.3 * Math.sin(2 * p + seed * 1.7 + 1.1)
    + 0.15 * Math.sin(3 * p + seed * 2.3 + 2.4)
}

// mulberry32: the same sequence on every read, so the blink calendar and the
// ring seeds are identical in every session and every process.
function createRng(seed) {
  var a = seed >>> 0
  return function() {
    a = (a + 0x6d2b79f5) >>> 0
    var t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/* --------------------------------------------------------------- profiles */

// Radial profiles r(theta) measured pixel by pixel off the reference video.
// theta = 0 points right and grows clockwise (y goes down). Unit: the resting
// ball's radius = 1.
var PROFILE_SAMPLES = 64

var PROFILES = {
  // egg: the ball's height, narrowed. Frame 164, footprint 1.647 x 2.000.
  egg: [0.8369,0.8424,0.8497,0.8585,0.8674,0.8775,0.8878,0.8983,0.9089,0.9185,0.9288,0.9374,0.9445,0.9504,0.9543,0.9559,0.9555,0.9519,0.9466,0.9389,0.9302,0.9193,0.9085,0.8969,0.8852,0.8734,0.8625,0.8513,0.8411,0.8325,0.8243,0.8179,0.8137,0.8112,0.8102,0.8128,0.8178,0.8262,0.8374,0.8518,0.8702,0.8922,0.9169,0.9446,0.9741,1.0023,1.0267,1.0433,1.0481,1.0393,1.0216,0.9970,0.9697,0.9418,0.9169,0.8949,0.8760,0.8604,0.8490,0.8394,0.8337,0.8314,0.8305,0.8326],
  // hexagon, point up, very round corners. Frame 174, footprint 1.826 x 2.011.
  hexagon: [0.9210,0.9282,0.9441,0.9706,0.9984,1.0059,0.9896,0.9562,0.9290,0.9124,0.9047,0.9058,0.9157,0.9349,0.9642,0.9873,0.9882,0.9665,0.9336,0.9105,0.8968,0.8918,0.8955,0.9080,0.9293,0.9611,0.9820,0.9812,0.9590,0.9282,0.9089,0.8978,0.8964,0.9026,0.9189,0.9439,0.9778,0.9990,0.9964,0.9713,0.9439,0.9274,0.9196,0.9206,0.9308,0.9502,0.9799,1.0121,1.0226,1.0071,0.9752,0.9510,0.9366,0.9316,0.9351,0.9485,0.9711,1.0026,1.0213,1.0155,0.9863,0.9547,0.9347,0.9232],
  // triangle, point up, very round corners. Frame 190, footprint 1.995 x 1.884.
  triangle: [0.7819,0.8211,0.8747,0.9440,1.0223,1.0960,1.1401,1.1340,1.0808,1.0047,0.9265,0.8603,0.8104,0.7730,0.7450,0.7273,0.7151,0.7118,0.7148,0.7245,0.7427,0.7680,0.8037,0.8518,0.9148,0.9876,1.0583,1.1073,1.1109,1.0667,0.9940,0.9164,0.8482,0.7948,0.7555,0.7261,0.7056,0.6925,0.6859,0.6869,0.6938,0.7084,0.7305,0.7615,0.8040,0.8595,0.9311,1.0092,1.0791,1.1171,1.1054,1.0501,0.9779,0.9050,0.8450,0.7990,0.7656,0.7413,0.7258,0.7160,0.7146,0.7204,0.7330,0.7528]
}

/* ------------------------------------------------------------- silhouettes */

// A silhouette is a radial profile r(theta) plus a pose.
//
// Every profile is sampled at the SAME angles, so any two shapes have points
// that correspond one to one and morphing is a linear interpolation of radii.
// That is what makes the transitions clean without a path-morphing library.

var ANGLES = []
var COS = []
var SIN = []
for (var _i = 0; _i < PROFILE_SAMPLES; _i++) {
  var _a = (_i / PROFILE_SAMPLES) * TAU
  ANGLES.push(_a)
  COS.push(Math.cos(_a))
  SIN.push(Math.sin(_a))
}

function poseDefaults(radii, pose) {
  var out = { radii: radii, rot: 0, cx: 0, cy: 0, sx: 1, sy: 1 }
  if (pose) for (var k in pose) out[k] = pose[k]
  return out
}

function silhouette(name, pose) {
  return poseDefaults(PROFILES[name].slice(), pose)
}

/** A true circle: the neutral base, and the target every fade resolves to. */
function circle(radius, pose) {
  var radii = new Array(PROFILE_SAMPLES)
  for (var i = 0; i < PROFILE_SAMPLES; i++) radii[i] = radius
  return poseDefaults(radii, pose)
}

/** Interpolates two silhouettes. `out` is reused to avoid allocating at 60 fps. */
function blendSil(a, b, t, out) {
  var dst = out || { radii: new Array(PROFILE_SAMPLES), rot: 0, cx: 0, cy: 0, sx: 1, sy: 1 }
  for (var i = 0; i < PROFILE_SAMPLES; i++) {
    var ra = a.radii[i] === undefined ? 1 : a.radii[i]
    var rb = b.radii[i] === undefined ? 1 : b.radii[i]
    dst.radii[i] = lerp(ra, rb, t)
  }
  // Shortest-path rotation: going from +170 to -170 degrees must not spin all
  // the way round the long side.
  var dRot = b.rot - a.rot
  while (dRot > Math.PI) dRot -= TAU
  while (dRot < -Math.PI) dRot += TAU
  dst.rot = a.rot + dRot * t
  dst.cx = lerp(a.cx, b.cx, t)
  dst.cy = lerp(a.cy, b.cy, t)
  dst.sx = lerp(a.sx, b.sx, t)
  dst.sy = lerp(a.sy, b.sy, t)
  return dst
}

/** Projects a silhouette to screen points. `scale` = ball radius in view units. */
function toPoints(s, scale, out) {
  if (!out) out = []
  var cr = Math.cos(s.rot)
  var sr = Math.sin(s.rot)
  for (var i = 0; i < PROFILE_SAMPLES; i++) {
    var r = s.radii[i] === undefined ? 1 : s.radii[i]
    var x = r * COS[i]
    var y = r * SIN[i]
    // rotate, then squash in screen space, then translate
    var rx = x * cr - y * sr
    var ry = x * sr + y * cr
    var p = out[i] || { x: 0, y: 0 }
    p.x = (rx * s.sx + s.cx) * scale
    p.y = (ry * s.sy + s.cy) * scale
    out[i] = p
  }
  out.length = PROFILE_SAMPLES
  return out
}

/**
 * Closed polyline -> Catmull-Rom cubics, emitted straight into a Canvas path.
 *
 * With 64 points centred tangents are plenty: the outline is smooth to the
 * pixel even at 600 px, and there is nothing to allocate per frame.
 */
function traceClosed(ctx, pts, tension) {
  if (tension === undefined) tension = 1 / 6
  var n = pts.length
  if (n < 3) return
  ctx.moveTo(pts[0].x, pts[0].y)
  for (var i = 0; i < n; i++) {
    var p0 = pts[(i - 1 + n) % n]
    var p1 = pts[i]
    var p2 = pts[(i + 1) % n]
    var p3 = pts[(i + 2) % n]
    ctx.bezierCurveTo(
      p1.x + (p2.x - p0.x) * tension, p1.y + (p2.y - p0.y) * tension,
      p2.x - (p3.x - p1.x) * tension, p2.y - (p3.y - p1.y) * tension,
      p2.x, p2.y)
  }
  ctx.closePath()
}

/**
 * Arbitrary polygon -> radial profile, by casting rays from `center`.
 *
 * Builds the shapes that do not express naturally as r(theta) — the tapered
 * bar of the "!". Computed once at load, never in the render loop.
 */
function profileFromPolygon(poly, cx, cy) {
  var radii = new Array(PROFILE_SAMPLES)
  var n = poly.length
  for (var k = 0; k < PROFILE_SAMPLES; k++) {
    var dx = COS[k]
    var dy = SIN[k]
    var best = 0
    for (var i = 0; i < n; i++) {
      var a = poly[i]
      var b = poly[(i + 1) % n]
      var ex = b.x - a.x
      var ey = b.y - a.y
      var den = dx * ey - dy * ex
      if (Math.abs(den) < 1e-9) continue
      var px = a.x - cx
      var py = a.y - cy
      var t = (px * ey - py * ex) / den // distance along the ray
      var u = (px * dy - py * dx) / den // position along the segment
      if (t > best && u >= 0 && u <= 1) best = t
    }
    radii[k] = best
  }
  return radii
}

/** Convex hull of two circles: the tapered bar of the upright "!". */
function hullOfCircles(x1, y1, r1, x2, y2, r2v, steps) {
  if (steps === undefined) steps = 96
  var dx = x2 - x1
  var dy = y2 - y1
  var dist = Math.hypot(dx, dy) || 1e-6
  // angle of the common external tangents
  var base = Math.atan2(dy, dx)
  var spread = Math.acos(Math.max(-1, Math.min(1, (r1 - r2v) / dist)))
  var pts = []
  var half = steps / 2
  var i, a
  for (i = 0; i <= half; i++) {
    a = base + spread + ((TAU - 2 * spread) * i) / half
    pts.push({ x: x1 + Math.cos(a) * r1, y: y1 + Math.sin(a) * r1 })
  }
  for (i = 0; i <= half; i++) {
    a = base - spread + (2 * spread * i) / half
    pts.push({ x: x2 + Math.cos(a) * r2v, y: y2 + Math.sin(a) * r2v })
  }
  return pts
}

/**
 * The profile's radius in an arbitrary direction, interpolated between the two
 * neighbouring samples.
 *
 * Re-seats whatever sits ON the body — the eyes, the notification pip — once
 * the silhouette stops being a circle: without it an eye placed at 0.62 radius
 * leaves a shape whose edge is at 0.55 in that direction, and gets clipped.
 */
function radiusAtAngle(radii, angle) {
  var n = radii.length
  var t = ((((angle / TAU) % 1) + 1) % 1) * n
  var i = Math.floor(t)
  var ra = radii[i % n] === undefined ? 1 : radii[i % n]
  var rb = radii[(i + 1) % n] === undefined ? 1 : radii[(i + 1) % n]
  return lerp(ra, rb, t - i)
}

/** Superellipse |x/sx|^n + |y/sy|^n = 1. n = 2 is an ellipse, n ~ 4 the squircle. */
function superellipseProfile(n, sx, sy) {
  if (sx === undefined) sx = 1
  if (sy === undefined) sy = 1
  var out = new Array(PROFILE_SAMPLES)
  for (var i = 0; i < PROFILE_SAMPLES; i++) {
    var c = Math.pow(Math.abs(COS[i] / sx), n)
    var s = Math.pow(Math.abs(SIN[i] / sy), n)
    out[i] = Math.pow(c + s, -1 / n)
  }
  return out
}

/**
 * Radial profile of a UNION of discs: r(theta) is the farthest ray/circle
 * intersection. Exact as long as the origin is inside the union — this is what
 * gives the cloud its lobes without a path boolean.
 */
function unionOfCirclesProfile(circles) {
  var out = new Array(PROFILE_SAMPLES)
  for (var i = 0; i < PROFILE_SAMPLES; i++) {
    var dx = COS[i]
    var dy = SIN[i]
    var best = 0
    for (var j = 0; j < circles.length; j++) {
      var c = circles[j]
      var b = dx * c.x + dy * c.y
      var disc = b * b - (c.x * c.x + c.y * c.y - c.r * c.r)
      if (disc < 0) continue
      var t = b + Math.sqrt(disc)
      if (t > best) best = t
    }
    out[i] = best
  }
  return out
}

/**
 * Polygon with rounded corners, as a Minkowski sum with a disc: every edge is
 * pushed out by `rc` and every vertex becomes an arc of radius `rc`. Vertices
 * are therefore placed at the wanted radius MINUS rc. Expects a clockwise
 * polygon in screen space (y down).
 */
function roundedPolygon(verts, rc, arcSteps) {
  if (arcSteps === undefined) arcSteps = 10
  var n = verts.length
  var out = []
  var normal = function(a, b) {
    var dx = b.x - a.x
    var dy = b.y - a.y
    var len = Math.hypot(dx, dy) || 1
    // clockwise with y down: the outward normal is (dy, -dx)
    return Math.atan2(-dx / len, dy / len)
  }
  for (var i = 0; i < n; i++) {
    var prev = verts[(i - 1 + n) % n]
    var cur = verts[i]
    var next = verts[(i + 1) % n]
    var a0 = normal(prev, cur)
    var a1 = normal(cur, next)
    var d = a1 - a0
    while (d > Math.PI) d -= TAU
    while (d < -Math.PI) d += TAU
    for (var k = 0; k <= arcSteps; k++) {
      var a = a0 + (d * k) / arcSteps
      out.push({ x: cur.x + Math.cos(a) * rc, y: cur.y + Math.sin(a) * rc })
    }
  }
  return out
}

/** Regular polygon with rounded corners, inscribed in `radius`. */
function regularPolygonProfile(sides, radius, rc, rotationDeg) {
  if (rotationDeg === undefined) rotationDeg = 0
  var rot = (rotationDeg * Math.PI) / 180
  var verts = []
  for (var i = 0; i < sides; i++) {
    // clockwise on screen: theta grows with y pointing down
    var a = rot + (i / sides) * TAU
    verts.push({ x: Math.cos(a) * (radius - rc), y: Math.sin(a) * (radius - rc) })
  }
  return profileFromPolygon(roundedPolygon(verts, rc), 0, 0)
}

/**
 * Capsule (stadium) centred on the origin: the exact shape of the bot's eyes,
 * as bezier segments in local units so the caller can map them through the
 * tangent matrix itself.
 */
var KAPPA = 0.5522847498
function capsuleSegments(w, h) {
  var hw = Math.max(w, 0.01) / 2
  var hh = Math.max(h, 0.01) / 2
  var r = Math.min(hw, hh)
  var k = KAPPA * r
  return {
    start: { x: -hw, y: -hh + r },
    segs: [
      [{ x: -hw, y: -hh + r - k }, { x: -hw + r - k, y: -hh }, { x: -hw + r, y: -hh }],
      [{ x: -hw + r, y: -hh }, { x: hw - r, y: -hh }, { x: hw - r, y: -hh }],
      [{ x: hw - r + k, y: -hh }, { x: hw, y: -hh + r - k }, { x: hw, y: -hh + r }],
      [{ x: hw, y: -hh + r }, { x: hw, y: hh - r }, { x: hw, y: hh - r }],
      [{ x: hw, y: hh - r + k }, { x: hw - r + k, y: hh }, { x: hw - r, y: hh }],
      [{ x: hw - r, y: hh }, { x: -hw + r, y: hh }, { x: -hw + r, y: hh }],
      [{ x: -hw + r - k, y: hh }, { x: -hw, y: hh - r + k }, { x: -hw, y: hh - r }]
    ]
  }
}

/** Traces a capsule through the 2x3 matrix `m` = [a, b, c, d, e, f]. */
function traceCapsule(ctx, w, h, m) {
  var cap = capsuleSegments(w, h)
  var map = function(p) {
    return { x: m[0] * p.x + m[2] * p.y + m[4], y: m[1] * p.x + m[3] * p.y + m[5] }
  }
  var s = map(cap.start)
  ctx.moveTo(s.x, s.y)
  for (var i = 0; i < cap.segs.length; i++) {
    var c1 = map(cap.segs[i][0])
    var c2 = map(cap.segs[i][1])
    var p = map(cap.segs[i][2])
    ctx.bezierCurveTo(c1.x, c1.y, c2.x, c2.y, p.x, p.y)
  }
  ctx.closePath()
}

/* ------------------------------------------------------------------ skins */

// Shapes and colours the customiser offers.
//
// Unlike the animation silhouettes above, these are NOT measured off the video:
// they are built analytically from the original customiser's grid. Two separate
// sources, deliberately — the animated states have to stay faithful to the
// video, the base shape is the person's own choice.

/** Brings the largest radius back to `max` so every shape weighs the same by eye. */
function normalizeRadii(radii, max) {
  if (max === undefined) max = 1
  var peak = 0
  for (var i = 0; i < radii.length; i++) if (radii[i] > peak) peak = radii[i]
  if (peak <= 0) return radii
  var k = max / peak
  var out = new Array(radii.length)
  for (var j = 0; j < radii.length; j++) out[j] = radii[j] * k
  return out
}

/** Pebble: a circle deformed by two low harmonics, so irregular but smooth. */
var PEBBLE = (function() {
  var out = new Array(PROFILE_SAMPLES)
  for (var i = 0; i < PROFILE_SAMPLES; i++) {
    var a = ANGLES[i]
    out[i] = 1 + 0.075 * Math.cos(2 * a + 0.5) + 0.035 * Math.cos(3 * a + 2.1)
  }
  return normalizeRadii(out, 1.02)
})()

/** Cloud: a union of bumps, wide at the bottom, two lobes on top. */
var CLOUD = normalizeRadii(unionOfCirclesProfile([
  { x: -0.44, y: 0.2, r: 0.54 },
  { x: 0.46, y: 0.2, r: 0.5 },
  { x: 0.02, y: 0.3, r: 0.6 },
  { x: -0.24, y: -0.3, r: 0.48 },
  { x: 0.3, y: -0.24, r: 0.44 }
]), 1.02)

/** Droplet: a fat disc below, drawn out to a point above. */
var DROPLET = normalizeRadii(
  profileFromPolygon(hullOfCircles(0, 0.28, 0.66, 0, -0.96, 0.05), 0, 0), 1.04)

/** Capsule lying down: the hull of two discs side by side. */
var CAPSULE = profileFromPolygon(hullOfCircles(-0.42, 0, 0.62, 0.42, 0, 0.62), 0, 0)

var SHAPES = [
  { id: "cercle", name: "Circle", radii: circle(1).radii },
  { id: "galet", name: "Pebble", radii: PEBBLE },
  // 1.15 and not 1.02: on a superellipse the largest radius is the diagonal, so
  // normalising on it yields a shape that reads smaller than the circle.
  { id: "squircle", name: "Squircle", radii: normalizeRadii(superellipseProfile(4.2), 1.15) },
  { id: "capsule", name: "Capsule", radii: CAPSULE },
  // -90deg: one vertex towards the top of the screen (y points down)
  { id: "triangle", name: "Triangle", radii: regularPolygonProfile(3, 1.12, 0.34, -90) },
  // 0deg: vertices left and right, so the top and bottom edges are flat
  { id: "hexagone", name: "Hexagon", radii: regularPolygonProfile(6, 1.04, 0.26, 0) },
  { id: "nuage", name: "Cloud", radii: CLOUD },
  { id: "goutte", name: "Droplet", radii: DROPLET }
]

var SHAPE_BY_ID = {}
for (var _s = 0; _s < SHAPES.length; _s++) SHAPE_BY_ID[SHAPES[_s].id] = SHAPES[_s]
var DEFAULT_SHAPE = "cercle"

// The original customiser's palette, plus two that only make sense on a
// desktop: a plain white, which is what a dark Omarchy theme wants and is this
// plugin's default, and `theme`, which wears the current accent and is resolved
// by the renderer because only it knows the palette.
var COLORS = [
  { id: "blanc", name: "White", hex: "#ffffff" },
  { id: "encre", name: "Ink", hex: "#0a0a0c" },
  { id: "brun", name: "Brown", hex: "#8b5e3c" },
  { id: "rouge", name: "Red", hex: "#e8483f" },
  { id: "orange", name: "Orange", hex: "#f08a24" },
  { id: "ambre", name: "Amber", hex: "#f0b429" },
  { id: "vert", name: "Green", hex: "#3ecf8e" },
  { id: "turquoise", name: "Turquoise", hex: "#2fbfa0" },
  { id: "bleu", name: "Blue", hex: "#3b93f0" },
  { id: "violet", name: "Violet", hex: "#8b5cf6" },
  { id: "rose", name: "Pink", hex: "#e152b0" },
  { id: "gris", name: "Grey", hex: "#a3a3a3" },
  { id: "creme", name: "Cream", hex: "#f1efe9" },
  { id: "theme", name: "Theme accent", hex: "", accent: true }
]

var COLOR_BY_ID = {}
for (var _c = 0; _c < COLORS.length; _c++) COLOR_BY_ID[COLORS[_c].id] = COLORS[_c]
var DEFAULT_COLOR = "blanc"

/**
 * Mixes two hex colours. Used by the depth haze on the burst particles.
 *
 * Takes the LAST six digits, because a colour that arrived from QML may carry
 * its alpha in front — `#ff1a1b26` — and reading that as `ff1a1b` is a
 * different colour that looks plausible enough not to be noticed.
 */
function mixHex(from, to, t) {
  var parse = function(h) {
    var hex = String(h).replace("#", "")
    var v = parseInt(hex.slice(Math.max(0, hex.length - 6)), 16)
    if (!isFinite(v)) v = 0
    return [(v >> 16) & 255, (v >> 8) & 255, v & 255]
  }
  var a = parse(from)
  var b = parse(to)
  var out = "#"
  for (var i = 0; i < 3; i++) {
    var x = Math.round(a[i] + (b[i] - a[i]) * t)
    out += (x < 16 ? "0" : "") + x.toString(16)
  }
  return out
}

/* ------------------------------------------------------------------- face */

// The eyes are painted on a sphere, not laid flat.
//
// Measured on the video: the eye nearer the edge is 0.69 times the width of the
// other and 0.663 times its area — exactly the depth factor (z = 0.669) of a
// point on a sphere at that distance from the centre. So this models a real
// head orientation: each eye takes the sphere's tangent frame, projected
// orthographically. The compression and the lean fall out on their own, and
// that is what gives the volume.
//
// These constants are not hand-picked: they come from fitting the model to the
// positions and sizes measured frame by frame (residual ~1 px on a 190 px
// radius).

/** Half the eye separation on the sphere, in degrees (total split ~31deg). */
var EYE_SPLIT = 15.46
/** Resting eye size, in ball-radius units. */
var EYE_W = 0.186
var EYE_H = 0.412
/** Resting head orientation, fitted on the reference frames. */
var REST_GAZE = { yaw: 28.49, pitch: 28.62, roll: -13 }

function deg(d) { return (d * Math.PI) / 180 }

/** Rotates two vectors of an orthonormal frame within their common plane. */
function spin(u, v, angle) {
  var c = Math.cos(angle)
  var s = Math.sin(angle)
  return [
    [u[0] * c + v[0] * s, u[1] * c + v[1] * s, u[2] * c + v[2] * s],
    [v[0] * c - u[0] * s, v[1] * c - u[1] * s, v[2] * c - u[2] * s]
  ]
}

/**
 * The head's frame, then each eye's.
 * Screen frame: x right, y down, z towards the viewer.
 * Index 0 is the inner eye, index 1 the outer one.
 */
function eyePoses(gaze, scale, split) {
  if (split === undefined) split = EYE_SPLIT
  var f = [0, 0, 1]
  var right = [1, 0, 0]
  var down = [0, 1, 0]
  var r

  // yaw: forward tips towards right
  r = spin(f, right, deg(gaze.yaw)); f = r[0]; right = r[1]
  // pitch: forward tips up, so away from down
  r = spin(down, f, deg(gaze.pitch)); down = r[0]; f = r[1]
  // roll: the head leans within its own plane
  r = spin(right, down, deg(gaze.roll)); right = r[0]; down = r[1]

  var build = function(side) {
    var e = spin(f, right, deg(split * side))
    var ef = e[0]
    var er = e[1]
    return {
      x: ef[0] * scale, y: ef[1] * scale,
      a: er[0], b: er[1], c: down[0], d: down[1],
      depth: ef[2]
    }
  }
  return [build(-1), build(1)]
}

// Resting life: slow gaze drift, saccades, blinks.
//
// A pure function of time with no internal state, so pausing, resuming and
// seeking to an arbitrary date always give the same picture. The values are
// OFFSETS to add to the current state's pose.

var BLINK_RNG = createRng(0x5eed)
/** Pre-drawn blink calendar: deterministic and stateless. */
var BLINKS = (function() {
  var out = []
  var t = 1.4
  while (t < 900) {
    out.push(t)
    // 1.9 to 4.6 s between blinks, plus the occasional double blink
    t += 1.9 + BLINK_RNG() * 2.7
    if (BLINK_RNG() < 0.18) { out.push(t); t += 0.24 }
  }
  return out
})()

/** Measured: 1 to 2 frames at 10 fps. */
var BLINK_DUR = 0.18

function blinkLid(t) {
  for (var i = 0; i < BLINKS.length; i++) {
    var start = BLINKS[i]
    if (t < start) break
    var k = (t - start) / BLINK_DUR
    if (k >= 0 && k <= 1) {
      // shuts fast, opens a little slower
      return k < 0.45 ? 1 - k / 0.45 : (k - 0.45) / 0.55
    }
  }
  return 1
}

function liveliness(t, opt) {
  opt = opt || {}
  var wander = opt.wander === undefined ? 1 : opt.wander
  var blink = opt.blink === undefined ? true : opt.blink
  var float = opt.float === undefined ? true : opt.float

  // Periods that are mutually prime: the drift never visibly repeats.
  return {
    dYaw: (loopNoise(t, 11.3, 0.4) * 5.5 + loopNoise(t, 3.7, 2.1) * 1.6) * wander,
    dPitch: (loopNoise(t, 9.1, 1.3) * 4.2 + loopNoise(t, 4.3, 0.7) * 1.3) * wander,
    dRoll: loopNoise(t, 13.7, 3.2) * 2.2 * wander,
    lid: blink ? blinkLid(t) : 1,
    // At rest the video is almost still — the centre holds to +-0.003 and the
    // radius is constant — so all the life is in the gaze and the blinks. Keep
    // just enough not to freeze the picture outright.
    driftX: float ? loopNoise(t, 7.9, 1.9) * 0.006 : 0,
    driftY: float ? loopNoise(t, 5.3, 0.3) * 0.007 : 0,
    // The width is constant; only the height breathes, very slightly.
    breath: float ? 1 + Math.sin((t / 3.4) * Math.PI * 2) * 0.005 : 1
  }
}

/**
 * A blink is a VERTICAL squash in screen space about the eye's centre — measured:
 * the bbox width is preserved and the height falls to ~0.35 — not a shortening
 * along the capsule's leaning axis. So it composes AFTER the tangent matrix and
 * touches only the y outputs.
 */
function blinkScale(lid) { return 0.06 + 0.94 * clamp(lid) }

/* ------------------------------------------------------------ expressions */

// The bot's resting expression.
//
// The face is two capsules and nothing else, so everything rides on four
// levers: the head's orientation, how far apart the eyes sit, their
// proportions, and each eye's own lean. That last one is what makes anger and
// sadness possible: they need MIRRORED leans — tops converging or diverging —
// which head roll alone cannot do, since it leans both eyes the same way.
//
// Only the resting state wears this expression. The video's expressive states
// (wink, wide eyes, notification) keep their own: reproducing those is the
// whole point.

/** `tilt` in degrees, positive = the top of the capsule goes right. */
function eye(w, h, tilt, open) {
  return { w: w, h: h, tilt: tilt === undefined ? 0 : tilt, open: open === undefined ? 1 : open }
}

/** Both eyes alike, leans mirrored when `tilt` is given. */
function eyePair(w, h, tilt, open) {
  return [eye(w, h, tilt, open), eye(w, h, tilt === undefined ? 0 : -tilt, open)]
}

var EXPRESSIONS = [
  {
    // the pose measured frame by frame on the reference video
    id: "neutre", name: "Neutral",
    gaze: { yaw: REST_GAZE.yaw, pitch: REST_GAZE.pitch, roll: REST_GAZE.roll },
    split: EYE_SPLIT, eyes: [eye(EYE_W, EYE_H), eye(EYE_W, EYE_H)]
  },
  { id: "attentif", name: "Attentive",
    gaze: { yaw: 4, pitch: 5, roll: -4 }, split: 16, eyes: eyePair(0.21, 0.44) },
  { id: "surpris", name: "Surprised",
    gaze: { yaw: 3, pitch: -3, roll: 0 }, split: 19, eyes: eyePair(0.45, 0.47) },
  { id: "excite", name: "Excited",
    gaze: { yaw: 6, pitch: -14, roll: 0 }, split: 19.5, eyes: eyePair(0.4, 0.56, -10) },
  { // eyes creased into arcs: the tops converge slightly
    id: "heureux", name: "Happy",
    gaze: { yaw: 5, pitch: 9, roll: 0 }, split: 17, eyes: eyePair(0.27, 0.17, 14) },
  { id: "hilare", name: "Gleeful",
    gaze: { yaw: 4, pitch: 14, roll: 0 }, split: 18, eyes: eyePair(0.34, 0.13, 20) },
  { // eye tops converging hard towards the centre, and narrowed
    id: "colere", name: "Angry",
    gaze: { yaw: 3, pitch: 7, roll: 0 }, split: 17, eyes: eyePair(0.34, 0.15, 30) },
  { // the reverse: the tops diverge, and the gaze falls
    id: "triste", name: "Sad",
    gaze: { yaw: 3, pitch: -13, roll: 0 }, split: 16, eyes: eyePair(0.22, 0.4, -28) },
  { id: "effraye", name: "Afraid",
    gaze: { yaw: 2, pitch: -20, roll: 0 }, split: 20.5, eyes: eyePair(0.4, 0.6) },
  { // one eye distinctly more shut than the other
    id: "mefiant", name: "Suspicious",
    gaze: { yaw: 12, pitch: 6, roll: -6 }, split: 16,
    eyes: [eye(0.21, 0.4), eye(0.22, 0.15)] },
  { // asymmetric on both axes: mismatched sizes AND leans. The creased eye is
    // deliberately flat (ratio 1.6): near a ratio of 1 it would read as round
    // and its lean would not show.
    id: "confus", name: "Confused",
    gaze: { yaw: -14, pitch: 3, roll: 8 }, split: 16.5,
    eyes: [eye(0.2, 0.44, -18), eye(0.28, 0.17, 14)] },
  { // the head tips: roll is what carries curiosity
    id: "curieux", name: "Curious",
    gaze: { yaw: 16, pitch: -9, roll: -15 }, split: 16.5,
    eyes: [eye(0.24, 0.46, -8), eye(0.2, 0.38, -8)] },
  { id: "fier", name: "Proud",
    gaze: { yaw: 5, pitch: 17, roll: 0 }, split: 17, eyes: eyePair(0.3, 0.15, 18) },
  { id: "timide", name: "Shy",
    gaze: { yaw: -19, pitch: -14, roll: -7 }, split: 14, eyes: eyePair(0.17, 0.3) },
  { // horizontal slits, gaze off to the side
    id: "blase", name: "Unimpressed",
    gaze: { yaw: -22, pitch: 2, roll: 0 }, split: 16, eyes: eyePair(0.3, 0.12) },
  { // lids half down: this goes through `open`, so a vertical squash on screen
    // — the same mechanism as a blink
    id: "somnolent", name: "Sleepy",
    gaze: { yaw: 6, pitch: -9, roll: -3 }, split: 16, eyes: eyePair(0.2, 0.42, 0, 0.42) }
]

var EXPRESSION_BY_ID = {}
for (var _e = 0; _e < EXPRESSIONS.length; _e++) EXPRESSION_BY_ID[EXPRESSIONS[_e].id] = EXPRESSIONS[_e]
var DEFAULT_EXPRESSION = "neutre"

function lerpEyeCfg(a, b, t) {
  return {
    w: lerp(a.w, b.w, t),
    h: lerp(a.h, b.h, t),
    tilt: lerp(a.tilt || 0, b.tilt || 0, t),
    open: lerp(a.open, b.open, t)
  }
}

/** Interpolates two expressions: a change of mood slides, it does not cut. */
function blendExpression(a, b, t) {
  return {
    id: b.id,
    gaze: {
      yaw: lerp(a.gaze.yaw, b.gaze.yaw, t),
      pitch: lerp(a.gaze.pitch, b.gaze.pitch, t),
      roll: lerp(a.gaze.roll, b.gaze.roll, t)
    },
    split: lerp(a.split, b.split, t),
    eyes: [lerpEyeCfg(a.eyes[0], b.eyes[0], t), lerpEyeCfg(a.eyes[1], b.eyes[1], t)]
  }
}

/* ------------------------------------------------------------------ decor */

/**
 * The rings are not flat colours: the video shows a full hue wheel at constant
 * lightness, with a gradient along each stroke. Measured: S 45-62%, L 50-67%.
 */
function wheel(hue, s, l) {
  if (s === undefined) s = 0.55
  if (l === undefined) l = 0.62
  var h = ((hue % 360) + 360) % 360
  var c = (1 - Math.abs(2 * l - 1)) * s
  var x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  var m = l - c / 2
  var rgb = h < 60 ? [c, x, 0]
    : h < 120 ? [x, c, 0]
    : h < 180 ? [0, c, x]
    : h < 240 ? [0, x, c]
    : h < 300 ? [x, 0, c]
    : [c, 0, x]
  var out = "#"
  for (var i = 0; i < 3; i++) {
    var v = Math.round((rgb[i] + m) * 255)
    out += (v < 16 ? "0" : "") + v.toString(16)
  }
  return out
}

/**
 * Projects a tilted 3D circle orthographically.
 *
 * The circle lives in the plane spanned by u (in the screen) and v (which dives
 * into depth). The z component splits the arc in two: the back half is drawn
 * before the body, so the body occludes it. That real depth sort is what makes
 * the rings read as orbits rather than as a flat drawing.
 */
function arcRender(seed, t, scale, id, opacity) {
  if (opacity === undefined) opacity = 1
  var spinT = seed.phase + t * seed.speed * TAU
  var cu = Math.cos(seed.tilt)
  var su = Math.sin(seed.tilt)
  var kz = Math.sqrt(Math.max(0, 1 - seed.k * seed.k))

  var N = 64
  var span = seed.sweep * TAU
  var front = []
  var back = []
  var prev = null

  for (var i = 0; i <= N; i++) {
    var th = spinT + (i / N) * span
    var ct = Math.cos(th)
    var st = Math.sin(th)
    // u = (cos tilt, sin tilt, 0) ; v = (-sin tilt * k, cos tilt * k, kz)
    var x = seed.a * (ct * cu + st * -su * seed.k) + seed.cx
    var y = seed.a * (ct * su + st * cu * seed.k) + seed.cy
    var z = seed.a * st * kz

    var behind = z < 0
    var dst = behind ? back : front
    // a new sub-stroke every time the arc crosses the body's plane
    if (behind !== prev || dst.length === 0) dst.push([])
    dst[dst.length - 1].push({ x: x * scale, y: y * scale })
    prev = behind
  }

  var gx = Math.cos(seed.tilt) * seed.a * scale
  var gy = Math.sin(seed.tilt) * seed.a * scale
  return {
    id: id, front: front, back: back,
    width: seed.width * scale, opacity: opacity,
    grad: {
      x1: seed.cx * scale - gx, y1: seed.cy * scale - gy,
      x2: seed.cx * scale + gx, y2: seed.cy * scale + gy,
      stops: [wheel(seed.hue), wheel(seed.hue + seed.hueSpan * 0.5), wheel(seed.hue + seed.hueSpan)]
    }
  }
}

var RING_RNG = createRng(0xa11ce)

/**
 * 6 rings, semi-major axis 1.30-1.40 (so distinctly larger than the ball),
 * flattening always <= 0.45, width 0.055, ~3.3 turns/s.
 */
var RINGS = (function() {
  var out = []
  for (var i = 0; i < 6; i++) {
    out.push({
      a: 1.3 + RING_RNG() * 0.1,
      k: 0.05 + RING_RNG() * 0.4,
      tilt: (i / 6) * Math.PI + RING_RNG() * 0.5,
      speed: 3 + RING_RNG() * 0.7,
      phase: RING_RNG() * TAU,
      sweep: 0.6 + RING_RNG() * 0.25,
      hue: (i * 360) / 6 + RING_RNG() * 30,
      hueSpan: 60 + RING_RNG() * 60,
      width: 0.05 + RING_RNG() * 0.012,
      cx: 0, cy: 0.1
    })
  }
  return out
})()

/**
 * The nested bouquet of arcs that sweeps across the triangle just before the
 * orbits. Seen almost edge on — hence the hairpin shape — rmax 1.37.
 */
var SWOOSH = (function() {
  var out = []
  for (var i = 0; i < 4; i++) {
    out.push({
      a: 0.78 + i * 0.2, k: 0.05 + i * 0.02, tilt: -0.62 + i * 0.05,
      speed: 0.3, phase: 0.06 * i, sweep: 0.4,
      hue: 95 + i * 62, hueSpan: 100, width: 0.05, cx: 0, cy: -0.12
    })
  }
  return out
})()

/** Measured x: -0.557 / -0.013 / +0.532, y = 0. */
var DOT_X = [-0.557, -0.013, 0.532]
var DOT_R = 0.165
var DOT_PEAK = 1.25

var P_RNG = createRng(0xbeef)

/** 5 particles, a new one every 0.2 s, lifetime 0.55 s. */
var PARTICLES = (function() {
  var out = []
  for (var i = 0; i < 5; i++) {
    out.push({ birth: i * 0.2, angle: P_RNG() * TAU, rho: 0.58 + P_RNG() * 0.18 })
  }
  return out
})()

/**
 * The particles do not fly off in a straight line: they spiral inwards (radius
 * x0.75 per frame, angle +100 deg/s) while growing, and pass behind the core,
 * where they are swallowed.
 */
function particles(t, scale) {
  var out = []
  for (var i = 0; i < PARTICLES.length; i++) {
    var p = PARTICLES[i]
    var u = t - p.birth
    if (u < 0 || u > 0.62) continue
    var rho = p.rho * Math.pow(0.75, u * 10)
    var a = p.angle + (u * 100 * Math.PI) / 180
    out.push({
      x: Math.cos(a) * rho * scale,
      y: Math.sin(a) * rho * scale,
      r: (0.04 + 0.028 * clamp(u / 0.55)) * scale,
      depth: clamp(1 - rho / 0.8),
      opacity: clamp(u / 0.06) * clamp((0.62 - u) / 0.08)
    })
  }
  return out
}

/**
 * Counter-intuitively, the dot does not cross the screen: it stays centred and
 * the trail orbits it. Ellipse a = 0.85, b = 0.15, major axis tilted +34deg,
 * 4 ribbons, ~210 deg/s.
 */
var COMET_RNG = createRng(0xc0e7)
var COMET_RIBBONS = (function() {
  var out = []
  for (var i = 0; i < 4; i++) {
    var d = i - 1.5
    out.push({
      a: 0.85 * (1 + d * 0.03),
      // the same flattening to within +-5%: the ribbons form a tight bundle
      k: (0.15 / 0.85) * (1 + d * 0.16),
      tilt: (34 * Math.PI) / 180 + d * 0.035,
      speed: 210 / 360,
      // measured phase offset: 10 to 20 degrees between ribbons, no more
      phase: -i * 0.045 + COMET_RNG() * 0.012,
      sweep: 0.34, hue: i * 85 + COMET_RNG() * 20, hueSpan: 80,
      width: 0.095, cx: 0, cy: 0
    })
  }
  return out
})()

/** The comet dot's radius, measured at 0.129. */
var COMET_DOT = 0.129

/** Blue read off the pixels. */
var NOTIF_BLUE = "#2496e8"
/** The pip sits exactly on the circumference, at -42deg. */
var NOTIF_ANGLE = -42
var NOTIF_DIST = 1.003
/** Resting radius; the pop peaks 14% above it. */
var NOTIF_R = 0.15
var NOTIF_POP = 1.14
/**
 * The notch is a disc concentric with the pip, subtracted from the body. Its
 * margin is constant (0.054 R) and follows the body's scale.
 */
var NOTIF_MARGIN = 0.054

/* ----------------------------------------------------------------- states */

function basePose(over) {
  var p = {
    sil: circle(1),
    offX: 0, offY: 0,
    gaze: { yaw: REST_GAZE.yaw, pitch: REST_GAZE.pitch, roll: REST_GAZE.roll },
    split: EYE_SPLIT,
    eyes: [eye(EYE_W, EYE_H), eye(EYE_W, EYE_H)],
    eyeAlpha: 1,
    bodyAlpha: 1,
    dots: [],
    arcs: [],
    notif: null,
    // true = the decor passes behind the body (the burst particles)
    dotsBehind: false
  }
  if (over) for (var k in over) p[k] = over[k]
  return p
}

/* ------------------------------------------------ non-radial shapes */

/**
 * The bar of the upright "!": the convex hull of two circles.
 * Measured: top circle (0, -0.505) r 0.132, bottom (0, +0.130) r 0.075, with
 * straight flanks. So it is tapered, top/bottom ratio 1.76.
 */
var BAR_UPRIGHT_CY = -0.1875
var BAR_UPRIGHT = profileFromPolygon(
  hullOfCircles(0, -0.505, 0.132, 0, 0.13, 0.075), 0, BAR_UPRIGHT_CY)

/** The bar of the leaning "!": a pure capsule (constant width 0.269, length 0.776). */
var BAR_ITALIC = profileFromPolygon(
  hullOfCircles(0, -0.2535, 0.1345, 0, 0.2535, 0.1345), 0, 0)

function barUpright(pose) {
  return poseDefaults(BAR_UPRIGHT.slice(),
    (function() { var p = { cy: BAR_UPRIGHT_CY }; if (pose) for (var k in pose) p[k] = pose[k]; return p })())
}

function barItalic(pose) { return poseDefaults(BAR_ITALIC.slice(), pose) }

/**
 * The dot of the leaning "!" is not a disc: it is a teardrop, round (r 0.118)
 * on the bar's side and drawn out to a point away from it, 0.300 long along the
 * glyph's axis. Centred on the round end's centroid.
 */
var TEAR = hullOfCircles(0, 0, 0.118, 0, 0.172, 0.012)

/**
 * The triangle does not spin about itself: its centre traces a circle of radius
 * 0.213 about the origin (measured). That offset is what makes it read as
 * tumbling rather than pivoting in place.
 */
var TRI_ORBIT = 0.213

function spinningTriangle(rot) {
  return silhouette("triangle", {
    rot: rot,
    cx: -TRI_ORBIT * Math.sin(rot),
    cy: TRI_ORBIT * Math.cos(rot)
  })
}

/** The pulse that travels across the three dots, left to right. */
function dotPulse(t, index) {
  var p = ((((t - index * 0.5) / 1.5) % 1) + 1) % 1
  var k = p < 0.5 ? 0.5 - 0.5 * Math.cos(p * TAU) : 0
  return clamp(k * 2)
}

// Each state declares:
//   duration    how long it is held when the whole sequence is played
//   minDuration below which the animation is cut before it resolves; read off
//               the constants in `pose`, never chosen
//   morph       how long the entry cross-fade lasts
//   blinkIn     true = the entry is masked by a blink, as in the video
//   baseBody    true = the body is the RESTING silhouette, so the chosen shape
//               may replace it. States that draw their own shape are false:
//               there, the shape IS the animation
//   baseFace    true = the state wears the RESTING face, so the chosen
//               expression may replace it. Only `idle` and `swirl`: the other
//               faced states have an expression measured off the video, and
//               reproducing it is precisely the point

var STATES = [
  { id: "idle", duration: 2.4, morph: 0.45, blinkIn: false,
    baseFace: true, baseBody: true,
    pose: function() { return basePose() } },

  { id: "thinking", duration: 2.6, morph: 0.4, blinkIn: true,
    baseFace: false, baseBody: false,
    pose: function(t) {
      var mid = dotPulse(t, 1)
      // The side dots come out of the ball's flanks: in the video they stay
      // fused with it for 1-2 frames before detaching.
      var emerge = 0.3 + 0.7 * easings.easeOutCubic(clamp(t / 0.3))
      var dots = []
      var idx = [0, 2]
      for (var i = 0; i < idx.length; i++) {
        var k = dotPulse(t, idx[i])
        dots.push({
          x: DOT_X[idx[i]] * emerge, y: 0,
          r: DOT_R * (1 + (DOT_PEAK - 1) * k),
          opacity: 0.55 + 0.45 * k
        })
      }
      return basePose({
        // the ball BECOMES the middle dot, so the morph stays continuous
        sil: circle(DOT_R * (1 + (DOT_PEAK - 1) * mid), { cx: DOT_X[1] }),
        eyeAlpha: 0, dots: dots
      })
    } },

  { id: "wink", duration: 1.6, morph: 0.3, blinkIn: true,
    baseFace: false, baseBody: true,
    pose: function() {
      return basePose({
        gaze: { yaw: -5.37, pitch: 4.55, roll: 6.7 },
        split: 16.25,
        // The shut eye is not the open one squashed: it is a horizontal dash
        // WIDER than the open eye (0.447 against 0.236).
        eyes: [{ w: 0.236, h: 0.464, open: 1, tilt: 0 },
               { w: 0.447, h: 0.089, open: 1, tilt: 0 }]
      })
    } },

  { id: "wide", duration: 1.8, morph: 0.55, blinkIn: true,
    baseFace: false, baseBody: true,
    pose: function() {
      return basePose({
        gaze: { yaw: 6.92, pitch: -21.96, roll: 11.6 },
        split: 18.43, eyes: eyePair(0.356, 0.875)
      })
    } },

  { id: "alert", duration: 2.4,
    // the "!" comes back into place at 1.6 + 0.4
    minDuration: 2, morph: 0.45, blinkIn: false,
    baseFace: false, baseBody: false,
    pose: function(t) {
      // Measured run: -0.087 -> +0.732 in 1.5 s, ease-in-out, micro-overshoot.
      var p = clamp(t / 1.5)
      var travel = easings.easeInOutCubic(p) * 0.82 - 0.087
      var back = t > 1.6 ? clamp((t - 1.6) / 0.4) : 0
      var x = travel * (1 - back) + 0.1 * back
      // Secondary buzz at 2.5 Hz, bar and dot in antiphase.
      var buzz = Math.sin(t * 2.5 * TAU) * 0.005
      var tilt = (17.7 * Math.PI) / 180
      return basePose({
        sil: barItalic({ rot: tilt, cx: x, cy: -0.325 - buzz }),
        eyeAlpha: 0,
        dots: [{
          // the dot follows the glyph's axis, 0.580 from the bar's centre
          x: x - Math.sin(tilt) * 0.58,
          y: -0.325 + Math.cos(tilt) * 0.58 + buzz * 2.8,
          r: 0.118, poly: TEAR, rot: (tilt * 180) / Math.PI, opacity: 1
        }]
      })
    } },

  { id: "notify", duration: 2.2, morph: 0.5, blinkIn: true,
    baseFace: false, baseBody: true,
    pose: function(t) {
      // The blue dot pops: peaks at +14% around 0.3 s, then settles.
      var p = clamp(t / 0.45)
      var pop = 1 + (NOTIF_POP - 1) * Math.sin(p * Math.PI) * (1 - p * 0.35)
      var r = NOTIF_R * (p < 1 ? pop : 1)
      var a = (NOTIF_ANGLE * Math.PI) / 180
      return basePose({
        // the gaze goes the opposite way from the pip
        gaze: { yaw: -21.94, pitch: -5.82, roll: -12.2 },
        split: 18.89, eyes: eyePair(0.505, 0.498),
        notif: { x: Math.cos(a) * NOTIF_DIST, y: Math.sin(a) * NOTIF_DIST,
                 r: r, notch: r + NOTIF_MARGIN }
      })
    } },

  { id: "exclaim", duration: 2, morph: 0.45, blinkIn: false,
    baseFace: false, baseBody: false,
    pose: function() {
      return basePose({
        sil: barUpright(), eyeAlpha: 0,
        dots: [{ x: -0.012, y: 0.526, r: 0.113, opacity: 1 }]
      })
    } },

  { id: "sleep", duration: 2.4, morph: 0.5, blinkIn: false,
    baseFace: false, baseBody: false,
    pose: function(t) {
      return basePose({
        // Measured vertical bounce: +-0.19 about +0.11, period 0.6 s.
        sil: circle(0.1585, { cy: 0.11 + Math.sin(t * (TAU / 0.6)) * 0.19 }),
        eyeAlpha: 0
      })
    } },

  { id: "egg", duration: 1.8, morph: 0.4, blinkIn: true,
    baseFace: false, baseBody: false,
    pose: function() {
      return basePose({
        sil: silhouette("egg"),
        gaze: { yaw: 19.97, pitch: 26.01, roll: -17.1 },
        // the eyes draw together as the body does
        split: 11.07, eyes: eyePair(0.164, 0.385)
      })
    } },

  { id: "hexagon", duration: 1.6, morph: 0.4, blinkIn: true,
    baseFace: false, baseBody: false,
    pose: function() {
      return basePose({
        sil: silhouette("hexagon"),
        gaze: { yaw: 23.11, pitch: 24.42, roll: -13.3 },
        split: 13.37, eyes: eyePair(0.177, 0.411)
      })
    } },

  { id: "play", duration: 2, morph: 0.5, blinkIn: true,
    baseFace: false, baseBody: false,
    pose: function(t) {
      // The triangle stays almost still while the bouquet crosses it.
      var fade = clamp(t / 0.35) * clamp((2.2 - t) / 0.5)
      var arcs = []
      for (var i = 0; i < SWOOSH.length; i++) {
        var seed = {}
        for (var k in SWOOSH[i]) seed[k] = SWOOSH[i][k]
        seed.cx = 0.45 - t * 0.42
        arcs.push({ id: "sw" + i, seed: seed, t: t, opacity: fade })
      }
      return basePose({
        sil: spinningTriangle(0),
        gaze: { yaw: 12, pitch: -8, roll: -6 },
        split: 15, eyes: eyePair(0.18, 0.34),
        // the bouquet sweeps right to left over the triangle
        arcs: arcs
      })
    } },

  { id: "orbit", duration: 3.4,
    // the body has finished relaxing from triangle to ball at 1.6 + 0.9
    minDuration: 2.5, morph: 0.6, blinkIn: false,
    baseFace: false, baseBody: false,
    pose: function(t) {
      // Measured rotation: ramps over 0.35 s then 1.25 turns/s, anticlockwise.
      var ramp = easings.easeInOutCubic(clamp(t / 0.35))
      var rot = -TAU * 1.25 * t * ramp
      // The body relaxes from the triangle into the ball during the orbit.
      var back = easings.easeInOutCubic(clamp((t - 1.6) / 0.9))
      var tri = spinningTriangle(rot)
      var ball = circle(1, { rot: rot })
      var radii = new Array(PROFILE_SAMPLES)
      for (var i = 0; i < PROFILE_SAMPLES; i++) {
        radii[i] = tri.radii[i] + (ball.radii[i] - tri.radii[i]) * back
      }
      var sil = { radii: radii, rot: rot, cx: tri.cx * (1 - back), cy: tri.cy * (1 - back), sx: 1, sy: 1 }
      var fade = clamp(t / 0.8) * clamp((3.6 - t) / 0.9)
      var arcs = []
      for (var j = 0; j < RINGS.length; j++) {
        // the rings come in one at a time over 0.8 s
        arcs.push({ id: "rg" + j, seed: RINGS[j], t: t,
                    opacity: fade * clamp((t - j * 0.13) / 0.3) })
      }
      return basePose({
        sil: sil,
        // the eyes race round the sphere ~3x faster than the silhouette
        gaze: { yaw: REST_GAZE.yaw + Math.sin(t * 6.5) * 65 * (1 - back),
                pitch: -4 + back * 32, roll: -13 },
        eyes: eyePair(0.18, 0.34 + back * 0.07),
        arcs: arcs
      })
    } },

  {
    // Entering the settings view.
    //
    // The ONLY state not measured off the video: it is chosen. It borrows
    // `orbit`'s vocabulary — the same rings, with their measured parameters —
    // but cuts short: 1 s instead of 3.4, half the rings, and no triangle.
    //
    // Both flags being true is the whole point of this state: `baseBody` lets
    // the chosen shape replace the body, so a pebble or a droplet MORPHS into
    // the circle instead of cutting to it; `baseFace` makes it wear the resting
    // face, so cursor tracking applies from this entry on.
    id: "swirl",
    // a little more than the gaze's own turn (1.1 s): the eyes must be settled
    // before the rings fade
    duration: 1.3, minDuration: 1.3, morph: 0.3, blinkIn: true,
    baseFace: true, baseBody: true,
    pose: function(t) {
      var arcs = []
      // three rings out of orbit's six: half the bouquet is enough to recognise
      // it, and that is three fewer arcs to rasterise per frame
      for (var i = 0; i < 3; i++) {
        arcs.push({ id: "sw" + i, seed: RINGS[i], t: t,
                    // they come in one after another then fade before the block
                    // ends, so the return to rest lands on an already clean frame
                    opacity: clamp((t - i * 0.06) / 0.14) * clamp((1.22 - t) / 0.34) })
      }
      return basePose({ arcs: arcs })
    } },

  { id: "burst", duration: 2.6,
    // the body is back together at 1.7 + 0.7
    minDuration: 2.4, morph: 0.4, blinkIn: false,
    baseFace: false, baseBody: false,
    pose: function(t) {
      // Measured collapse: 1.0 -> 0.166 in 0.7 s, ease-out, no bounce.
      var collapse = 1 - 0.834 * easings.easeOutQuint(clamp(t / 0.7))
      var regrow = easings.easeOutQuint(clamp((t - 1.7) / 0.7))
      return basePose({
        sil: circle(collapse + (1 - collapse) * regrow),
        eyeAlpha: clamp((t - 1.85) / 0.4),
        dots: particles(t, 1),
        dotsBehind: true
      })
    } },

  { id: "comet", duration: 2.4,
    // the dot reassembles at 1.85 + 0.6 = 2.45, so 0.05 s after the video's
    // cut: that remainder finishes during the next cross-fade, as in the
    // reference. So this does not go below the measured duration.
    minDuration: 2.4, morph: 0.45, blinkIn: false,
    baseFace: false, baseBody: false,
    pose: function(t) {
      var collapse = 1 - (1 - COMET_DOT) * easings.easeOutQuint(clamp(t / 0.55))
      var regrow = easings.easeOutQuint(clamp((t - 1.85) / 0.6))
      var fade = clamp((t - 0.15) / 0.25) * clamp((1.95 - t) / 0.3)
      var arcs = []
      for (var i = 0; i < COMET_RIBBONS.length; i++) {
        arcs.push({ id: "cm" + i, seed: COMET_RIBBONS[i], t: t, opacity: fade })
      }
      return basePose({
        // The dot drifts 0.035 downwards then back up (measured wobble).
        sil: circle(collapse + (1 - collapse) * regrow,
                    { cy: Math.sin(clamp(t / 1.7) * Math.PI) * 0.035 }),
        eyeAlpha: clamp((t - 2) / 0.35),
        arcs: arcs
      })
    } }
]

var STATE_BY_ID = {}
for (var _st = 0; _st < STATES.length; _st++) STATE_BY_ID[STATES[_st].id] = STATES[_st]

/**
 * The moment, in local time, where each state reads best: the pose the frozen
 * previews show. Also what a reduced-motion desktop is shown, since it holds
 * one frame instead of animating.
 */
var POSES = {
  idle: 1, thinking: 1.1, wink: 0.8, wide: 0.8, alert: 0.75, notify: 0.9,
  exclaim: 0.8, sleep: 0.45, egg: 0.8, hexagon: 0.8, play: 0.9, orbit: 1.2,
  swirl: 0.5, burst: 0.45, comet: 1.15
}

/** When to freeze a state for a desktop that has asked for reduced motion. */
function restingMoment(state) {
  var t = lookup(POSES, state)
  return t === null ? 1 : t
}

/* ----------------------------------------------------------------- engine */

var NO_LOOK = { yaw: 0, pitch: 0, mix: 0, spin: 0, wander: 1 }

function lerpLook(a, b, t) {
  return {
    yaw: lerp(a.yaw, b.yaw, t), pitch: lerp(a.pitch, b.pitch, t),
    mix: lerp(a.mix, b.mix, t), spin: lerp(a.spin, b.spin, t),
    wander: lerp(a.wander, b.wander, t)
  }
}

function lerpEye(a, b, t) {
  return {
    w: lerp(a.w, b.w, t), h: lerp(a.h, b.h, t),
    open: lerp(a.open, b.open, t), tilt: lerp(a.tilt || 0, b.tilt || 0, t)
  }
}

function fadedDots(list, k) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    var d = {}
    for (var key in list[i]) d[key] = list[i][key]
    d.opacity = list[i].opacity * k
    out.push(d)
  }
  return out
}

function fadedArcs(list, prefix, k) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    out.push({ id: prefix + list[i].id, seed: list[i].seed, t: list[i].t,
               opacity: list[i].opacity * k })
  }
  return out
}

/** Interpolates two poses. The decor cross-fades in opacity, not in geometry. */
function blendPose(a, b, t) {
  var out = 1 - t
  return {
    sil: blendSil(a.sil, b.sil, t),
    offX: lerp(a.offX, b.offX, t),
    offY: lerp(a.offY, b.offY, t),
    gaze: {
      yaw: lerp(a.gaze.yaw, b.gaze.yaw, t),
      pitch: lerp(a.gaze.pitch, b.gaze.pitch, t),
      roll: lerp(a.gaze.roll, b.gaze.roll, t)
    },
    split: lerp(a.split, b.split, t),
    eyes: [lerpEye(a.eyes[0], b.eyes[0], t), lerpEye(a.eyes[1], b.eyes[1], t)],
    eyeAlpha: lerp(a.eyeAlpha, b.eyeAlpha, t),
    bodyAlpha: lerp(a.bodyAlpha, b.bodyAlpha, t),
    dots: fadedDots(a.dots, out).concat(fadedDots(b.dots, t)),
    arcs: fadedArcs(a.arcs, "a", out).concat(fadedArcs(b.arcs, "b", t)),
    // the pip belongs to one state or the other; it does not blend
    notif: t < 0.5 ? a.notif : b.notif,
    dotsBehind: t < 0.5 ? a.dotsBehind : b.dotsBehind
  }
}

/** How long a change of body shape takes to morph. */
var SHAPE_MORPH = 0.45
/**
 * How long the gaze takes to catch up with its target. Shorter than
 * SHAPE_MORPH: a gaze that follows should look attentive, not viscous. Since
 * the target is reset on every pointer move, this duration is what gives the
 * tracking its inertia — the gaze never quite reaches a moving cursor.
 */
var LOOK_MORPH = 0.24

/**
 * A clockless engine: `sample(t)` is a pure function of time.
 *
 * The practical consequence is that pausing, resuming and seeking to any date
 * all give exactly the same picture, and the whole thing is testable with no
 * canvas at all. Everything external enters through a DATED setter, never
 * through a variable read during `sample`.
 */
function createEngine(scale, initial, shapeId, exprId) {
  var self = {}
  var R = scale === undefined ? 100 : scale

  var cur = initial || "idle"
  var prev = null
  // A FROZEN departure pose, set only when a state change lands while a
  // cross-fade is already running. See setState.
  var departFrozen = null
  var tCur = 0
  var tPrev = 0
  var blinkAt = -10
  var pts = []

  var shape = shapeId || null
  var shapePrev = null
  var shapeAt = -10
  var expr = exprId || null
  var exprPrev = null
  var exprAt = -10
  var look = NO_LOOK
  var lookPrev = NO_LOOK
  var lookAt = -10
  var lookMorph = LOOK_MORPH

  function shapeRadii(id) {
    var s = lookup(SHAPE_BY_ID, id)
    return s ? s.radii : null
  }

  /**
   * The resting expression chosen in the customiser. Like the shape, it slides
   * to its new value instead of cutting.
   */
  self.setExpression = function(id, now) {
    if (id === expr) return
    exprPrev = expr
    expr = id
    exprAt = now || 0
  }

  /** The effective expression at `now`, mid-morph included. */
  function exprAtTime(now) {
    var to = lookup(EXPRESSION_BY_ID, expr)
    var from = lookup(EXPRESSION_BY_ID, exprPrev)
    if (!to || !from) return to || null
    var k = (now - exprAt) / SHAPE_MORPH
    if (k >= 1) return to
    return blendExpression(from, to, easings.easeOutQuint(clamp(k)))
  }

  /**
   * The shape chosen in the customiser. It only replaces the body on resting
   * states (`baseBody`): elsewhere the silhouette IS the animation and must not
   * be overwritten.
   *
   * The change morphs rather than cutting: since every shape is sampled at the
   * same angles, interpolating the radii is enough.
   */
  self.setShape = function(id, now) {
    if (id === shape) return
    shapePrev = shape
    shape = id
    shapeAt = now || 0
  }

  /**
   * The effective profile at `now`, mid-morph included.
   *
   * Does NOT clear `shapePrev` when the morph ends: `sample` has to stay a pure
   * function of time, so re-reading a past date must give back the intermediate
   * picture. It only costs one extra reference.
   */
  function shapeAtTime(now) {
    var to = shapeRadii(shape)
    var from = shapeRadii(shapePrev)
    if (!to || !from) return to
    var k = (now - shapeAt) / SHAPE_MORPH
    if (k >= 1) return to
    var t = easings.easeOutQuint(clamp(k))
    // allocates only during the morph; outside one the array is handed back as is
    var out = new Array(to.length)
    for (var i = 0; i < to.length; i++) {
      out[i] = lerp(from[i] === undefined ? to[i] : from[i], to[i], t)
    }
    return out
  }

  /**
   * A new gaze target, `null` to fall back to the state's own.
   *
   * It restarts from the CURRENT value, not from the previous target the way
   * setShape does: this is called on every pointer move, and restarting from
   * the old target would step the gaze backwards before each catch-up — the
   * tracking would judder instead of gliding.
   */
  self.setLook = function(next, now, morph) {
    /*
     * A non-finite target is refused, and the engine KEEPS the last one: a NaN
     * set even once would propagate into every frame and the bot would never
     * rest again. That happened for real — a zero-sized item gives 0/0 in the
     * caller. The engine should not depend on its callers being careful to stay
     * replayable.
     */
    if (next && !isFinite(next.yaw + next.pitch + next.mix + next.spin + next.wander)) return
    lookPrev = lookAtTime(now)
    look = next || NO_LOOK
    lookAt = now
    lookMorph = morph === undefined ? LOOK_MORPH : morph
  }

  /** The effective gaze target at `now`, catch-up included. */
  function lookAtTime(now) {
    var k = (now - lookAt) / lookMorph
    if (k >= 1) return look
    return lerpLook(lookPrev, look, easings.easeOutQuint(clamp(k)))
  }

  function posed(def, t, radii, expression) {
    var pose = def.pose(t)
    if (def.baseBody && radii) {
      // keep the pose — rotation, offset, squash — and swap only the profile
      var sil = {}
      for (var k in pose.sil) sil[k] = pose.sil[k]
      sil.radii = radii
      pose.sil = sil
    }
    if (def.baseFace && expression) {
      pose.gaze = expression.gaze
      pose.split = expression.split
      pose.eyes = expression.eyes
    }
    return pose
  }

  /**
   * The eye offset at `now` for a given state, in ball-radius units.
   *
   * It is READ from a table and interpolated, never recomputed — that
   * distinction is the whole fix. Solved inside the render loop, the correction
   * reacts to everything that moves at sixty frames a second (the gaze drift,
   * the pointer, an expression mid-morph, which edge is nearest, which eye is
   * most constrained) and every such version produced a visible motion artefact.
   * The rest of the engine does not work that way: poses are DECLARED and it
   * only interpolates them along known curves. A tabulated offset fits that
   * mould, and interpolating between two constants is monotone by construction.
   *
   * The table is queried on the morph's BOUNDS, never on the interpolated
   * profile: that one is a fresh array with no identity and is in no table.
   */
  function offsetAtTime(now, state) {
    var onAxis = function(start, duration, a, b) {
      if (a === b) return b
      var k = (now - start) / duration
      if (k >= 1) return b
      var t = easings.easeOutQuint(clamp(k))
      return { x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t) }
    }
    // the expression axis, for each of the two shapes in play
    var perShape = function(id) {
      return onAxis(exprAt, SHAPE_MORPH,
        BloubFit.offset(id, state, exprPrev),
        BloubFit.offset(id, state, expr))
    }
    // then the shape axis
    return onAxis(shapeAt, SHAPE_MORPH, perShape(shapePrev), perShape(shape))
  }

  self.state = function() { return cur }

  /**
   * Restarts on `id` with NO previous state, like a fresh engine placed there.
   *
   * `setState` alone cannot do this: it keeps the state being left in order to
   * fade it, which is exactly its job during playback and exactly what must not
   * happen when returning to the start of a sequence.
   */
  self.reset = function(id, now) {
    cur = id
    prev = null
    departFrozen = null
    tCur = now
    tPrev = now
    blinkAt = -10
  }

  /**
   * Where the running fade starts: the frozen pose if there is one, otherwise
   * the state being left evaluated at its OWN elapsed time — so still animating,
   * which is intended.
   */
  function origin(now, radii, expression) {
    if (departFrozen) return departFrozen
    if (!prev) return null
    return posed(lookup(STATE_BY_ID, prev), Math.max(0, now - tPrev), radii, expression)
  }

  /** The composite pose at `now`, running fade included. */
  function composedPose(now) {
    var def = lookup(STATE_BY_ID, cur)
    var radii = shapeAtTime(now)
    var expression = exprAtTime(now)
    var pose = posed(def, Math.max(0, now - tCur), radii, expression)
    var since = now - tCur
    if (since >= def.morph) return pose
    var from = origin(now, radii, expression)
    if (!from) return pose
    return blendPose(from, pose, easings.easeOutQuint(clamp(since / def.morph)))
  }

  /**
   * A dated state change.
   *
   * The engine keeps only ONE slot of history, so a change arriving mid-fade
   * used to replace the blend's origin with the FULL pose of the state being
   * left, instead of the partly blended frame that was actually on screen.
   * Measured on `idle -> wide -> idle` at 100 ms: a 35.9 px jump against 8.0 px
   * of normal movement. So the composite pose is frozen and the blend runs from
   * it — continuous by construction however many changes are chained.
   *
   * And ONLY in that case. Freezing on every change would stop the outgoing
   * state's animation dead for the whole fade — the "!" of `alert` would halt
   * mid-run — while outside a morph there is nothing to fix.
   */
  self.setState = function(id, now) {
    if (id === cur) return
    var morph = lookup(STATE_BY_ID, cur).morph
    var midFade = prev !== null && now - tCur < morph
    departFrozen = midFade ? composedPose(now) : null
    prev = cur
    tPrev = tCur
    cur = id
    tCur = now
    // In the video, every change of shape is masked by a blink.
    if (lookup(STATE_BY_ID, id) && lookup(STATE_BY_ID, id).blinkIn) blinkAt = now
  }

  self.sample = function(now) {
    var def = lookup(STATE_BY_ID, cur)
    var radii = shapeAtTime(now)
    var expression = exprAtTime(now)
    var pose = posed(def, Math.max(0, now - tCur), radii, expression)
    var offset = offsetAtTime(now, cur)

    // --- transition ------------------------------------------------------
    var since = now - tCur
    // The previous state is never purged: `since < def.morph` is enough to
    // ignore it once the fade is over, and forgetting it would make the engine
    // unreplayable. That is the optimisation that looks innocent and breaks
    // everything.
    var from = since < def.morph ? origin(now, radii, expression) : null
    if (from) {
      // Exponential ease-out: the curve measured on the video. The body has no
      // overshoot — only the pip and the eyes opening do. The ratio is clamped
      // because re-reading a date BEFORE the state change would give a negative
      // ratio, which the ease-out extrapolates thirty times too far.
      var ratio = easings.easeOutQuint(clamp(since / def.morph))
      pose = blendPose(from, pose, ratio)
      // The eye offset follows the SAME curve as the silhouette that motivates it.
      if (prev) {
        var before = offsetAtTime(now, prev)
        offset = { x: lerp(before.x, offset.x, ratio), y: lerp(before.y, offset.y, ratio) }
      }
    }

    // --- resting life ----------------------------------------------------
    var alive = pose.eyeAlpha > 0.01
    var lk = lookAtTime(now)
    var life = liveliness(now, { wander: alive ? lk.wander : 0, blink: alive })

    var gaze = {
      // The two aims REPLACE the pose's rather than adding to it, and the turn
      // is subtracted along the way. The drift is added AFTER the blend, or the
      // target would cancel it along with the pose — and it has to survive a
      // head turned with no pointer.
      yaw: lerp(pose.gaze.yaw, lk.yaw, lk.mix) + life.dYaw - lk.spin,
      pitch: lerp(pose.gaze.pitch, lk.pitch, lk.mix) + life.dPitch,
      // roll follows nothing: the bot's head leans -13deg in the video, and
      // rolling it with the cursor breaks that signature
      roll: pose.gaze.roll + life.dRoll
    }

    // a blink triggered by the state change, on top of the calendar
    var forced = clamp((now - blinkAt) / 0.2)
    var forcedLid = forced < 1 ? Math.abs(forced * 2 - 1) : 1
    var lid = Math.min(life.lid, forcedLid)

    var offX = pose.offX + life.driftX
    var offY = pose.offY + life.driftY

    // --- body ------------------------------------------------------------
    var sil = { radii: pose.sil.radii, rot: pose.sil.rot,
                cx: pose.sil.cx + offX, cy: pose.sil.cy + offY,
                sx: pose.sil.sx, sy: pose.sil.sy * life.breath }
    var bodyPts = toPoints(sil, R, pts)

    // --- eyes -------------------------------------------------------------
    // The eyes live on a sphere of radius 1; as soon as the silhouette stops
    // being a circle they are brought back pro rata to the real radius in their
    // direction, or they overhang and the mask cuts them.
    var bodyRadius = function(x, y) {
      return radiusAtAngle(pose.sil.radii, Math.atan2(y, x) - pose.sil.rot)
    }

    var eyes = []
    if (pose.eyeAlpha > 0.01) {
      var poses = eyePoses(gaze, R, pose.split)
      for (var i = 0; i < 2; i++) {
        var e = poses[i]
        if (e.depth <= 0.02) continue
        var cfg = pose.eyes[i]
        var fit = bodyRadius(e.x, e.y)
        // The eye's own lean: the tangent frame composed with a rotation within
        // the eye's plane (Basis x Rot). That is what allows mirrored leans
        // between the two eyes.
        var phi = ((cfg.tilt || 0) * Math.PI) / 180
        var cp = Math.cos(phi)
        var sp = Math.sin(phi)
        var ax = e.a * cp + e.c * sp
        var ay = e.b * cp + e.d * sp
        var cx2 = -e.a * sp + e.c * cp
        var cy2 = -e.b * sp + e.d * cp
        // The blink applies AFTER all of that: it is a vertical squash on
        // screen, not one along the capsule's axis.
        var k = blinkScale(Math.min(lid, cfg.open))
        eyes.push({
          w: cfg.w * R, h: cfg.h * R,
          m: [ax, ay * k, cx2, cy2 * k,
              e.x * fit + (offX + offset.x) * R,
              e.y * fit + (offY + offset.y) * R],
          alpha: pose.eyeAlpha * clamp(e.depth / 0.12)
        })
      }
    }

    // --- decor ------------------------------------------------------------
    var dots = []
    for (var d = 0; d < pose.dots.length; d++) {
      var p = pose.dots[d]
      if (p.opacity <= 0.01 || p.r <= 0.0005) continue
      dots.push({ x: (p.x + offX) * R, y: (p.y + offY) * R, r: p.r * R,
                  opacity: p.opacity, color: p.color, depth: p.depth,
                  poly: p.poly, rot: p.rot, scale: R })
    }

    // the pip sits on the outline, so it follows the shape too
    var nFit = pose.notif ? bodyRadius(pose.notif.x, pose.notif.y) : 1
    var nx = pose.notif ? (pose.notif.x * nFit + offX) * R : 0
    var ny = pose.notif ? (pose.notif.y * nFit + offY) * R : 0

    var arcs = []
    for (var j = 0; j < pose.arcs.length; j++) {
      var spec = pose.arcs[j]
      if (spec.opacity <= 0.01) continue
      // States declare arcs in ball-radius units; the engine is the only one
      // that knows the view's scale, so it is the one that traces them.
      arcs.push(arcRender(spec.seed, spec.t, R, spec.id, spec.opacity))
    }

    return {
      bodyPts: bodyPts,
      bodyAlpha: pose.bodyAlpha,
      eyes: eyes,
      dots: dots,
      dotsBehind: pose.dotsBehind,
      arcs: arcs,
      notif: pose.notif ? { x: nx, y: ny, r: pose.notif.r * R } : null,
      notch: pose.notif ? { x: nx, y: ny, r: pose.notif.notch * R } : null
    }
  }

  return self
}

/* ------------------------------------------------------- moods and states */

// Omarchief speaks in moods; the bot speaks in states and expressions. This is
// the whole of the translation, and it keeps the two vocabularies separate: a
// mood picks an ANIMATION, and — only on the states that wear the resting face
// — it may also pick an EXPRESSION, which otherwise stays the person's own.
//
// `dragged` is the one mood with no agent behind it: it is what the creature
// does while you are carrying it, so it gets the wide-eyed state rather than an
// expression, the way the video's `wide` reads as being picked up.

var MOOD_STATE = {
  idle: "idle",
  parked: "idle",
  tired: "idle",
  love: "idle",
  // NOT the catalogue's `thinking`. That state is faithful — one of the
  // fourteen measured off the video — but it dissolves the body into three
  // pulsing dots, and on a desktop three pulsing dots are a progress bar. A
  // companion that vanishes into a loading indicator the moment you ask it
  // something is the opposite of the point, so a turn keeps the body and the
  // face and puts the thought in the eyes. See MOOD_EXPRESSION and ponderLook.
  working: "idle",
  waiting: "notify",
  success: "burst",
  error: "alert",
  sleeping: "sleep",
  dragged: "wide"
}

/** Moods that speak through the face instead of through the animation. */
var MOOD_EXPRESSION = {
  tired: "somnolent",
  love: "heureux",
  // A head tilted, eyes of unequal size looking off to one side: working
  // something out. It is what tells a turn apart from resting, together with
  // the slow sweep of `ponderLook`, since the two share a body.
  working: "curieux"
}

/**
 * The state a mood is shown as. Unknown moods rest, which is what every other
 * fallback in the plugin does.
 */
function stateForMood(mood) {
  var id = lookup(MOOD_STATE, mood)
  return id && lookup(STATE_BY_ID, id) ? id : "idle"
}

/**
 * The expression a mood imposes, or null to leave the chosen one alone. Only
 * consulted on states that wear the resting face — asking on `burst` would
 * change nothing, since that state draws its own eyes.
 */
function expressionForMood(mood, chosen) {
  var id = lookup(MOOD_EXPRESSION, mood)
  if (id && lookup(EXPRESSION_BY_ID, id)) return id
  return expressionId(chosen)
}

/**
 * Expressions a resting creature may borrow for a few seconds on its own.
 *
 * Only ones that carry no news, so the bot is never found looking alarmed for
 * no reason: this is the same rule Omarchief applies to a sprite pet's idle
 * faces, and the reason `triste`, `colere` and `effraye` are not in the pool.
 */
var IDLE_EXPRESSIONS = ["heureux", "curieux", "fier", "attentif", "blase", "timide"]

/**
 * One of the idle expressions, never the one already worn.
 *
 * `rand` is a FUNCTION returning 0..1, the same contract as Model.idleGlance,
 * so a caller passes `Math.random` rather than calling it. Using the argument
 * as though it were the number gives `NaN` for the index and `undefined` for
 * the expression, which QML then refuses to assign — silently costing every
 * idle glance rather than failing anywhere near the mistake.
 */
function idleExpression(rand, current) {
  var pool = []
  for (var i = 0; i < IDLE_EXPRESSIONS.length; i++) {
    if (IDLE_EXPRESSIONS[i] !== current) pool.push(IDLE_EXPRESSIONS[i])
  }
  if (pool.length === 0) return current
  return pool[Math.min(pool.length - 1, Math.floor(rand() * pool.length))]
}

/* --------------------------------------------------- standby performances */

// What the creature does with itself while nothing is happening.
//
// Omarchy Companion already calls these activities and owns the machinery for them:
// how often one is offered, how long it rests afterwards, the Play button, and
// `play <name>`. A spritesheet pet's activity is a row of its atlas; a drawn
// one has no atlas, so a performance here is the same three things minus the
// sheet — a name, a state, and how long to hold it.
//
// Every one of them is NEUTRAL, and that is the selection rule rather than a
// matter of taste. The catalogue also holds `thinking`, `notify`, `alert` and
// `burst`, and those four are how the plugin says something is happening. A
// creature that performed them for its own amusement would be crying wolf, and
// the next real one would not be believed.
//
// `notice` is the one that is not just a state: it looks up at whoever is at
// the desk, which is a gaze rather than a pose. See `noticeLook`.
var PERFORMANCES = [
  { name: "notice", state: "idle", seconds: 3.4 },
  { name: "wink", state: "wink", seconds: 1.6 },
  { name: "stretch", state: "wide", seconds: 1.8 },
  { name: "egg", state: "egg", seconds: 1.8 },
  { name: "hexagon", state: "hexagon", seconds: 1.6 },
  { name: "tumble", state: "play", seconds: 2.4 },
  { name: "orbit", state: "orbit", seconds: 3.6 },
  { name: "comet", state: "comet", seconds: 2.6 },
  // Long enough to read as asleep rather than as a blink. It is the one
  // performance whose whole point is that nothing happens for a while.
  { name: "doze", state: "sleep", seconds: 9 }
]

var PERFORMANCE_BY_NAME = {}
for (var _p = 0; _p < PERFORMANCES.length; _p++) {
  PERFORMANCE_BY_NAME[PERFORMANCES[_p].name] = PERFORMANCES[_p]
}

/**
 * The performances as activity tracks, which is what the rest of the plugin
 * already knows how to schedule.
 *
 * One frame held for the whole performance: `Model.activityDuration` multiplies
 * frames by holds, so a single hold of the full length is the honest way to say
 * "this lasts nine seconds" to code that was written for spritesheets. No `row`
 * is declared, because there is no sheet to have a row in.
 */
function performanceTracks() {
  var out = []
  for (var i = 0; i < PERFORMANCES.length; i++) {
    out.push({
      name: PERFORMANCES[i].name,
      frames: 1,
      holds: [Math.round(PERFORMANCES[i].seconds * 1000)]
    })
  }
  return out
}

function performanceState(name) {
  var p = lookup(PERFORMANCE_BY_NAME, name)
  return p && lookup(STATE_BY_ID, p.state) ? p.state : "idle"
}

function performanceSeconds(name) {
  var p = lookup(PERFORMANCE_BY_NAME, name)
  return p ? p.seconds : 0
}

/**
 * Looking up at whoever is at the desk.
 *
 * A gaze script: a pure function of the time since the performance began, in
 * seconds, evaluated every frame. The rule that keeps such a script free of
 * maintenance is that it must END at `mix: 0`, handing the eyes back to the
 * pose with nothing left to release — otherwise there is one last slide just as
 * everything should have settled.
 *
 * `mayTurn` is not a style choice. The eyes travel round the sphere rather than
 * sliding across the face, and because -360 degrees is the same angle as 0 the
 * turn lands exactly where the look asks, by construction. But the eyes are
 * re-seated to the real outline, so on a shape that is not a circle they follow
 * the profile while they travel and hop along it. On those the gaze slides
 * instead, which is the same intent and the only thing that reads.
 */
function noticeLook(t, seconds, mayTurn) {
  var release = 0.6
  var arrive = easings.easeOutQuint(clamp(t / 0.4))
  var leave = easings.easeOutQuint(clamp((t - (seconds - release)) / release))
  var mix = arrive * (1 - leave)
  return {
    yaw: 0,
    pitch: LOOK_PITCH,
    mix: mix,
    spin: mayTurn ? 360 * (1 - easings.easeInOutCubic(clamp(t / 1.1))) : 0,
    // The automatic drift comes back as the look lets go, not after it.
    wander: 1 - mix
  }
}

/**
 * Thinking, as the character rather than as a spinner.
 *
 * A gaze script like `noticeLook`, but with no end: it runs for as long as the
 * turn does, and the caller stops asking when the work finishes.
 *
 * `mix` is a flat 1 and `wander` a flat 0, so this REPLACES the resting drift
 * rather than adding to it — cumulative, the eyes would wander about a moving
 * target and read as agitated instead of thoughtful. The two periods do not
 * divide into one another, so the sweep never settles into a visible loop; the
 * same trick the resting drift uses, just wider and slower so that a turn does
 * not look like standing still.
 */
function ponderLook(t) {
  return {
    yaw: Math.sin(t * 0.55) * 12 + Math.sin(t * 0.23 + 1.7) * 3,
    pitch: LOOK_PITCH + 2 + Math.sin(t * 0.41 + 0.9) * 6,
    mix: 1,
    spin: 0,
    wander: 0
  }
}

/* ------------------------------------------------------------- validation */

// Every one of these reads a value that came from shell.json or a command line,
// so none of them may assume anything about its type.

function shapeId(value) {
  return lookup(SHAPE_BY_ID, value) ? String(value) : DEFAULT_SHAPE
}

function colorId(value) {
  return lookup(COLOR_BY_ID, value) ? String(value) : DEFAULT_COLOR
}

function expressionId(value) {
  return lookup(EXPRESSION_BY_ID, value) ? String(value) : DEFAULT_EXPRESSION
}

function isShapeId(value) { return lookup(SHAPE_BY_ID, value) !== null }
function isColorId(value) { return lookup(COLOR_BY_ID, value) !== null }
function isExpressionId(value) { return lookup(EXPRESSION_BY_ID, value) !== null }

/** `{ value, label }` pairs, the shape every picker in the panel expects. */
function panelOptions(list) {
  var out = []
  for (var i = 0; i < list.length; i++) out.push({ value: list[i].id, label: list[i].name })
  return out
}

/** The accepted values, for a command line that was given something else. */
function idsOf(list) {
  var out = []
  for (var i = 0; i < list.length; i++) out.push(list[i].id)
  return out.join(", ")
}

/**
 * The body's colour, resolved. `theme` is the one entry with no hex of its own:
 * it wears whatever accent the desktop currently has, which only the caller
 * knows.
 */
function inkFor(id, accent) {
  var c = lookup(COLOR_BY_ID, colorId(id))
  return c.accent ? String(accent) : c.hex
}

/* ------------------------------------------------------------------ paint */

/**
 * The creature as a bar icon: its outline in one colour, eyes punched clean
 * through.
 *
 * A bar icon is not a small drawing of the creature, it is a MARK. It carries
 * no decor, holds still, and takes the bar's own foreground like every glyph
 * beside it — a mark that kept its own colours would be the one unthemed thing
 * in the row and would read as wrong.
 *
 * The eyes are cut with `destination-out` rather than filled with a background
 * colour, because a bar may be transparent and there is no colour that is
 * right for a hole in that case. That works here and not on the desktop only
 * because this canvas holds nothing but the creature: erasing takes whatever
 * is underneath with it, and on the desktop that would include the half of an
 * orbit drawn behind the body.
 */
function paintMark(ctx, frame, ink) {
  ctx.globalAlpha = 1
  ctx.beginPath()
  traceClosed(ctx, frame.bodyPts)
  ctx.fillStyle = ink
  ctx.fill()

  ctx.globalCompositeOperation = "destination-out"
  for (var i = 0; i < frame.eyes.length; i++) {
    var e = frame.eyes[i]
    if (e.alpha < 0.5) continue
    ctx.beginPath()
    traceCapsule(ctx, e.w, e.h, e.m)
    ctx.fill()
  }
  ctx.globalCompositeOperation = "source-over"
}

/**
 * Draws one sampled frame onto a Canvas context whose origin is the bot's
 * centre.
 *
 * `ink` is the body, `paper` what shows through the eyes. In the original the
 * eyes are real holes punched in the body, so that the silhouette clips them on
 * its own when the gaze carries them to the edge. A Canvas has no mask, so the
 * same thing is had by clipping the eyes to the body path and painting them in
 * `paper` — the colour a hole would have revealed anyway, since the body sits on
 * an opaque fill of it. Filling them white instead would make them lighter than
 * the ground, which shows on a large creature.
 */
function paint(ctx, frame, ink, paper) {
  var i, j, k

  var tracePolys = function(polys) {
    for (var a = 0; a < polys.length; a++) {
      var run = polys[a]
      if (run.length < 2) continue
      ctx.beginPath()
      ctx.moveTo(run[0].x, run[0].y)
      for (var b = 1; b < run.length; b++) ctx.lineTo(run[b].x, run[b].y)
      ctx.stroke()
    }
  }

  var strokeArc = function(arc, which) {
    var g = ctx.createLinearGradient(arc.grad.x1, arc.grad.y1, arc.grad.x2, arc.grad.y2)
    for (var s = 0; s < arc.grad.stops.length; s++) {
      g.addColorStop(s / (arc.grad.stops.length - 1), arc.grad.stops[s])
    }
    ctx.strokeStyle = g
    ctx.lineWidth = arc.width
    ctx.lineCap = "round"
    ctx.globalAlpha = arc.opacity
    tracePolys(which)
  }

  var paintDots = function() {
    for (var d = 0; d < frame.dots.length; d++) {
      var dot = frame.dots[d]
      // The colour follows the body by default; `depth` is for the burst
      // particles, which fade into the ground as they fall behind the core.
      ctx.fillStyle = dot.color ? dot.color
        : (dot.depth === undefined ? ink : mixHex(paper, ink, dot.depth))
      ctx.globalAlpha = dot.opacity
      ctx.beginPath()
      if (dot.poly) {
        var a = ((dot.rot || 0) * Math.PI) / 180
        var ca = Math.cos(a)
        var sa = Math.sin(a)
        for (var p = 0; p < dot.poly.length; p++) {
          var v = dot.poly[p]
          var x = dot.x + (v.x * ca - v.y * sa) * dot.scale
          var y = dot.y + (v.x * sa + v.y * ca) * dot.scale
          if (p === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
        }
        ctx.closePath()
      } else {
        ctx.ellipse(dot.x - dot.r, dot.y - dot.r, dot.r * 2, dot.r * 2)
      }
      ctx.fill()
    }
  }

  // the back half of the orbits, drawn before the body so the body occludes it
  for (i = 0; i < frame.arcs.length; i++) strokeArc(frame.arcs[i], frame.arcs[i].back)

  if (frame.dotsBehind) paintDots()

  ctx.globalAlpha = frame.bodyAlpha

  // An opaque ground in the body's exact shape, under the body itself: the eyes
  // are holes, and a hole would otherwise show the back half of the rings.
  ctx.beginPath()
  traceClosed(ctx, frame.bodyPts)
  ctx.fillStyle = paper
  ctx.fill()
  ctx.fillStyle = ink
  ctx.fill()

  // the eyes, clipped to the body so they cannot spill past its outline
  if (frame.eyes.length > 0 || frame.notch) {
    ctx.save()
    ctx.beginPath()
    traceClosed(ctx, frame.bodyPts)
    ctx.clip()
    ctx.fillStyle = paper
    for (j = 0; j < frame.eyes.length; j++) {
      var e = frame.eyes[j]
      ctx.globalAlpha = frame.bodyAlpha * e.alpha
      ctx.beginPath()
      traceCapsule(ctx, e.w, e.h, e.m)
      ctx.fill()
    }
    if (frame.notch) {
      ctx.globalAlpha = frame.bodyAlpha
      ctx.beginPath()
      ctx.ellipse(frame.notch.x - frame.notch.r, frame.notch.y - frame.notch.r,
                  frame.notch.r * 2, frame.notch.r * 2)
      ctx.fill()
    }
    ctx.restore()
  }

  ctx.globalAlpha = 1
  if (!frame.dotsBehind) paintDots()

  if (frame.notif) {
    ctx.fillStyle = NOTIF_BLUE
    ctx.globalAlpha = 1
    ctx.beginPath()
    ctx.ellipse(frame.notif.x - frame.notif.r, frame.notif.y - frame.notif.r,
                frame.notif.r * 2, frame.notif.r * 2)
    ctx.fill()
  }

  // the front half of the orbits
  for (k = 0; k < frame.arcs.length; k++) strokeArc(frame.arcs[k], frame.arcs[k].front)

  ctx.globalAlpha = 1
}

/* ------------------------------------------------------------ looking at you */

/**
 * Head angles, in degrees, for following the pointer. CHOSEN, not measured: the
 * reference video has no cursor in it. Wide enough to read as more than the
 * resting drift (+-7deg of yaw, +-5.5 of pitch), held back enough that neither
 * eye disappears behind the limb of the sphere.
 */
var YAW_MAX = 16
var PITCH_MAX = 13
/**
 * The height the gaze holds with the pointer level with the centre. Slightly
 * above the equator, which reads as attentive rather than absent.
 *
 * An ABSOLUTE value, and that is the whole point: relative, the eye height
 * followed each expression's own, and since `neutre` looks at +28.6deg while the
 * moods sit between -9 and +9, the eyes dropped the moment the mood changed.
 */
var LOOK_PITCH = 10

/**
 * Where to look for a pointer at `nx`, `ny` — its offset from the creature's
 * centre, each -1 to 1, y positive downwards. `mix` is how much of the pose the
 * pointer commands, which the caller ramps so that the gaze arrives rather than
 * snapping.
 *
 * Nothing here compensates for the expression on screen: the engine does that
 * blend, because only it knows the pose at this instant. Doing it here would
 * mean reading an expression's ARRIVAL yaw while the engine is still morphing
 * towards it, and the eyes jumped at every change of mood.
 */
function lookAt(nx, ny, mix) {
  return {
    yaw: clamp(nx, -1, 1) * YAW_MAX,
    // positive pitch means looking up, while the screen's y goes down
    pitch: LOOK_PITCH - clamp(ny, -1, 1) * PITCH_MAX,
    mix: clamp(mix),
    spin: 0,
    // With a pointer the automatic drift stands down: added together, the bot
    // looks like it is hunting for the cursor without ever holding it.
    wander: 1 - clamp(mix)
  }
}
