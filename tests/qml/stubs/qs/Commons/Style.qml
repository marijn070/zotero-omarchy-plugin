pragma Singleton
import QtQuick

QtObject {
  readonly property int cornerRadius: 4
  readonly property var font: ({ family: "monospace", title: 16, body: 14, bodySmall: 12 })
  function space(value) { return value }
  function hoverFillFor(foreground, accent) { return Qt.rgba(1, 1, 1, 0.1) }
}
