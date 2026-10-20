pragma Singleton
import QtQuick

// Test double for the Quickshell singleton. It records detached commands and
// holds the fake disk and fake Zotero server shared by the Io stubs.
QtObject {
  property var execs: []
  property var disk: ({})
  // "bbt": Better BibTeX export works. "api": only Zotero's own API. "down": nothing answers.
  property string zoteroMode: "bbt"
  property var bbtLibrary: []
  property var apiItems: []
  property var requests: []

  function env(name) { return name === "HOME" ? "/home/test" : "" }
  function execDetached(command) {
    var next = execs.slice()
    next.push(command)
    execs = next
  }
  function reset() {
    execs = []
    disk = ({})
    zoteroMode = "bbt"
    bbtLibrary = []
    apiItems = []
    requests = []
  }
}
