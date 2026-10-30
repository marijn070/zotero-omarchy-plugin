import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "marijn.zotero"
  ipcTarget: "marijn.zotero"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dimForeground: Qt.darker(foreground, 1.6)

  property string query: ""
  property var library: []
  property var rawResults: []
  property var results: []
  property var pinned: []
  property var recent: []
  property bool libraryLoaded: false
  property bool fallbackMode: false
  property bool loading: false
  property int selectedIndex: 0
  property string errorMessage: ""
  property string statusMessage: ""
  property bool zoteroUnavailable: false
  property bool zoteroStarting: false
  property int startupAttempts: 0
  property string copyFormat: "typst"
  property bool stateLoaded: false
  property bool stateFileValid: false
  property bool stateDirty: false

  readonly property string endpoint: "http://127.0.0.1:23119/better-bibtex/export?library.json"
  readonly property string zoteroProbeEndpoint: "http://127.0.0.1:23119/api/users/0/items?limit=1&format=json"
  readonly property string statePath: Quickshell.env("HOME") + "/.config/omarchy/zotero-search.json"
  readonly property bool homeView: root.query.trim() === ""
  readonly property int resultLimit: 50
  readonly property int startupRetryLimit: 20

  onOpenedChanged: if (opened) focusTimer.restart()
  onSettingsChanged: if (root.stateLoaded && !root.stateFileValid && !root.stateDirty)
    root.applyLegacyCopyFormat()
  onPinnedChanged: root.updateView(true)
  onRecentChanged: if (root.homeView) root.updateView(true)
  onSelectedIndexChanged: scrollToSelection()
  onResultsChanged: scrollToSelection()

  Timer {
    id: focusTimer
    interval: 100
    onTriggered: {
      if (!root.opened) return
      searchField.forceActiveFocus()
      searchField.selectAll()
    }
  }

  function open() {
    root.controller.show()
    if (!root.libraryLoaded && !libraryProcess.running && !fallbackMode && !root.zoteroStarting) root.refresh()
    focusTimer.restart()
  }

  function close() {
    root.controller.hide()
    setCenterHoverRevealSuppressed(false)
  }

  function closeForPopoutSwitch() {
    root.close()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  function applyLegacyCopyFormat() {
    var configured = Model.normalizeCopyFormat(root.setting("copyFormat", "typst"))
    root.copyFormat = configured || "typst"
  }

  function loadState(raw) {
    var state = Model.parseState(raw)

    if (!root.stateDirty) {
      root.copyFormat = state.copyFormat || "typst"
      root.stateFileValid = state.copyFormat !== ""
      if (!root.stateFileValid) root.applyLegacyCopyFormat()
      root.pinned = state.pinned
      root.recent = state.recent
    }
    root.stateLoaded = true
    if (root.stateDirty) stateSaveTimer.restart()
  }

  function markStateDirty() {
    root.stateDirty = true
    stateSaveTimer.restart()
  }

  function setCopyFormat(value) {
    var configured = Model.normalizeCopyFormat(value)
    if (!configured) return
    if (root.copyFormat === configured && root.stateLoaded && root.stateFileValid) return
    root.copyFormat = configured
    root.stateFileValid = false
    root.markStateDirty()
  }

  function saveState() {
    if (!root.stateLoaded || !root.stateDirty) return
    stateFile.setText(Model.serializeState(root.copyFormat, root.pinned, root.recent))
    root.stateDirty = false
  }

  function togglePin(item) {
    if (!item || !Model.hasIdentity(item)) return
    root.pinned = Model.togglePin(root.pinned, item)
    root.markStateDirty()
  }

  function togglePinSelected() {
    root.togglePin(root.results[root.selectedIndex])
  }

  function recordRecent(item) {
    root.recent = Model.recordRecent(root.recent, item)
    root.markStateDirty()
  }

  function indexOfEntry(item) {
    for (var i = 0; i < root.results.length; i++)
      if (Model.sameItem(root.results[i], item)) return i
    return -1
  }

  // The list shows pinned then recent papers for an empty query, and the search
  // results (flagged with their pin state) as soon as the user types.
  function updateView(keepSelection) {
    var selected = keepSelection ? root.results[root.selectedIndex] : null
    root.results = root.homeView
      ? Model.homeEntries(root.pinned, root.recent, root.library, root.libraryLoaded)
      : Model.decorateResults(root.rawResults, root.pinned)
    var index = selected ? root.indexOfEntry(selected) : -1
    if (index !== -1) root.selectedIndex = index
    else if (root.selectedIndex >= root.results.length)
      root.selectedIndex = Math.max(0, root.results.length - 1)
  }

  function refresh() {
    if (libraryProcess.running || root.zoteroStarting) return
    fallbackMode = false
    libraryLoaded = false
    library = []
    rawResults = []
    updateView(false)
    loading = true
    zoteroUnavailable = false
    errorMessage = ""
    statusMessage = "Connecting to Zotero..."
    libraryProcess.running = true
  }

  function applyBibliography(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      var normalized = Model.normalizeBibliography(parsed)
      if (normalized.length === 0) throw new Error("No items returned")
      root.library = normalized
      root.libraryLoaded = true
      root.fallbackMode = false
      root.loading = false
      root.errorMessage = ""
      root.statusMessage = normalized.length + " items loaded"
      root.applySearch()
    } catch (error) {
      root.probeZotero()
    }
  }

  function probeZotero() {
    if (zoteroProbeProcess.running) return
    root.loading = true
    root.statusMessage = root.zoteroStarting ? "Waiting for Zotero to start..." : "Checking Zotero..."
    zoteroProbeProcess.running = true
  }

  function applyZoteroProbe(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (!Array.isArray(parsed)) throw new Error("Unexpected Zotero response")
      root.zoteroUnavailable = false
      if (root.zoteroStarting) {
        root.zoteroStarting = false
        startupRetry.stop()
        root.statusMessage = "Connecting to Zotero..."
        root.refresh()
        return
      }
      root.startFallback()
    } catch (error) {
      root.showZoteroUnavailable()
    }
  }

  function showZoteroUnavailable() {
    root.loading = false
    root.fallbackMode = false
    root.libraryLoaded = false
    root.rawResults = []
    root.updateView(false)
    root.zoteroUnavailable = true
    root.statusMessage = root.zoteroStarting
      ? "Waiting for Zotero to start..."
      : "Zotero local API is unavailable"
  }

  function startZotero() {
    if (root.zoteroStarting) return
    root.zoteroStarting = true
    root.zoteroUnavailable = true
    root.startupAttempts = 0
    root.loading = true
    root.errorMessage = ""
    root.statusMessage = "Starting Zotero..."
    Quickshell.execDetached(["/usr/bin/zotero"])
    startupRetry.restart()
    root.probeZotero()
  }

  function startFallback() {
    root.fallbackMode = true
    root.libraryLoaded = false
    root.loading = false
    root.zoteroUnavailable = false
    root.errorMessage = ""
    root.statusMessage = "Searching Zotero library"
    root.applySearch()
  }

  function applySearch() {
    root.selectedIndex = 0
    if (!root.libraryLoaded && !root.fallbackMode && !root.zoteroUnavailable
        && !root.zoteroStarting && !libraryProcess.running && !zoteroProbeProcess.running)
      root.refresh()
    if (root.fallbackMode) {
      if (root.homeView) {
        root.rawResults = []
        root.loading = false
        root.updateView(false)
        return
      }
      root.requestFallback()
      return
    }
    root.rawResults = root.homeView ? [] : Model.searchItems(root.library, root.query, root.resultLimit)
    root.updateView(false)
  }

  function requestFallback() {
    if (fallbackProcess.running) fallbackProcess.running = false
    var encoded = encodeURIComponent(root.query.trim())
    fallbackProcess.command = [
      "curl", "-fsS", "--max-time", "5",
      "http://127.0.0.1:23119/api/users/0/items?limit=50&format=json&q=" + encoded
    ]
    root.loading = true
    fallbackProcess.running = true
  }

  function applyFallback(raw) {
    try {
      var items = Model.normalizeZotero(JSON.parse(String(raw || "")))
      root.loading = false
      if (root.homeView) return
      root.rawResults = items
    } catch (error) {
      root.rawResults = []
      root.loading = false
      root.errorMessage = "Zotero did not return readable search results"
    }
    root.updateView(false)
  }

  function copyItem(item) {
    if (!item) return

    if (item.missing) {
      root.statusMessage = "This paper is no longer in your Zotero library"
      statusTimer.restart()
      return
    }

    var output = Model.copyOutput(item, root.copyFormat)
    if (!output) {
      root.statusMessage = (root.copyFormat === "latex" ? "LaTeX" : "Typst")
        + " citekeys require Better BibTeX"
      statusTimer.restart()
      return
    }

    Quickshell.execDetached(["wl-copy", "--", output])
    root.statusMessage = "Copied " + output
    statusTimer.restart()
    root.recordRecent(item)
  }

  function moveSelection(delta) {
    if (root.results.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.results.length - 1, root.selectedIndex + delta))
  }

  function cycleSelection(delta) {
    if (root.results.length === 0) return
    root.selectedIndex = (root.selectedIndex + delta + root.results.length) % root.results.length
  }

  function scrollToSelection() {
    if (root.results.length === 0) return
    Qt.callLater(function() {
      if (root.selectedIndex >= 0 && root.selectedIndex < resultList.count)
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  QtObject {
    id: keyboardShortcuts
    property var next: Shortcut {
      sequence: "Ctrl+N"
      context: Qt.ApplicationShortcut
      enabled: root.opened
      onActivated: root.cycleSelection(1)
    }
    property var previous: Shortcut {
      sequence: "Ctrl+P"
      context: Qt.ApplicationShortcut
      enabled: root.opened
      onActivated: root.cycleSelection(-1)
    }
    property var pin: Shortcut {
      sequence: "Ctrl+B"
      context: Qt.ApplicationShortcut
      enabled: root.opened
      onActivated: root.togglePinSelected()
    }
  }

  Timer {
    id: searchDebounce
    interval: 180
    onTriggered: root.applySearch()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
    onFileChanged: reload()
    onSaved: root.stateFileValid = true
    onSaveFailed: {
      root.stateDirty = true
      root.stateFileValid = false
    }
  }

  Timer {
    id: stateSaveTimer
    interval: 150
    onTriggered: root.saveState()
  }

  Timer {
    id: statusTimer
    interval: 2200
    onTriggered: root.statusMessage = ""
  }

  Timer {
    id: startupRetry
    interval: 1200
    repeat: true
    onTriggered: {
      if (!root.zoteroStarting) {
        stop()
        return
      }
      if (root.startupAttempts >= root.startupRetryLimit) {
        root.zoteroStarting = false
        root.showZoteroUnavailable()
        root.statusMessage = "Zotero did not become ready"
        stop()
        return
      }
      root.startupAttempts++
      root.probeZotero()
    }
  }

  Process {
    id: libraryProcess
    command: ["curl", "-fsS", "--max-time", "10", root.endpoint]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyBibliography(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.libraryLoaded) root.probeZotero()
    }
  }

  Process {
    id: zoteroProbeProcess
    command: ["curl", "-fsS", "--max-time", "3", root.zoteroProbeEndpoint]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyZoteroProbe(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.showZoteroUnavailable()
    }
  }

  Process {
    id: fallbackProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyFallback(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.probeZotero()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(620))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || copyFormatDropdown.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.bar.switchPanelFrom(root.barIdentity, direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: contentColumn.width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scroll.width
          spacing: Style.space(12)

          Item {
            width: parent.width
            height: headerLabel.implicitHeight

            Text {
              textFormat: Text.PlainText
              id: headerLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "ZOTERO SEARCH"
              color: root.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              id: refreshLabel
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.loading ? "󰦖" : "󰑐"
              color: refreshMouse.containsMouse ? Color.accent : root.dimForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title

              RotationAnimator on rotation {
                running: root.loading
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
              }

              MouseArea {
                id: refreshMouse
                anchors.fill: parent
                anchors.margins: -Style.space(8)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
              }
            }
          }

          TextField {
            id: searchField
            objectName: "searchField"
            width: parent.width
            placeholderText: "Search title, author, or citekey"
            foreground: root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            onTextChanged: {
              root.query = text
              searchDebounce.restart()
            }
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.results.length > 0) root.copyItem(root.results[root.selectedIndex])
                event.accepted = true
              }
            }
          }

          Dropdown {
            id: copyFormatDropdown
            width: parent.width
            label: "Copy format"
            value: root.copyFormat
            options: [
              { value: "typst", label: "Typst - @citekey" },
              { value: "latex", label: "LaTeX - \\cite{citekey}" }
            ]
            foreground: root.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onChanged: root.setCopyFormat(value)
          }

          Text {
            textFormat: Text.PlainText
            visible: root.libraryLoaded || root.fallbackMode || root.errorMessage !== ""
              || root.zoteroUnavailable || root.zoteroStarting
            width: parent.width
            text: root.errorMessage !== ""
              ? root.errorMessage
              : (root.zoteroStarting || root.zoteroUnavailable
                ? root.statusMessage
                : (root.query.trim() === ""
                  ? (root.fallbackMode ? "Type a query to search Zotero" : root.statusMessage)
                  : (root.results.length === 0 && !root.loading ? "No matching items" : root.statusMessage)))
            color: root.errorMessage !== "" ? Color.urgent : root.dimForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Button {
            visible: root.zoteroUnavailable || root.zoteroStarting
            enabled: root.zoteroUnavailable && !root.zoteroStarting
            width: parent.width
            text: root.zoteroStarting ? "Starting Zotero..." : "Start Zotero"
            iconText: root.zoteroStarting ? "󰦖" : "󰐊"
            iconSpinning: root.zoteroStarting
            foreground: root.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.startZotero()
          }

          ListView {
            id: resultList
            objectName: "resultList"
            width: parent.width
            height: root.results.length === 0
              ? 0
              : Math.min(Style.space(420), resultList.contentHeight)
            model: root.results
            clip: true
            interactive: false
            spacing: Style.space(4)

            delegate: Item {
              id: entry
              required property var modelData
              required property int index
              readonly property bool canCopy: modelData.citationKey !== "" && !modelData.missing
              readonly property bool showSection: modelData.section !== "result"
                && (index === 0 || root.results[index - 1].section !== modelData.section)
              readonly property string pinLabel: modelData.pinned ? "Unpin paper" : "Pin paper"
              width: resultList.width
              height: row.height + (showSection ? sectionLabel.height + Style.space(4) : 0)

              Text {
                id: sectionLabel
                visible: entry.showSection
                height: visible ? implicitHeight : 0
                textFormat: Text.PlainText
                text: entry.modelData.section === "pinned" ? "PINNED" : "RECENT"
                color: root.dimForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Rectangle {
                id: row
                y: entry.showSection ? sectionLabel.height + Style.space(4) : 0
                width: parent.width
                height: Style.space(64)
                radius: Style.cornerRadius
                opacity: entry.modelData.missing ? 0.6 : 1
                color: rowMouse.containsMouse || root.selectedIndex === entry.index
                  ? Style.hoverFillFor(root.foreground, Color.accent)
                  : "transparent"

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.copyItem(entry.modelData)
                }

                Column {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.right: pinButton.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: entry.modelData.title
                    color: root.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: entry.modelData.missing
                      ? "No longer in your Zotero library"
                      : (entry.modelData.citationKey !== ""
                        ? entry.modelData.citationKey
                          + (entry.modelData.details !== "" ? "  \u00b7  " + entry.modelData.details : "")
                        : (entry.modelData.details || "No citekey available"))
                    color: root.dimForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                }

                Rectangle {
                  id: pinButton
                  width: Style.space(34)
                  height: Style.space(34)
                  anchors.right: copyButton.left
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  radius: Style.cornerRadius
                  color: pinMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                  opacity: entry.modelData.pinned || pinMouse.containsMouse || root.selectedIndex === entry.index ? 1 : 0.55

                  Accessible.role: Accessible.Button
                  Accessible.name: entry.pinLabel

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: entry.modelData.pinned ? "󰐃" : "󰤱"
                    color: entry.modelData.pinned ? Color.accent : root.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.title
                  }

                  MouseArea {
                    id: pinMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePin(entry.modelData)

                    PanelToolTip {
                      visible: pinMouse.containsMouse
                      text: entry.pinLabel + " (Ctrl+B)"
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    }
                  }
                }

                Rectangle {
                  id: copyButton
                  width: Style.space(34)
                  height: Style.space(34)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  radius: Style.cornerRadius
                  color: copyMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                  opacity: entry.canCopy ? 1 : 0.35

                  Accessible.role: Accessible.Button
                  Accessible.name: root.copyFormat === "latex" ? "Copy LaTeX citekey" : "Copy Typst citekey"

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "󰆏"
                    color: root.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.title
                  }

                  MouseArea {
                    id: copyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: entry.canCopy
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.copyItem(entry.modelData)

                    PanelToolTip {
                      visible: copyMouse.containsMouse
                      text: entry.canCopy
                        ? (root.copyFormat === "latex" ? "Copy LaTeX citekey" : "Copy Typst citekey")
                        : (entry.modelData.missing
                          ? "No longer in your Zotero library"
                          : "Better BibTeX required for citekeys")
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    }
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.homeView && root.results.length === 0 && root.errorMessage === ""
            width: parent.width
            text: "No pinned or recent papers yet. Type to search, then pin a paper with Ctrl+B."
            color: root.dimForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: root.results.length === 0 && root.query.trim() !== "" && !root.loading && root.errorMessage === ""
            width: parent.width
            text: "No items found"
            color: root.dimForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
