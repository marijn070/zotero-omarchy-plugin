import QtQuick

// Same Escape and blocked handling as the shell's Ui/PanelKeyCatcher.qml.
Item {
  id: root
  property bool blocked: false
  signal closeRequested()
  signal tabRequested(int direction)
  signal textKey(string text, int modifiers)

  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (blocked) return
    if (event.key === Qt.Key_Escape) { closeRequested(); event.accepted = true; return }
    if (event.text && event.text.length === 1) textKey(event.text, event.modifiers)
  }
}
