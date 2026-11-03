import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQml.Models
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Model.js" as Model

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string favoritesFile: home + "/.config/omarchy/quay.json"
  property var shell: null
  property var manifest: null

  property var favorites: []          // resolved [{ id, name, icon }] shown in the Quay
  property var favoriteIds: []        // every pinned id, including temporarily missing apps
  property bool opened: false
  property bool windowHover: false
  property bool hovering: false
  property bool sliding: false
  readonly property bool quayShown: root.hovering
  readonly property bool overlayActive: root.opened || root.gridOpen || root.prefsOpen
    || root.menuOpen || root.detailOpen
  readonly property bool panelOpen: root.gridOpen || root.prefsOpen
    || root.menuOpen || root.detailOpen
  property var runningClasses: []
  // Merged display list (pinned + running-unpinned).
  ListModel { id: entriesModel }
  property var clients: []            // [{ address, cls, title }]
  property int hoveredIndex: -1
  // Pointer hover wins; otherwise the keyboard-selected icon is the one that
  // zooms. No selection frame is drawn.
  readonly property int activeIconIndex: {
    if (root.hoveredIndex >= 0) return root.hoveredIndex
    if (!root.opened || root.dragActive) return -1
    if (root.gridOpen || root.prefsOpen
        || root.menuOpen || root.detailOpen) return -1
    return (root.keySel >= 0 && root.keySel < entriesModel.count) ? root.keySel : -1
  }
  // Pointer reorder state: drag an icon along the rail and drop it into a
  // slot. Pinned items move; a running unpinned item is pinned at the slot.
  property bool dragActive: false
  property int dragIndex: -1
  property int dragSlot: -1
  property real dragX: 0
  property var dragEntry: null
  property bool suppressIconClick: false
  // Keyboard navigation state.
  property int keySel: -1              // selected Quay entry; entriesModel.count = the add button
  property int menuSel: 0              // selected row inside an open sub-panel (context menu/prefs)
  property bool focusPrimed: false     // brief Exclusive prime before settling keyboard focus to OnDemand
  property bool gridOpen: false
  // Logical open state. The indices below are kept while a panel fades out so
  // its content does not collapse mid-fade; `menuOpen`/`detailOpen` are what
  // the keyboard and input routing follow.
  property bool menuOpen: false
  property bool detailOpen: false
  property int menuIndex: -1
  property int detailIndex: -1
  // The icon a context menu / details card is anchored to. -1 falls back to
  // the centre of the Quay.
  property int menuAnchorIndex: -1
  property int detailAnchorIndex: -1
  // Panels always use their own fixed fade, independent of the dock's
  // configurable show/hide animation.
  readonly property int panelFadeDuration: 150
  property var cyclePos: ({})
  property string screenPref: ""        // "" = auto (widest), else monitor name
  property int hideDelay: 1500          // ms the Quay/menus stay after hover ends
  property bool showName: false         // tooltip with the app name on hover/keyboard selection
  property bool showOnHover: true       // bottom hotspot reveals Quay on pointer hover
  property int iconSize: 48             // base icon edge in px
  property real zoom: 1.8               // hovered icon scale
  property int paddingX: 12             // horizontal card padding
  property int paddingY: 5              // vertical card padding
  property int iconSpacing: 6           // gap between icon slots
  property int gridColumns: 6           // columns in the application grid
  property int gridRows: 4              // visible rows in the application grid
  property bool gridShowLabels: true    // application names under grid tiles
  // Fixed slot width: reserve room for the configured zoom and its neighbour
  // once, so hovering never changes the row or the card width.
  readonly property real iconSlotWidth: Model.slotWidth(root.iconSize, root.zoom, root.iconSpacing)
  // Reserve a little room under the icons for the running-window dots so the
  // largest zoom never touches the card border.
  readonly property int cardHeight: Math.max(Style.space(56) + 2 * root.paddingY,
    Math.ceil(root.iconSize * Math.max(1, root.zoom)) + 2 * root.paddingY + Style.space(6))
  readonly property int prefsHeaderHeight: Math.max(Style.space(46),
    Math.ceil(Style.font.title + Style.space(24)))
  readonly property int prefsFooterHeight: Math.max(Style.space(28),
    Math.ceil(Style.font.caption + Style.space(14)))
  // Keyboard navigation is slower than pointing: a key press (or the ALT + SPACE
  // summon) keeps the Quay alive for this long instead of hideDelay.
  readonly property int keyboardHideDelay: 10000
  property bool keyboardSession: false  // hide timer currently in the keyboard (10 s) mode
  property string animMode: "slide"     // "slide" | "fade" | "scale" | "fadeSlide" | "bounce" | "zoom" | "stagger" | "blur" | "slideH"
  property string animSpeed: "normal"   // "fast" | "normal" | "slow"
  readonly property int animDuration: root.animSpeed === "fast" ? 120 : (root.animSpeed === "slow" ? 350 : 220)

  // Animation modes are components joined with "+" (e.g. "bounce+blur");
  // each component enables one visual aspect. Legacy "fadeSlide" is
  // normalized to "fade+slide" when loading settings.
  function animComponents() {
    var out = []
    var parts = String(root.animMode).split("+")
    for (var i = 0; i < parts.length; i++) {
      var p = String(parts[i]).trim()
      if (p) out.push(p)
    }
    return out
  }
  function animHas(comp) {
    return root.animComponents().indexOf(comp) >= 0
  }
  function isValidAnimMode(mode) {
    var known = ["slide", "fade", "scale", "bounce", "zoom", "stagger", "blur", "slideH"]
    var parts = String(mode).split("+")
    if (parts.length === 0) return false
    for (var i = 0; i < parts.length; i++) {
      if (known.indexOf(String(parts[i]).trim()) < 0) return false
    }
    return true
  }
  readonly property var animationModes: [
    "slide", "bounce", "scale", "zoom", "slideH", "fade", "blur", "stagger",
    "bounce+fade", "bounce+blur", "bounce+stagger", "bounce+scale", "bounce+zoom",
    "fade+slide", "slide+blur", "slide+stagger",
    "scale+fade", "scale+blur", "scale+stagger",
    "zoom+blur", "zoom+stagger", "stagger+blur",
    "slideH+fade", "slideH+blur", "slideH+stagger"
  ]
  function animationLabel(mode) {
    var names = {
      slide: "Slide", bounce: "Bounce", scale: "Scale", zoom: "Zoom",
      slideH: "Slide horizontal", fade: "Fade", blur: "Blur", stagger: "Stagger"
    }
    var parts = String(mode).split("+")
    for (var i = 0; i < parts.length; i++)
      parts[i] = names[parts[i]] || parts[i]
    return parts.join(" + ")
  }
  // Components whose arrival/hide animates the card's opacity.
  function animUsesFade() {
    return root.animHas("fade") || root.animHas("zoom") || root.animHas("stagger") || root.animHas("blur")
  }
  readonly property string settingsFile: home + "/.config/omarchy/quay-settings.json"
  property bool prefsOpen: false

  function entryFromModel(index) {
    if (index < 0 || index >= entriesModel.count) return null
    var e = entriesModel.get(index)
    return { id: e.appId, name: e.name, icon: e.icon, pinned: e.pinned, running: e.running }
  }

  // Cumulative x offset of the icon at `index`; slots are fixed so hover
  // magnification never changes the Quay width.
  function slotXFor(index) {
    return index * root.iconSlotWidth
  }

  readonly property var menuEntry: root.entryFromModel(root.menuIndex)
  readonly property var menuWindows: root.menuEntry ? root.windowsFor(root.menuEntry) : []
  readonly property var menuDesktopEntry: root.menuEntry ? root.lookupDesktopEntry(root.menuEntry.id) : null
  readonly property string menuStatusText: {
    if (!root.menuEntry) return ""
    var count = root.menuWindows.length
    if (count === 0) return "Not running"
    return count === 1 ? "Running · 1 window" : "Running · " + count + " windows"
  }
  readonly property var detailEntry: root.entryFromModel(root.detailIndex)
  readonly property var detailDesktopEntry: root.detailEntry ? root.lookupDesktopEntry(root.detailEntry.id) : null
  readonly property var detailWindows: root.detailEntry ? root.windowsFor(root.detailEntry) : []
  readonly property string detailStatusText: {
    if (!root.detailEntry) return ""
    var count = root.detailWindows.length
    if (count === 0) return "Not running"
    return count === 1 ? "Running · 1 window" : "Running · " + count + " windows"
  }
  // Panels open above the icon that spawned them, clamped to the screen by
  // each panel's x binding.
  readonly property real menuAnchorX: root.menuAnchorIndex < 0
    ? quayWindow.width / 2
    : card.x + iconsRow.x + root.slotXFor(root.menuAnchorIndex) + root.iconSlotWidth / 2
  readonly property real detailAnchorX: root.detailAnchorIndex < 0
    ? quayWindow.width / 2
    : card.x + iconsRow.x + root.slotXFor(root.detailAnchorIndex) + root.iconSlotWidth / 2
  readonly property string quayVersion: root.manifest && root.manifest.version
    ? String(root.manifest.version) : ""


  function iconPathFor(icon) {
    var value = String(icon || "")
    var themed = value.length > 0 ? Quickshell.iconPath(value, true) : ""
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  // Screen the Quay lives on: the configured monitor name (from settings), or
  // fall back to the widest monitor (the main horizontal display). Kept as a
  // property binding (not a function call) so it re-evaluates when
  // Quickshell.screens changes, e.g. after a suspend or a monitor hotplug.
  readonly property var targetScreen: {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    if (root.screenPref) {
      for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === root.screenPref) return screens[i]
      }
    }
    var best = screens[0]
    for (var j = 1; j < screens.length; j++) {
      if (screens[j].width > best.width) best = screens[j]
    }
    return best
  }

  readonly property int screenHeight: {
    var screen = root.targetScreen
    return screen && screen.height > 0 ? screen.height : 1080
  }
  readonly property int panelMaxHeight: Math.max(Style.space(320), root.screenHeight - Style.space(150))

  function resolveFavorites(ids) {
    var values = DesktopEntries.applications.values || []
    return Model.resolveFavorites(ids, values)
  }

  function saveFavorites() {
    favoritesView.setText(JSON.stringify(root.favoriteIds) + "\n")
  }

  // Commit a new visible order while keeping ids whose desktop entries are
  // currently missing. Missing pins move to the end instead of being lost.
  function applyFavoriteOrder(display) {
    var ids = []
    var seen = Object.create(null)
    for (var i = 0; i < display.length; i++) {
      var id = Model.normalizeId(display[i].id)
      if (!id || seen[id]) continue
      seen[id] = true
      ids.push(id)
    }
    for (var j = 0; j < root.favoriteIds.length; j++) {
      var kept = Model.normalizeId(root.favoriteIds[j])
      if (!kept || seen[kept]) continue
      seen[kept] = true
      ids.push(kept)
    }
    root.favoriteIds = ids
    root.favorites = root.resolveFavorites(ids)
    root.saveFavorites()
  }

  function launchApp(entry) {
    if (!entry || !entry.id) return
    Util.execArgv(["uwsm-app", "--", "gtk-launch", Model.normalizeId(entry.id) + ".desktop"])
  }

  function launchNewWindow(entry) {
    if (!entry || !entry.id) return
    var de = root.lookupDesktopEntry(entry.id)
    var argv = de ? Model.parseExec(de.execString) : []
    if (argv.length === 0) { root.launchApp(entry); return }
    Util.execArgv(["uwsm-app", "--"].concat(argv))
  }

  function isRunningId(id) {
    if (!id) return false
    var value = Model.normalizeId(id).toLowerCase()
    var classes = root.runningClasses
    for (var i = 0; i < classes.length; i++) {
      if (classes[i] === value) return true
    }
    return false
  }

  function isRunning(entry) {
    return entry ? root.isRunningId(entry.id) : false
  }

  function entryForClass(cls) {
    var values = DesktopEntries.applications.values || []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e.id) continue
      if (Model.normalizeId(e.id).toLowerCase() === cls) return e
      var sc = String(e.startupClass || "").toLowerCase()
      if (sc && sc === cls) return e
    }
    return null
  }

  function isPinned(id) {
    var nid = Model.normalizeId(id).toLowerCase()
    for (var i = 0; i < root.favoriteIds.length; i++) {
      if (Model.normalizeId(root.favoriteIds[i]).toLowerCase() === nid) return true
    }
    return false
  }

  function rebuildEntries() {
    var out = []
    var i
    for (i = 0; i < root.favorites.length; i++) {
      var f = root.favorites[i]
      out.push({ id: f.id, name: f.name, icon: f.icon, pinned: true, running: root.isRunning(f), winCount: root.windowsFor(f).length })
    }
    var classes = root.runningClasses
    for (i = 0; i < classes.length; i++) {
      var e = entryForClass(classes[i])
      if (!e) continue
      var nid = Model.normalizeId(e.id)
      if (root.isPinned(nid)) continue
      out.push({ id: nid, name: String(e.name || nid), icon: String(e.icon || ""), pinned: false, running: true, winCount: root.windowsFor({ id: nid }).length })
    }
    // Skip the rebuild when nothing changed: clearing and re-appending
    // destroys every delegate, which replays the stagger cascade and
    // flickers the icons on every running-apps poll.
    var same = out.length === entriesModel.count
    if (same) {
      for (i = 0; i < out.length; i++) {
        var cur = entriesModel.get(i)
        if (!cur || cur.appId !== out[i].id || cur.name !== out[i].name
            || cur.icon !== out[i].icon || cur.pinned !== out[i].pinned
            || cur.running !== out[i].running || cur.winCount !== out[i].winCount) {
          same = false
          break
        }
      }
    }
    if (!same) {
      entriesModel.clear()
      for (i = 0; i < out.length; i++) {
        entriesModel.append({ appId: out[i].id, name: out[i].name, icon: out[i].icon, pinned: out[i].pinned, running: out[i].running, winCount: out[i].winCount })
      }
      if (root.keySel > entriesModel.count) root.keySel = entriesModel.count
    }
  }

  function parseClients(raw) {
    var out = []
    var clist = []
    try {
      var list = JSON.parse(String(raw || ""))
      for (var i = 0; i < list.length; i++) {
        var c = list[i]
        // Dropdown parks its hidden windows with this tag; do not list them.
        var tags = Array.isArray(c.tags) ? c.tags : []
        if (tags.indexOf("dropdown-hidden") >= 0) continue
        var cls = String(c.class || "").toLowerCase()
        var icls = String(c.initialClass || "").toLowerCase()
        if (cls && out.indexOf(cls) < 0) out.push(cls)
        if (icls && out.indexOf(icls) < 0) out.push(icls)
        var workspace = c.workspace
          ? String(c.workspace.name || c.workspace.id || "")
          : ""
        clist.push({
          address: String(c.address || ""),
          cls: cls,
          title: String(c.title || ""),
          workspace: workspace
        })
      }
    } catch (e) {
      out = []
      clist = []
    }
    root.runningClasses = out
    root.clients = clist
    root.rebuildEntries()
  }

  function lookupDesktopEntry(nid) {
    var values = DesktopEntries.applications.values || []
    var target = Model.normalizeId(nid).toLowerCase()
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (Model.normalizeId(e.id).toLowerCase() === target) return e
    }
    return null
  }

  function windowsFor(entry) {
    if (!entry || !entry.id) return []
    var id = Model.normalizeId(entry.id).toLowerCase()
    var de = root.lookupDesktopEntry(entry.id)
    var sc = de ? String(de.startupClass || "").toLowerCase() : ""
    var out = []
    for (var i = 0; i < root.clients.length; i++) {
      var c = root.clients[i]
      if (c.cls === id || (sc && c.cls === sc)) out.push(c)
    }
    return out
  }

  function windowAddress(address) {
    var value = String(address || "").trim()
    return /^0x[0-9a-fA-F]+$/.test(value) ? value : ""
  }

  function focusWindow(address) {
    var addr = root.windowAddress(address)
    if (!addr) return
    Util.execArgv(["hyprctl", "dispatch",
      "hl.dsp.focus({ window = \"address:" + addr + "\" })"])
  }

  function closeWindow(address) {
    var addr = root.windowAddress(address)
    if (!addr) return
    Util.execArgv(["hyprctl", "dispatch",
      "hl.dsp.window.close({ window = \"address:" + addr + "\" })"])
  }

  function focusApp(entry) {
    var wins = root.windowsFor(entry)
    if (wins.length === 0) { root.launchApp(entry); root.dismiss(); return }
    root.focusWindow(wins[0].address)
    root.dismiss()
  }

  function cycleWindow(entry, delta) {
    var wins = root.windowsFor(entry)
    if (wins.length <= 1) return
    var key = "app:" + Model.normalizeId(entry.id)
    var pos = root.cyclePos[key] || 0
    pos = (pos + delta + wins.length) % wins.length
    root.cyclePos[key] = pos
    root.focusWindow(wins[pos].address)
  }

  function quitApp(entry) {
    var wins = root.windowsFor(entry)
    for (var i = 0; i < wins.length; i++) root.closeWindow(wins[i].address)
    root.dismiss()
  }

  function unpinApp(id) {
    var nid = Model.normalizeId(id)
    var display = []
    for (var i = 0; i < root.favorites.length; i++) {
      if (Model.normalizeId(root.favorites[i].id) !== nid) display.push(root.favorites[i])
    }
    var ids = []
    for (var j = 0; j < root.favoriteIds.length; j++) {
      if (Model.normalizeId(root.favoriteIds[j]) !== nid) ids.push(root.favoriteIds[j])
    }
    root.favoriteIds = ids
    root.favorites = display
    root.saveFavorites()
  }

  function openMenu(index) {
    if (!root.entryFromModel(index)) return
    root.menuIndex = index
    root.menuAnchorIndex = index
    root.menuOpen = true
    root.detailOpen = false
    root.closeGrid()
    root.prefsOpen = false
    root.menuSel = 0
    Qt.callLater(function() {
      if (root.menuOpen) quayKeys.forceActiveFocus()
      root.refreshMenuHighlight()
      if (menuScroll.contentItem) menuScroll.contentItem.contentY = 0
    })
  }

  function closeMenu() {
    // Keep menuIndex/menuAnchorIndex: the panel fades out with its content
    // intact, and the next openMenu replaces them.
    root.menuOpen = false
  }

  // Details replace the context menu instead of stacking on top of it. Closing
  // them with Escape returns to the app's menu, the same progressive back
  // behaviour as the grid/preferences panels.
  function openDetails(index) {
    if (!root.entryFromModel(index)) return
    root.detailIndex = index
    root.detailAnchorIndex = index
    root.detailOpen = true
    root.menuOpen = false
    root.closeGrid()
    root.prefsOpen = false
    root.menuSel = 0
    Qt.callLater(function() {
      if (root.detailOpen) quayKeys.forceActiveFocus()
      root.refreshMenuHighlight()
      if (detailScroll.contentItem) detailScroll.contentItem.contentY = 0
    })
  }

  function closeDetails(backToMenu) {
    var index = root.detailIndex
    root.detailOpen = false
    if (backToMenu && index >= 0) root.openMenu(index)
  }

  function openPrefs() {
    root.prefsOpen = true
    root.menuOpen = false
    root.detailOpen = false
    root.closeGrid()
    root.menuSel = 0
    Qt.callLater(function() {
      if (root.prefsOpen) quayKeys.forceActiveFocus()
      root.refreshMenuHighlight()
      if (prefsScroll.contentItem) prefsScroll.contentItem.contentY = 0
    })
  }

  function closePrefs() {
    root.prefsOpen = false
  }

  // ---- Keyboard navigation -------------------------------------------------
  // Enter launches/focuses the selected app; Space cycles its windows;
  // arrows move the selection (Quay icons, or rows of an open sub-panel);
  // Escape closes progressively (panel → menu → Quay). Super is left to
  // Hyprland's own release-bound toggle (see the key handler comment).

  function refocusKeys() {
    if (!root.opened) return
    Qt.callLater(function() {
      if (root.opened && !root.gridOpen) quayKeys.forceActiveFocus()
    })
  }

  // Keep the auto-hide timer from firing while the user is actively
  // navigating with the keyboard; keyboard sessions get a 10 s window.
  function keepAlive() {
    if (root.windowHover) return
    root.keyboardSession = true
    hideTimer.restart()
  }

  function activeMenuKind() {
    if (root.menuOpen) return "menu"
    if (root.prefsOpen) return "prefs"
    if (root.detailOpen) return "detail"
    return ""
  }

  // Ordered interactive rows of the context menu. Rows carry `highlighted`
  // and `trigger()`; separators/headers are skipped.
  function menuRows() {
    var rows = [menuFocus]
    if (menuNewWindow.visible) rows.push(menuNewWindow)
    if (menuPin.visible) rows.push(menuPin)
    else if (menuUnpin.visible) rows.push(menuUnpin)
    for (var i = 0; i < menuWinRepeater.count; i++) rows.push(menuWinRepeater.itemAt(i))
    if (menuDetails.visible) rows.push(menuDetails)
    if (menuQuit.visible) rows.push(menuQuit)
    return rows
  }

  function prefsRows() {
    var rows = [prefsAuto]
    for (var i = 0; i < prefsScreens.count; i++) rows.push(prefsScreens.itemAt(i))
    rows.push(prefsShowOnHover, prefsHideDelay, prefsShowName)
    rows.push(prefsIconSize, prefsZoom, prefsGap, prefsPadX, prefsPadY)
    rows.push(prefsGridColumns, prefsGridRows, prefsGridLabels)
    rows.push(prefsAnimMode, prefsSpeed)
    return rows
  }

  function activeMenuRows() {
    var out = root.activeMenuKind() === "menu" ? root.menuRows()
      : (root.activeMenuKind() === "prefs" ? root.prefsRows() : [])
    var clean = []
    for (var i = 0; i < out.length; i++) if (out[i]) clean.push(out[i])
    return clean
  }

  function refreshMenuHighlight() {
    var rows = root.activeMenuRows()
    for (var j = 0; j < rows.length; j++) rows[j].highlighted = (j === root.menuSel)
  }

  function keyNav(dx, dy) {
    root.keepAlive()
    var kind = root.activeMenuKind()
    if (kind === "prefs" && dx !== 0) {
      var focused = root.activeMenuRows()[root.menuSel]
      if (focused && typeof focused.adjust === "function") {
        focused.adjust(dx)
        return
      }
    }
    if (kind !== "") {
      root.menuMove(dx !== 0 ? dx : dy)
      return
    }
    var dir = dx !== 0 ? dx : dy
    var total = entriesModel.count + 1  // + add button
    if (total <= 0) { root.keySel = -1; return }
    if (root.keySel < 0) root.keySel = dir > 0 ? 0 : total - 1
    else root.keySel = (root.keySel + dir + total) % total
  }

  function keyTrigger(space) {
    root.keepAlive()
    var kind = root.activeMenuKind()
    if (kind !== "") { root.menuTrigger(); return }
    if (root.keySel === entriesModel.count) {
      root.openGrid()
      Qt.callLater(function() { if (root.gridOpen) appGrid.focusSearch() })
      return
    }
    var entry = root.entryFromModel(root.keySel)
    if (!entry) return
    if (space) {
      var wins = root.windowsFor(entry)
      if (wins.length > 1) root.cycleWindow(entry, 1)
      else root.focusApp(entry)
    } else {
      root.focusApp(entry)
    }
  }

  function keyEscape() {
    if (root.gridOpen) { root.closeGrid(); root.refocusKeys(); return }
    if (root.detailOpen) { root.closeDetails(true); return }
    if (root.menuOpen) { root.closeMenu(); return }
    if (root.prefsOpen) { root.closePrefs(); return }
    root.close()
  }

  function menuMove(dy) {
    root.keepAlive()
    var kind = root.activeMenuKind()
    var rows = root.activeMenuRows()
    if (rows.length === 0) return
    root.menuSel = (root.menuSel + dy + rows.length) % rows.length
    root.refreshMenuHighlight()
    if (kind === "prefs") root.scrollPrefsToSel()
    else if (kind === "menu") root.scrollMenuToSel()
  }

  // Keep the highlighted prefs row visible inside the scrollable menu.
  function scrollPrefsToSel() {
    var rows = root.activeMenuRows()
    if (rows.length === 0 || root.menuSel < 0 || root.menuSel >= rows.length) return
    var row = rows[root.menuSel]
    var flick = prefsScroll.contentItem  // the ScrollView's internal Flickable
    if (!flick) return
    var target = row.y - flick.height / 2 + row.height / 2
    flick.contentY = Math.max(0, Math.min(target, flick.contentHeight - flick.height))
  }

  // Scroll only when the highlighted row lives in the windows list; the
  // fixed menu actions around it should not move the list.
  function scrollMenuToSel() {
    var rows = root.activeMenuRows()
    if (root.menuSel < 0 || root.menuSel >= rows.length) return
    var row = rows[root.menuSel]
    var inside = false
    for (var i = 0; i < menuWinRepeater.count; i++) {
      if (menuWinRepeater.itemAt(i) === row) { inside = true; break }
    }
    if (!inside) return
    var flick = menuScroll.contentItem
    if (!flick) return
    var target = row.y - flick.height / 2 + row.height / 2
    flick.contentY = Math.max(0, Math.min(target, flick.contentHeight - flick.height))
  }

  function menuTrigger() {
    root.keepAlive()
    var kind = root.activeMenuKind()
    if (kind === "detail") return
    var rows = root.activeMenuRows()
    if (rows.length === 0) return
    root.menuSel = Math.min(root.menuSel, rows.length - 1)
    var row = rows[root.menuSel]
    if (row && typeof row.trigger === "function") row.trigger()
  }

  // Open the application grid (the keyboard path then focuses its search).
  function openGrid() {
    root.prefsOpen = false
    root.menuOpen = false
    root.detailOpen = false
    root.gridOpen = true
  }

  function setScreenPref(name) {
    var value = String(name || "")
    if (value !== "") {
      var screens = Quickshell.screens || []
      var known = false
      for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === value) { known = true; break }
      }
      if (!known) return
    }
    root.screenPref = value
    root.saveSettings()
    root.dismiss()
  }

  function setHideDelay(ms) {
    var next = parseInt(ms, 10)
    if (!isFinite(next) || next < 250 || next > 30000) return
    root.hideDelay = next
    root.saveSettings()
  }

  function setShowName(on) {
    root.showName = on
    root.saveSettings()
  }

  function setShowOnHover(on) {
    root.showOnHover = on
    root.saveSettings()
  }

  function setIconSize(size) {
    var value = parseInt(size, 10)
    if (!isFinite(value) || value < 24 || value > 96) return
    root.iconSize = value
    root.saveSettings()
  }

  function setZoom(value) {
    var next = Number(value)
    if (!isFinite(next) || next < 1.0 || next > 2.5) return
    root.zoom = next
    root.saveSettings()
  }

  function setPaddingX(value) {
    var next = parseInt(value, 10)
    if (!isFinite(next) || next < 0 || next > 64) return
    root.paddingX = next
    root.saveSettings()
  }

  function setPaddingY(value) {
    var next = parseInt(value, 10)
    if (!isFinite(next) || next < 0 || next > 64) return
    root.paddingY = next
    root.saveSettings()
  }

  function setIconSpacing(value) {
    var next = parseInt(value, 10)
    if (!isFinite(next) || next < 0 || next > 48) return
    root.iconSpacing = next
    root.saveSettings()
  }

  function setAnimMode(mode) {
    if (!root.isValidAnimMode(mode)) return
    root.animMode = mode
    root.saveSettings()
  }

  function setAnimSpeed(speed) {
    if (["fast", "normal", "slow"].indexOf(speed) < 0) return
    root.animSpeed = speed
    root.saveSettings()
  }

  function setGridColumns(value) {
    var next = parseInt(value, 10)
    if (!isFinite(next) || next < 3 || next > 12) return
    root.gridColumns = next
    root.saveSettings()
  }

  function setGridRows(value) {
    var next = parseInt(value, 10)
    if (!isFinite(next) || next < 1 || next > 10) return
    root.gridRows = next
    root.saveSettings()
  }

  function setGridShowLabels(on) {
    root.gridShowLabels = on === true
    root.saveSettings()
  }

  function saveSettings() {
    var json = JSON.stringify({
      screen: root.screenPref,
      hideDelay: root.hideDelay,
      animMode: root.animMode,
      animSpeed: root.animSpeed,
      showName: root.showName,
      showOnHover: root.showOnHover,
      iconSize: root.iconSize,
      zoom: root.zoom,
      paddingX: root.paddingX,
      paddingY: root.paddingY,
      iconSpacing: root.iconSpacing,
      gridColumns: root.gridColumns,
      gridRows: root.gridRows,
      gridShowLabels: root.gridShowLabels
    })
    settingsView.setText(json + "\n")
  }

  function dismiss() {
    root.opened = false
    root.closeGrid()
    root.menuOpen = false
    root.detailOpen = false
    root.prefsOpen = false
  }

  // Sticky "shown" state driven by pointer presence. ALT + SPACE (opened) is
  // handled separately in open() and also auto-hides after the keyboard
  // delay. Pointer-driven hides use the configured hideDelay again.
  function refreshHovering() {
    // An open panel keeps the Quay alive even when the pointer is over a
    // child surface the hover handler cannot see (or briefly leaves it while
    // scrolling). Panels close explicitly, not through the hover timer.
    // Pointer reveal is optional; an already-open Quay (shortcut or an
    // existing hover) still stays alive while the pointer is over it.
    var keepAlive = root.windowHover || root.dragActive || root.panelOpen
    var show = keepAlive && (root.showOnHover || root.hovering || root.opened)
    if (show) {
      root.hovering = true
      root.sliding = false
      hideTimer.stop()
    } else if (root.hovering && !hideTimer.running) {
      root.keyboardSession = false
      hideTimer.restart()
    }
  }

  onWindowHoverChanged: refreshHovering()
  onGridOpenChanged: refreshHovering()
  onMenuOpenChanged: refreshHovering()
  onDetailOpenChanged: refreshHovering()
  onMenuIndexChanged: refreshHovering()
  onDetailIndexChanged: refreshHovering()
  onPrefsOpenChanged: refreshHovering()
  onDragActiveChanged: refreshHovering()
  onShowOnHoverChanged: refreshHovering()

  // Keyboard focus follows the ALT + SPACE summon: prime briefly with Exclusive
  // (the Quay window is always mapped, so OnDemand alone never re-grabs
  // focus), then settle on OnDemand so pointer hit-testing is released
  // to the rest of the compositor.
  onOpenedChanged: {
    if (root.opened) {
      root.focusPrimed = false
      focusPrimeTimer.restart()
      root.refocusKeys()
    } else {
      root.focusPrimed = false
      focusPrimeTimer.stop()
    }
  }

  onFavoritesChanged: root.rebuildEntries()

  function pinApp(id) {
    var nid = Model.normalizeId(id)
    if (!nid) return
    if (root.isPinned(nid)) return
    var resolved = root.resolveFavorites([nid])
    if (resolved.length === 0) return
    root.applyFavoriteOrder(root.favorites.concat(resolved[0]))
  }

  // ---- pointer reorder ----

  function beginIconDrag(index, x) {
    var entry = root.entryFromModel(index)
    if (!entry) return
    root.dragEntry = entry
    root.dragIndex = index
    root.dragSlot = index
    root.dragX = x
    root.dragActive = true
    root.hoveredIndex = -1
    root.menuOpen = false
    root.detailOpen = false
    root.prefsOpen = false
    hideTimer.stop()
  }

  function updateIconDrag(x) {
    if (!root.dragActive) return
    root.dragX = x
    var count = entriesModel.count
    root.dragSlot = Math.max(0, Math.min(count, Math.round(x / root.iconSlotWidth)))
  }

  function endIconDrag() {
    if (!root.dragActive) return
    var entry = root.dragEntry
    var fromIndex = root.dragIndex
    var slot = root.dragSlot
    root.dragActive = false
    root.dragIndex = -1
    root.dragSlot = -1
    root.dragEntry = null
    root.suppressIconClick = true
    if (entry) root.moveEntryToSlot(entry, fromIndex, slot)
  }

  function cancelIconDrag() {
    root.dragActive = false
    root.dragIndex = -1
    root.dragSlot = -1
    root.dragEntry = null
  }

  // `slot` is a boundary in the merged Quay list (0..count). Pinned items
  // move within the favourites; an unpinned running item is inserted at the
  // same boundary, which pins it there.
  function moveEntryToSlot(entry, fromIndex, slot) {
    if (!entry || slot < 0) return
    if (slot === fromIndex || slot === fromIndex + 1) return
    var display = root.favorites.slice()
    var nid = Model.normalizeId(entry.id)
    var from = -1
    for (var i = 0; i < display.length; i++) {
      if (Model.normalizeId(display[i].id) === nid) { from = i; break }
    }
    if (from >= 0) {
      var moved = display.splice(from, 1)[0]
      var insert = slot > from ? slot - 1 : slot
      insert = Math.max(0, Math.min(insert, display.length))
      display.splice(insert, 0, moved)
    } else {
      var resolved = root.resolveFavorites([nid])
      if (resolved.length === 0) return
      var insertAt = Math.max(0, Math.min(slot, display.length))
      display.splice(insertAt, 0, resolved[0])
    }
    root.applyFavoriteOrder(display)
  }

  function closeGrid() {
    root.gridOpen = false
  }

  // Tab toggles focus between the grid's search field and its settings
  // button. Focus must be forced explicitly: blurring the field leaves
  // activeFocus null and no key would reach the catcher anymore.
  function toggleGridFocus() {
    root.keepAlive()
    if (appGrid.gearSelected) {
      appGrid.gearSelected = false
      appGrid.focusSearch()
    } else {
      appGrid.gearSelected = true
      quayKeys.forceActiveFocus()
    }
  }

  // A printable key typed while the dock is open starts a grid search. The
  // keyboard session is already active; typing is the fastest launcher path.
  function isSearchCharacter(event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
    var text = String(event.text || "")
    if (text.length !== 1) return false
    return text.charCodeAt(0) >= 0x21
  }

  function beginGridSearch(text) {
    root.openGrid()
    appGrid.startSearch(text)
  }

  // 3×3 dot glyph for the application-grid button. Drawn from theme colors
  // instead of a text character so it stays crisp and consistent.
  component AppGridGlyph: Item {
    id: glyph
    property color glyphColor: Commons.Color.popups.text
    property real dotSize: Style.space(3)
    property real dotGap: Style.space(5)

    implicitWidth: 3 * glyph.dotSize + 2 * glyph.dotGap
    implicitHeight: implicitWidth

    Repeater {
      model: 9
      Rectangle {
        required property int index
        width: glyph.dotSize
        height: width
        radius: width / 2
        x: (index % 3) * (glyph.dotSize + glyph.dotGap)
        y: Math.floor(index / 3) * (glyph.dotSize + glyph.dotGap)
        color: glyph.glyphColor
      }
    }
  }

  component PrefsInfo: Item {
    property string label: ""
    property string value: ""
    width: parent ? parent.width : 0
    height: Math.max(Style.space(30), Math.ceil(Style.font.body + Style.space(12)))

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.right: valueText.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: label
      color: Commons.Color.popups.text
      opacity: 0.52
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      id: valueText
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: value
      color: Commons.Color.popups.text
      opacity: 0.88
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  component DetailField: Item {
    id: field
    property string label: ""
    property string value: ""
    property bool wrapValue: false
    width: parent ? parent.width : 0
    height: fieldColumn.implicitHeight

    Column {
      id: fieldColumn
      width: parent.width
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: field.label.toUpperCase()
        color: Commons.Color.popups.text
        opacity: 0.48
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: field.value
        color: Commons.Color.popups.text
        opacity: 0.88
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: field.wrapValue ? Text.WrapAnywhere : Text.NoWrap
        elide: field.wrapValue ? Text.ElideNone : Text.ElideRight
      }
    }
  }

  FileView {
    id: favoritesView
    path: root.favoritesFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      // An existing `[]` is a deliberate empty Quay; only a missing file
      // falls back to the default favorites.
      root.favoriteIds = Model.parseFavorites(text())
      root.favorites = root.resolveFavorites(root.favoriteIds)
    }
    onLoadFailed: {
      if (root.favoriteIds.length === 0) {
        root.favoriteIds = Model.defaultFavorites()
        root.favorites = root.resolveFavorites(root.favoriteIds)
        root.saveFavorites()
      }
    }
    onFileChanged: reload()
  }

  // Read the Quay's persisted preferences (screen selection).
  FileView {
    id: settingsView
    path: root.settingsFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var obj = JSON.parse(String(text() || ""))
        root.screenPref = String(obj.screen || "")
        var d = parseInt(obj.hideDelay, 10)
        if (d > 0) root.hideDelay = d
        var am = String(obj.animMode || "")
        if (am === "fadeSlide") am = "fade+slide"  // legacy single-name combo
        if (root.isValidAnimMode(am)) root.animMode = am
        var as = String(obj.animSpeed || "")
        if (["fast", "normal", "slow"].indexOf(as) >= 0) root.animSpeed = as
        root.showName = obj.showName === true
        root.showOnHover = obj.showOnHover !== false
        var size = parseInt(obj.iconSize, 10)
        if (size >= 24 && size <= 96) root.iconSize = size
        var zoom = Number(obj.zoom)
        if (isFinite(zoom) && zoom >= 1.0 && zoom <= 2.5) root.zoom = zoom
        var px = parseInt(obj.paddingX, 10)
        if (px >= 0 && px <= 64) root.paddingX = px
        var py = parseInt(obj.paddingY, 10)
        if (py >= 0 && py <= 64) root.paddingY = py
        var gap = parseInt(obj.iconSpacing, 10)
        if (gap >= 0 && gap <= 48) root.iconSpacing = gap
        var gc = parseInt(obj.gridColumns, 10)
        if (gc >= 3 && gc <= 12) root.gridColumns = gc
        var gr = parseInt(obj.gridRows, 10)
        if (gr >= 1 && gr <= 10) root.gridRows = gr
        root.gridShowLabels = obj.gridShowLabels !== false
      } catch (e) {
        root.screenPref = ""
      }
    }
  }

  // Poll Hyprland for running window classes to mark running favourites.
  Process {
    id: clientsProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.parseClients(String(text || ""))
    }
  }

  Timer {
    id: runningPoll
    interval: 2000
    // Poll only while Quay is visible or interactive. Hidden Quay costs no
    // hyprctl subprocess; showing it refreshes immediately.
    running: root.opened || root.hovering || root.panelOpen || root.dragActive
    triggeredOnStart: true
    repeat: true
    onTriggered: if (!clientsProc.running) clientsProc.running = true
  }

  // Brief compositor-wide Exclusive phase so the always-mapped Quay window
  // actually grabs keyboard focus when summoned (see onOpenedChanged).
  Timer {
    id: focusPrimeTimer
    interval: 75
    onTriggered: if (root.opened) root.focusPrimed = true
  }

  Timer {
    id: hideTimer
    interval: root.keyboardSession ? root.keyboardHideDelay : root.hideDelay
    onTriggered: {
      if (root.panelOpen || root.dragActive) return
      root.hovering = false
      root.sliding = true
      slideTimer.restart()
      root.dismiss()
    }
  }

  Timer {
    id: slideTimer
    interval: root.animDuration
    onTriggered: root.sliding = false
  }

  // Overlay contract used by `omarchy-shell shell toggle io.github.apachaiz.quay`.
  // The ALT + SPACE summon is a keyboard flow: it gets the 10 s keyboard delay.
  function open(payloadJson) {
    root.opened = true
    root.hovering = true
    root.sliding = false
    root.keySel = entriesModel.count > 0 ? 0 : -1
    root.keyboardSession = true
    hideTimer.restart()
  }
  function close() {
    root.opened = false
    root.closeGrid()
    root.menuOpen = false
    root.detailOpen = false
    root.prefsOpen = false
    root.hovering = false
    root.sliding = true
    hideTimer.stop()
    slideTimer.restart()
  }

  IpcHandler {
    target: "io.github.apachaiz.quay"

    function open(): void { root.open("{}") }
    function close(): void { root.close() }
    function toggle(): void {
      if (root.opened) root.close()
      else root.open("{}")
    }
    function settings(): void {
      root.open("{}")
      root.openPrefs()
    }
  }

  // Both windows are single layer surfaces tied to one screen. When an
  // output disappears — suspend/resume, monitor hotplug, or Hyprland's
  // FALLBACK placeholder — the compositor destroys the surface. Quickshell
  // keeps the QML object alive but never maps it again, leaving the dock
  // invisible (its IPC still answers) until the whole shell restarts.
  // Toggling visible on every screens change forces a fresh wl_surface
  // against the (now valid) targetScreen.
  property bool surfacesEnabled: true
  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.surfacesEnabled = false
      surfaceRemapTimer.restart()
    }
  }
  Timer {
    id: surfaceRemapTimer
    interval: 100
    onTriggered: root.surfacesEnabled = true
  }

  // Full-screen transparent scrim: closes the Quay when clicking outside it.
  PanelWindow {
    id: scrimWindow
    visible: root.surfacesEnabled && root.overlayActive
    screen: root.targetScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quay-scrim"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }
  }

  PanelWindow {
    id: quayWindow
    visible: root.surfacesEnabled
    screen: root.targetScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quay"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive while the grid's search field needs typing, or during the
    // brief focus prime after a ALT + SPACE summon; OnDemand otherwise while
    // opened (keeps keyboard focus without monopolizing pointer hit-testing).
    WlrLayershell.keyboardFocus: root.gridOpen ? WlrKeyboardFocus.Exclusive
      : (root.opened ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None)
    anchors { bottom: true; left: true; right: true }
    // A constant full-height surface is intentional. If this height followed
    // the open panel, every menu would resize the layer surface and make the
    // dock look like it jumps while the panel opens. The mask below keeps the
    // transparent area click-through.
    implicitHeight: root.screenHeight

    // Only the visible card, panels, and the reveal strip accept input. The
    // rest of this full-sized layer stays click-through to the windows below.
    // Panels use their logical `shown` state (not `visible`) so the input
    // region ends as soon as a panel starts fading out.
    mask: Region {
      Region {
        x: 0
        y: quayWindow.height - 8
        width: quayWindow.width
        height: 8
      }
      Region {
        x: card.x
        y: card.y
        width: root.hovering ? card.width : 0
        height: root.hovering ? card.height : 0
      }
      Region {
        x: appGrid.x
        y: appGrid.y
        width: appGrid.shown ? appGrid.width : 0
        height: appGrid.shown ? appGrid.height : 0
      }
      Region {
        x: contextMenu.x
        y: contextMenu.y
        width: contextMenu.shown ? contextMenu.width : 0
        height: contextMenu.shown ? contextMenu.height : 0
      }
      Region {
        x: detailPanel.x
        y: detailPanel.y
        width: detailPanel.shown ? detailPanel.width : 0
        height: detailPanel.shown ? detailPanel.height : 0
      }
      Region {
        x: prefsMenu.x
        y: prefsMenu.y
        width: prefsMenu.shown ? prefsMenu.width : 0
        height: prefsMenu.shown ? prefsMenu.height : 0
      }
    }

    // ---- Keyboard handler (active when the Quay has keyboard focus) ----
    // Wraps ALL window content: Keys.priority BeforeItem only reaches
    // handlers that are ancestors of the focused item, so the catcher must
    // contain the grid's search field to keep seeing keys while typing
    // (it then forwards everything except Escape to the field).
    Item {
      id: quayKeys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem

      Keys.onPressed: function(event) {
        if (root.gridOpen) {
          if (event.isAutoRepeat) {
            // Held arrows keep stepping the grid; single-shot keys don't.
            root.keepAlive()
            var repeatX = event.key === Qt.Key_Left ? -1 : (event.key === Qt.Key_Right ? 1 : 0)
            var repeatY = event.key === Qt.Key_Up ? -1 : (event.key === Qt.Key_Down ? 1 : 0)
            if (repeatX !== 0 || repeatY !== 0) {
              event.accepted = true
              appGrid.moveSelection(repeatX, repeatY)
            }
            return
          }
          root.keepAlive()
          if (event.key === Qt.Key_Escape) {
            event.accepted = true
            root.closeGrid()
            root.refocusKeys()
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            event.accepted = true
            root.toggleGridFocus()
          } else if (event.key === Qt.Key_Left) {
            event.accepted = true
            appGrid.moveSelection(-1, 0)
          } else if (event.key === Qt.Key_Right) {
            event.accepted = true
            appGrid.moveSelection(1, 0)
          } else if (event.key === Qt.Key_Up) {
            event.accepted = true
            appGrid.moveSelection(0, -1)
          } else if (event.key === Qt.Key_Down) {
            event.accepted = true
            appGrid.moveSelection(0, 1)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true
            if (appGrid.gearSelected) root.openPrefs()
            else appGrid.activate()
          } else if (event.key === Qt.Key_Space && appGrid.gearSelected) {
            event.accepted = true
            root.openPrefs()
          } else if (appGrid.gearSelected && root.isSearchCharacter(event)) {
            event.accepted = true
            appGrid.appendSearch(event.text)
          }
          // Everything else falls through to the focused item (typing).
          return
        }
        // Super is intentionally NOT handled: Hyprland's own release-bound
        // ALT + SPACE toggle closes the Quay. Consuming it here made our close
        // race the bind and the follow-up toggle re-summon the Quay.
        if (event.isAutoRepeat) {
          // Held arrows keep stepping the selection one cell per repeat.
          if (event.key === Qt.Key_Left) { event.accepted = true; root.keyNav(-1, 0); return }
          if (event.key === Qt.Key_Right) { event.accepted = true; root.keyNav(1, 0); return }
          if (event.key === Qt.Key_Up) { event.accepted = true; root.keyNav(0, -1); return }
          if (event.key === Qt.Key_Down) { event.accepted = true; root.keyNav(0, 1); return }
          return
        }
        if (event.key === Qt.Key_Escape) {
          event.accepted = true
          root.keyEscape()
          return
        }
        if (event.key === Qt.Key_Left) { event.accepted = true; root.keyNav(-1, 0); return }
        if (event.key === Qt.Key_Right) { event.accepted = true; root.keyNav(1, 0); return }
        if (event.key === Qt.Key_Up) { event.accepted = true; root.keyNav(0, -1); return }
        if (event.key === Qt.Key_Down) { event.accepted = true; root.keyNav(0, 1); return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          event.accepted = true
          root.keyTrigger(false)
          return
        }
        if (event.key === Qt.Key_Space) {
          event.accepted = true
          root.keyTrigger(true)
          return
        }
        // Type-to-search: a letter or number while the dock is open summons
        // the application grid with that character already in the filter.
        if (!root.panelOpen && root.isSearchCharacter(event)) {
          event.accepted = true
          root.beginGridSearch(event.text)
          return
        }
      }

      // Background click-catcher: dismiss when clicking empty areas of the panel.
      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }

      // Tracks whether the pointer is over any part of the Quay window
      // (card or any open menu), to drive the delayed hide/auto-close.
      HoverHandler {
        id: windowHoverHandler
        onHoveredChanged: root.windowHover = hovered
      }

    // ---- Application grid, shown when gridOpen ----
    AppGrid {
      id: appGrid
      shown: root.gridOpen && root.quayShown
      fadeDuration: root.panelFadeDuration
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: 8
      columns: root.gridColumns
      rows: root.gridRows
      showLabels: root.gridShowLabels
      maxPanelWidth: Math.max(Style.space(260), parent.width - 2 * Style.space(16))
      maxPanelHeight: root.panelMaxHeight
      iconResolver: function(icon) { return root.iconPathFor(icon) }
      isPinnedFn: function(id) { return root.isPinned(id) }
      isRunningFn: function(id) { return root.isRunningId(id) }
      onAppActivated: function(app) {
        root.launchApp(app)
        root.dismiss()
      }
      onPinToggled: function(app) {
        if (root.isPinned(app.id)) root.unpinApp(app.id)
        else root.pinApp(app.id)
      }
      onSettingsRequested: root.openPrefs()
      onCloseRequested: {
        root.closeGrid()
        root.refocusKeys()
      }
    }

    // ---- Quay card ----
    Rectangle {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 10
      width: Math.min(iconsRow.width + 2 * root.paddingX, parent.width - 32)
      height: root.cardHeight
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1

      // Arrival/departure animation, configurable via the settings menu.
      opacity: root.animUsesFade() ? (root.hovering ? 1 : 0) : 1
      Behavior on opacity {
        NumberAnimation {
          duration: root.animDuration
          // Keep the fade in step with the zoom's faster finish.
          easing.type: root.animHas("zoom") ? Easing.OutQuad : Easing.OutCubic
        }
      }

      // Blur component: the card materializes blurred then sharpens.
      layer.enabled: root.animHas("blur") && (root.hovering || root.sliding)
      layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 32
        blur: root.hovering ? 0 : 0.6
        Behavior on blur {
          NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }
      }

      transform: [
        Translate {
          y: (root.animHas("slide") || root.animHas("bounce")) ? (root.hovering ? 0 : 112) : 0
          Behavior on y {
            NumberAnimation {
              duration: root.animDuration
              // Bounce overshoots slightly past the resting position.
              easing.type: root.animHas("bounce") ? Easing.OutBack : Easing.OutCubic
            }
          }
        },
        // Horizontal glide from the left screen edge.
        Translate {
          x: root.animHas("slideH") ? (root.hovering ? 0 : -(quayWindow.width + card.width) / 2) : 0
          Behavior on x {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
          }
        },
        Scale {
          origin.y: card.height
          // More travel (0.3 → 1) and a faster-finishing curve: the old
          // 0.6 → 1 with OutCubic crawled and read as slow motion.
          yScale: root.animHas("scale") ? (root.hovering ? 1 : 0.3) : 1
          Behavior on yScale {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutQuad }
          }
        },
        // Zoom: grows from the center of the card (with a fade via opacity).
        Scale {
          origin.x: card.width / 2
          origin.y: card.height / 2
          xScale: root.animHas("zoom") ? (root.hovering ? 1 : 0.4) : 1
          yScale: root.animHas("zoom") ? (root.hovering ? 1 : 0.4) : 1
          Behavior on xScale {
            // OutQuad: OutCubic left a slow crawl on the last 8% of the
            // growth, which read as a sluggish hitch.
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutQuad }
          }
          Behavior on yScale {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutQuad }
          }
        }
      ]

      HoverHandler {
        id: cardHover
        onHoveredChanged: if (!hovered) root.hoveredIndex = -1
      }

      // Empty card areas: right-click opens preferences (as documented), and
      // a left click is consumed instead of dismissing the Quay when the user
      // misses an icon.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openPrefs()
        }
      }

      Item {
        id: iconsRow
        anchors.centerIn: parent
        width: root.slotXFor(entriesModel.count) + 48
        height: root.cardHeight

        ListView {
          id: iconList
          width: root.slotXFor(entriesModel.count)
          height: root.cardHeight
          orientation: ListView.Horizontal
          interactive: false
          model: entriesModel

          delegate: Item {
            id: iconItem
            required property string appId
            required property string name
            required property string icon
            required property bool running
            required property int winCount
            required property int index

            width: root.iconSlotWidth
            height: root.cardHeight

            Accessible.role: Accessible.Button
            Accessible.name: name
            Accessible.onPressAction: {
              var entry = root.entryFromModel(index)
              if (entry && entry.running) root.focusApp(entry)
              else root.launchApp(entry)
            }

            // Stagger component: icons cascade in one by one. A per-index
            // Timer flips staggerIn after its delay; the Behavior only fades
            // (SequentialAnimation inside a Behavior hits a Qt bug with
            // negative durations on retargeting).
            property bool staggerIn: false
            readonly property bool dragSource: root.dragActive && root.dragIndex === index
            opacity: dragSource ? 0 : (root.animHas("stagger") ? (iconItem.staggerIn ? 1 : 0) : 1)
            Behavior on opacity {
              enabled: root.animHas("stagger")
              // Short fade so the cascade finishes alongside the card
              // instead of trailing it (which read as slow motion).
              NumberAnimation { duration: Math.min(root.animDuration, 140); easing.type: Easing.OutCubic }
            }

            function syncStagger() {
              if (!root.animHas("stagger")) { iconItem.staggerIn = true; staggerTimer.stop(); return }
              if (root.hovering || root.sliding) staggerTimer.restart()
              else { staggerTimer.stop(); iconItem.staggerIn = false }
            }

            Timer {
              id: staggerTimer
              interval: index * 12
              onTriggered: iconItem.staggerIn = true
            }

            Connections {
              target: root
              function onHoveringChanged() { iconItem.syncStagger() }
              function onSlidingChanged() { iconItem.syncStagger() }
              function onAnimModeChanged() { iconItem.syncStagger() }
            }
            Component.onCompleted: iconItem.syncStagger()

            HoverHandler {
              id: iconHover
              onHoveredChanged: {
                if (hovered && !root.dragActive) root.hoveredIndex = index
                else if (!hovered && root.hoveredIndex === index) root.hoveredIndex = -1
              }
            }

            Image {
              anchors.centerIn: parent
              width: root.iconSize
              height: root.iconSize
              source: root.iconPathFor(icon)
              smooth: true
              mipmap: true
              antialiasing: true
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              scale: Model.iconScale(index, root.activeIconIndex, root.zoom)
              transformOrigin: Item.Center

              Behavior on scale {
                NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
              }
            }

            Row {
              visible: winCount > 0
              anchors.horizontalCenter: parent.horizontalCenter
              y: parent.height / 2 + (root.iconSize / 2) * Model.iconScale(index, root.activeIconIndex, root.zoom) + 2
              spacing: 3

              Behavior on y {
                NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
              }

              // Cap the indicators: a busy app should not stretch its slot.
              Repeater {
                model: Math.min(winCount, 4)
                delegate: Rectangle {
                  width: 5
                  height: 5
                  radius: 2.5
                  color: Commons.Color.accent
                }
              }
            }

            MouseArea {
              id: iconMouse
              anchors.fill: parent
              cursorShape: root.dragActive && root.dragIndex === index
                ? Qt.ClosedHandCursor : Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
              preventStealing: true

              property real pressX: 0
              property bool pressedLeft: false

              onPressed: function(mouse) {
                if (mouse.button !== Qt.LeftButton) return
                root.keepAlive()
                root.suppressIconClick = false
                pressedLeft = true
                pressX = mapToItem(iconsRow, mouse.x, 0).x
              }
              onPositionChanged: function(mouse) {
                if (!pressedLeft || !(mouse.buttons & Qt.LeftButton)) return
                var x = mapToItem(iconsRow, mouse.x, 0).x
                if (!root.dragActive && Math.abs(x - pressX) >= 6)
                  root.beginIconDrag(index, pressX)
                if (root.dragActive && root.dragIndex === index)
                  root.updateIconDrag(x)
              }
              onReleased: function(mouse) {
                if (mouse.button !== Qt.LeftButton) return
                pressedLeft = false
                if (root.dragActive) root.endIconDrag()
              }
              onCanceled: {
                pressedLeft = false
                if (root.dragActive) root.cancelIconDrag()
              }
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) root.openMenu(index)
                else if (mouse.button === Qt.MiddleButton) root.launchNewWindow(root.entryFromModel(index))
                else {
                  if (root.suppressIconClick) { root.suppressIconClick = false; return }
                  var entry = root.entryFromModel(index)
                  if (entry && entry.running) root.focusApp(entry)
                  else root.launchApp(entry)
                }
              }
              onWheel: function(wheel) {
                if (wheel.angleDelta.y !== 0) {
                  root.cycleWindow(root.entryFromModel(index), wheel.angleDelta.y > 0 ? -1 : 1)
                }
              }
            }

            Ui.PanelToolTip {
              visible: !root.dragActive && root.showName
                && (iconHover.hovered || (root.keySel === index && root.opened))
              text: name
              delay: iconHover.hovered ? 400 : 0
            }
          }
        }

        // Separator between the pinned favorites and the running apps that
        // are not pinned, so the two groups read as one rail without looking
        // like a single undifferentiated list.
        Rectangle {
          visible: root.favorites.length > 0 && entriesModel.count > root.favorites.length
          x: root.slotXFor(root.favorites.length) - width / 2
          anchors.verticalCenter: parent.verticalCenter
          width: 1
          height: Math.max(Style.space(18), Math.round(root.iconSize * 0.55))
          color: Util.alpha(Commons.Color.popups.text, 0.18)
          z: 70
        }

        // Insertion marker: the slot boundary where the icon will land.
        Rectangle {
          id: dropMarker
          visible: root.dragActive && root.dragSlot >= 0
          x: root.dragSlot * root.iconSlotWidth - 1
          y: Math.max(4, (root.cardHeight - height) / 2)
          width: 2
          height: Math.max(Style.space(44), root.iconSize * 1.1)
          radius: 1
          color: Commons.Color.accent
          z: 80
        }

        // Drag ghost: the original delegate fades out and this follows the
        // pointer along the rail, leaving the drop marker as the target.
        Image {
          id: dragGhost
          visible: root.dragActive && root.dragEntry !== null
          x: Math.max(-root.iconSize / 2, Math.min(iconsRow.width - root.iconSize / 2, root.dragX - root.iconSize / 2))
          y: (iconsRow.height - height) / 2
          width: root.iconSize
          height: root.iconSize
          source: root.dragEntry ? root.iconPathFor(root.dragEntry.icon) : ""
          smooth: true
          mipmap: true
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          opacity: 0.92
          scale: 1.06
          z: 90
        }

        // Application-grid button: a 3×3 dot glyph, quiet at rest and
        // accented while the grid is open.
        Item {
          id: addButton
          x: root.slotXFor(entriesModel.count)
          width: 48
          height: root.cardHeight

          readonly property real buttonSize: Math.min(Style.space(48),
            Math.max(Style.space(30), Math.round(root.iconSize * 0.75)))

          Accessible.role: Accessible.Button
          Accessible.name: root.gridOpen ? "Hide the app grid" : "All applications"
          Accessible.onPressAction: {
            if (root.gridOpen) root.closeGrid()
            else root.openGrid()
          }

          // Last element of the stagger cascade (same timer technique as
          // the icon delegates).
          property bool staggerIn: false
          opacity: root.animHas("stagger") ? (addButton.staggerIn ? 1 : 0) : 1
          Behavior on opacity {
            enabled: root.animHas("stagger")
            NumberAnimation { duration: Math.min(root.animDuration, 140); easing.type: Easing.OutCubic }
          }

          function syncStagger() {
            if (!root.animHas("stagger")) { addButton.staggerIn = true; addStaggerTimer.stop(); return }
            if (root.hovering || root.sliding) addStaggerTimer.restart()
            else { addStaggerTimer.stop(); addButton.staggerIn = false }
          }

          Timer {
            id: addStaggerTimer
            interval: entriesModel.count * 12
            onTriggered: addButton.staggerIn = true
          }

          Connections {
            target: root
            function onHoveringChanged() { addButton.syncStagger() }
            function onSlidingChanged() { addButton.syncStagger() }
            function onAnimModeChanged() { addButton.syncStagger() }
          }
          Component.onCompleted: addButton.syncStagger()

          Rectangle {
            anchors.centerIn: parent
            width: addButton.buttonSize
            height: width
            radius: width / 2
            color: root.gridOpen
              ? Style.selectedFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)
              : (addHover.hovered
                ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)
                : "transparent")
            border.width: 1
            border.color: root.gridOpen
              ? Commons.Color.accent
              : Util.alpha(Commons.Color.popups.text, addHover.hovered ? 0.5 : 0.26)
            Behavior on color { ColorAnimation { duration: 100 } }
          }

          AppGridGlyph {
            anchors.centerIn: parent
            dotSize: Math.max(Style.space(3), Math.round(addButton.buttonSize * 0.09))
            dotGap: Math.max(Style.space(4), Math.round(addButton.buttonSize * 0.16))
            glyphColor: root.gridOpen ? Commons.Color.accent : Commons.Color.popups.text
            opacity: addHover.hovered || root.gridOpen ? 1 : 0.82
          }

          HoverHandler {
            id: addHover
            onHoveredChanged: if (hovered) root.hoveredIndex = -1
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.gridOpen) root.closeGrid()
              else root.openGrid()
            }
          }

          Ui.PanelToolTip {
            visible: addHover.hovered
            text: root.gridOpen ? "Hide the app grid" : "All applications"
            delay: 450
          }

          // Keyboard selection ring when the add button is selected.
          Rectangle {
            visible: root.keySel === entriesModel.count && root.opened && !root.gridOpen
            anchors.centerIn: parent
            width: addButton.buttonSize + Style.space(8)
            height: width
            radius: width / 2
            color: "transparent"
            border.color: Commons.Color.accent
            border.width: 2
          }
        }
      }
    }

    // ---- Context menu (right-click on an icon) ----
    Rectangle {
      id: contextMenu
      property bool shown: root.menuOpen && root.menuEntry !== null
      visible: shown || opacity > 0.001
      opacity: shown ? 1 : 0
      enabled: shown
      anchors.bottom: card.top
      anchors.bottomMargin: 8
      x: Math.round(Math.max(Style.space(16),
        Math.min(root.menuAnchorX - width / 2, parent.width - width - Style.space(16))))
      width: Math.min(Style.space(300), parent.width - 32)
      height: Math.min(menuColumn.implicitHeight + 2 * contextMenu.menuMargin, root.panelMaxHeight)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1
      clip: true
      Behavior on opacity {
        NumberAnimation { duration: root.panelFadeDuration; easing.type: Easing.OutCubic }
      }

      readonly property int menuMargin: Style.space(6)

      // Consume clicks on the menu's padding; only the scrim outside closes.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
      }

      Column {
        id: menuColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: contextMenu.menuMargin
        spacing: Style.space(1)

        // Header: app icon, name, and a live running/window status.
        Item {
          width: parent.width
          height: Math.max(Style.space(50),
            Math.ceil(Style.font.title + Style.font.caption + Style.space(18)))

          Image {
            id: menuIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30)
            height: width
            source: root.menuEntry ? root.iconPathFor(root.menuEntry.icon) : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            sourceSize.width: width * 2
            sourceSize.height: height * 2
          }

          Column {
            anchors.left: menuIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: root.menuEntry ? root.menuEntry.name : ""
              textFormat: Text.PlainText
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.menuStatusText
              textFormat: Text.PlainText
              color: Commons.Color.popups.text
              opacity: 0.55
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(Commons.Color.popups.text, 0.12)
        }

        MenuRow {
          id: menuFocus
          icon: "▶"
          label: root.menuWindows.length > 0 ? "Focus window" : "Launch"
          onTriggered: root.focusApp(root.menuEntry)
        }

        MenuRow {
          id: menuNewWindow
          icon: "↗"
          label: "New window"
          visible: root.menuDesktopEntry
            && String(root.menuDesktopEntry.execString || "") !== ""
          onTriggered: {
            root.launchNewWindow(root.menuEntry)
            root.dismiss()
          }
        }

        MenuRow {
          id: menuPin
          icon: "★"
          visible: root.menuEntry ? !root.isPinned(root.menuEntry.id) : false
          label: "Pin to Quay"
          onTriggered: {
            root.pinApp(root.menuEntry.id)
            root.closeMenu()
          }
        }

        MenuRow {
          id: menuUnpin
          icon: "☆"
          visible: root.menuEntry ? root.isPinned(root.menuEntry.id) : false
          label: "Unpin from Quay"
          onTriggered: {
            root.unpinApp(root.menuEntry.id)
            root.closeMenu()
          }
        }

        Rectangle {
          visible: root.menuWindows.length > 0
          width: parent.width
          height: 1
          color: Util.alpha(Commons.Color.popups.text, 0.12)
        }

        SectionHeader {
          visible: root.menuWindows.length > 0
          title: "Windows"
        }

        ScrollView {
          id: menuScroll
          visible: root.menuWindows.length > 0
          width: parent.width
          height: Math.min(menuWinColumn.implicitHeight, Style.space(224))
          clip: true
          ScrollBar.vertical: SlimScrollBar { }
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

          Column {
            id: menuWinColumn
            width: menuScroll.width - Style.space(10)
            spacing: Style.space(1)

            Repeater {
              id: menuWinRepeater
              model: root.menuWindows

              delegate: MenuRow {
                required property var modelData
                icon: "▤"
                label: modelData.title
                detail: modelData.workspace !== ""
                  ? "Workspace " + modelData.workspace : ""
                trailingIcon: "×"
                trailingTooltip: "Close window"
                onTriggered: {
                  root.focusWindow(modelData.address)
                  root.closeMenu()
                }
                onTrailingTriggered: root.closeWindow(modelData.address)
              }
            }
          }
        }

        Rectangle {
          visible: root.menuWindows.length > 0
          width: parent.width
          height: 1
          color: Util.alpha(Commons.Color.popups.text, 0.12)
        }

        MenuRow {
          id: menuDetails
          icon: "ℹ"
          label: "Details"
          onTriggered: root.openDetails(root.menuIndex)
        }

        MenuRow {
          id: menuQuit
          icon: "⏻"
          danger: true
          visible: root.menuWindows.length > 0
          label: "Quit"
          onTriggered: root.quitApp(root.menuEntry)
        }
      }
    }

    // ---- Details panel ----
    Rectangle {
      id: detailPanel
      property bool shown: root.detailOpen && root.detailEntry !== null
      visible: shown || opacity > 0.001
      opacity: shown ? 1 : 0
      enabled: shown
      anchors.bottom: card.top
      anchors.bottomMargin: 8
      x: Math.round(Math.max(Style.space(16),
        Math.min(root.detailAnchorX - width / 2, parent.width - width - Style.space(16))))
      width: Math.min(Style.space(360), parent.width - 32)
      height: Math.min(detailColumn.implicitHeight + 2 * detailPanel.detailMargin,
        Math.min(root.panelMaxHeight, Style.space(460)))
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1
      clip: true
      Behavior on opacity {
        NumberAnimation { duration: root.panelFadeDuration; easing.type: Easing.OutCubic }
      }

      readonly property int detailMargin: Style.space(14)

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
      }

      ScrollView {
        id: detailScroll
        anchors.fill: parent
        anchors.margins: detailPanel.detailMargin
        anchors.rightMargin: detailPanel.detailMargin + Style.space(26)
        clip: true
        ScrollBar.vertical: SlimScrollBar { }
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          id: detailColumn
          width: detailScroll.availableWidth
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(10)

            Image {
              width: Style.space(36)
              height: width
              source: root.detailEntry ? root.iconPathFor(root.detailEntry.icon) : ""
              fillMode: Image.PreserveAspectFit
              smooth: true
              sourceSize.width: width * 2
              sourceSize.height: height * 2
            }

            Column {
              width: parent.width - Style.space(46)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.detailEntry ? root.detailEntry.name : ""
                textFormat: Text.PlainText
                color: Commons.Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: root.detailDesktopEntry
                  && String(root.detailDesktopEntry.genericName || "") !== ""
                text: root.detailDesktopEntry
                  ? String(root.detailDesktopEntry.genericName || "") : ""
                textFormat: Text.PlainText
                color: Commons.Color.popups.text
                opacity: 0.58
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }

          Text {
            width: parent.width
            visible: root.detailDesktopEntry
              && String(root.detailDesktopEntry.comment || "") !== ""
            text: root.detailDesktopEntry
              ? String(root.detailDesktopEntry.comment || "") : ""
            textFormat: Text.PlainText
            color: Commons.Color.popups.text
            opacity: 0.72
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(Commons.Color.popups.text, 0.12)
          }

          DetailField {
            label: "Status"
            value: root.detailStatusText
          }

          DetailField {
            label: "Desktop entry"
            value: root.detailEntry
              ? Model.normalizeId(root.detailEntry.id) + ".desktop" : ""
          }

          DetailField {
            visible: root.detailDesktopEntry
              && String(root.detailDesktopEntry.execString || "") !== ""
            label: "Command"
            value: root.detailDesktopEntry
              ? String(root.detailDesktopEntry.execString || "") : ""
            wrapValue: true
          }

          Ui.Button {
            visible: root.detailDesktopEntry
              && String(root.detailDesktopEntry.execString || "") !== ""
            text: "New window"
            bordered: true
            foreground: Commons.Color.popups.text
            accent: Commons.Color.accent
            onClicked: {
              root.launchNewWindow(root.detailEntry)
              root.dismiss()
            }
          }
        }
      }

      Ui.PanelActionButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(8)
        iconText: "×"
        tooltipText: "Back to the menu"
        foreground: Commons.Color.popups.text
        hoverColor: Commons.Color.accent
        size: Style.space(28)
        onClicked: root.closeDetails(true)
      }
    }

    // ---- Preferences (right-click on empty Quay area) ----
    Rectangle {
      id: prefsMenu
      property bool shown: root.prefsOpen
      visible: shown || opacity > 0.001
      opacity: shown ? 1 : 0
      enabled: shown
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: 8
      width: Math.min(Style.space(440), parent.width - 32)
      height: Math.min(root.prefsHeaderHeight + prefsBody.implicitHeight
        + root.prefsFooterHeight + 2, root.panelMaxHeight)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1
      clip: true
      Behavior on opacity {
        NumberAnimation { duration: root.panelFadeDuration; easing.type: Easing.OutCubic }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
      }

      Item {
        id: prefsHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.prefsHeaderHeight

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          text: "Quay settings"
          textFormat: Text.PlainText
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Ui.PanelActionButton {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(7)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "×"
          tooltipText: "Close settings"
          foreground: Commons.Color.popups.text
          hoverColor: Commons.Color.accent
          size: Style.space(30)
          onClicked: root.closePrefs()
        }
      }

      Ui.PanelSeparator {
        id: prefsHeaderRule
        anchors.top: prefsHeader.bottom
        width: parent.width
        foreground: Commons.Color.popups.text
      }

      ScrollView {
        id: prefsScroll
        anchors.top: prefsHeaderRule.bottom
        anchors.bottom: prefsFooter.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        clip: true
        ScrollBar.vertical: SlimScrollBar { }
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          id: prefsBody
          width: prefsScroll.availableWidth
          spacing: 0

          SectionHeader { title: "Placement" }

          MenuRow {
            id: prefsAuto
            label: "Automatic (widest screen)"
            checked: root.screenPref === ""
            onTriggered: root.setScreenPref("")
          }

          Repeater {
            id: prefsScreens
            model: Quickshell.screens

            delegate: MenuRow {
              required property var modelData
              label: modelData.name
              checked: root.screenPref === modelData.name
              onTriggered: root.setScreenPref(modelData.name)
            }
          }

          Ui.PanelSeparator {
            width: parent.width
            foreground: Commons.Color.popups.text
          }

          SectionHeader { title: "Behavior" }

          PrefsToggleRow {
            id: prefsShowOnHover
            label: "Hover reveal"
            description: "ALT + SPACE always opens Quay."
            checked: root.showOnHover
            onPicked: root.setShowOnHover(value)
          }

          PrefsRow {
            id: prefsHideDelay
            label: "Hide delay"
            options: [500, 1000, 1500, 2000, 3000]
            current: root.hideDelay
            formatValue: function(value) { return (value / 1000) + " s" }
            onPicked: root.setHideDelay(value)
          }

          PrefsToggleRow {
            id: prefsShowName
            label: "Name tooltip"
            checked: root.showName
            onPicked: root.setShowName(value)
          }

          Ui.PanelSeparator {
            width: parent.width
            foreground: Commons.Color.popups.text
          }

          SectionHeader { title: "Dock" }

          PrefsRow {
            id: prefsIconSize
            label: "Icon size"
            options: [32, 36, 40, 44, 48, 52, 56, 60, 64]
            current: root.iconSize
            formatValue: function(value) { return value + " px" }
            onPicked: root.setIconSize(value)
          }

          PrefsRow {
            id: prefsZoom
            label: "Hover zoom"
            options: [1.3, 1.5, 1.8]
            current: root.zoom
            formatValue: function(value) { return value + "×" }
            onPicked: root.setZoom(value)
          }

          PrefsRow {
            id: prefsGap
            label: "Icon gap"
            options: [0, 2, 4, 6, 8, 10, 12, 16, 20, 24]
            current: root.iconSpacing
            formatValue: function(value) { return value + " px" }
            onPicked: root.setIconSpacing(value)
          }

          PrefsRow {
            id: prefsPadX
            label: "Padding X"
            options: [4, 8, 12, 16, 20, 24]
            current: root.paddingX
            formatValue: function(value) { return value + " px" }
            onPicked: root.setPaddingX(value)
          }

          PrefsRow {
            id: prefsPadY
            label: "Padding Y"
            options: [2, 4, 5, 6, 8, 10, 12, 16]
            current: root.paddingY
            formatValue: function(value) { return value + " px" }
            onPicked: root.setPaddingY(value)
          }

          Ui.PanelSeparator {
            width: parent.width
            foreground: Commons.Color.popups.text
          }

          SectionHeader { title: "App grid" }

          PrefsRow {
            id: prefsGridColumns
            label: "Columns"
            options: [3, 4, 5, 6, 7, 8, 9, 10, 12]
            current: root.gridColumns
            formatValue: function(value) { return String(value) }
            onPicked: root.setGridColumns(value)
          }

          PrefsRow {
            id: prefsGridRows
            label: "Visible rows"
            options: [1, 2, 3, 4, 5, 6, 8, 10]
            current: root.gridRows
            formatValue: function(value) { return String(value) }
            onPicked: root.setGridRows(value)
          }

          PrefsToggleRow {
            id: prefsGridLabels
            label: "Tile labels"
            checked: root.gridShowLabels
            onPicked: root.setGridShowLabels(value)
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            leftPadding: Style.space(10)
            rightPadding: Style.space(10)
            topPadding: Style.space(2)
            bottomPadding: Style.space(4)
            text: "Type while Quay is open to start a search."
            color: Commons.Color.popups.text
            opacity: 0.42
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Ui.PanelSeparator {
            width: parent.width
            foreground: Commons.Color.popups.text
          }

          SectionHeader { title: "Bar motion" }

          PrefsRow {
            id: prefsAnimMode
            label: "Bar animation"
            options: root.animationModes
            current: root.animMode
            formatValue: function(value) { return root.animationLabel(value) }
            onPicked: root.setAnimMode(value)
          }

          PrefsRow {
            id: prefsSpeed
            label: "Bar speed"
            options: ["fast", "normal", "slow"]
            current: root.animSpeed
            formatValue: function(value) {
              return value.charAt(0).toUpperCase() + value.slice(1)
            }
            onPicked: root.setAnimSpeed(value)
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            leftPadding: Style.space(10)
            rightPadding: Style.space(10)
            topPadding: Style.space(2)
            bottomPadding: Style.space(4)
            text: "Menus and the app grid always use their own fixed fade."
            color: Commons.Color.popups.text
            opacity: 0.42
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Ui.PanelSeparator {
            width: parent.width
            foreground: Commons.Color.popups.text
          }

          SectionHeader { title: "About" }

          PrefsInfo {
            label: "Shortcut"
            value: "ALT + SPACE"
          }

          PrefsInfo {
            visible: root.quayVersion !== ""
            label: "Version"
            value: root.quayVersion
          }

          Item { width: 1; height: Style.space(6) }
        }
      }

      Item {
        id: prefsFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.prefsFooterHeight

        Ui.PanelSeparator {
          anchors.top: parent.top
          width: parent.width
          foreground: Commons.Color.popups.text
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: Style.space(1)
          text: "Changes save automatically"
          textFormat: Text.PlainText
          color: Commons.Color.popups.text
          opacity: 0.42
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        KeyHint {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: Style.space(1)
          keys: "Esc"
          label: "Close"
        }
      }
    }
  }
}
}
