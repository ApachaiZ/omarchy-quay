import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// A single actionable row shared by the Quay context menu and the
// preferences panel. It uses the shell's state tokens instead of hard-coded
// whites so every theme gets a consistent hover/keyboard highlight.
//
// `detail` adds a quiet second line (window workspace, for example).
// `checked` draws a trailing check (screen selection). `trailingIcon` adds a
// small row action (close a window) without changing the row's main action.
Rectangle {
  id: row

  property string label: ""
  property string icon: ""
  property string detail: ""
  property bool danger: false
  property bool highlighted: false
  property bool checked: false
  property string trailingIcon: ""
  property string trailingTooltip: ""

  signal triggered()
  signal trailingTriggered()

  function trigger() {
    if (row.enabled) row.triggered()
  }

  readonly property int rowHeight: Math.max(Style.space(32),
    Math.ceil(Style.font.body + Style.space(13)))
  readonly property bool active: row.enabled && (row.highlighted || rowHover.hovered)
  readonly property color foreground: Commons.Color.popups.text
  readonly property var fillAccent: Commons.Color.accent
  readonly property var fillUrgent: Commons.Color.urgent

  width: parent ? parent.width : Style.space(220)
  height: row.rowHeight + (row.detail !== "" ? Style.space(12) : 0)
  radius: Math.max(0, Math.min(Style.cornerRadius, Style.space(8)))
  color: !row.enabled
    ? "transparent"
    : row.highlighted
      ? Style.selectedFillFor(row.foreground, row.fillAccent, row.fillUrgent)
      : rowHover.hovered
        ? Style.hoverFillFor(row.foreground, row.fillAccent, row.fillUrgent)
        : "transparent"
  opacity: row.enabled ? 1 : 0.45

  Behavior on color { ColorAnimation { duration: 90 } }

  Accessible.role: Accessible.Button
  Accessible.name: row.label
  Accessible.onPressAction: row.trigger()

  // Declared before the row content so the trailing action button stays
  // clickable above it.
  MouseArea {
    anchors.fill: parent
    enabled: row.enabled
    cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: row.trigger()
  }

  Text {
    id: iconText
    textFormat: Text.PlainText
    visible: row.icon !== ""
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(20)
    text: row.icon
    color: row.danger
      ? Commons.Color.urgent
      : (row.active ? Commons.Color.accent : Commons.Color.popups.text)
    opacity: row.danger ? 1 : (row.active ? 1 : 0.72)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    horizontalAlignment: Text.AlignHCenter
  }

  Column {
    anchors.left: iconText.visible ? iconText.right : parent.left
    anchors.leftMargin: iconText.visible ? Style.space(6) : Style.space(10)
    anchors.right: trail.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Text {
      id: labelText
      textFormat: Text.PlainText
      width: parent.width
      text: row.label
      color: row.danger
        ? Commons.Color.urgent
        : (row.active ? Commons.Color.accent : Commons.Color.popups.text)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      visible: row.detail !== ""
      width: parent.width
      text: row.detail
      color: Commons.Color.popups.text
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Row {
    id: trail
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      visible: row.checked
      text: "✓"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Ui.PanelActionButton {
      visible: row.trailingIcon !== ""
      iconText: row.trailingIcon
      tooltipText: row.trailingTooltip
      foreground: row.danger ? Commons.Color.urgent : Commons.Color.popups.text
      hoverColor: row.danger ? Commons.Color.urgent : Commons.Color.accent
      size: Style.space(22)
      onClicked: row.trailingTriggered()
    }
  }

  HoverHandler { id: rowHover }
}
