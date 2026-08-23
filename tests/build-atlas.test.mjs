import test, { after, before } from "node:test"
import assert from "node:assert/strict"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { spawnSync } from "node:child_process"

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, "..")
const builderPath = join(root, "tools/build-atlas.py")
const childEnv = { ...process.env, PYTHONDONTWRITEBYTECODE: "1" }

let work
let walkPath
let idlePath
let activitiesPath

function run(command, args) {
  return spawnSync(command, args, {
    cwd: root,
    encoding: "utf8",
    env: childEnv,
    maxBuffer: 16 * 1024 * 1024,
  })
}

function succeed(result, context) {
  assert.equal(result.signal, null, `${context} was killed by ${result.signal}`)
  assert.equal(result.status, 0, `${context} failed:\n${result.stderr || result.stdout}`)
  return result.stdout
}

function fail(result, expected, context) {
  assert.equal(result.signal, null, `${context} was killed by ${result.signal}`)
  assert.notEqual(result.status, 0, `${context} unexpectedly succeeded`)
  assert.match(`${result.stderr}\n${result.stdout}`, expected)
}

function magick(args) {
  return succeed(run("magick", args), `magick ${args.join(" ")}`)
}

function build(args) {
  return run(builderPath, args)
}

function minimalArgs(outPath) {
  return [outPath, "--walk", walkPath, "3", "--idle", idlePath]
}

function completeArgs(outPath) {
  return [
    ...minimalArgs(outPath),
    "--activities", activitiesPath, "4", "2", "ponder,celebrate",
    "--poses", "working=0:0,error=0:1,waiting=1:0,success=1:1",
  ]
}

function draw(path, size, shapes) {
  const args = ["-size", size, "xc:none"]
  for (const [colour, shape] of shapes)
    args.push("-fill", colour, "-draw", shape)
  args.push(`PNG32:${path}`)
  magick(args)
}

function cellBox(atlasPath, column, row) {
  const raw = magick([
    atlasPath,
    "-crop", `192x208+${column * 192}+${row * 208}`,
    "+repage", "-alpha", "extract", "-threshold", "20%",
    "-format", "%@", "info:",
  ]).trim()
  const match = raw.match(/^(\d+)x(\d+)\+(\d+)\+(\d+)$/)
  assert.ok(match, `cell ${row}:${column} has no visible bounding box: ${raw}`)
  const [width, height, x, y] = match.slice(1).map(Number)
  return { width, height, x, y }
}

before(() => {
  const version = run("magick", ["-version"])
  const output = succeed(version, "ImageMagick version check")
  assert.match(output, /^Version: ImageMagick 7\./m,
    "the atlas contract requires ImageMagick 7's magick command")

  work = mkdtempSync(join(tmpdir(), "omarchief-atlas-test-"))
  walkPath = join(work, "walk.png")
  idlePath = join(work, "idle.png")
  activitiesPath = join(work, "activities.png")

  // The middle and final walk frames deliberately reach one edge of their
  // 100px source cell. A height-only scaler would enlarge and clip them.
  draw(walkPath, "300x120", [
    ["#5ed6a0", "rectangle 35,35 64,110"],
    ["#5ed6a0", "polygon 100,110 100,45 179,110"],
    ["#5ed6a0", "polygon 220,110 299,45 299,110"],
  ])
  draw(idlePath, "100x120", [
    ["#5ed6a0", "ellipse 50,75 15,35 0,360"],
  ])
  draw(activitiesPath, "400x240", [
    ["#5ed6a0", "rectangle 35,35 64,110"],
    ["#62a9ff", "ellipse 150,75 25,35 0,360"],
    ["#ffcf5e", "polygon 215,110 250,25 285,110"],
    ["#ec7f9b", "rectangle 330,55 370,110"],
    ["#5ed6a0", "rectangle 35,155 64,230"],
    ["#b985ff", "polygon 115,230 150,145 185,230"],
    ["#62a9ff", "rectangle 220,160 299,230"],
    ["#ffcf5e", "ellipse 350,195 25,35 0,360"],
  ])
})

after(() => {
  if (work) rmSync(work, { recursive: true, force: true })
})

test("a complete tiny source set builds the fixed atlas without horizontal clipping", () => {
  const atlasPath = join(work, "atlas.webp")
  const stdout = succeed(build(completeArgs(atlasPath)), "valid atlas build")
  const metadataStart = stdout.indexOf("{")
  assert.notEqual(metadataStart, -1, `builder printed no metadata:\n${stdout}`)
  const metadata = JSON.parse(stdout.slice(metadataStart))

  assert.equal(metadata.rows, 11)
  assert.equal(metadata.walkFrames, 3)
  assert.deepEqual(metadata.activities.map(({ name, row, frames }) => ({ name, row, frames })), [
    { name: "ponder", row: 9, frames: 4 },
    { name: "celebrate", row: 10, frames: 4 },
  ])

  const dimensions = magick(["identify", "-format", "%w %h", atlasPath])
    .trim().split(/\s+/).map(Number)
  assert.deepEqual(dimensions, [192 * 8, 208 * 11])

  const boxes = [0, 1, 2].map((column) => cellBox(atlasPath, column, 1))
  for (const box of boxes) {
    assert.ok(box.x >= 2, `walk frame crosses the left safe edge: ${JSON.stringify(box)}`)
    assert.ok(box.x + box.width <= 190,
      `walk frame crosses the right safe edge: ${JSON.stringify(box)}`)
  }
  assert.ok(boxes.some((box) => box.x <= 4),
    "fixture no longer exercises the left horizontal limit")
  assert.ok(boxes.some((box) => box.x + box.width >= 188),
    "fixture no longer exercises the right horizontal limit")
})

test("the CLI rejects invalid dimensions, pose coordinates, and activity names", () => {
  const outPath = join(work, "invalid.webp")
  const cases = [
    ["zero walk frames", [outPath, "--walk", walkPath, "0", "--idle", idlePath],
      /--walk FRAMES must be between 1 and 8/],
    ["nine walk frames", [outPath, "--walk", walkPath, "9", "--idle", idlePath],
      /--walk FRAMES must be between 1 and 8/],
    ["nine activity columns", [...minimalArgs(outPath),
      "--activities", activitiesPath, "9", "2", "ponder,celebrate"],
      /--activities COLS must be between 1 and 8/],
    ["zero activity rows", [...minimalArgs(outPath),
      "--activities", activitiesPath, "4", "0", "ponder"],
      /--activities ROWS must be greater than zero/],
    ["too few activity names", [...minimalArgs(outPath),
      "--activities", activitiesPath, "4", "2", "ponder"],
      /--activities NAMES must contain exactly one name per row/],
    ["repeated activity name", [...minimalArgs(outPath),
      "--activities", activitiesPath, "4", "2", "ponder,ponder"],
      /--activities NAMES may not repeat: ponder/],
    ["negative pose row", [...minimalArgs(outPath),
      "--activities", activitiesPath, "4", "2", "ponder,celebrate",
      "--poses", "working=-1:0"],
      /pose working row and column must be non-negative/],
    ["negative pose column", [...minimalArgs(outPath),
      "--activities", activitiesPath, "4", "2", "ponder,celebrate",
      "--poses", "working=0:-1"],
      /pose working row and column must be non-negative/],
    ["unsupported pose name", [...minimalArgs(outPath),
      "--activities", activitiesPath, "4", "2", "ponder,celebrate",
      "--poses", "joy=0:0"],
      /unsupported pose 'joy'; expected one of working, error, waiting, success, sleep/],
  ]

  for (const [name, args, message] of cases)
    fail(build(args), message, name)
})

test("walk and activity sheets must divide exactly into their declared grids", () => {
  const outPath = join(work, "indivisible.webp")
  fail(build([outPath, "--walk", walkPath, "8", "--idle", idlePath]),
    /walk sheet is 300x120, not exactly divisible by 8x1/, "indivisible walk sheet")
  fail(build([
    ...minimalArgs(outPath),
    "--activities", activitiesPath, "3", "2", "ponder,celebrate",
  ]), /activity sheet is 400x240, not exactly divisible by 3x2/,
    "indivisible activity sheet")
  fail(build([
    ...minimalArgs(outPath),
    "--activities", activitiesPath, "4", "7", "one,two,three,four,five,six,seven",
  ]), /activity sheet is 400x240, not exactly divisible by 4x7/,
    "indivisible activity sheet height")
})

test("unknown and repeated flags are hard errors", () => {
  const outPath = join(work, "bad-flags.webp")
  fail(build([...minimalArgs(outPath), "--unknown"]), /unrecognized arguments: --unknown/,
    "unknown flag")

  const repeated = [
    ["--walk", [outPath, "--walk", walkPath, "3", "--walk", walkPath, "3", "--idle", idlePath]],
    ["--idle", [...minimalArgs(outPath), "--idle", idlePath]],
    ["--activities", [...completeArgs(outPath),
      "--activities", activitiesPath, "4", "2", "ponder,celebrate"]],
    ["--poses", [...completeArgs(outPath), "--poses", "working=0:0"]],
  ]
  for (const [flag, args] of repeated)
    fail(build(args), new RegExp(`${flag} may only be specified once`), `repeated ${flag}`)
})

test("compare accepts exit 0/1 and rejects tool or RMSE protocol failures", () => {
  const probe = String.raw`
import json
import runpy
import sys
from types import SimpleNamespace

namespace = runpy.run_path(sys.argv[1])
response = SimpleNamespace(returncode=int(sys.argv[2]), stderr=sys.argv[3], stdout="")
namespace["rmse"].__globals__["subprocess"].run = lambda *args, **kwargs: response
try:
    value = namespace["rmse"]("first.png", "second.png")
except namespace["BuildError"] as error:
    print(json.dumps({"kind": "error", "message": str(error)}))
else:
    print(json.dumps({"kind": "value", "value": value}))
`
  const inspect = (returnCode, detail) => {
    const stdout = succeed(run("python3", [
      "-c", probe, builderPath, String(returnCode), detail,
    ]), `RMSE probe for exit ${returnCode}`)
    return JSON.parse(stdout)
  }

  assert.deepEqual(inspect(0, "0 (0)"), { kind: "value", value: 0 })
  assert.deepEqual(inspect(1, "123.5 (0.001884)"), { kind: "value", value: 123.5 })
  assert.match(inspect(2, "delegate exploded").message,
    /compare failed.*exit 2.*delegate exploded/)
  assert.match(inspect(0, "not-an-rmse").message, /no parseable RMSE/)
})

test("unexpected connected-components records become a builder error", () => {
  const probe = String.raw`
import json
import runpy
import sys

namespace = runpy.run_path(sys.argv[1])
try:
    namespace["parse_connected_components"](
        "  1: not-a-geometry centroid 42 gray(255)", "cell.png"
    )
except namespace["BuildError"] as error:
    print(json.dumps({"kind": "error", "message": str(error)}))
else:
    print(json.dumps({"kind": "value"}))
`
  const stdout = succeed(run("python3", ["-c", probe, builderPath]),
    "connected-components parser probe")
  const result = JSON.parse(stdout)
  assert.equal(result.kind, "error")
  assert.match(result.message,
    /cannot parse ImageMagick connected-components output for cell\.png/)
})
