import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "file:///usr/share/omarchy/shell/plugins/notifications/Security.js" as Security
import "file:///usr/share/omarchy/shell/plugins/notifications/Store.js" as Store
import "file:///usr/share/omarchy/shell/plugins/notifications/Icons.js" as Icons

// The notification history (omext bell): what Omarchy's notification service
// keeps in ~/.local/state/omarchy/notifications/history.json (its last 100,
// newest first), read as it changes. Nothing is written there: what's been seen,
// cleared or put away is bell's own, in ~/.local/state/omext/bell/state.json.
Item {
  id: history
  visible: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string historyPath: stateHome + "/omarchy/notifications/history.json"
  readonly property string statePath: stateHome + "/omext/bell/state.json"

  property var raw: []                         // as Omarchy keeps them
  property var state: ({ seen: 0, cleared: 0, hidden: [] })
  property double now: Date.now()
  property bool dnd: false

  // Settings, in ~/.config/omext/bell.json (the same for every screen's bell,
  // and for Start's Notifications): the size, and the count on the bell.
  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omext/bell.json"
  // (Read, watched and written by omext core's Settings.)
  readonly property string coreDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/plugins/omext.core"
  Loader { id: coreOwn; Component.onCompleted: setSource("file://" + history.coreDir + "/Settings.qml", { name: "bell" }) }
  readonly property var config: coreOwn.item ? coreOwn.item.values : ({})
  readonly property var sizes: ({
    compact: { label: "Compact", width: 380, height: 520, scale: 0.9 },
    default: { label: "Default", width: 440, height: 600, scale: 1 },
    large:   { label: "Large", width: 500, height: 700, scale: 1.12 },
    xlarge:  { label: "Extra large", width: 580, height: 820, scale: 1.25 }
  })
  readonly property var sizeNames: ["compact", "default", "large", "xlarge"]
  readonly property string sizeName: sizes[config.size] ? config.size : "default"
  readonly property var dims: sizes[sizeName]
  readonly property bool showCount: config.count !== false
  function saveConfig(patch) { if (coreOwn.item) coreOwn.item.set(patch) }

  // Shown: newer than the last clear, not put away; newest first.
  readonly property var entries: {
    var hidden = state.hidden || [], cleared = Number(state.cleared || 0)
    return raw.filter(e => e && Number(e.ts || 0) > cleared && hidden.indexOf(e.key) < 0)
  }
  readonly property int unread: entries.filter(e => Number(e.ts || 0) > Number(state.seen || 0)).length

  FileView {
    path: history.historyPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { var v = JSON.parse(text()); history.raw = Array.isArray(v) ? v : [] } catch (e) { history.raw = [] } }
    onLoadFailed: history.raw = []
  }
  FileView {
    id: stateFile
    path: history.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { var v = JSON.parse(text()); if (v && typeof v === "object") history.state = v } catch (e) {} }
  }
  // The file is there from the start: one that isn't can't be watched, and the
  // bell's panel and Start's list each have a History of their own, which would
  // then not hear of what the other took off the list (and write over it).
  Process {
    running: true
    command: ["bash", "-c", 'mkdir -p "$(dirname "$0")" && { [ -s "$0" ] || printf "%s\\n" \'{"seen":0,"cleared":0,"hidden":[]}\' > "$0"; }', history.statePath]
    onExited: { stateFile.path = ""; stateFile.path = history.statePath }
  }
  function save(patch) {
    var s = Object.assign({ seen: 0, cleared: 0, hidden: [] }, state, patch)
    state = s
    Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$0")" && printf "%s\\n" "$1" > "$0"', statePath, JSON.stringify(s)])
  }
  function markSeen() {
    var newest = entries.length ? Number(entries[0].ts || 0) : 0
    if (newest > Number(state.seen || 0)) save({ seen: newest })
  }
  function clearAll() { save({ cleared: Date.now() / 1000, hidden: [] }) }
  function hide(key) {
    // Only those still in Omarchy's history are worth remembering.
    var keys = raw.map(e => e.key)
    save({ hidden: (state.hidden || []).filter(k => keys.indexOf(k) >= 0).concat([key]) })
  }

  // Do Not Disturb: Omarchy's.
  Process {
    id: dndProc
    command: ["omarchy-shell", "notifications", "isDnd"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: history.dnd = text.trim() === "on" }
  }
  function readDnd() { if (!dndProc.running) dndProc.running = true }
  function toggleDnd() {
    dnd = !dnd
    Quickshell.execDetached(["bash", "-c", "omarchy-shell notifications setDnd " + (dnd ? "on" : "off") + " >/dev/null"])
  }
  Component.onCompleted: readDnd()

  Timer { interval: 30000; repeat: true; running: true; onTriggered: { history.now = Date.now(); history.readDnd() } }

  // --- one notification --------------------------------------------------------

  function redacted(e) { try { return Store.redacted(e) } catch (x) { return false } }
  function actions(e) { return Security.parseExecActions(e.execActions) || [] }

  // A click: what Omarchy's card would do (its command), else to the app's window.
  function activate(e) {
    var argv = Security.parseExecArgv(e.execArgv)
    if (argv) { Quickshell.execDetached(argv); return true }
    var names = [e.appIcon, e.source, e.app].map(n => String(n || "").toLowerCase()).filter(n => !!n)
    var slugs = names.map(n => Icons.slug(n))
    for (var t of Hyprland.toplevels.values) {
      var cls = String(t.lastIpcObject && t.lastIpcObject.class || "").toLowerCase()
      if (!cls) continue
      if (names.some(n => cls === n || cls.indexOf(n) >= 0) || slugs.some(n => n && cls.indexOf(n) >= 0)) {
        var a = String(t.address); Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + (a.indexOf("0x") === 0 ? a : "0x" + a) + "' })")
        return true
      }
    }
    return false
  }
  function run(argv) { if (argv && argv.length) Quickshell.execDetached(argv) }

  // The app's picture: the sender's image, the icon theme, a desktop entry (as
  // Omarchy's cards look it up).
  function iconFor(e) {
    var sent = Security.localImageUrl(e.image)
    if (sent) return sent
    var _ = DesktopEntries.applications.values.length
    var want = Icons.candidates(e)
    for (var n of want.themed) { var p = n ? Quickshell.iconPath(n, true) : ""; if (p) return p }
    for (var m of want.entries) {
      var entry = m ? DesktopEntries.heuristicLookup(m) : null
      if (entry && entry.icon) {
        var v = String(entry.icon)
        var u = v.charAt(0) === "/" ? "file://" + v : Quickshell.iconPath(v, true)
        if (u) return u
      }
    }
    return ""
  }
  function glyphFor(e) { return Security.safeGlyph(e.glyph) || "" }
  function appName(e) {
    var a = String(e.app || "")
    if (a === "notify-send" || a === "omarchy-action") return "Omarchy"
    return a ? a.charAt(0).toUpperCase() + a.slice(1) : "Notification"
  }

  // When: minutes, then the time, then the day.
  function ago(e) {
    var t = Number(e.ts || 0) * 1000
    if (!t) return ""
    var s = Math.max(0, (now - t) / 1000)
    if (s < 60) return "now"
    if (s < 3600) return Math.round(s / 60) + " min"
    var then = new Date(t)
    return Qt.formatTime(then, "HH:mm")
  }
  function dayOf(e) {
    var then = new Date(Number(e.ts || 0) * 1000), today = new Date(now)
    if (then.toDateString() === today.toDateString()) return "Today"
    if (then.toDateString() === new Date(now - 86400000).toDateString()) return "Yesterday"
    return Qt.formatDate(then, "dddd d MMMM")
  }
}
