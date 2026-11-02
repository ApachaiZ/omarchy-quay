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

  signal appActivated(var app)
  signal pinToggled(var app)
  signal settingsRequested()

  // ---- Derived geometry --------------------------------------------------
  readonly property var apps: Model.sortedAppList(
    DesktopEntries.applications ? DesktopEntries.applications.values : [], query)
  readonly property int resultCount: grid.apps.length
  readonly property int safeRows: Math.max(1, grid.rows)
  readonly property int padding: Style.space(14)
  readonly property int headerHeight: Style.space(40)
  readonly property int footerHeight: Style.space(22)
  readonly property int sectionGap: Style.space(10)
  readonly property int scrollbarGutter: Style.space(10)
  readonly property int emptyHeight: Style.space(156)
  readonly property real availableWidth: Math.max(Style.space(220), grid.maxPanelWidth - 2 * grid.padding - grid.scrollbarGutter)
  // Honor the chosen column count, but never let a 12-column setting overflow
  // a narrow screen: drop to the largest count that still fits a 56 px cell.
  readonly property int safeColumns: Math.max(1, Math.min(Math.max(1, grid.columns),
    Math.floor(grid.availableWidth / Style.space(56))))
  readonly property real cellWidth: Math.max(Style.space(56),
    Math.min(Style.space(108), grid.availableWidth / grid.safeColumns))
  readonly property real cellHeight: Math.round(grid.cellWidth * (grid.showLabels ? 1.16 : 0.92))
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
  opacity: visible ? 1 : 0
  radius: Style.cornerRadius
  color: Commons.Color.popups.background
  border.color: Commons.Color.popups.border
  border.width: 1
  clip: true

  Behavior on opacity {
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
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

  // ---- Search ------------------------------------------------------------
  Ui.TextField {
    id: searchField
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: gearButton.left
    anchors.topMargin: grid.padding
    anchors.leftMargin: grid.padding
    anchors.rightMargin: grid.sectionGap
    height: grid.headerHeight
    verticalPadding: Style.spacing.inputPaddingY + Style.space(2)
    horizontalPadding: Style.space(34)
    rightPadding: Style.space(34) + Style.spacing.controlPaddingX
    text: grid.query
    placeholderText: "Search applications…"
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
    opacity: searchField.activeFocus ? 0.9 : 0.55
    sourceSize.width: width * 2
    sourceSize.height: height * 2
  }

  Text {
    anchors.left: searchField.left
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: searchField.verticalCenter
    visible: grid.searchIconPath === ""
    text: "⌕"
    color: Commons.Color.popups.text
    opacity: 0.55
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
    size: Style.space(24)
    visible: searchField.text.length > 0
    onClicked: grid.clearSearch()
  }

  Ui.PanelActionButton {
    id: gearButton
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: grid.padding
    anchors.rightMargin: grid.padding
    iconText: "⚙"
    tooltipText: "Settings"
    size: grid.headerHeight
    bordered: true
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
    ScrollBar.vertical: ScrollBar {
      width: grid.scrollbarGutter
      policy: ScrollBar.AsNeeded
      background: Item { }
      contentItem: Rectangle {
        implicitWidth: Style.space(4)
        radius: width / 2
        color: Util.alpha(Commons.Color.popups.text, 0.3)
      }
    }

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

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(4)
        radius: Style.cornerRadius
        color: tile.selected
          ? Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent)
          : (tile.hovered
            ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent)
            : "transparent")
        border.width: tile.selected ? 1 : 0
        border.color: Util.alpha(Commons.Color.accent, 0.7)
        Behavior on color { ColorAnimation { duration: 90 } }
      }

      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(16)
        spacing: Style.space(6)

        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(Style.space(52), Math.round(grid.cellWidth * 0.46))
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
          visible: grid.showLabels
          width: parent.width
          text: modelData.name
          textFormat: Text.PlainText
          color: Commons.Color.popups.text
          opacity: tile.selected || tile.hovered ? 1.0 : 0.82
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }

      // Pin toggle. Visible on hover or when pinned, so the grid stays quiet
      // at rest while the action remains discoverable with the pointer.
      Rectangle {
        id: pinBadge
        visible: tile.pinned || tile.hovered
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        width: Style.space(20)
        height: width
        radius: width / 2
        color: tile.pinned
          ? Util.alpha(Commons.Color.accent, 0.9)
          : Util.alpha(Commons.Color.popups.background, 0.9)
        border.width: tile.pinned ? 0 : 1
        border.color: Commons.Color.popups.border
        z: 2

        Text {
          anchors.centerIn: parent
          text: tile.pinned ? "★" : "☆"
          textFormat: Text.PlainText
          color: tile.pinned ? Commons.Color.popups.background : Commons.Color.popups.text
          opacity: tile.pinned ? 1 : 0.8
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: grid.pinToggled(modelData)
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

      ToolTip {
        visible: !grid.showLabels && tile.hovered
        delay: 450
        text: modelData.name
        contentItem: Text {
          textFormat: Text.PlainText
          text: modelData.name
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Commons.Color.tooltip.text
          wrapMode: Text.Wrap
        }
        background: Rectangle {
          radius: Style.cornerRadius
          color: Commons.Color.tooltip.background
          border.color: Commons.Color.tooltip.border
          border.width: 1
        }
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
      width: parent.width - 2 * grid.padding
      spacing: Style.space(8)

      Image {
        x: Math.round((parent.width - width) / 2)
        width: Style.space(28)
        height: width
        source: grid.searchIconPath
        visible: grid.searchIconPath.length > 0
        opacity: 0.35
      }

      Text {
        width: parent.width
        text: grid.query.length > 0 ? "No matching applications" : "No applications found"
        textFormat: Text.PlainText
        color: Commons.Color.popups.text
        opacity: 0.82
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: grid.query.length > 0
        text: "Try a different name or keyword."
        textFormat: Text.PlainText
        color: Commons.Color.popups.text
        opacity: 0.45
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
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

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: grid.query.length > 0
        ? (grid.resultCount + (grid.resultCount === 1 ? " result" : " results"))
        : (grid.resultCount + (grid.resultCount === 1 ? " app" : " apps"))
      textFormat: Text.PlainText
      color: Commons.Color.popups.text
      opacity: 0.48
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: grid.width > Style.space(420)
      text: "↵ Open    ⇥ Settings    Esc Close"
      textFormat: Text.PlainText
      color: Commons.Color.popups.text
      opacity: 0.48
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
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
    else if (dx !== 0) index = (index + dx + count) % count
    else if (dy !== 0) {
      var next = index + dy * grid.safeColumns
      if (next >= 0 && next < count) index = next
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

  onVisibleChanged: {
    if (visible) {
      grid.selectedIndex = grid.apps.length > 0 ? 0 : -1
      grid.scrollToTop()
      grid.focusSearch()
    } else {
      grid.query = ""
      grid.gearSelected = false
      grid.selectedIndex = -1
    }
  }

  Component.onCompleted: {
    if (grid.apps.length > 0) grid.selectedIndex = 0
  }
}
