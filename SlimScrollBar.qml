import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons

// Thin, quiet scrollbar used by the app grid and the scrollable menus.
ScrollBar {
  id: root

  policy: ScrollBar.AsNeeded
  width: Style.space(10)
  background: Item {}

  contentItem: Rectangle {
    implicitWidth: Style.space(4)
    implicitHeight: Style.space(4)
    radius: width / 2
    color: Util.alpha(Commons.Color.popups.text, 0.3)
  }
}
