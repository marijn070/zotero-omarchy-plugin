const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const context = {}
vm.runInNewContext(source, context)

test("normalizes Better BibTeX JSON and searches citation keys", () => {
  const items = context.normalizeBibliography([
    {
      title: "Robots and RDF",
      "citation-key": "smithRobots2024",
      author: [{ family: "Smith", given: "Ada" }],
      issued: { "date-parts": [[2024]] }
    }
  ])

  assert.equal(items[0].citationKey, "smithRobots2024")
  assert.equal(context.searchItems(items, "smithRobots", 10).length, 1)
  assert.equal(context.searchItems(items, "missing", 10).length, 0)
})

test("normalizes Zotero fallback items without inventing citation keys", () => {
  const items = context.normalizeZotero([
    { data: { title: "A fallback result", creators: [{ lastName: "Doe" }] } }
  ])

  assert.equal(items[0].citationKey, "")
  assert.equal(items[0].authors, "Doe")
})
