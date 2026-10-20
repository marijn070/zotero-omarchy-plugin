const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const panelSource = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
const context = {}
vm.runInNewContext(source, context)

test("publishes Typst as the safe default copy format", () => {
  const metadata = manifest.barWidget
  assert.equal(metadata.defaults.copyFormat, "typst")
  assert.deepEqual(metadata.schema[0].options, ["typst", "latex"])
  assert.equal(metadata.schema[0].defaultValue, "typst")
})

test("copies exact Typst and LaTeX citekey output", () => {
  const item = { citationKey: "smithRobots2024" }
  assert.equal(context.copyOutput(item, "typst"), "@smithRobots2024")
  assert.equal(context.copyOutput(item, "latex"), "\\cite{smithRobots2024}")
  assert.equal(context.copyOutput(item, "citekey"), "@smithRobots2024")
  assert.equal(context.copyOutput(item, "citation"), "@smithRobots2024")
  assert.equal(context.copyOutput({ citationKey: "" }, "latex"), "")
})

test("starts Zotero only through the fixed local command", () => {
  assert.match(panelSource, /Quickshell\.execDetached\(\["\/usr\/bin\/zotero"\]\)/)
  assert.match(panelSource, /text: root\.zoteroStarting \? "Starting Zotero\.\.\." : "Start Zotero"/)
  assert.match(panelSource, /zoteroProbeEndpoint/)
})

test("persists settings, pins and recents with the documented atomic config schema", () => {
  assert.ok(panelSource.includes('statePath: Quickshell.env("HOME") + "/.config/omarchy/zotero-search.json"'))
  assert.match(panelSource, /atomicWrites: true/)
  assert.match(panelSource, /stateFile\.setText\(Model\.serializeState\(root\.copyFormat, root\.pinned, root\.recent\)\)/)
  assert.match(panelSource, /onSaveFailed/)
  assert.match(source, /schemaVersion: 1/)
})

test("renders every Text element as plain text", () => {
  const texts = panelSource.match(/^\s*Text \{$/gm) || []
  const plain = panelSource.match(/^\s*textFormat: Text\.PlainText$/gm) || []
  assert.ok(texts.length >= 8)
  assert.equal(plain.length, texts.length, "Zotero titles and citekeys are untrusted and must never be parsed as rich text")
})

test("records a recent paper only when a citekey was actually copied", () => {
  const copy = panelSource.match(/function copyItem\(item\) \{([\s\S]*?)\n  \}/)[1]
  assert.ok(copy.indexOf('Quickshell.execDetached(["wl-copy"') < copy.indexOf("root.recordRecent(item)"))
  assert.equal((copy.match(/recordRecent/g) || []).length, 1)
  assert.ok(copy.indexOf("item.missing") < copy.indexOf("Quickshell.execDetached"))
})

test("offers an accessible pin action with a keyboard shortcut", () => {
  assert.match(panelSource, /sequence: "Ctrl\+B"/)
  assert.match(panelSource, /onActivated: root\.togglePinSelected\(\)/)
  assert.match(panelSource, /Accessible\.name: entry\.pinLabel/)
  assert.match(panelSource, /"Unpin paper" : "Pin paper"/)
})

test("uses Better BibTeX first but gates startup on the Zotero API probe", () => {
  const exportIndex = panelSource.indexOf('command: ["curl", "-fsS", "--max-time", "10", root.endpoint]')
  const probeIndex = panelSource.indexOf('command: ["curl", "-fsS", "--max-time", "3", root.zoteroProbeEndpoint]')
  assert.ok(exportIndex >= 0 && probeIndex > exportIndex)
  assert.match(panelSource, /root\.startFallback\(\)/)
  assert.match(panelSource, /root\.statusMessage = "Searching Zotero library"/)
  assert.match(panelSource, /visible: root\.zoteroUnavailable \|\| root\.zoteroStarting/)
  assert.doesNotMatch(panelSource, /Better BibTeX is unavailable; searching Zotero/)
  assert.doesNotMatch(panelSource, /items from Better BibTeX/)
})

test("normalizes Better BibTeX JSON and searches citation keys", () => {
  const items = context.normalizeBibliography([
    {
      title: "Robots and RDF",
      "citation-key": "smithRobots2024",
      author: [{ family: "Smith", given: "Ada" }],
      issued: { "date-parts": [[2024]] },
      "container-title": "Journal of RDF"
    }
  ])

  assert.equal(items[0].citationKey, "smithRobots2024")
  assert.equal(items[0].citation, "Smith, Ada (2024). Robots and RDF. Journal of RDF.")
  assert.equal(context.searchItems(items, "smithRobots", 10).length, 1)
  assert.equal(context.searchItems(items, "missing", 10).length, 0)
})

test("normalizes Zotero fallback items without inventing citation keys", () => {
  const items = context.normalizeZotero([
    {
      data: {
        title: "A fallback result",
        creators: [{ firstName: "Jane", lastName: "Doe" }],
        date: "2023-05-01",
        publicationTitle: "Local Journal"
      }
    }
  ])

  assert.equal(items[0].citationKey, "")
  assert.equal(items[0].authors, "Doe, Jane")
  assert.equal(items[0].citation, "Doe, Jane (2023). A fallback result. Local Journal.")
})

test("formats citations deterministically when an author is missing", () => {
  assert.equal(
    context.formatCitation({ title: "Untitled study", year: "2022", container: "Proceedings" }),
    "Untitled study (2022). Proceedings."
  )
  assert.equal(context.formatCitation({ title: "Just a title" }), "Just a title.")
})

test("closing the panel always hides it and never assigns read-only bar properties", () => {
  const closeBody = panelSource.match(/function close\(\) \{([\s\S]*?)\n  \}/)[1]
  assert.ok(closeBody.indexOf("root.controller.hide()") !== -1)
  assert.ok(
    closeBody.indexOf("root.controller.hide()") < closeBody.indexOf("setCenterHoverRevealSuppressed(false)"),
    "hide must run before the optional bar call so a bar API failure cannot strand the panel"
  )
  // The plugin bar API exposes centerHoverRevealSuppressed read-only; assigning it throws in close().
  assert.doesNotMatch(panelSource, /root\.bar\.centerHoverRevealSuppressed\s*=/)
  assert.match(panelSource, /root\.bar\.setCenterHoverRevealSuppressed\(value\)/)
})

function paper(citationKey, extra) {
  return Object.assign({
    title: "Paper " + citationKey,
    citationKey: citationKey,
    zoteroKey: "",
    authors: "Smith, Ada",
    year: "2024",
    container: "Journal of RDF",
    details: "Smith, Ada · 2024 · Journal of RDF"
  }, extra || {})
}

const plain = (value) => JSON.parse(JSON.stringify(value))
const sections = (entries) => plain(entries).map((entry) => entry.section + ":" + (entry.citationKey || entry.zoteroKey))

test("keeps the stable Zotero item key from Better BibTeX and the Zotero API", () => {
  const fromApi = context.normalizeZotero([{ key: "ABCD2345", data: { key: "ABCD2345", title: "API paper" } }])
  assert.equal(fromApi[0].zoteroKey, "ABCD2345")
  const fromExport = context.normalizeBibliography([
    { id: "http://zotero.org/users/local/abc/items/WXYZ6789", "citation-key": "doe2020", title: "Export paper" },
    { id: "doe2021", "citation-key": "doe2021", title: "No key" }
  ])
  assert.equal(fromExport[0].zoteroKey, "WXYZ6789")
  assert.equal(fromExport[1].zoteroKey, "")
})

test("matches papers by Zotero key or citation key", () => {
  assert.ok(context.sameItem({ zoteroKey: "ABCD2345", citationKey: "a" }, { zoteroKey: "ABCD2345", citationKey: "b" }))
  assert.ok(context.sameItem({ zoteroKey: "", citationKey: "same" }, { zoteroKey: "ABCD2345", citationKey: "same" }))
  assert.ok(!context.sameItem({ zoteroKey: "ABCD2345", citationKey: "" }, { zoteroKey: "WXYZ6789", citationKey: "" }))
  assert.ok(!context.sameItem({ zoteroKey: "", citationKey: "" }, { zoteroKey: "", citationKey: "" }))
})

test("pins newest first, unpins on toggle, and bounds the pinned list", () => {
  let pinned = []
  pinned = context.togglePin(pinned, paper("a"))
  pinned = context.togglePin(pinned, paper("b"))
  assert.deepEqual(plain(pinned).map((entry) => entry.citationKey), ["b", "a"])
  pinned = context.togglePin(pinned, paper("a"))
  assert.deepEqual(plain(pinned).map((entry) => entry.citationKey), ["b"])
  assert.deepEqual(plain(context.togglePin([], { title: "no identity" })), [])

  for (let i = 0; i < 80; i++) pinned = context.togglePin(pinned, paper("k" + i))
  assert.equal(pinned.length, 50)
  assert.equal(pinned[0].citationKey, "k79")
})

test("records recents most recent first, deduplicated and bounded", () => {
  let recent = []
  for (const key of ["a", "b", "c"]) recent = context.recordRecent(recent, paper(key))
  recent = context.recordRecent(recent, paper("a"))
  assert.deepEqual(plain(recent).map((entry) => entry.citationKey), ["a", "c", "b"])
  for (let i = 0; i < 30; i++) recent = context.recordRecent(recent, paper("r" + i))
  assert.equal(recent.length, 10)
  assert.equal(recent[0].citationKey, "r29")
  assert.deepEqual(context.recordRecent(recent, { title: "no identity" }).length, 10)
})

test("empty-query view lists pinned first, then recents without pinned duplicates", () => {
  const library = [paper("a"), paper("b"), paper("c")]
  const pinned = [paper("b"), paper("a")]
  const recent = [paper("c"), paper("a"), paper("b")]
  const view = context.homeEntries(pinned, recent, library, true)
  assert.deepEqual(sections(view), ["pinned:b", "pinned:a", "recent:c"])
  assert.ok(view[0].pinned && !view[2].pinned)
  assert.deepEqual(plain(context.homeEntries([], [], library, true)), [])
})

test("pinned and recent entries refresh from the library and survive a missing item", () => {
  const renamed = paper("a", { title: "Renamed paper", details: "Renamed details" })
  const library = [renamed]
  const pinned = [paper("a"), paper("gone")]
  const recent = [paper("also-gone"), paper("a")]
  const view = context.homeEntries(pinned, recent, library, true)
  assert.equal(view[0].title, "Renamed paper")
  assert.equal(view[0].details, "Renamed details")
  assert.ok(!view[0].missing)
  assert.equal(view[1].citationKey, "gone")
  assert.ok(view[1].missing, "a pinned paper missing from the loaded library stays visible and flagged")
  assert.equal(view.length, 2, "missing recents are dropped and pinned papers are not repeated as recents")
})

test("shows stored snapshots while the library is not loaded", () => {
  const view = context.homeEntries([paper("a")], [paper("b")], [], false)
  assert.deepEqual(sections(view), ["pinned:a", "recent:b"])
  assert.ok(view.every((entry) => !entry.missing))
  assert.equal(view[0].details, "Smith, Ada · 2024 · Journal of RDF")
})

test("flags search results with their pin state", () => {
  const results = context.decorateResults([paper("a"), paper("b")], [paper("b")])
  assert.deepEqual(plain(results).map((entry) => entry.pinned), [false, true])
  assert.ok(results.every((entry) => entry.section === "result" && entry.missing === false))
})

test("round-trips persisted state and rejects unusable files", () => {
  const text = context.serializeState("latex", [paper("a", { zoteroKey: "ABCD2345" })], [paper("b")])
  assert.ok(text.endsWith("}\n"))
  const state = context.parseState(text)
  assert.ok(state.valid)
  assert.equal(state.copyFormat, "latex")
  assert.equal(state.pinned[0].zoteroKey, "ABCD2345")
  assert.equal(state.recent[0].citationKey, "b")
  assert.ok(!("details" in state.pinned[0]), "only identity and display fields are persisted")

  for (const raw of ["", "not json", "{\"schemaVersion\":2}", "[]", "null"]) {
    const rejected = context.parseState(raw)
    assert.ok(!rejected.valid)
    assert.deepEqual(plain(rejected.pinned), [])
  }
})

test("drops malformed persisted entries and keeps the legacy copy format file readable", () => {
  const state = context.parseState(JSON.stringify({
    schemaVersion: 1,
    copyFormat: "citation",
    pinned: [null, 4, "x", {}, { citationKey: "ok" }, { citationKey: "ok" }, { zoteroKey: "bad" }],
    recent: "nope"
  }))
  assert.equal(state.copyFormat, "typst")
  assert.deepEqual(plain(state.pinned).map((entry) => entry.citationKey), ["ok"])
  assert.deepEqual(plain(state.recent), [])

  const legacy = context.parseState("{\n  \"schemaVersion\": 1,\n  \"copyFormat\": \"latex\"\n}\\n")
  assert.ok(legacy.valid)
  assert.equal(legacy.copyFormat, "latex")
})

test("bounds persisted display strings", () => {
  const entry = context.snapshot(paper("a", { title: "t".repeat(5000), authors: "x".repeat(5000) }))
  assert.equal(entry.title.length, 300)
  assert.equal(entry.authors.length, 300)
})
