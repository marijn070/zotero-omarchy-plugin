import QtQuick

Item {
  id: root
  property Item anchorItem: null
  property var owner: null
  property QtObject bar: null
  property bool open: false
  property bool centerOnBar: false
  property Item focusTarget: null
  property int contentWidth: 0
  property int contentHeight: 0
  default property alias contentItem: holder.children
  function fittedContentWidth(width) { return width }
  function fittedContentHeight(height) { return height }

  visible: open
  width: 700
  height: 600
  Item { id: holder; anchors.fill: parent }
  onOpenChanged: if (open && focusTarget) Qt.callLater(function() { focusTarget.forceActiveFocus() })
}
