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

test("persists copy format with the documented atomic config schema", () => {
  assert.ok(panelSource.includes('copyConfigPath: Quickshell.env("HOME") + "/.config/omarchy/zotero-search.json"'))
  assert.match(panelSource, /atomicWrites: true/)
  assert.match(panelSource, /schemaVersion: 1/)
  assert.match(panelSource, /copyConfigFile\.setText\(JSON\.stringify/)
  assert.match(panelSource, /onSaveFailed/)
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
