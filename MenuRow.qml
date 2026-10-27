import QtQuick
import qs.Commons
import qs.Commons as Commons

Rectangle {
  id: row
  property string label: ""
  property string icon: ""
  property bool danger: false
  property bool highlighted: false
  signal triggered()
  // Emit the signal so keyboard navigation can activate the row the same
  // way a mouse click does.
  function trigger() { row.triggered() }

  width: parent ? parent.width : 200
  height: 34
  radius: 8
  color: row.highlighted ? Qt.rgba(1, 1, 1, 0.14) : (hover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

  Text {
    visible: row.icon !== ""
    anchors.left: parent.left
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    width: 18
    text: row.icon
    color: row.danger ? Commons.Color.urgent : Commons.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    horizontalAlignment: Text.AlignHCenter
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: row.icon !== "" ? 32 : 10
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    text: row.label
    color: row.danger ? Commons.Color.urgent : Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  HoverHandler { id: hover }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: row.triggered()
  }
}
