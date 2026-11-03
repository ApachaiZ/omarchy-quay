import QtQuick
import qs.Commons
import qs.Commons as Commons

// Quiet small-caps section label used across the Quay's panels. Left aligned
// and letter-spaced, matching the shell's panel section headers.
Text {
  id: root

  property string title: ""

  textFormat: Text.PlainText
  text: root.title.toUpperCase()
  width: parent ? parent.width : implicitWidth
  color: Util.alpha(Commons.Color.popups.text, 0.58)
  font.family: Style.font.family
  font.pixelSize: Style.font.caption
  font.bold: true
  font.letterSpacing: 1.1
  leftPadding: Style.space(10)
  rightPadding: Style.space(10)
  topPadding: Style.space(12)
  bottomPadding: Style.space(5)
  elide: Text.ElideRight
}
