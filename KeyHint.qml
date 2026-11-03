import QtQuick
import qs.Commons
import qs.Commons as Commons

// Keyboard hint: a small keycap followed by its action. Used in panel
// footers so the shortcuts are visible without turning the footer into a
// wall of text.
Row {
  id: root

  property string keys: ""
  property string label: ""

  spacing: Style.space(4)

  Rectangle {
    width: keyLabel.implicitWidth + Style.space(8)
    height: Style.space(18)
    radius: Math.max(2, Math.min(Style.cornerRadius, Style.space(4)))
    color: Util.alpha(Commons.Color.popups.text, 0.08)
    border.width: 1
    border.color: Util.alpha(Commons.Color.popups.text, 0.16)

    Text {
      id: keyLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.keys
      color: Commons.Color.popups.text
      opacity: 0.78
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Text {
    textFormat: Text.PlainText
    height: Style.space(18)
    verticalAlignment: Text.AlignVCenter
    text: root.label
    color: Commons.Color.popups.text
    opacity: 0.48
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
