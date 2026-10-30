import QtQuick
import Quickshell

// In-memory file backed by the Quickshell test double's fake disk.
Item {
  id: root
  property string path: ""
  property bool watchChanges: false
  property bool atomicWrites: false
  property bool printErrors: true
  signal loaded()
  signal loadFailed(var error)
  signal fileChanged()
  signal saved()
  signal saveFailed(var error)

  function text() { return Quickshell.disk[path] === undefined ? "" : Quickshell.disk[path] }
  function setText(value) {
    var next = Object.assign({}, Quickshell.disk)
    next[path] = String(value)
    Quickshell.disk = next
    saved()
  }
  function reload() { Qt.callLater(root.load) }
  function load() {
    if (Quickshell.disk[path] === undefined) loadFailed("missing")
    else loaded()
  }
  Component.onCompleted: Qt.callLater(root.load)
}
