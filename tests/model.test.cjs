const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
const context = {}
vm.runInNewContext(source, context)

test("publishes citekey as the backward-compatible default copy format", () => {
  const metadata = manifest.barWidget
  assert.equal(metadata.defaults.copyFormat, "citekey")
  assert.deepEqual(metadata.schema[0].options, ["citekey", "citation"])
  assert.equal(metadata.schema[0].defaultValue, "citekey")
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
