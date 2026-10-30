function clean(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

function lower(value) {
  return clean(value).toLowerCase()
}

function normalizeCopyFormat(value) {
  var format = lower(value)
  if (format === "latex") return "latex"
  if (format === "typst" || format === "citekey" || format === "citation") return "typst"
  return ""
}

function copyOutput(item, format) {
  var citationKey = clean(item && item.citationKey)
  if (!citationKey) return ""
  return normalizeCopyFormat(format) === "latex"
    ? "\\cite{" + citationKey + "}"
    : "@" + citationKey
}

function firstYear(value) {
  var parts = value && value["date-parts"]
  if (!Array.isArray(parts) || !Array.isArray(parts[0]) || parts[0].length === 0) return ""
  return clean(parts[0][0])
}

function authorsFor(item) {
  var people = Array.isArray(item.author) ? item.author : item.creators
  if (!Array.isArray(people)) return ""

  var names = []
  for (var i = 0; i < people.length; i++) {
    var person = people[i] || {}
    var family = clean(person.family || person.lastName)
    var given = clean(person.given || person.firstName)
    var name = family || given
    if (family && given) name = family + ", " + given
    if (name) names.push(name)
  }

  if (names.length > 3) return names.slice(0, 3).join("; ") + "; et al."
  return names.join("; ")
}

function formatCitation(item) {
  var source = item || {}
  var authors = clean(source.authors) || authorsFor(source)
  var year = clean(source.year) || firstYear(source.issued) || clean(source.date).slice(0, 4)
  var title = clean(source.title)
  var container = clean(source.container || source["container-title"] || source.publicationTitle)
  var parts = []

  if (title === "Untitled item") title = ""
  if (authors) {
    parts.push(authors + (year ? " (" + year + ")" : ""))
  } else if (title) {
    parts.push(title + (year ? " (" + year + ")" : ""))
    title = ""
  } else if (year) {
    parts.push(year)
  }
  if (title) parts.push(title)
  if (container) parts.push(container)

  return parts.length > 0 ? parts.join(". ") + "." : ""
}

function zoteroKeyFor(item, data) {
  var candidates = [
    item && item.key, data && data.key,
    item && item["zotero-key"], data && data["zotero-key"],
    item && item.itemKey, data && data.itemKey
  ]
  for (var i = 0; i < candidates.length; i++) {
    var value = clean(candidates[i])
    if (/^[A-Z0-9]{8}$/.test(value)) return value
  }
  var uri = clean((item && item.id) || (data && data.id))
  var match = uri.match(/\/items\/([A-Z0-9]{8})$/)
  return match ? match[1] : ""
}

function normalized(item, data) {
  var source = data || item || {}
  var title = clean(source.title)
  var citationKey = clean(source["citation-key"] || source.citationKey)
  var year = firstYear(source.issued) || clean(source.date).slice(0, 4)
  var authors = authorsFor(source)
  var container = clean(source["container-title"] || source.publicationTitle)
  var details = [authors, year, container].filter(function(value) { return value !== "" }).join(" · ")

  return {
    title: title || "Untitled item",
    zoteroKey: zoteroKeyFor(item, data),
    citationKey: citationKey,
    authors: authors,
    year: year,
    container: container,
    citation: formatCitation({
      title: title || "Untitled item",
      authors: authors,
      year: year,
      container: container
    }),
    details: details,
    searchText: lower([title, citationKey, authors, year, container].join(" "))
  }
}

function normalizeBibliography(raw) {
  if (!Array.isArray(raw)) return []
  var result = []
  for (var i = 0; i < raw.length; i++) {
    var item = normalized(raw[i])
    if (item.citationKey || item.title !== "Untitled item") result.push(item)
  }
  return result
}

function normalizeZotero(raw) {
  if (!Array.isArray(raw)) return []
  var result = []
  for (var i = 0; i < raw.length; i++) {
    var item = raw[i] || {}
    var data = item.data || {}
    var normalizedItem = normalized(item, data)
    if (normalizedItem.title !== "Untitled item") result.push(normalizedItem)
  }
  return result
}

function score(item, query) {
  var title = lower(item.title)
  var key = lower(item.citationKey)
  var author = lower(item.authors)
  if (title.indexOf(query) === 0) return 300
  if (key.indexOf(query) === 0) return 260
  if (title.indexOf(query) !== -1) return 220
  if (key.indexOf(query) !== -1) return 180
  if (author.indexOf(query) !== -1) return 120
  return 20
}

function searchItems(items, query, limit) {
  var needle = lower(query)
  var maximum = Number(limit) > 0 ? Number(limit) : 50
  if (!Array.isArray(items)) return []
  if (needle === "") return items.slice(0, maximum)

  var terms = needle.split(/\s+/).filter(function(term) { return term !== "" })
  var matches = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    var haystack = item.searchText || ""
    var matchesAll = true
    for (var j = 0; j < terms.length; j++) {
      if (haystack.indexOf(terms[j]) === -1) {
        matchesAll = false
        break
      }
    }
    if (matchesAll) matches.push({ item: item, score: score(item, needle), index: i })
  }

  matches.sort(function(a, b) {
    if (a.score !== b.score) return b.score - a.score
    var titleOrder = lower(a.item.title).localeCompare(lower(b.item.title))
    return titleOrder !== 0 ? titleOrder : a.index - b.index
  })

  var result = []
  for (var k = 0; k < matches.length && k < maximum; k++) result.push(matches[k].item)
  return result
}

// --- pinned and recent papers -------------------------------------------------
//
// Entries are small snapshots, not private library exports: the stable Zotero
// item key (when the source provides one), the Better BibTeX citation key, and
// the display fields needed to render the row while Zotero is unreachable.
// Items are matched by Zotero key or by citation key, because the Better BibTeX
// export and Zotero's own API do not always expose the same identifier.

var pinnedLimit = 50
var recentLimit = 10

function bounded(value, length) {
  var text = clean(value)
  return text.length > length ? text.slice(0, length) : text
}

function snapshot(item) {
  var source = item || {}
  var zoteroKey = clean(source.zoteroKey)
  return {
    zoteroKey: /^[A-Z0-9]{8}$/.test(zoteroKey) ? zoteroKey : "",
    citationKey: bounded(source.citationKey, 200),
    title: bounded(source.title, 300) || "Untitled item",
    authors: bounded(source.authors, 300),
    year: bounded(source.year, 16),
    container: bounded(source.container, 300)
  }
}

function sameItem(a, b) {
  if (!a || !b) return false
  var aKey = clean(a.zoteroKey)
  var bKey = clean(b.zoteroKey)
  var aCite = clean(a.citationKey)
  var bCite = clean(b.citationKey)
  if (aKey && bKey && aKey === bKey) return true
  return aCite !== "" && aCite === bCite
}

function hasIdentity(item) {
  return !!item && (clean(item.zoteroKey) !== "" || clean(item.citationKey) !== "")
}

function indexOfItem(list, item) {
  if (!Array.isArray(list)) return -1
  for (var i = 0; i < list.length; i++) if (sameItem(list[i], item)) return i
  return -1
}

function isPinned(pinned, item) {
  return indexOfItem(pinned, item) !== -1
}

function sanitizeEntries(raw, limit) {
  var result = []
  if (!Array.isArray(raw)) return result
  for (var i = 0; i < raw.length && result.length < limit; i++) {
    if (!raw[i] || typeof raw[i] !== "object") continue
    var entry = snapshot(raw[i])
    if (hasIdentity(entry) && indexOfItem(result, entry) === -1) result.push(entry)
  }
  return result
}

// Newly pinned papers go to the top of the pinned section.
function togglePin(pinned, item) {
  var entries = sanitizeEntries(pinned, pinnedLimit)
  var index = indexOfItem(entries, item)
  if (index !== -1) {
    entries.splice(index, 1)
    return entries
  }
  if (!hasIdentity(item)) return entries
  entries.unshift(snapshot(item))
  return entries.slice(0, pinnedLimit)
}

function recordRecent(recent, item) {
  var entries = sanitizeEntries(recent, recentLimit)
  if (!hasIdentity(item)) return entries
  var index = indexOfItem(entries, item)
  if (index !== -1) entries.splice(index, 1)
  entries.unshift(snapshot(item))
  return entries.slice(0, recentLimit)
}

// A pinned or recent entry is shown with the library's current metadata when the
// library snapshot is loaded. An entry the loaded library no longer contains is
// flagged missing; while the library is not loaded the stored snapshot is shown.
function resolveEntry(entry, library, libraryLoaded, section) {
  var base = snapshot(entry)
  var current = null
  if (libraryLoaded && Array.isArray(library)) {
    var index = indexOfItem(library, base)
    if (index !== -1) current = library[index]
  }
  var resolved = current ? snapshot(current) : base
  if (current) {
    resolved.details = clean(current.details)
  } else {
    resolved.details = [base.authors, base.year, base.container]
      .filter(function(value) { return value !== "" }).join(" \u00b7 ")
  }
  resolved.section = section
  resolved.pinned = section === "pinned"
  resolved.missing = !!libraryLoaded && !current
  return resolved
}

// Empty-query view: pinned papers first, then recent papers that are not pinned.
// Recent papers the loaded library no longer contains are dropped from the view.
function homeEntries(pinned, recent, library, libraryLoaded) {
  var result = []
  var pinnedEntries = sanitizeEntries(pinned, pinnedLimit)
  for (var i = 0; i < pinnedEntries.length; i++)
    result.push(resolveEntry(pinnedEntries[i], library, libraryLoaded, "pinned"))

  var recentEntries = sanitizeEntries(recent, recentLimit)
  for (var j = 0; j < recentEntries.length; j++) {
    if (indexOfItem(pinnedEntries, recentEntries[j]) !== -1) continue
    var resolved = resolveEntry(recentEntries[j], library, libraryLoaded, "recent")
    if (!resolved.missing) result.push(resolved)
  }
  return result
}

// Search-result view: plain results flagged with their pin state.
function decorateResults(items, pinned) {
  var result = []
  if (!Array.isArray(items)) return result
  for (var i = 0; i < items.length; i++) {
    var copy = {}
    for (var key in items[i]) copy[key] = items[i][key]
    copy.section = "result"
    copy.pinned = isPinned(pinned, items[i])
    copy.missing = false
    result.push(copy)
  }
  return result
}

// --- persisted state ----------------------------------------------------------

// Parses ~/.config/omarchy/zotero-search.json. Files written by the first
// release ended with a literal backslash-n instead of a newline; that suffix is
// accepted so existing settings are not lost.
function parseState(raw) {
  var state = { valid: false, copyFormat: "", pinned: [], recent: [] }
  var text = clean(raw)
  if (text.slice(-2) === "\\n") text = text.slice(0, -2)
  try {
    var parsed = JSON.parse(text)
    if (!parsed || parsed.schemaVersion !== 1) return state
    state.copyFormat = normalizeCopyFormat(parsed.copyFormat)
    state.pinned = sanitizeEntries(parsed.pinned, pinnedLimit)
    state.recent = sanitizeEntries(parsed.recent, recentLimit)
    state.valid = true
  } catch (error) {
    return { valid: false, copyFormat: "", pinned: [], recent: [] }
  }
  return state
}

function serializeState(copyFormat, pinned, recent) {
  return JSON.stringify({
    schemaVersion: 1,
    copyFormat: normalizeCopyFormat(copyFormat) || "typst",
    pinned: sanitizeEntries(pinned, pinnedLimit),
    recent: sanitizeEntries(recent, recentLimit)
  }, null, 2) + "\n"
}
