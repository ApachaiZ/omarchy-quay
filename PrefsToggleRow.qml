import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// Labeled on/off row for the preferences panel. The whole row is the click
// target (matching the shell's Toggle), with an optional description line
// for settings that need a sentence of context.
Rectangle {
  id: row

  property string label: ""
  property string description: ""
  property bool checked: false
  property bool highlighted: false

  signal picked(bool value)

  readonly property int rowHeight: Math.max(Style.space(34),
    Math.ceil(Style.font.body + Style.space(16)))
  readonly property bool active: row.highlighted || rowHover.hovered
  readonly property int extraHeight: row.description !== "" ? Style.space(14) : 0

  function trigger() { row.picked(!row.checked) }
  function adjust(delta) { if (delta !== 0) row.picked(!row.checked) }

  width: parent ? parent.width : Style.space(280)
  height: row.rowHeight + row.extraHeight
  radius: Math.max(0, Math.min(Style.cornerRadius, Style.space(8)))
  color: row.highlighted
    ? Style.selectedFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)
    : rowHover.hovered
      ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)
      : "transparent"

  Behavior on color { ColorAnimation { duration: 90 } }

  Accessible.role: Accessible.CheckBox
  Accessible.name: row.label
  Accessible.checked: row.checked
  Accessible.onPressAction: row.trigger()

  Column {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.right: toggle.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: row.label
      color: row.active ? Commons.Color.accent : Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      visible: row.description !== ""
      width: parent.width
      text: row.description
      color: Commons.Color.popups.text
      opacity: 0.52
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Ui.ToggleSwitch {
    id: toggle
    checked: row.checked
    interactive: false
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    foreground: Commons.Color.popups.text
    accent: Commons.Color.accent
  }

  HoverHandler { id: rowHover }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: row.trigger()
  }
}
