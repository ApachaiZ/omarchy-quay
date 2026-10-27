// Quay model: favorites persistence + resolution against the desktop-entry DB.

function normalizeId(id) {
  var value = String(id || "").trim()
  if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
  return value
}

// Default pinned apps, filtered to those actually installed.
function defaultFavorites() {
  return ["firefox.desktop", "foot.desktop", "org.gnome.Nautilus.desktop"]
}

// Build an id -> entry map from DesktopEntries.applications.values.
function entryIndex(values) {
  var index = {}
  var list = values || []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (entry && entry.id) index[String(entry.id)] = entry
  }
  return index
}

// Resolve favorite desktop ids into { id, name, icon } entries, dropping ids
// that are no longer installed.
function resolveFavorites(ids, values) {
  var index = entryIndex(values)
  var out = []
  for (var i = 0; i < ids.length; i++) {
    var id = normalizeId(ids[i])
    var entry = index[id] || index[id + ".desktop"]
    if (!entry) continue
    out.push({
      id: id,
      name: String(entry.name || id),
      icon: String(entry.icon || "")
    })
  }
  return out
}

// Parse the favorites file (JSON array of desktop ids) into a string array.
function parseFavorites(raw) {
  var ids = []
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (Array.isArray(parsed)) ids = parsed
  } catch (e) {
    ids = []
  }
  var out = []
  for (var i = 0; i < ids.length; i++) {
    var id = normalizeId(ids[i])
    if (id && out.indexOf(id) < 0) out.push(id)
  }
  return out
}

// Split a Desktop Entry Exec line into an argv vector. Handles double-quoted
// arguments and backslash escapes, then drops field codes (%f, %U, ...) so
// the caller can launch it without a shell. Returns [] for malformed input.
function parseExec(command) {
  var out = []
  var token = null
  var quote = false
  var escape = false
  var text = String(command || "")
  for (var i = 0; i < text.length; i++) {
    var ch = text.charAt(i)
    if (escape) {
      token = (token === null ? "" : token) + ch
      escape = false
      continue
    }
    if (quote) {
      if (ch === "\\") { escape = true; continue }
      if (ch === '"') { quote = false; continue }
      token = (token === null ? "" : token) + ch
      continue
    }
    if (ch === '"') {
      quote = true
      if (token === null) token = ""
      continue
    }
    if (ch === " " || ch === "\t" || ch === "\n") {
      if (token !== null) { out.push(token); token = null }
      continue
    }
    if (ch === "\\") {
      escape = true
      if (token === null) token = ""
      continue
    }
    token = (token === null ? "" : token) + ch
  }
  if (token !== null) out.push(token)
  var cleaned = []
  for (var j = 0; j < out.length; j++) {
    var value = out[j]
    if (/^%[a-zA-Z]$/.test(value)) continue
    value = value.replace(/%%/g, "\u0000").replace(/%[a-zA-Z]/g, "").replace(/\u0000/g, "%")
    if (value.length > 0) cleaned.push(value)
  }
  return cleaned
}

// Magnification curve: the hovered icon grows most, neighbours a little.
// `zoom` is the hovered scale; the neighbour keeps the historical 1.8 -> 1.1
// ratio so the Quay feels the same at the default setting.
function iconScale(index, hovered, zoom) {
  if (hovered < 0) return 1.0
  var z = Number(zoom)
  if (!isFinite(z) || z < 1) z = 1.8
  var d = Math.abs(index - hovered)
  if (d === 0) return z
  if (d === 1) return 1 + (z - 1) * 0.125
  return 1.0
}

// Fixed slot width for the configured icon size and hover zoom. Reserving
// the magnified icon plus its immediate neighbour once removes the constant
// width changes while the pointer moves across the Quay.
function slotWidth(iconSize, zoom, spacing) {
  var size = Number(iconSize)
  if (!isFinite(size) || size < 16) size = 48
  var z = Number(zoom)
  if (!isFinite(z) || z < 1) z = 1.8
  var gap = Number(spacing)
  if (!isFinite(gap) || gap < 0) gap = 6
  var neighbor = 1 + (z - 1) * 0.125
  return Math.ceil(size * (z + neighbor) / 2) + gap
}

// Sorted, search-filtered list of installed apps for the "add to Quay" picker.
function sortedAppList(values, query) {
  var q = String(query || "").toLowerCase().trim()
  var list = []
  var ids = values || []
  for (var i = 0; i < ids.length; i++) {
    var e = ids[i]
    if (!e || !e.id) continue
    var name = String(e.name || e.id)
    if (q && name.toLowerCase().indexOf(q) < 0) continue
    list.push({ id: String(e.id), name: name, icon: String(e.icon || "") })
  }
  list.sort(function(a, b) {
    var na = a.name.toLowerCase()
    var nb = b.name.toLowerCase()
    return na < nb ? -1 : (na > nb ? 1 : 0)
  })
  return list
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeId: normalizeId,
    defaultFavorites: defaultFavorites,
    entryIndex: entryIndex,
    resolveFavorites: resolveFavorites,
    parseFavorites: parseFavorites,
    parseExec: parseExec,
    iconScale: iconScale,
    slotWidth: slotWidth,
    sortedAppList: sortedAppList
  }
}
