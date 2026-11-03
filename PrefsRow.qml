import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// A preferences row with a label on the left and a compact control on the
// right. Two to three options render as a segmented picker; longer lists
// render as a stepper. Clicking anywhere on the row cycles the value, and
// left/right (keyboard) adjusts it through `adjust`.
Rectangle {
  id: row

  property string label: ""
  property var options: []
  property var current: null
  property var formatValue: function(value) { return String(value) }
  property bool highlighted: false

  signal picked(var value)

  readonly property int rowHeight: Math.max(Style.space(34),
    Math.ceil(Style.font.body + Style.space(16)))
  readonly property bool active: row.highlighted || rowHover.hovered
  readonly property bool segmented: row.options.length > 0 && row.options.length <= 3
  readonly property real labelWidth: Math.max(Style.space(88),
    Math.min(row.width * 0.45, Style.space(154)))
  readonly property real controlWidth: Math.max(Style.space(116),
    row.width - row.labelWidth - Style.space(24))

  function next(delta) {
    var count = row.options.length
    if (count === 0) return
    var index = row.options.indexOf(row.current)
    if (index < 0) index = delta > 0 ? -1 : 0
    index = (index + delta + count) % count
    row.picked(row.options[index])
  }
  function trigger() { row.next(1) }
  function adjust(delta) { if (delta !== 0) row.next(delta) }

  width: parent ? parent.width : Style.space(280)
  height: row.rowHeight
  radius: Math.max(0, Math.min(Style.cornerRadius, Style.space(8)))
  color: row.highlighted
    ? Style.selectedFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)
    : rowHover.hovered
      ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)
      : "transparent"

  Behavior on color { ColorAnimation { duration: 90 } }

  Accessible.role: Accessible.Button
  Accessible.name: row.label
  Accessible.description: row.formatValue(row.current)
  Accessible.onPressAction: row.trigger()

  // Declared before the controls so the segment buttons and stepper arrows
  // receive their clicks above this whole-row fallback.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: row.trigger()
  }

  Text {
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: row.labelWidth - Style.space(10)
    text: row.label
    color: row.active ? Commons.Color.accent : Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  // Segmented picker for short lists (On/Off, 1.3×/1.5×/1.8×).
  Row {
    id: segments
    visible: row.segmented
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    readonly property real segmentWidth: Math.max(Style.space(38),
      (row.controlWidth - (row.options.length - 1) * spacing) / Math.max(1, row.options.length))

    Repeater {
      model: row.options

      Rectangle {
        id: segment
        required property var modelData
        readonly property bool selected: row.current === modelData
        width: segments.segmentWidth
        height: Math.max(Style.space(26), Math.round(Style.font.body + Style.space(12)))
        radius: Math.max(0, Math.min(Style.cornerRadius, Style.space(7)))
        color: segment.selected
          ? Style.selectedFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)
          : (segmentHover.hovered
            ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)
            : "transparent")
        border.width: 1
        border.color: segment.selected
          ? Commons.Color.accent
          : Util.alpha(Commons.Color.popups.text, 0.16)

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          width: Math.min(implicitWidth, parent.width - Style.space(8))
          text: row.formatValue(segment.modelData)
          color: segment.selected ? Commons.Color.accent : Commons.Color.popups.text
          opacity: segment.selected ? 1 : 0.72
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }

        HoverHandler { id: segmentHover }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: row.picked(segment.modelData)
        }
      }
    }
  }

  // Stepper for longer lists (icon size, animation mode, ...).
  Row {
    visible: !row.segmented && row.options.length > 0
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Ui.PanelActionButton {
      iconText: "‹"
      fontSize: Style.font.title
      foreground: Commons.Color.popups.text
      hoverColor: Commons.Color.accent
      size: Style.space(26)
      onClicked: row.next(-1)
    }

    Text {
      textFormat: Text.PlainText
      width: Math.max(Style.space(58),
        Math.min(Style.space(176), row.controlWidth - Style.space(58)))
      height: Style.space(26)
      text: row.formatValue(row.current)
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }

    Ui.PanelActionButton {
      iconText: "›"
      fontSize: Style.font.title
      foreground: Commons.Color.popups.text
      hoverColor: Commons.Color.accent
      size: Style.space(26)
      onClicked: row.next(1)
    }
  }

  HoverHandler { id: rowHover }
}
