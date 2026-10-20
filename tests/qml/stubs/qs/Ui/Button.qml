import QtQuick

Item {
  property string text: ""
  property string iconText: ""
  property bool iconSpinning: false
  property color foreground: "#ffffff"
  property string fontFamily: ""
  signal clicked()
  implicitHeight: 30
}
