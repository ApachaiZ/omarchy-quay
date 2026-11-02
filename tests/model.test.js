// Run with: node tests/model.test.js
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const apps = [
  { id: "firefox.desktop", name: "Firefox", icon: "firefox", keywords: ["browser", "web"] },
  { id: "org.gnome.Nautilus.desktop", name: "Files", genericName: "File Manager", icon: "org.gnome.Nautilus", keywords: ["nautilus"] },
  { id: "libreoffice-writer.desktop", name: "LibreOffice Writer", icon: "libreoffice-writer" },
  { id: "org.gnome.Calculator.desktop", name: "Calculator", icon: "org.gnome.Calculator", keywords: ["math"] },
  { id: "café.desktop", name: "Café", icon: "cafe" },
  { id: "hidden.desktop", name: "Hidden App", icon: "hidden", noDisplay: true }
]

assert.equal(Model.normalizeId("firefox.desktop"), "firefox")
assert.equal(Model.normalizeId(" firefox.desktop "), "firefox")
assert.deepEqual(Model.parseFavorites('["a.desktop","a","b"]'), ["a", "b"])
assert.deepEqual(Model.parseFavorites("not json"), [])
assert.deepEqual(
  Model.resolveFavorites(["firefox.desktop", "missing.desktop"], apps).map(a => a.id),
  ["firefox"])
const prototypeEntry = { id: "__proto__", name: "Prototype", icon: "x" }
assert.equal(Model.entryIndex([prototypeEntry])["__proto__"].name, "Prototype")

assert.deepEqual(Model.parseExec('firefox --new-window "%u"'), ["firefox", "--new-window"])
assert.deepEqual(Model.parseExec('sh -c "echo $(id)"'), ["sh", "-c", "echo $(id)"])
assert.deepEqual(Model.parseExec("app %%name %f"), ["app", "%name"])
assert.deepEqual(Model.parseExec(""), [])

assert.equal(Model.normalizeSearch("LibreOffice"), "libre office")
assert.equal(Model.normalizeSearch("org.gnome.Nautilus"), "org gnome nautilus")
assert.equal(Model.normalizeSearch("Café"), "cafe")

assert.deepEqual(Model.sortedAppList(apps, "").map(a => a.id), [
  "café.desktop",
  "org.gnome.Calculator.desktop",
  "org.gnome.Nautilus.desktop",
  "firefox.desktop",
  "libreoffice-writer.desktop"
])
assert.equal(Model.sortedAppList(apps, "hidden").length, 0)
assert.equal(Model.sortedAppList(apps, "cafe")[0].id, "café.desktop")
assert.equal(Model.sortedAppList(apps, "lo wri")[0].id, "libreoffice-writer.desktop")
assert.equal(Model.sortedAppList(apps, "file man")[0].id, "org.gnome.Nautilus.desktop")
assert.equal(Model.sortedAppList(apps, "browser")[0].id, "firefox.desktop")
assert.equal(Model.sortedAppList(apps, "cal")[0].id, "org.gnome.Calculator.desktop")
assert.equal(Model.sortedAppList(apps, "fbw")[0].id, "firefox.desktop")
assert.equal(Model.scoreEntry(apps[0], "fire"), 12000 - "firefox".length)
assert.equal(Model.scoreEntry(apps[0], "zzz"), -1)
assert.equal(Model.sortedAppList(apps, "<img src=x>").length, 0)

console.log("Model tests passed")
