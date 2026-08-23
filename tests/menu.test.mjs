// Every row in the popout runs a command over the shell's IPC, and Quickshell
// counts a call's arguments before it looks at them: a verb declared
// `function speak(on: string)` refuses a bare `speak` outright. The popout
// closes on click, so the refusal is never seen by anybody — the setting
// simply does not change. That is how seven toggles, the agent picker and
// "Do something" were all quietly inert at once.
//
// So: read the menu's commands and the IPC verbs out of the source, and hold
// them to each other.
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

// The entry directory is renamed on every deploy to defeat the shell's QML
// cache, so ask the manifest where the source is rather than naming it here.
const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, "..")
const manifest = JSON.parse(readFileSync(join(root, "manifest.json"), "utf8"))
const entry = dirname(manifest.entryPoints.panel)
const read = (f) => readFileSync(join(root, entry, f), "utf8")

// The verbs, and how many arguments each insists on.
function ipcVerbs() {
  const src = read("ChiefPanel.qml")
  const at = src.indexOf("IpcHandler {")
  assert.ok(at > 0, "no IpcHandler in the panel")
  const verbs = new Map()
  for (const m of src.slice(at).matchAll(/^\s{4}function\s+(\w+)\(([^)]*)\)\s*:/gm))
    verbs.set(m[1], m[2].trim() === "" ? 0 : m[2].split(",").length)
  return verbs
}

// Every command the popout can run, and how many arguments it supplies.
function menuCalls() {
  const src = read("BarWidget.qml")
  const head = "omarchy-shell omarchief "
  const calls = []
  const add = (literal, appended) => {
    if (!literal.startsWith(head)) return
    const rest = literal.slice(head.length)
    const verb = rest.split(/\s+/)[0]
    const tail = rest.slice(verb.length).trim()
    calls.push({ verb, args: (tail === "" ? 0 : tail.split(/\s+/).length) + (appended ? 1 : 0) })
  }
  for (const m of src.matchAll(/\bcommand:\s*"([^"]*)"(\s*\+)?/g)) add(m[1], !!m[2])
  for (const m of src.matchAll(/\bprefix:\s*"([^"]*)"/g)) add(m[1], true)
  for (const m of src.matchAll(/\brun\("([^"]*)"\)/g)) add(m[1], false)
  return calls
}

test("every menu command names a verb that exists", () => {
  const verbs = ipcVerbs()
  const calls = menuCalls()
  assert.ok(calls.length >= 15, `only found ${calls.length} menu commands`)
  for (const c of calls)
    assert.ok(verbs.has(c.verb), `the menu runs "${c.verb}", which the panel does not answer`)
})

test("every menu command supplies the arguments its verb requires", () => {
  const verbs = ipcVerbs()
  for (const c of menuCalls())
    assert.equal(c.args, verbs.get(c.verb),
      `"${c.verb}" is declared with ${verbs.get(c.verb)} argument(s); the menu passes ${c.args}`)
})

test("no chosen value reaches IPC unquoted", () => {
  const src = read("BarWidget.qml")
  assert.equal(src.includes("run(modelData.prefix + v)"), false,
    "a value with a space in it would arrive as several arguments")
  assert.ok(src.includes("runValue(modelData.prefix, v)"))
})
