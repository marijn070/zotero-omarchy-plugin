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
  property var results: []
  property bool libraryLoaded: false
  property bool fallbackMode: false
  property bool loading: false
  property int selectedIndex: 0
  property string errorMessage: ""
  property string statusMessage: ""
  property bool zoteroUnavailable: false
  property bool zoteroStarting: false
  property int startupAttempts: 0

  readonly property string endpoint: "http://127.0.0.1:23119/better-bibtex/export?library.json"
  readonly property string zoteroProbeEndpoint: "http://127.0.0.1:23119/api/users/0/items?limit=1&format=json"
  readonly property int resultLimit: 50
  readonly property int startupRetryLimit: 20
  readonly property string copyFormat: {
    var configured = String(root.setting("copyFormat", "citekey")).toLowerCase()
    return configured === "citation" ? "citation" : "citekey"
  }

  onOpenedChanged: if (opened) focusTimer.restart()
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
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function closeForPopoutSwitch() {
    root.close()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    if (libraryProcess.running || root.zoteroStarting) return
    fallbackMode = false
    libraryLoaded = false
    library = []
    results = []
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
    root.results = []
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
      if (root.query.trim() === "") {
        root.results = []
        return
      }
      root.requestFallback()
      return
    }
    root.results = Model.searchItems(root.library, root.query, root.resultLimit)
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
      root.results = Model.normalizeZotero(JSON.parse(String(raw || "")))
      root.loading = false
    } catch (error) {
      root.results = []
      root.loading = false
      root.errorMessage = "Zotero did not return readable search results"
    }
  }

  function copyItem(item) {
    if (!item) return

    var output = root.copyFormat === "citation"
      ? Model.formatCitation(item)
      : (item.citationKey ? "@" + item.citationKey : "")
    if (!output) {
      root.statusMessage = root.copyFormat === "citation"
        ? "No citation data available"
        : "Better BibTeX required for citekeys"
      statusTimer.restart()
      return
    }

    Quickshell.execDetached(["wl-copy", "--", output])
    root.statusMessage = root.copyFormat === "citation" ? "Copied citation" : "Copied " + output
    statusTimer.restart()
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
  }

  Timer {
    id: searchDebounce
    interval: 180
    onTriggered: root.applySearch()
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
      blocked: searchField.activeFocus
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

          Text {
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
            width: parent.width
            height: root.results.length === 0
              ? Style.space(44)
              : Math.min(Style.space(420), root.results.length * Style.space(68))
            model: root.results
            clip: true
            interactive: false
            spacing: Style.space(4)

            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool canCopy: root.copyFormat === "citation"
                ? Model.formatCitation(modelData) !== ""
                : modelData.citationKey !== ""
              width: resultList.width
              height: Style.space(64)
              radius: Style.cornerRadius
              color: rowMouse.containsMouse || root.selectedIndex === index
                ? Style.hoverFillFor(root.foreground, Color.accent)
                : "transparent"

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyItem(modelData)
              }

              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.right: copyButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Text {
                  width: parent.width
                  text: modelData.title
                  color: root.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: modelData.citationKey !== ""
                    ? modelData.citationKey + (modelData.details !== "" ? "  ·  " + modelData.details : "")
                    : (modelData.details || "No citation key available")
                  color: root.dimForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
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
                opacity: canCopy ? 1 : 0.35

                Text {
                  anchors.centerIn: parent
                  text: "󰆏"
                  color: root.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.title
                }

                MouseArea {
                  id: copyMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: canCopy
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.copyItem(modelData)

                  PanelToolTip {
                    visible: copyMouse.containsMouse
                    text: canCopy
                      ? (root.copyFormat === "citation" ? "Copy citation" : "Copy citekey")
                      : (root.copyFormat === "citation" ? "No citation data" : "Better BibTeX required")
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                  }
                }
              }
            }
          }

          Text {
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
