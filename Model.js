function clean(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

function lower(value) {
  return clean(value).toLowerCase()
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
