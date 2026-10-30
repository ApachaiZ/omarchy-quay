import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQml.Models
import qs.Commons
import qs.Commons as Commons
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
  property bool edgeHover: false
  property bool windowHover: false
  property bool hovering: false
  property bool sliding: false
  readonly property bool quayShown: root.hovering
  readonly property bool overlayActive: root.opened || root.pickerOpen || root.menuIndex >= 0 || root.detailIndex >= 0 || root.prefsOpen
  readonly property bool panelOpen: root.pickerOpen || root.prefsOpen
    || root.menuIndex >= 0 || root.detailIndex >= 0
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
    if (root.pickerOpen || root.prefsOpen
        || root.menuIndex >= 0 || root.detailIndex >= 0) return -1
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
  property int appSel: -1              // selected app row in the picker list (-1 = none)
  property bool gearSel: false         // Tab focus on the picker's settings (gear) button
  property bool focusPrimed: false     // brief Exclusive prime before settling keyboard focus to OnDemand
  property bool pickerOpen: false
  property string searchText: ""
  property int menuIndex: -1
  property int detailIndex: -1
  property var cyclePos: ({})
  property string wheelTitle: ""
  property string screenPref: ""        // "" = auto (widest), else monitor name
  property int hideDelay: 1500          // ms the Quay/menus stay after hover ends
  property bool showName: false         // tooltip with the app name on hover/keyboard selection
  property int iconSize: 48             // base icon edge in px
  property real zoom: 1.8               // hovered icon scale
  property int paddingX: 12             // horizontal card padding
  property int paddingY: 5              // vertical card padding
  property int iconSpacing: 6           // gap between icon slots
  // Fixed slot width: reserve room for the configured zoom and its neighbour
  // once, so hovering never changes the row or the card width.
  readonly property real iconSlotWidth: Model.slotWidth(root.iconSize, root.zoom, root.iconSpacing)
  readonly property int cardHeight: Math.max(52 + 2 * root.paddingY,
    Math.ceil(root.iconSize * Math.max(1, root.zoom)) + 2 * root.paddingY)
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

  readonly property var filteredApps: Model.sortedAppList(
    DesktopEntries.applications.values || [], root.searchText)

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
  readonly property var detailEntry: root.entryFromModel(root.detailIndex)
  readonly property var detailDesktopEntry: root.detailEntry ? root.lookupDesktopEntry(root.detailEntry.id) : null


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
    var seen = ({})
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

  function isRunning(entry) {
    if (!entry || !entry.id) return false
    var id = Model.normalizeId(entry.id).toLowerCase()
    var classes = root.runningClasses
    for (var i = 0; i < classes.length; i++) {
      if (classes[i] === id) return true
    }
    return false
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
        clist.push({
          address: String(c.address || ""),
          cls: cls,
          title: String(c.title || "")
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
    var key = Model.normalizeId(entry.id)
    var pos = root.cyclePos[key] || 0
    pos = (pos + delta + wins.length) % wins.length
    root.cyclePos[key] = pos
    root.focusWindow(wins[pos].address)
    root.wheelTitle = wins[pos].title
    root.wheelFlash.restart()
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
    root.menuIndex = index
    root.detailIndex = -1
    root.closePicker()
    root.prefsOpen = false
    root.menuSel = 0
    Qt.callLater(function() { root.refreshMenuHighlight() })
  }

  function closeMenu() {
    root.menuIndex = -1
  }

  function openPrefs() {
    root.prefsOpen = true
    root.menuIndex = -1
    root.detailIndex = -1
    root.closePicker()
    root.menuSel = 0
    Qt.callLater(function() {
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
      if (root.opened && !root.pickerOpen) quayKeys.forceActiveFocus()
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
    if (root.menuIndex >= 0) return "menu"
    if (root.prefsOpen) return "prefs"
    if (root.detailIndex >= 0) return "detail"
    return ""
  }

  // Ordered interactive rows of the context menu. Rows carry `highlighted`
  // and `trigger()`; separators/headers are skipped.
  function menuRows() {
    var rows = [menuFocus]
    if (menuPin.visible) rows.push(menuPin)
    else if (menuUnpin.visible) rows.push(menuUnpin)
    for (var i = 0; i < menuWinRepeater.count; i++) rows.push(menuWinRepeater.itemAt(i))
    if (menuQuit.visible) rows.push(menuQuit)
    rows.push(menuDetails)
    return rows
  }

  function prefsRows() {
    var rows = [prefsAuto]
    for (var i = 0; i < prefsScreens.count; i++) rows.push(prefsScreens.itemAt(i))
    rows.push(prefsHideDelay, prefsShowName)
    rows.push(prefsIconSize, prefsZoom, prefsGap, prefsPadX, prefsPadY)
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
      root.openPicker()
      Qt.callLater(function() { if (root.pickerOpen) searchField.forceActiveFocus() })
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
    if (root.pickerOpen) { root.closePicker(); root.refocusKeys(); return }
    if (root.detailIndex >= 0) { root.detailIndex = -1; return }
    if (root.menuIndex >= 0) { root.closeMenu(); return }
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

  // Open the app picker (keyboard path calls this, then focuses the field).
  function openPicker() {
    root.prefsOpen = false
    root.menuIndex = -1
    root.detailIndex = -1
    root.appSel = -1
    root.gearSel = false
    root.pickerOpen = true
  }

  function setScreenPref(name) {
    root.screenPref = name
    root.saveSettings()
    root.dismiss()
  }

  function setHideDelay(ms) {
    root.hideDelay = ms
    root.saveSettings()
  }

  function setShowName(on) {
    root.showName = on
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
    root.animMode = mode
    root.saveSettings()
  }

  function setAnimSpeed(speed) {
    root.animSpeed = speed
    root.saveSettings()
  }

  function saveSettings() {
    var json = JSON.stringify({ screen: root.screenPref, hideDelay: root.hideDelay, animMode: root.animMode, animSpeed: root.animSpeed, showName: root.showName, iconSize: root.iconSize, zoom: root.zoom, paddingX: root.paddingX, paddingY: root.paddingY, iconSpacing: root.iconSpacing })
    settingsView.setText(json + "\n")
  }

  function dismiss() {
    root.opened = false
    root.closePicker()
    root.menuIndex = -1
    root.detailIndex = -1
    root.prefsOpen = false
  }

  // Sticky "shown" state driven by pointer presence. ALT + SPACE (opened) is
  // handled separately in open() and also auto-hides after the keyboard
  // delay. Pointer-driven hides use the configured hideDelay again.
  function refreshHovering() {
    // An open panel keeps the Quay alive even when the pointer is over a
    // child surface the hover handler cannot see (or briefly leaves it while
    // scrolling). Panels close explicitly, not through the hover timer.
    var show = root.windowHover || root.dragActive || root.panelOpen
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
  onEdgeHoverChanged: refreshHovering()
  onPickerOpenChanged: refreshHovering()
  onMenuIndexChanged: refreshHovering()
  onDetailIndexChanged: refreshHovering()
  onPrefsOpenChanged: refreshHovering()
  onDragActiveChanged: refreshHovering()

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
    root.menuIndex = -1
    root.detailIndex = -1
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

  function closePicker() {
    root.pickerOpen = false
    root.searchText = ""
    root.appSel = -1
    root.gearSel = false
  }

  // Tab toggles picker focus between the search field and the gear button.
  // Focus must be forced explicitly: blurring the field leaves activeFocus
  // null and no key would reach the catcher anymore.
  function togglePickerFocus() {
    root.keepAlive()
    root.gearSel = !root.gearSel
    if (root.gearSel) quayKeys.forceActiveFocus()
    else searchField.forceActiveFocus()
  }

  // Arrows in the picker move the highlighted app row.
  function pickerNav(dy) {
    root.keepAlive()
    var n = root.filteredApps.length
    if (n === 0) { root.appSel = -1; return }
    if (root.appSel < 0) root.appSel = dy > 0 ? 0 : n - 1
    else root.appSel = (root.appSel + dy + n) % n
    appList.positionViewAtIndex(root.appSel, ListView.Contain)
  }

  // Enter (or Space on the gear) in the picker: open the settings when the
  // gear is selected, else launch the highlighted app (or the first match).
  function pickerTrigger() {
    root.keepAlive()
    if (root.gearSel) { root.openPrefs(); return }
    var apps = root.filteredApps
    if (apps.length === 0) return
    var idx = (root.appSel >= 0 && root.appSel < apps.length) ? root.appSel : 0
    root.launchApp(apps[idx])
    root.closePicker()
  }

  component PrefsHeader: Item {
    property string title: ""
    width: parent ? parent.width : 0
    height: 28

    Text {
      anchors.centerIn: parent
      text: title
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }

  component PrefsChoice: Item {
    id: choice
    property string label: ""
    property var options: []
    property var current: null
    property var formatValue: function(value) { return String(value) }
    property bool highlighted: false
    signal picked(var value)
    width: parent ? parent.width : 220
    height: 36

    function next(delta) {
      var count = choice.options.length
      if (count === 0) return
      var index = choice.options.indexOf(choice.current)
      if (index < 0) index = delta > 0 ? -1 : 0
      index = (index + delta + count) % count
      choice.picked(choice.options[index])
    }
    function trigger() { next(1) }
    function adjust(delta) { next(delta) }

    Rectangle {
      anchors.fill: parent
      radius: 8
      color: choice.highlighted ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
    }

    MouseArea {
      anchors.fill: parent
      onClicked: choice.trigger()
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      width: 86
      text: choice.label
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Row {
      visible: choice.options.length <= 3
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4

      Repeater {
        model: choice.options
        delegate: Rectangle {
          required property var modelData
          width: Math.max(36, Math.min(58,
            (choice.width - 104 - (choice.options.length - 1) * 4) / choice.options.length))
          height: 26
          radius: 7
          color: choice.current === modelData ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
          border.color: choice.current === modelData ? Commons.Color.accent : Commons.Color.popups.border
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: choice.formatValue(modelData)
            color: choice.current === modelData ? Commons.Color.accent : Qt.darker(Commons.Color.popups.text, 1.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: choice.picked(modelData)
          }
        }
      }
    }

    Row {
      visible: choice.options.length > 3
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4

      Rectangle {
        width: 24
        height: 24
        radius: 6
        border.color: Commons.Color.popups.border
        Text {
          anchors.centerIn: parent
          text: "‹"
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: 16
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: choice.next(-1)
        }
      }

      Text {
        width: Math.max(44, choice.width - 104 - 56)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: choice.formatValue(choice.current)
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Rectangle {
        width: 24
        height: 24
        radius: 6
        border.color: Commons.Color.popups.border
        Text {
          anchors.centerIn: parent
          text: "›"
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: 16
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: choice.next(1)
        }
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

  Timer {
    id: wheelFlash
    interval: 1200
    onTriggered: root.wheelTitle = ""
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
    root.closePicker()
    root.menuIndex = -1
    root.detailIndex = -1
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
    // Exclusive while the picker's search field needs typing, or during the
    // brief focus prime after a ALT + SPACE summon; OnDemand otherwise while
    // opened (keeps keyboard focus without monopolizing pointer hit-testing).
    WlrLayershell.keyboardFocus: root.pickerOpen ? WlrKeyboardFocus.Exclusive
      : (root.opened ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None)
    anchors { bottom: true; left: true; right: true }
    // Window height follows the tallest visible panel plus the card, so
    // menu tops never get clipped by the window bounds. The context menu
    // grows with its window rows (capped), the others have fixed sizes.
    // 10 px card bottom margin + 8 px panel gap + 2 px frame safety.
    // The old 16 px reserve put the panel top 2 px above the layer bounds,
    // clipping the rounded frame.
    implicitHeight: (root.hovering || root.sliding) ? (
      root.pickerOpen ? picker.height + card.height + 20
      : root.prefsOpen ? prefsMenu.height + card.height + 20
      : root.menuIndex >= 0 ? contextMenu.height + card.height + 20
      : root.detailIndex >= 0 ? detailPanel.height + card.height + 20
      : 112) : 8

    // Only the visible card, panels, and the reveal strip accept input. The
    // rest of this full-width layer stays click-through to the windows below.
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
        x: picker.x
        y: picker.y
        width: picker.visible ? picker.width : 0
        height: picker.visible ? picker.height : 0
      }
      Region {
        x: contextMenu.x
        y: contextMenu.y
        width: contextMenu.visible ? contextMenu.width : 0
        height: contextMenu.visible ? contextMenu.height : 0
      }
      Region {
        x: detailPanel.x
        y: detailPanel.y
        width: detailPanel.visible ? detailPanel.width : 0
        height: detailPanel.visible ? detailPanel.height : 0
      }
      Region {
        x: prefsMenu.x
        y: prefsMenu.y
        width: prefsMenu.visible ? prefsMenu.width : 0
        height: prefsMenu.visible ? prefsMenu.height : 0
      }
    }

    // ---- Keyboard handler (active when the Quay has keyboard focus) ----
    // Wraps ALL window content: Keys.priority BeforeItem only reaches
    // handlers that are ancestors of the focused item, so the catcher must
    // contain the picker's search field to keep seeing keys while typing
    // (it then forwards everything except Escape to the field).
    Item {
      id: quayKeys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem

      Keys.onPressed: function(event) {
        if (root.pickerOpen) {
          if (event.isAutoRepeat) {
            // Held arrows keep stepping the list; single-shot keys don't.
            root.keepAlive()
            if (event.key === Qt.Key_Up) { event.accepted = true; root.pickerNav(-1) }
            else if (event.key === Qt.Key_Down) { event.accepted = true; root.pickerNav(1) }
            return
          }
          root.keepAlive()
          if (event.key === Qt.Key_Escape) {
            event.accepted = true
            root.closePicker()
            root.refocusKeys()
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            event.accepted = true
            root.togglePickerFocus()
          } else if (event.key === Qt.Key_Up) {
            event.accepted = true
            root.pickerNav(-1)
          } else if (event.key === Qt.Key_Down) {
            event.accepted = true
            root.pickerNav(1)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
              || (event.key === Qt.Key_Space && root.gearSel)) {
            event.accepted = true
            root.pickerTrigger()
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

    // ---- App picker (search + list), shown when pickerOpen ----
    Rectangle {
      id: picker
      visible: root.pickerOpen && root.quayShown
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: 8
      width: Math.min(380, parent.width - 32)
      height: 320
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1

      Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Row {
          width: parent.width
          spacing: 8

          TextField {
            id: searchField
            width: parent.width - 42
            focus: !root.gearSel
            placeholderText: "Search apps…"
            color: Commons.Color.popups.text
            placeholderTextColor: Qt.darker(Commons.Color.popups.text, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            leftPadding: 10
            rightPadding: 10
            background: Rectangle {
              radius: 8
              color: Qt.rgba(1, 1, 1, 0.05)
              border.color: Commons.Color.popups.border
            }
            onTextChanged: {
              root.searchText = text
              root.appSel = -1
            }
            // Clicking the field takes focus back from the gear button.
            onActiveFocusChanged: if (activeFocus) root.gearSel = false
          }

          // Gear button: opens the settings menu (aligned with the list pin buttons).
          Rectangle {
            width: 28
            height: 28
            anchors.verticalCenter: parent.verticalCenter
            radius: 14
            color: (root.gearSel || gearHover.hovered) ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
            border.color: root.gearSel ? Commons.Color.accent : Commons.Color.popups.border
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: "⚙"
              color: Commons.Color.popups.text
              font.pixelSize: 15
            }

            HoverHandler { id: gearHover }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openPrefs()
            }
          }
        }

        ListView {
          id: appList
          width: parent.width
          height: parent.height - searchField.height - 8
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          model: root.filteredApps
          spacing: 2

            Connections {
              target: root
              function onAppSelChanged() {
                if (root.appSel >= 0)
                  appList.positionViewAtIndex(root.appSel, ListView.Contain)
              }
            }

            delegate: Item {
              required property var modelData
              required property int index
              width: ListView.view.width
              height: 40

              Rectangle {
                anchors.fill: parent
                radius: 8
                color: index === root.appSel ? Qt.rgba(1, 1, 1, 0.14) : (appHover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
              }

              Image {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                source: root.iconPathFor(modelData.icon)
                smooth: true
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: 42
                anchors.right: parent.right
                anchors.rightMargin: 42
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
                color: Commons.Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              HoverHandler { id: appHover }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.launchApp(modelData)
                  root.closePicker()
                }
              }

              // Pin/unpin button. The state is read from favoriteIds, so the
              // glyph flips as soon as the list changes.
              Rectangle {
                id: pinButton
                readonly property bool pinned: root.isPinned(modelData.id)
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                radius: 14
                color: pinHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                border.color: pinButton.pinned ? Commons.Color.accent : Commons.Color.popups.border
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: pinButton.pinned ? "✓" : "📌"
                  color: pinButton.pinned ? Commons.Color.accent : Commons.Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: 14
                }

                ToolTip {
                  visible: pinHover.hovered
                  text: pinButton.pinned ? "Unpin" : "Pin to favorites"
                }

                HoverHandler { id: pinHover }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (pinButton.pinned) root.unpinApp(modelData.id)
                    else root.pinApp(modelData.id)
                  }
                }
              }
            }
          }
      }
    }

    // ---- Hotspot : fine bande en bas, toujours présente, révèle le Quay au survol ----
    Rectangle {
      id: hotspot
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: 8
      color: "transparent"
      HoverHandler {
        id: hotspotHover
        onHoveredChanged: root.edgeHover = hotspotHover.hovered || cardHover.hovered
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
        onHoveredChanged: {
          root.edgeHover = hotspotHover.hovered || cardHover.hovered
          if (!hovered) root.hoveredIndex = -1
        }
      }

      Item {
        id: iconsRow
        anchors.centerIn: parent
        width: root.slotXFor(entriesModel.count) + 44
        height: 52

        ListView {
          id: iconList
          width: root.slotXFor(entriesModel.count)
          height: 52
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
            height: 52

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
              onHoveredChanged: if (hovered && !root.dragActive) root.hoveredIndex = index
            }

            Image {
              anchors.centerIn: parent
              width: root.iconSize
              height: root.iconSize
              source: root.iconPathFor(icon)
              smooth: true
              antialiasing: true
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

              Repeater {
                model: winCount
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

            ToolTip {
              visible: !root.dragActive && root.showName && (iconHover.hovered || (root.keySel === index && root.opened))
              text: name
              delay: iconHover.hovered ? 400 : 0
            }
          }
        }

        // Insertion marker: the slot boundary where the icon will land.
        Rectangle {
          id: dropMarker
          visible: root.dragActive && root.dragSlot >= 0
          x: root.dragSlot * root.iconSlotWidth - 1
          y: 4
          width: 2
          height: Math.max(44, root.iconSize * 0.9)
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
          opacity: 0.92
          scale: 1.06
          z: 90
        }

        // Menu button: opens the app picker (search + list)
        Item {
          id: addButton
          x: root.slotXFor(entriesModel.count)
          width: 44
          height: 52

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
            width: 34
            height: 34
            radius: 17
            color: addHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
            border.color: Commons.Color.popups.border
            border.width: 1
          }

          Text {
            anchors.centerIn: parent
            text: "☰"
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }

          HoverHandler { id: addHover }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.pickerOpen) root.closePicker()
              else root.openPicker()
            }
          }

          // Keyboard selection ring when the add button is selected.
          Rectangle {
            visible: root.keySel === entriesModel.count && root.opened
            anchors.centerIn: parent
            width: 40
            height: 40
            radius: 20
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
      visible: root.menuIndex >= 0 && root.menuEntry !== null
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: 8
      width: Math.min(280, parent.width - 32)
      // Grows with the window list, capped so it can't overflow the screen.
      height: Math.min(menuColumn.implicitHeight + 12, 620, root.panelMaxHeight)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1

      Column {
        id: menuColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 6
        spacing: 2

        PrefsHeader {
          title: root.menuEntry ? root.menuEntry.name : ""
        }

        MenuRow {
          id: menuFocus
          icon: "▶"
          label: root.menuWindows.length > 0 ? "Focus window" : "Launch"
          onTriggered: root.focusApp(root.menuEntry)
        }

        MenuRow {
          id: menuPin
          icon: "📌"
          visible: root.menuEntry ? !root.menuEntry.pinned : false
          label: "Pin to favorites"
          onTriggered: {
            root.pinApp(root.menuEntry.id)
            root.closeMenu()
          }
        }

        MenuRow {
          id: menuUnpin
          icon: "⊘"
          visible: root.menuEntry ? root.menuEntry.pinned : false
          label: "Unpin"
          onTriggered: {
            root.unpinApp(root.menuEntry.id)
            root.closeMenu()
          }
        }

        Rectangle {
          visible: root.menuWindows.length > 0
          width: parent.width
          height: 1
          color: Commons.Color.popups.border
        }

        PrefsHeader {
          visible: root.menuWindows.length > 0
          title: "Windows"
        }

        Repeater {
          id: menuWinRepeater
          model: root.menuWindows
          delegate: MenuRow {
            required property var modelData
            icon: "▤"
            label: modelData.title
            onTriggered: root.focusWindow(modelData.address)
          }
        }

        MenuRow {
          id: menuQuit
          icon: "⏻"
          danger: true
          visible: root.menuWindows.length > 0
          label: "Quit"
          onTriggered: root.quitApp(root.menuEntry)
        }

        MenuRow {
          id: menuDetails
          icon: "ℹ"
          label: "Details"
          onTriggered: { root.detailIndex = root.menuIndex }
        }
      }
    }

    // ---- Details panel ----
    Rectangle {
      id: detailPanel
      visible: root.detailIndex >= 0 && root.detailEntry !== null
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: 8
      width: Math.min(340, parent.width - 32)
      height: 210
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1

      Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 6

        Text {
          width: parent.width
          text: root.detailEntry ? root.detailEntry.name : ""
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          visible: root.detailDesktopEntry && String(root.detailDesktopEntry.genericName || "") !== ""
          width: parent.width
          text: root.detailDesktopEntry ? String(root.detailDesktopEntry.genericName || "") : ""
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          visible: root.detailDesktopEntry && String(root.detailDesktopEntry.comment || "") !== ""
          width: parent.width
          text: root.detailDesktopEntry ? String(root.detailDesktopEntry.comment || "") : ""
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Commons.Color.popups.border
        }

        Text {
          visible: root.detailDesktopEntry && String(root.detailDesktopEntry.execString || "") !== ""
          width: parent.width
          text: root.detailDesktopEntry ? ("Exec : " + String(root.detailDesktopEntry.execString || "")) : ""
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: root.detailEntry ? ("Fichier : " + Model.normalizeId(root.detailEntry.id) + ".desktop") : ""
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }
    }

    // ---- Preferences (right-click on empty Quay area) ----
    Rectangle {
      id: prefsMenu
      visible: root.prefsOpen
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: 8
      width: Math.min(840, parent.width - 32)
      // Three columns keep the panel compact; the cap still protects short
      // screens and the ScrollView resets to the top on open.
      height: Math.min(prefsColumns.implicitHeight + 12, root.panelMaxHeight)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1

      ScrollView {
        id: prefsScroll
        anchors.fill: parent
        anchors.margins: 6
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Row {
          id: prefsColumns
          width: prefsScroll.availableWidth
          spacing: 8

        Column {
          id: prefsColA
          width: (prefsColumns.width - 4 * prefsColumns.spacing - 2) / 3
          spacing: 2

        PrefsHeader {
          title: "Placement"
        }

        MenuRow {
          id: prefsAuto
          label: root.screenPref === "" ? "Auto (widest) ✓" : "Auto (widest)"
          onTriggered: root.setScreenPref("")
        }

        Repeater {
          id: prefsScreens
          model: Quickshell.screens
          delegate: Rectangle {
            id: scrRow
            required property var modelData
            property bool highlighted: false
            function trigger() { root.setScreenPref(modelData.name) }
            width: parent.width
            height: 34
            radius: 8
            color: scrRow.highlighted ? Qt.rgba(1, 1, 1, 0.14) : (scrHover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 10
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name + (root.screenPref === modelData.name ? " ✓" : "")
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            HoverHandler { id: scrHover }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: scrRow.trigger()
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Commons.Color.popups.border
        }

        PrefsHeader {
          title: "Behavior"
        }

        PrefsChoice {
          id: prefsHideDelay
          label: "Hide delay"
          options: [500, 1000, 1500, 2000, 3000]
          current: root.hideDelay
          formatValue: function(value) { return (value / 1000) + " s" }
          onPicked: root.setHideDelay(value)
        }

        PrefsChoice {
          id: prefsShowName
          label: "App name"
          options: ["On", "Off"]
          current: root.showName ? "On" : "Off"
          onPicked: root.setShowName(value === "On")
        }

        }

        Rectangle {
          width: 1
          height: Math.max(prefsColA.height, prefsColB.height, prefsColC.height)
          color: Commons.Color.popups.border
        }

        Column {
          id: prefsColB
          width: (prefsColumns.width - 4 * prefsColumns.spacing - 2) / 3
          spacing: 2

        PrefsHeader {
          title: "Appearance"
        }

        PrefsChoice {
          id: prefsIconSize
          label: "Icon size"
          options: [32, 36, 40, 44, 48, 52, 56, 60, 64]
          current: root.iconSize
          formatValue: function(value) { return value + " px" }
          onPicked: root.setIconSize(value)
        }

        PrefsChoice {
          id: prefsZoom
          label: "Hover zoom"
          options: [1.3, 1.5, 1.8]
          current: root.zoom
          formatValue: function(value) { return value + "×" }
          onPicked: root.setZoom(value)
        }

        PrefsChoice {
          id: prefsGap
          label: "Icon gap"
          options: [0, 2, 4, 6, 8, 10, 12, 16, 20, 24]
          current: root.iconSpacing
          formatValue: function(value) { return value + " px" }
          onPicked: root.setIconSpacing(value)
        }

        PrefsChoice {
          id: prefsPadX
          label: "Padding X"
          options: [4, 8, 12, 16, 20, 24]
          current: root.paddingX
          formatValue: function(value) { return value + " px" }
          onPicked: root.setPaddingX(value)
        }

        PrefsChoice {
          id: prefsPadY
          label: "Padding Y"
          options: [2, 4, 6, 8, 10, 12, 16]
          current: root.paddingY
          formatValue: function(value) { return value + " px" }
          onPicked: root.setPaddingY(value)
        }

        }

        Rectangle {
          width: 1
          height: Math.max(prefsColA.height, prefsColB.height, prefsColC.height)
          color: Commons.Color.popups.border
        }

        Column {
          id: prefsColC
          width: (prefsColumns.width - 4 * prefsColumns.spacing - 2) / 3
          spacing: 2

        PrefsHeader {
          title: "Motion"
        }

        PrefsChoice {
          id: prefsAnimMode
          label: "Mode"
          options: root.animationModes
          current: root.animMode
          formatValue: function(value) { return root.animationLabel(value) }
          onPicked: root.setAnimMode(value)
        }

        PrefsChoice {
          id: prefsSpeed
          label: "Speed"
          options: ["fast", "normal", "slow"]
          current: root.animSpeed
          formatValue: function(value) { return value.charAt(0).toUpperCase() + value.slice(1) }
          onPicked: root.setAnimSpeed(value)
        }
        }
        }
      }
    }
  }
}
}
