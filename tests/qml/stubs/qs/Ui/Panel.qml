import QtQuick

// Mirrors the lifecycle of the Omarchy shell's Ui/Panel.qml.
Item {
  id: root
  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})
  property string ipcTarget: ""
  property bool manageIpc: true
  property alias controller: panelController
  readonly property bool opened: panelController.open

  function open() { panelController.show() }
  function close() { panelController.hide() }
  function toggle() { opened ? close() : open() }
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  QtObject {
    id: panelController
    property bool open: false
    function show() { if (!open) open = true }
    function hide() { open = false }
  }
}
