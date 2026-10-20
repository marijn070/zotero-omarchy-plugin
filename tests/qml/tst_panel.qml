import QtQuick
import QtTest
import Quickshell

// Runs the real Panel.qml against test doubles of the Omarchy shell types (see
// ./stubs). Exercises the search panel's behavior: dismissal, pinned and recent
// papers, search transitions, persistence and keyboard handling.
TestCase {
  id: testCase
  name: "ZoteroPanel"
  width: 800
  height: 700
  visible: true
  when: windowShown

  property var current: null

  readonly property var bbtLibrary: [
    paper("Neural Radiance Fields", "mildenhallNeural2020", "AAAA1111", "Mildenhall", 2020),
    paper("Attention Is All You Need", "vaswaniAttention2017", "BBBB2222", "Vaswani", 2017),
    paper("Deep Residual Learning", "heDeep2016", "CCCC3333", "He", 2016),
    paper("Graph Attention Networks", "velickovicGraph2018", "DDDD4444", "Velickovic", 2018),
    paper("<img src=\"https://example.invalid/t.png\"> Markup", "markupMarkup2023", "EEEE5555", "Evil", 2023)
  ]

  function paper(title, citationKey, zoteroKey, family, year) {
    return {
      "id": citationKey,
      "citation-key": citationKey,
      "zotero-key": zoteroKey,
      "title": title,
      "author": [{ "family": family, "given": "A." }],
      "issued": { "date-parts": [[year]] },
      "container-title": "Journal"
    }
  }

  function apiItem(title, key, family) {
    return { "key": key, "data": { "key": key, "title": title, "creators": [{ "lastName": family, "firstName": "A." }],
                                      "date": "2020", "publicationTitle": "Journal" } }
  }

  Component {
    id: barComponent
    // Mirrors the shell's plugin bar API: the suppress flag is read-only and only
    // changed through the setter function.
    QtObject {
      property color foreground: "#dddddd"
      property string fontFamily: "monospace"
      readonly property bool centerHoverRevealSuppressed: false
      property bool failSetter: false
      function setCenterHoverRevealSuppressed(value) {
        if (failSetter) throw new Error("bar API unavailable")
      }
      function switchPanelFrom(owner, direction) { return false }
    }
  }

  Component {
    id: panelComponent
    Loader {
      property alias panel: loader.item
      source: Qt.resolvedUrl("../../Panel.qml")
      id: loader
    }
  }

  function init() {
    Quickshell.reset()
    Quickshell.bbtLibrary = bbtLibrary
    Quickshell.apiItems = [apiItem("Fallback Only Paper", "FFFF6666", "Doe"), apiItem("Another API Paper", "GGGG7777", "Roe")]
  }

  function cleanup() {
    if (current) { current.destroy(); current = null }
  }

  function makePanel(options) {
    var bar = createTemporaryObject(barComponent, testCase)
    if (options && options.failSetter) bar.failSetter = true
    var host = createTemporaryObject(panelComponent, testCase)
    var panel = host.panel
    panel.bar = bar
    current = host
    return panel
  }

  function openPanel(panel) {
    panel.open()
    tryVerify(function() { return panel.stateLoaded })
    tryVerify(function() { return panel.libraryLoaded || panel.fallbackMode || panel.zoteroUnavailable })
    tryVerify(function() { return panel.opened })
  }

  function find(root, name) {
    var queue = [root]
    while (queue.length > 0) {
      var item = queue.shift()
      if (item.objectName === name) return item
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) queue.push(kids[i])
      if (item.contentItem) {
        var inner = item.contentItem.children || []
        for (var j = 0; j < inner.length; j++) queue.push(inner[j])
      }
    }
    return null
  }

  function typeQuery(panel, text) {
    find(panel, "searchField").text = text
    tryCompare(panel, "query", text)
    wait(260)
  }

  function keys(panel) {
    return panel.results.map(function(entry) { return entry.section + ":" + (entry.citationKey || entry.zoteroKey) })
  }

  function savedState() {
    return JSON.parse(Quickshell.disk["/home/test/.config/omarchy/zotero-search.json"])
  }

  function waitSaved() {
    tryVerify(function() { return Quickshell.disk["/home/test/.config/omarchy/zotero-search.json"] !== undefined })
    wait(50)
  }

  function focusSearch(panel) {
    var field = find(panel, "searchField")
    tryVerify(function() { return field.activeFocus }, 2000)
    return field
  }

  // --- dismissal ----------------------------------------------------------

  function test_escapeClosesPanelFromSearchField() {
    var panel = makePanel()
    openPanel(panel)
    focusSearch(panel)
    keyClick(Qt.Key_Escape)
    tryCompare(panel, "opened", false)
  }

  function test_escapeClosesPanelWithTypedQuery() {
    var panel = makePanel()
    openPanel(panel)
    focusSearch(panel)
    keyClick("a")
    keyClick("b")
    keyClick(Qt.Key_Escape)
    tryCompare(panel, "opened", false)
  }

  function test_panelReopensAndClosesAgain() {
    var panel = makePanel()
    for (var round = 0; round < 3; round++) {
      openPanel(panel)
      focusSearch(panel)
      keyClick(Qt.Key_Escape)
      tryCompare(panel, "opened", false)
    }
  }

  function test_closeHidesEvenWhenBarApiFails() {
    var panel = makePanel({ failSetter: true })
    openPanel(panel)
    try { panel.close() } catch (error) { /* a failing optional bar call must not strand the panel */ }
    compare(panel.opened, false)
  }

  function test_closeUsesBarSetterNotReadOnlyProperty() {
    var panel = makePanel()
    openPanel(panel)
    panel.close()
    compare(panel.opened, false)
    compare(panel.bar.centerHoverRevealSuppressed, false)
  }

  // --- empty and no-history states ------------------------------------------

  function test_emptyQueryWithoutHistoryShowsNothingToList() {
    var panel = makePanel()
    openPanel(panel)
    compare(panel.results.length, 0)
    compare(panel.homeView, true)
  }

  // --- pinning ----------------------------------------------------------------

  function test_pinFromSearchResultPersistsAndShowsPinnedFirst() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "attention")
    compare(panel.results.length, 2)
    compare(panel.results[0].pinned, false)
    panel.selectedIndex = 0
    panel.togglePin(panel.results[0])
    compare(panel.results[0].pinned, true)

    waitSaved()
    var state = savedState()
    compare(state.pinned.length, 1)
    compare(state.pinned[0].zoteroKey.length, 8)
    verify(state.pinned[0].citationKey !== "")

    typeQuery(panel, "")
    compare(keys(panel).length, 1)
    compare(panel.results[0].section, "pinned")
  }

  function test_homeViewListsPinnedThenRecentWithoutDuplicates() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "neural")
    panel.copyItem(panel.results[0])
    typeQuery(panel, "attention")
    panel.copyItem(panel.results[0])
    typeQuery(panel, "deep")
    panel.copyItem(panel.results[0])
    typeQuery(panel, "")
    compare(keys(panel).join(), "recent:heDeep2016,recent:vaswaniAttention2017,recent:mildenhallNeural2020")

    // Pin the middle recent: it moves to the pinned section and leaves the recents.
    panel.togglePin(panel.results[1])
    compare(keys(panel).join(), "pinned:vaswaniAttention2017,recent:heDeep2016,recent:mildenhallNeural2020")
    // Pin another: newest pin on top.
    panel.togglePin(panel.results[2])
    compare(keys(panel).join(), "pinned:mildenhallNeural2020,pinned:vaswaniAttention2017,recent:heDeep2016")
    // Unpin restores the paper to the recents.
    panel.togglePin(panel.results[0])
    compare(keys(panel).join(), "pinned:vaswaniAttention2017,recent:heDeep2016,recent:mildenhallNeural2020")
  }

  function test_typingReplacesSectionsAndClearingRestoresThem() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "graph")
    panel.togglePin(panel.results[0])
    typeQuery(panel, "deep")
    panel.copyItem(panel.results[0])
    typeQuery(panel, "")
    compare(keys(panel).join(), "pinned:velickovicGraph2018,recent:heDeep2016")

    typeQuery(panel, "attention")
    verify(panel.results.every(function(entry) { return entry.section === "result" }))
    compare(panel.results.length, 2)

    typeQuery(panel, "")
    compare(keys(panel).join(), "pinned:velickovicGraph2018,recent:heDeep2016")

    typeQuery(panel, "zzzz-no-match")
    compare(panel.results.length, 0)
    typeQuery(panel, "")
    compare(keys(panel).join(), "pinned:velickovicGraph2018,recent:heDeep2016")
  }

  function test_searchResultsShowPinStateOfPinnedPapers() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "graph")
    panel.togglePin(panel.results[0])
    typeQuery(panel, "attention")
    var graph = panel.results.filter(function(entry) { return entry.citationKey === "velickovicGraph2018" })[0]
    compare(graph.pinned, true)
    var attention = panel.results.filter(function(entry) { return entry.citationKey === "vaswaniAttention2017" })[0]
    compare(attention.pinned, false)
  }

  // --- recents ----------------------------------------------------------------

  function test_copyingRecordsRecentAndCopiesCitekey() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "neural")
    panel.copyItem(panel.results[0])
    compare(Quickshell.execs.length, 1)
    compare(Quickshell.execs[0].join(" "), "wl-copy -- @mildenhallNeural2020")
    waitSaved()
    compare(savedState().recent[0].citationKey, "mildenhallNeural2020")
  }

  function test_recentsAreBoundedAndMostRecentFirst() {
    var panel = makePanel()
    var many = []
    for (var i = 0; i < 14; i++) many.push(paper("Bulk paper " + i, "bulk" + i, "BULK" + (1000 + i), "Bulk", 2000 + i))
    Quickshell.bbtLibrary = many
    openPanel(panel)
    for (var j = 0; j < 14; j++) {
      typeQuery(panel, "bulk paper " + j)
      panel.copyItem(panel.results[0])
    }
    typeQuery(panel, "")
    compare(panel.results.length, 10)
    compare(panel.results[0].citationKey, "bulk13")
    compare(panel.results[9].citationKey, "bulk4")
  }

  function test_copyingWithoutCitekeyDoesNotRecordRecent() {
    Quickshell.zoteroMode = "api"
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "fallback")
    compare(panel.results.length, 1)
    panel.copyItem(panel.results[0])
    compare(Quickshell.execs.length, 0)
    compare(panel.recent.length, 0)
  }

  // --- persistence --------------------------------------------------------------

  function test_pinsAndRecentsSurviveRestart() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "graph")
    panel.togglePin(panel.results[0])
    typeQuery(panel, "deep")
    panel.copyItem(panel.results[0])
    waitSaved()
    wait(300)
    var disk = Quickshell.disk
    cleanup()

    Quickshell.disk = disk
    var restarted = makePanel()
    openPanel(restarted)
    compare(keys(restarted).join(), "pinned:velickovicGraph2018,recent:heDeep2016")
  }

  function test_copyFormatIsKeptAlongsidePinsAndRecents() {
    var panel = makePanel()
    openPanel(panel)
    panel.setCopyFormat("latex")
    typeQuery(panel, "graph")
    panel.togglePin(panel.results[0])
    waitSaved()
    wait(300)
    var state = savedState()
    compare(state.copyFormat, "latex")
    compare(state.pinned.length, 1)
    compare(state.schemaVersion, 1)
  }

  function test_legacyConfigFileWithLiteralBackslashNStillLoads() {
    var path = "/home/test/.config/omarchy/zotero-search.json"
    var disk = {}
    disk[path] = "{\n  \"schemaVersion\": 1,\n  \"copyFormat\": \"latex\"\n}\\n"
    Quickshell.disk = disk
    var panel = makePanel()
    openPanel(panel)
    compare(panel.copyFormat, "latex")
  }

  function test_malformedStateFileFallsBackToDefaults() {
    var path = "/home/test/.config/omarchy/zotero-search.json"
    var disk = {}
    disk[path] = "{ not json"
    Quickshell.disk = disk
    var panel = makePanel()
    openPanel(panel)
    compare(panel.copyFormat, "typst")
    compare(panel.pinned.length, 0)
    compare(panel.recent.length, 0)
  }

  // --- missing items and offline -------------------------------------------------

  function test_pinnedPaperMissingFromLibraryStaysVisibleButCannotBeCopied() {
    var path = "/home/test/.config/omarchy/zotero-search.json"
    var disk = {}
    disk[path] = JSON.stringify({
      schemaVersion: 1, copyFormat: "typst",
      pinned: [{ zoteroKey: "ZZZZ9999", citationKey: "deletedPaper2001", title: "Deleted paper" }],
      recent: [{ zoteroKey: "YYYY8888", citationKey: "alsoDeleted2002", title: "Also deleted" },
               { zoteroKey: "AAAA1111", citationKey: "mildenhallNeural2020", title: "Old title" }]
    })
    Quickshell.disk = disk
    var panel = makePanel()
    openPanel(panel)
    compare(keys(panel).join(), "pinned:deletedPaper2001,recent:mildenhallNeural2020")
    compare(panel.results[0].missing, true)
    compare(panel.results[1].title, "Neural Radiance Fields")
    panel.copyItem(panel.results[0])
    compare(Quickshell.execs.length, 0)
    panel.togglePin(panel.results[0])
    compare(keys(panel).join(), "recent:mildenhallNeural2020")
  }

  function test_pinnedPapersShowFromSnapshotWhileZoteroIsDown() {
    var path = "/home/test/.config/omarchy/zotero-search.json"
    var disk = {}
    disk[path] = JSON.stringify({
      schemaVersion: 1, copyFormat: "typst",
      pinned: [{ zoteroKey: "AAAA1111", citationKey: "mildenhallNeural2020", title: "Neural Radiance Fields" }],
      recent: []
    })
    Quickshell.disk = disk
    Quickshell.zoteroMode = "down"
    var panel = makePanel()
    openPanel(panel)
    compare(panel.zoteroUnavailable, true)
    compare(keys(panel).join(), "pinned:mildenhallNeural2020")
    compare(panel.results[0].missing, false)
    panel.copyItem(panel.results[0])
    compare(Quickshell.execs[0].join(" "), "wl-copy -- @mildenhallNeural2020")
  }

  function test_pinningWorksInZoteroApiFallbackMode() {
    Quickshell.zoteroMode = "api"
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "another")
    compare(panel.results.length, 1)
    panel.togglePin(panel.results[0])
    waitSaved()
    compare(savedState().pinned[0].zoteroKey, "GGGG7777")
    typeQuery(panel, "")
    compare(panel.results.length, 1)
    compare(panel.results[0].section, "pinned")
    typeQuery(panel, "fallback")
    compare(panel.results.length, 1)
    compare(panel.results[0].section, "result")
  }

  // --- keyboard ------------------------------------------------------------------

  function test_keyboardNavigationSkipsSectionHeadersAndWraps() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "graph")
    panel.togglePin(panel.results[0])
    typeQuery(panel, "deep")
    panel.copyItem(panel.results[0])
    typeQuery(panel, "neural")
    panel.copyItem(panel.results[0])
    typeQuery(panel, "")
    compare(keys(panel).length, 3)
    focusSearch(panel)
    compare(panel.selectedIndex, 0)
    keyClick(Qt.Key_Down)
    compare(panel.selectedIndex, 1)
    keyClick(Qt.Key_Down)
    compare(panel.selectedIndex, 2)
    keyClick(Qt.Key_Down)
    compare(panel.selectedIndex, 2)
    keyClick(Qt.Key_N, Qt.ControlModifier)
    compare(panel.selectedIndex, 0)
    keyClick(Qt.Key_P, Qt.ControlModifier)
    compare(panel.selectedIndex, 2)
    keyClick(Qt.Key_Up)
    compare(panel.selectedIndex, 1)
  }

  function test_enterCopiesSelectedHomeEntry() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "graph")
    panel.togglePin(panel.results[0])
    typeQuery(panel, "")
    focusSearch(panel)
    keyClick(Qt.Key_Return)
    compare(Quickshell.execs[0].join(" "), "wl-copy -- @velickovicGraph2018")
  }

  function test_ctrlBPinsAndUnpinsTheSelectedEntryAndKeepsSelection() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "attention")
    focusSearch(panel)
    compare(panel.results.length, 2)
    keyClick(Qt.Key_Down)
    var target = panel.results[1].citationKey
    keyClick(Qt.Key_B, Qt.ControlModifier)
    compare(panel.pinned.length, 1)
    compare(panel.pinned[0].citationKey, target)
    compare(panel.results[panel.selectedIndex].citationKey, target)
    keyClick(Qt.Key_B, Qt.ControlModifier)
    compare(panel.pinned.length, 0)
  }

  function test_escapeStillClosesWithPinnedEntriesSelected() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "graph")
    panel.togglePin(panel.results[0])
    typeQuery(panel, "")
    focusSearch(panel)
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Escape)
    tryCompare(panel, "opened", false)
  }

  // --- untrusted text ------------------------------------------------------------

  function test_markupShapedTitlesStayPlainData() {
    var panel = makePanel()
    openPanel(panel)
    typeQuery(panel, "markup")
    compare(panel.results.length, 1)
    verify(panel.results[0].title.indexOf("<img") === 0)
  }
}
