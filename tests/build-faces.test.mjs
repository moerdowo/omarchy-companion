import test, { after, before } from "node:test"
import assert from "node:assert/strict"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { spawnSync } from "node:child_process"

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, "..")
const builderPath = join(root, "tools/build-faces.py")
const childEnv = { ...process.env, PYTHONDONTWRITEBYTECODE: "1" }

let work
let sourcePath

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

function build(args) {
  return run(builderPath, args)
}

function basicArgs(outPath) {
  return [outPath, sourcePath, "2", "1", "idle,blink"]
}

before(() => {
  const magick = run("magick", ["-version"])
  assert.match(succeed(magick, "ImageMagick version check"), /^Version: ImageMagick 7\./m)
  succeed(run("python3", ["-c", "import numpy"]), "NumPy import")

  work = mkdtempSync(join(tmpdir(), "grokchief-faces-test-"))
  sourcePath = join(work, "faces.png")
  succeed(run("magick", [
    "-size", "400x220", "xc:none",
    "-fill", "#5ed6a0", "-draw", "rectangle 30,20 170,200",
    "-fill", "#62a9ff", "-draw", "rectangle 230,20 370,200",
    `PNG32:${sourcePath}`,
  ]), "synthetic face sheet")
})

after(() => {
  if (work) rmSync(work, { recursive: true, force: true })
})

test("the documented face-sheet command builds aligned named cells", () => {
  const outPath = join(work, "faces.webp")
  const stdout = succeed(build([
    ...basicArgs(outPath),
    "--height", "64",
    "--borrow-body", "idle:blink",
    "--panel", "15,12,20,20,0",
  ]), "documented build-faces command")
  const metadata = JSON.parse(stdout)

  assert.equal(metadata.spritesheetPath, "faces.webp")
  assert.equal(metadata.rows, 1)
  assert.equal(metadata.columns, 2)
  assert.deepEqual(metadata.faces, { idle: [0, 0], blink: [0, 1] })
  assert.equal(metadata._cell[1], 64)
  assert.ok(metadata._cell[0] > 0)
  assert.ok(metadata._bodyHeight > 0)
  assert.ok(metadata._groundLine > 0 && metadata._groundLine <= 64)

  const dimensions = succeed(run("magick", [
    "identify", "-format", "%w %h", outPath,
  ]), "face-sheet dimensions").trim().split(/\s+/).map(Number)
  assert.deepEqual(dimensions, [metadata._cell[0] * 2, 64])

  const pixels = succeed(run("magick", [
    outPath, "-format",
    `%[pixel:p{25,20}] %[pixel:p{${metadata._cell[0] + 25},20}] `
      + `%[pixel:p{25,45}] %[pixel:p{${metadata._cell[0] + 25},45}]`,
    "info:",
  ]), "borrowed face pixels").trim().split(/\s+/)
  assert.notEqual(pixels[0], pixels[1], "the target expression must fill the borrowed panel")
  assert.equal(pixels[2], pixels[3], "outside the panel, the base body must remain byte-exact")
})

test("the face-sheet CLI rejects missing, unknown, repeated, and incomplete options", () => {
  const outPath = join(work, "invalid.webp")
  const cases = [
    ["missing positional names", [outPath, sourcePath, "2", "1"],
      /the following arguments are required: NAME,NAME,\.\.\./],
    ["unknown flag", [...basicArgs(outPath), "--unknown"],
      /unrecognized arguments: --unknown/],
    ["height without value", [...basicArgs(outPath), "--height"],
      /argument --height: expected one argument/],
    ["borrow without value", [...basicArgs(outPath), "--borrow-body"],
      /argument --borrow-body: expected one argument/],
    ["panel without value", [...basicArgs(outPath), "--panel"],
      /argument --panel: expected one argument/],
    ["borrow without panel", [...basicArgs(outPath), "--borrow-body", "idle:blink"],
      /--borrow-body and --panel must be used together/],
    ["panel without borrow", [...basicArgs(outPath), "--panel", "15,12,20,20,0"],
      /--borrow-body and --panel must be used together/],
  ]
  for (const [name, args, message] of cases)
    fail(build(args), message, name)

  const repeated = [
    ["--height", [...basicArgs(outPath), "--height", "64", "--height", "80"]],
    ["--borrow-body", [...basicArgs(outPath),
      "--borrow-body", "idle:blink", "--borrow-body", "idle:blink"]],
    ["--panel", [...basicArgs(outPath),
      "--panel", "15,12,20,20,0", "--panel", "15,12,20,20,0"]],
  ]
  for (const [flag, args] of repeated)
    fail(build(args), new RegExp(`${flag} may only be specified once`), `repeated ${flag}`)
})

test("face names are unique and every declared dimension is positive", () => {
  const outPath = join(work, "invalid-dimensions.webp")
  const cases = [
    ["duplicate face", [outPath, sourcePath, "2", "1", "idle,idle"],
      /face names may not repeat: idle/],
    ["empty face", [outPath, sourcePath, "2", "1", "idle,"],
      /face names may not be empty/],
    ["zero columns", [outPath, sourcePath, "0", "1", "idle"],
      /argument COLS: must be greater than zero/],
    ["negative rows", [outPath, sourcePath, "2", "-1", "idle,blink"],
      /argument ROWS: must be greater than zero/],
    ["zero height", [...basicArgs(outPath), "--height", "0"],
      /argument --height: must be greater than zero/],
    ["zero panel width", [...basicArgs(outPath),
      "--borrow-body", "idle:blink", "--panel", "15,12,0,20,0"],
      /--panel width and height must be positive/],
  ]
  for (const [name, args, message] of cases)
    fail(build(args), message, name)
})
