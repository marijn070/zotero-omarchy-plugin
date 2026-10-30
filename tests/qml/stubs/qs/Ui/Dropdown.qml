import QtQuick

Item {
  id: root
  property string label: ""
  property string value: ""
  property var options: []
  property color foreground: "#ffffff"
  property string fontFamily: ""
  property bool popupOpen: false
  signal changed(string value)
  implicitHeight: 30
}
