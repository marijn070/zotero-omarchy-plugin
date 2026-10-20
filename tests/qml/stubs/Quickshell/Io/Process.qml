import QtQuick
import Quickshell

// Answers the plugin's curl commands from the Quickshell test double's fake Zotero.
Item {
  id: root
  property var command: []
  property bool running: false
  property var stdout: null
  signal exited(int exitCode, int exitStatus)

  function respond() {
    var url = String(command[command.length - 1])
    var mode = Quickshell.zoteroMode
    Quickshell.requests = Quickshell.requests.concat([url])
    var body = null
    if (mode !== "down") {
      if (url.indexOf("/better-bibtex/export") !== -1) {
        if (mode === "bbt") body = JSON.stringify(Quickshell.bbtLibrary)
      } else if (url.indexOf("/api/users/0/items") !== -1) {
        var match = url.match(/[?&]q=([^&]*)/)
        var query = match ? decodeURIComponent(match[1]).toLowerCase() : ""
        body = JSON.stringify(Quickshell.apiItems.filter(function(item) {
          return query === "" || String(item.data.title).toLowerCase().indexOf(query) !== -1
        }))
      }
    }
    root.running = false
    if (body === null) {
      root.exited(22, 0)
      return
    }
    if (stdout) {
      stdout.text = body
      stdout.streamFinished()
    }
    root.exited(0, 0)
  }

  onRunningChanged: if (running) Qt.callLater(root.respond)
}
