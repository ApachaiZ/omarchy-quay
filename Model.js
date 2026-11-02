// Quay model: favorites persistence, desktop-entry resolution, search, and
// safe Exec parsing. Pure functions only, so the file can be unit-tested with
// Node as well as imported by Quay.qml.

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
  var index = Object.create(null)
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
      if (ch === "\"") { quote = false; continue }
      token = (token === null ? "" : token) + ch
      continue
    }
    if (ch === "\"") {
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

// ---- Application search ----------------------------------------------------

// Remove diacritics so "e" matches "é", and split camelCase / separators so
// "org.gnome.Nautilus" and "gnome nautilus" both match sensibly.
function normalizeSearch(value) {
  // Split camelCase before lowercasing so "LibreOffice" becomes
  // "libre office" rather than one opaque token.
  var text = String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .toLowerCase()
  try {
    text = text.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
  } catch (e) {
    // Older QML runtimes may not expose String.normalize; ASCII still works.
  }
  return text
    .replace(/[._:/\\-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
}

function searchWords(value) {
  var text = normalizeSearch(value)
  return text ? text.split(" ") : []
}

function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function keywordText(entry) {
  try {
    if (entry && entry.keywords && typeof entry.keywords.join === "function")
      return entry.keywords.join(" ")
  } catch (e) {
  }
  return ""
}

function entrySearchText(entry) {
  if (!entry) return ""
  return normalizeSearch([
    entryName(entry),
    entry.genericName,
    entry.comment,
    keywordText(entry),
    entry.id
  ].join(" "))
}

function entryAcronym(entry) {
  var values = searchWords([
    entryName(entry),
    entry && entry.genericName,
    keywordText(entry),
    entry && entry.id
  ].join(" "))
  var result = ""
  for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
  return result
}

function termMatches(entry, term) {
  if (!term) return true
  var name = normalizeSearch(entryName(entry))
  var id = normalizeSearch(entry && entry.id)
  var haystack = entrySearchText(entry)
  if (name.indexOf(term) >= 0) return true
  if (id.indexOf(term) >= 0) return true
  if (haystack.indexOf(term) >= 0) return true
  return term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0
}

function scoreEntry(entry, query) {
  var q = normalizeSearch(query)
  if (!q) return 0
  var terms = q.split(" ")
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termMatches(entry, terms[i])) return -1
  }

  var name = normalizeSearch(entryName(entry))
  var id = normalizeSearch(entry && entry.id)
  var haystack = entrySearchText(entry)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  if (directName === 0) return 12000 - name.length
  if (directId === 0) return 11000 - id.length
  if (directName > 0) return 9000 - directName * 10 - name.length
  if (directId > 0) return 8500 - directId * 10 - id.length

  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return 6500 - hayIndex

  var acronym = entryAcronym(entry)
  var acronymIndex = acronym.indexOf(q)
  if (acronymIndex === 0) return 5000 - acronym.length
  if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length
  return 4000 - name.length
}

function isVisibleEntry(entry) {
  return !!(entry && entry.id && !entry.noDisplay && !entry.hidden)
}

// Sorted, fuzzy-filtered list of installed apps for the app grid.
function sortedAppList(values, query) {
  var list = []
  var entries = values || []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!isVisibleEntry(entry)) continue
    var name = entryName(entry)
    if (!name) continue
    var score = scoreEntry(entry, query)
    if (score < 0) continue
    list.push({
      id: String(entry.id),
      name: name,
      icon: String(entry.icon || ""),
      genericName: String(entry.genericName || ""),
      score: score
    })
  }
  list.sort(function(a, b) {
    if (query && a.score !== b.score) return b.score - a.score
    var na = a.name.toLowerCase()
    var nb = b.name.toLowerCase()
    if (na < nb) return -1
    if (na > nb) return 1
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0)
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
    normalizeSearch: normalizeSearch,
    entryName: entryName,
    entrySearchText: entrySearchText,
    entryAcronym: entryAcronym,
    scoreEntry: scoreEntry,
    sortedAppList: sortedAppList
  }
}
