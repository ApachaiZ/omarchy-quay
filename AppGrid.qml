import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Model.js" as Model

// Application grid shown above the Quay. The grid is sized from the user's
// column/row choice and adapts its cell size to the available screen width.
// Search, keyboard navigation, pinning and launch actions all live here; the
// dock only decides when the panel is visible and performs the launch.
Rectangle {
  id: grid

  // ---- Contract with Quay.qml -------------------------------------------
  property int columns: 6
  property int rows: 4
  property bool showLabels: true
  property real maxPanelWidth: 800
  property real maxPanelHeight: 600
  property var iconResolver: function(icon) { return "" }
  property var isPinnedFn: function(id) { return false }
  property var isRunningFn: function(id) { return false }

  property string query: ""
  property int selectedIndex: -1
  property bool gearSelected: false
  // Logical open state. The panel stays visible for the short opacity fade
  // after `shown` drops, so its content does not collapse mid-fade.
  property bool shown: false
  property int fadeDuration: 150

  signal appActivated(var app)
  signal pinToggled(var app)
  signal settingsRequested()
  signal closeRequested()

  // ---- Derived geometry --------------------------------------------------
  readonly property var apps: Model.sortedAppList(
    DesktopEntries.applications ? DesktopEntries.applications.values : [], query)
  readonly property int resultCount: grid.apps.length
  readonly property int safeRows: Math.max(1, grid.rows)
  readonly property int padding: Style.space(16)
  readonly property int headerHeight: Math.max(Style.space(42),
    Math.ceil(Style.font.body + Style.space(24)))
  readonly property int footerHeight: Math.max(Style.space(26),
    Math.ceil(Style.font.caption + Style.space(12)))
  readonly property int sectionGap: Style.space(12)
  readonly property int scrollbarGutter: Style.space(12)
  readonly property int emptyHeight: Style.space(196)
  readonly property real availableWidth: Math.max(Style.space(240),
    grid.maxPanelWidth - 2 * grid.padding - grid.scrollbarGutter)

  // Honor the chosen column count, but never let a 12-column setting overflow
  // a narrow screen: drop to the largest count that still fits a 58 px cell.
  readonly property int safeColumns: Math.max(1, Math.min(Math.max(1, grid.columns),
    Math.floor(grid.availableWidth / Style.space(58))))
  readonly property real cellWidth: Math.max(Style.space(58),
    Math.min(Style.space(122), grid.availableWidth / grid.safeColumns))
  // Two-line labels remove the aggressive truncation long application names
  // used to suffer in a 6-column grid; very narrow cells fall back to one line.
  readonly property int labelLines: grid.cellWidth >= Style.space(84) ? 2 : 1
  readonly property real iconSize: Math.min(Style.space(60),
    Math.round(grid.cellWidth * 0.5))
  readonly property real labelHeight: grid.showLabels
    ? Math.ceil(Style.font.bodySmall * 1.32) * grid.labelLines + Style.space(4)
    : 0
  readonly property real cellHeight: Math.round(
    grid.iconSize + grid.labelHeight + 2 * Style.space(10))
  readonly property real maxGridHeight: Math.max(grid.cellHeight,
    grid.maxPanelHeight - grid.headerHeight - grid.footerHeight - 2 * grid.padding - 2 * grid.sectionGap)
  readonly property int visibleRows: grid.apps.length > 0
    ? Math.max(1, Math.min(grid.safeRows, Math.ceil(grid.apps.length / grid.safeColumns)))
    : 0
  readonly property real contentHeight: grid.apps.length > 0
    ? Math.min(grid.visibleRows * grid.cellHeight, grid.maxGridHeight)
    : Math.min(grid.emptyHeight, grid.maxGridHeight)
  readonly property real panelWidth: Math.min(grid.maxPanelWidth,
    grid.safeColumns * grid.cellWidth + 2 * grid.padding + grid.scrollbarGutter)
  readonly property real panelHeight: grid.headerHeight + grid.contentHeight + grid.footerHeight
    + 2 * grid.padding + 2 * grid.sectionGap
  readonly property string searchIconPath: {
    var names = ["system-search-symbolic", "edit-find-symbolic", "system-search", "edit-find"]
    for (var i = 0; i < names.length; i++) {
      var path = Quickshell.iconPath(names[i], true)
      if (path) return path
    }
    return ""
  }

  width: grid.panelWidth
  height: grid.panelHeight
  radius: Style.cornerRadius
  color: Commons.Color.popups.background
  border.color: Commons.Color.popups.border
  border.width: 1
  clip: true
  visible: grid.shown || grid.opacity > 0.001
  opacity: grid.shown ? 1 : 0
  enabled: grid.shown
  Behavior on opacity {
    NumberAnimation { duration: grid.fadeDuration; easing.type: Easing.OutCubic }
  }

  // Very light top wash: gives the panel depth without a second palette.
  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: Math.max(0, parent.radius - 1)
    gradient: Gradient {
      GradientStop { position: 0.0; color: Util.alpha(Commons.Color.accent, 0.045) }
      GradientStop { position: 0.45; color: "transparent" }
    }
  }

  // Keep clicks on the panel's padding from falling through to the dismiss
  // catcher behind the window. Tiles and buttons are declared above this.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
  }

  // ---- Header: search, preferences, close --------------------------------
  Ui.TextField {
    id: searchField
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: closeButton.left
    anchors.topMargin: grid.padding
    anchors.leftMargin: grid.padding
    anchors.rightMargin: grid.sectionGap
    height: grid.headerHeight
    verticalPadding: Style.space(10)
    horizontalPadding: Style.space(36)
    rightPadding: Style.space(36)
    foreground: Commons.Color.popups.text
    accent: Commons.Color.accent
    text: grid.query
    placeholderText: "Search apps…"
    onTextChanged: if (grid.query !== text) grid.query = text
    onActiveFocusChanged: if (searchField.activeFocus) grid.gearSelected = false
  }

  Image {
    anchors.left: searchField.left
    anchors.leftMargin: Style.space(12)
    anchors.verticalCenter: searchField.verticalCenter
    width: Style.space(16)
    height: Style.space(16)
    source: grid.searchIconPath
    visible: grid.searchIconPath.length > 0
    opacity: searchField.activeFocus ? 0.9 : 0.5
    sourceSize.width: width * 2
    sourceSize.height: height * 2
  }

  Text {
    anchors.left: searchField.left
    anchors.leftMargin: Style.space(12)
    anchors.verticalCenter: searchField.verticalCenter
    visible: grid.searchIconPath === ""
    text: "⌕"
    color: Commons.Color.popups.text
    opacity: 0.5
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Ui.PanelActionButton {
    id: clearButton
    anchors.right: searchField.right
    anchors.rightMargin: Style.space(7)
    anchors.verticalCenter: searchField.verticalCenter
    iconText: "×"
    tooltipText: "Clear search"
    foreground: Commons.Color.popups.text
    hoverColor: Commons.Color.accent
    size: Style.space(26)
    visible: searchField.text.length > 0
    onClicked: grid.clearSearch()
  }

  Ui.PanelActionButton {
    id: closeButton
    anchors.top: parent.top
    anchors.right: gearButton.left
    anchors.topMargin: grid.padding
    anchors.rightMargin: Style.space(4)
    iconText: "▾"
    tooltipText: "Hide the app grid (Esc)"
    foreground: Commons.Color.popups.text
    hoverColor: Commons.Color.accent
    fontSize: Style.font.iconLarge
    size: grid.headerHeight
    onClicked: grid.closeRequested()
  }

  Ui.PanelActionButton {
    id: gearButton
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: grid.padding
    anchors.rightMargin: grid.padding
    iconText: "⚙"
    tooltipText: "Preferences"
    foreground: Commons.Color.popups.text
    hoverColor: Commons.Color.accent
    fontSize: Style.font.iconLarge
    size: grid.headerHeight
    hasCursor: grid.gearSelected
    onClicked: grid.settingsRequested()
  }

  // ---- Application grid --------------------------------------------------
  GridView {
    id: gridView
    anchors.top: searchField.bottom
    anchors.topMargin: grid.sectionGap
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: grid.padding
    anchors.rightMargin: grid.padding
    height: grid.contentHeight
    visible: grid.apps.length > 0
    clip: true
    cellWidth: grid.cellWidth
    cellHeight: grid.cellHeight
    boundsBehavior: Flickable.StopAtBounds
    model: grid.apps
    cacheBuffer: grid.cellHeight * 2
    ScrollBar.vertical: SlimScrollBar { }

    delegate: Item {
      id: tile
      required property var modelData
      required property int index

      readonly property bool selected: grid.selectedIndex === index
      readonly property bool pinned: grid.isPinnedFn(modelData.id)
      readonly property bool running: grid.isRunningFn(modelData.id)
      readonly property bool hovered: tileHover.hovered

      width: gridView.cellWidth
      height: gridView.cellHeight

      Accessible.role: Accessible.Button
      Accessible.name: modelData.name
      Accessible.onPressAction: grid.appActivated(modelData)

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(4)
        radius: Math.max(0, Math.min(Style.cornerRadius, Style.space(10)))
        color: tile.selected
          ? Style.selectedFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)
          : (tile.hovered
            ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)
            : "transparent")
        border.width: tile.selected ? 1 : 0
        border.color: Util.alpha(Commons.Color.accent, 0.85)
        Behavior on color { ColorAnimation { duration: 90 } }
      }

      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(12)
        spacing: Style.space(6)

        Item {
          x: Math.round((parent.width - width) / 2)
          width: grid.iconSize
          height: width

          Image {
            anchors.fill: parent
            source: grid.iconResolver(modelData.icon)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            sourceSize.width: width * 2
            sourceSize.height: height * 2
          }

          // Running marker: a quiet accent dot on the icon's corner, matching
          // the dock's semantics without adding a second label row.
          Rectangle {
            visible: tile.running
            width: Style.space(7)
            height: width
            radius: width / 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -Style.space(2)
            anchors.bottomMargin: -Style.space(2)
            color: Commons.Color.accent
            border.width: 1
            border.color: Commons.Color.popups.background
          }
        }

        Text {
          id: labelText
          visible: grid.showLabels
          width: parent.width
          text: modelData.name
          textFormat: Text.PlainText
          color: tile.selected || tile.hovered
            ? Commons.Color.accent
            : Commons.Color.popups.text
          opacity: tile.selected || tile.hovered ? 1.0 : 0.84
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          maximumLineCount: grid.labelLines
          elide: Text.ElideRight
        }
      }

      // Pin toggle. A quiet outlined star marks a pinned app; the badge only
      // gains the accent fill while the pointer is over it.
      Rectangle {
        id: pinBadge
        visible: tile.pinned || tile.hovered
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        width: Style.space(19)
        height: width
        radius: width / 2
        color: tile.pinned && pinMouse.containsMouse
          ? Commons.Color.accent
          : Util.alpha(Commons.Color.popups.background, 0.92)
        border.width: 1
        border.color: tile.pinned
          ? Util.alpha(Commons.Color.accent, pinMouse.containsMouse ? 1 : 0.7)
          : Util.alpha(Commons.Color.popups.text, pinMouse.containsMouse ? 0.5 : 0.24)
        z: 2

        Text {
          anchors.centerIn: parent
          text: tile.pinned ? "★" : "☆"
          textFormat: Text.PlainText
          color: tile.pinned
            ? (pinMouse.containsMouse ? Commons.Color.background : Commons.Color.accent)
            : Commons.Color.popups.text
          opacity: tile.pinned ? 1 : 0.8
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        MouseArea {
          id: pinMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: grid.pinToggled(modelData)

          Ui.PanelToolTip {
            visible: pinMouse.containsMouse
            text: tile.pinned ? "Unpin from Quay" : "Pin to Quay"
            delay: 500
          }
        }
      }

      HoverHandler { id: tileHover }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          grid.selectedIndex = index
          if (mouse.button === Qt.RightButton) grid.pinToggled(modelData)
          else grid.appActivated(modelData)
        }
      }

      Ui.PanelToolTip {
        visible: tile.hovered && (!grid.showLabels || labelText.truncated)
        text: modelData.name
        delay: 600
      }
    }
  }

  // ---- Empty state -------------------------------------------------------
  Item {
    anchors.top: searchField.bottom
    anchors.topMargin: grid.sectionGap
    anchors.left: parent.left
    anchors.right: parent.right
    height: grid.contentHeight
    visible: grid.apps.length === 0

    Column {
      anchors.centerIn: parent
      width: Math.min(parent.width - 2 * grid.padding, Style.space(320))
      spacing: Style.space(10)

      Rectangle {
        x: Math.round((parent.width - width) / 2)
        width: Style.space(54)
        height: width
        radius: width / 2
        color: Util.alpha(Commons.Color.accent, 0.08)
        border.width: 1
        border.color: Util.alpha(Commons.Color.accent, 0.22)

        Image {
          anchors.centerIn: parent
          width: Style.space(22)
          height: width
          source: grid.searchIconPath
          visible: grid.searchIconPath.length > 0
          opacity: 0.55
        }

        Text {
          anchors.centerIn: parent
          visible: grid.searchIconPath === ""
          text: "⌕"
          color: Commons.Color.popups.text
          opacity: 0.5
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
      }

      Text {
        width: parent.width
        text: grid.query.length > 0
          ? "No app matches “" + grid.query + "”"
          : "No applications found"
        textFormat: Text.PlainText
        color: Commons.Color.popups.text
        opacity: 0.88
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: grid.query.length > 0
          ? "Try a name, a keyword, or a shorter search."
          : "Check that your desktop entries are installed."
        textFormat: Text.PlainText
        color: Commons.Color.popups.text
        opacity: 0.48
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Ui.Button {
        visible: grid.query.length > 0
        x: Math.round((parent.width - width) / 2)
        text: "Clear search"
        bordered: true
        foreground: Commons.Color.popups.text
        accent: Commons.Color.accent
        onClicked: grid.clearSearch()
      }
    }
  }

  // ---- Footer ------------------------------------------------------------
  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: grid.padding
    anchors.rightMargin: grid.padding
    anchors.bottomMargin: grid.padding
    height: grid.footerHeight

    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: 1
      color: Util.alpha(Commons.Color.popups.text, 0.12)
    }

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: Style.space(3)
      text: grid.query.length > 0
        ? (grid.resultCount + (grid.resultCount === 1 ? " result" : " results"))
        : (grid.resultCount + (grid.resultCount === 1 ? " app" : " apps"))
      textFormat: Text.PlainText
      color: Commons.Color.popups.text
      opacity: 0.46
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: Style.space(3)
      visible: grid.width > Style.space(470)
      spacing: Style.space(12)

      KeyHint { keys: "↵"; label: "Open" }
      KeyHint { keys: "Tab"; label: "Preferences" }
      KeyHint { keys: "Esc"; label: "Close" }
    }
  }

  // ---- Keyboard and selection -------------------------------------------
  function focusSearch() {
    grid.gearSelected = false
    Qt.callLater(function() {
      if (grid.visible) searchField.forceActiveFocus()
    })
  }

  function clearSearch() {
    grid.query = ""
    grid.selectedIndex = grid.apps.length > 0 ? 0 : -1
    grid.scrollToTop()
    grid.focusSearch()
  }

  function startSearch(text) {
    grid.query = String(text || "")
    grid.gearSelected = false
    grid.focusSearch()
    grid.caretToEnd()
  }

  function appendSearch(text) {
    var value = String(text || "")
    if (!value) return
    grid.query += value
    grid.gearSelected = false
    grid.focusSearch()
    grid.caretToEnd()
  }

  function caretToEnd() {
    Qt.callLater(function() {
      searchField.cursorPosition = searchField.length
    })
  }

  function scrollToTop() {
    Qt.callLater(function() {
      if (gridView.contentY !== 0) gridView.contentY = 0
    })
  }

  function moveSelection(dx, dy) {
    var count = grid.apps.length
    if (count === 0) { grid.selectedIndex = -1; return }
    var index = grid.selectedIndex
    if (index < 0) index = (dx < 0 || dy < 0) ? count - 1 : 0
    else if (dx !== 0) {
      // Horizontal movement reads like text: crossing a row edge lands on
      // the first/last tile of the neighbouring row.
      index = (index + dx + count) % count
    } else if (dy !== 0) {
      var columns = grid.safeColumns
      var column = index % columns
      var row = Math.floor(index / columns)
      var lastRow = Math.floor((count - 1) / columns)
      var nextRow = row + dy
      if (nextRow >= 0 && nextRow <= lastRow) {
        var target = nextRow * columns + column
        // The final row can be partial: land on its last tile rather than
        // refusing to move.
        if (target >= count) target = count - 1
        index = target
      }
    }
    grid.selectedIndex = index
    gridView.positionViewAtIndex(index, GridView.Contain)
  }

  function activate() {
    var count = grid.apps.length
    if (count === 0) return
    var index = (grid.selectedIndex >= 0 && grid.selectedIndex < count) ? grid.selectedIndex : 0
    grid.appActivated(grid.apps[index])
  }

  onQueryChanged: {
    if (searchField.text !== grid.query) searchField.text = grid.query
    Qt.callLater(function() {
      grid.selectedIndex = grid.apps.length > 0 ? 0 : -1
      grid.scrollToTop()
    })
  }

  onAppsChanged: {
    if (grid.selectedIndex >= grid.apps.length)
      grid.selectedIndex = grid.apps.length > 0 ? grid.apps.length - 1 : -1
  }

  onColumnsChanged: {
    if (grid.selectedIndex >= grid.apps.length)
      grid.selectedIndex = grid.apps.length > 0 ? grid.apps.length - 1 : -1
  }

  onShownChanged: {
    if (grid.shown) {
      grid.selectedIndex = grid.apps.length > 0 ? 0 : -1
      grid.scrollToTop()
      grid.focusSearch()
    }
  }

  // Only clear the search once the fade finished. During the fade the panel
  // keeps its content so the dismissal reads as a fade, not a collapse.
  onVisibleChanged: {
    if (!grid.visible) {
      grid.query = ""
      grid.gearSelected = false
      grid.selectedIndex = -1
    }
  }

  Component.onCompleted: {
    if (grid.apps.length > 0) grid.selectedIndex = 0
  }
}
