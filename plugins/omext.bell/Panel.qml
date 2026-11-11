import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bell (omext bell, from omarchy-extended): the notification history on the bar.
// A bell, with how many came since you last looked (struck through while Do Not
// Disturb is on); a click opens them, by day, newest first, to search, act on,
// put away or clear. It reads what Omarchy's notification service keeps
// (History.qml) and leaves its pop-ups as they are.
Panel {
  id: root
  moduleName: "omext.bell"
  manageIpc: false

  // omarchy-shell omext.bell open|close|toggle|settings. There's a bell on every screen's
  // bar and only one gets these: it passes them on to all through a file, and
  // the one on the focused screen opens (an open one anywhere closes).
  ShellIpc {
    target: "omext.bell"
    function open(): void { root.request("open") }
    function show(): void { root.request("open") }
    function close(): void { root.request("close") }
    function hide(): void { root.request("close") }
    function toggle(): void { root.request("toggle") }
    function settings(): void { root.request("settings") }
  }
  property double lastRequest: 0
  function request(op) {
    var r = { op: op, t: Date.now() }
    requestFile.setText(JSON.stringify(r))
    onRequest(r)
  }
  function onRequest(r) {
    if (!r || !r.t || r.t <= lastRequest || Date.now() - r.t > 3000) return
    lastRequest = r.t
    var win = button.QsWindow.window
    var mine = win && win.screen ? win.screen.name : ""
    var here = !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === mine
    if (r.op === "close" || r.op === "toggle" && opened || !here) close()
    else { open(); settingsOpen = r.op === "settings" }
  }
  FileView {
    id: requestFile
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omext-bell-request.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.onRequest(JSON.parse(text())) } catch (e) {} }
  }

  readonly property color text: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Commons.Util.alpha(text, 0.55)
  readonly property string fontFamily: Style.font.family
  function px(n) { return Math.round(n * history.dims.scale) }  // the size setting

  History { id: history }

  // Off the bar while omext start shows the notifications in its menu and is
  // set to be their one place (the gear on its Notifications heading › Hide the
  // bar's bell). A choice that crosses addons: omext core keeps it (hideBell in
  // ~/.config/omext/omext.json; Start says whether it shows them), and says
  // whether Start is here and on. Start gone or off: back.
  readonly property string coreDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/plugins/omext.core"
  Loader { id: coreAddons; source: "file://" + root.coreDir + "/Addons.qml" }
  Loader { id: coreShared; Component.onCompleted: setSource("file://" + root.coreDir + "/Settings.qml", { name: "omext" }) }
  readonly property var shared: coreShared.item ? coreShared.item.values : ({})
  readonly property bool inStart: !!coreAddons.item && coreAddons.item.on("start") && shared.hideBell === true && shared.notificationsInStart === true

  implicitWidth: inStart ? 0 : button.implicitWidth
  implicitHeight: inStart ? 0 : button.implicitHeight

  property bool settingsOpen: false
  onOpenedChanged: if (opened) { history.readDnd(); search.text = ""; settingsOpen = false } else history.markSeen()

  WidgetButton {
    id: button
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    visible: !root.inStart
    bar: root.bar
    text: history.dnd ? "\u{F009B}" : history.unread ? "\u{F116B}" : "\u{F009A}"
    active: root.opened
    tooltipText: history.dnd ? "Notifications (Do Not Disturb)"
               : history.unread ? history.unread + " new notification" + (history.unread === 1 ? "" : "s") : "Notifications"
    onPressed: function(b) {
      if (b === Qt.RightButton) history.toggleDnd()
      else root.toggle()
    }

    Rectangle {  // how many are new
      visible: history.showCount && history.unread > 0 && !history.dnd
      anchors { right: parent.right; top: parent.top; rightMargin: 1; topMargin: 3 }
      width: Math.max(14, count.implicitWidth + 6); height: 14; radius: 7
      color: root.accent
      Text {
        id: count
        anchors.centerIn: parent
        text: history.unread > 99 ? "99+" : history.unread
        color: Commons.Color.popups.background
        font.family: root.fontFamily
        font.pixelSize: 9
        font.bold: true
      }
    }
  }

  component Chip: Rectangle {
    id: chip
    property string glyph: ""
    property string label: ""
    property bool on: false
    signal clicked()
    width: chipRow.implicitWidth + root.px(18); height: root.px(28); radius: height / 2
    color: on ? Commons.Util.alpha(root.accent, 0.3) : chipHit.containsMouse ? Commons.Util.alpha(root.text, 0.12) : Commons.Util.alpha(root.text, 0.06)
    Behavior on color { ColorAnimation { duration: 120 } }
    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: 6
      Text { anchors.verticalCenter: parent.verticalCenter; text: chip.glyph; color: root.text; font.family: Style.font.menuFamily || root.fontFamily; font.pixelSize: root.px(13) }
      Text { visible: chip.label !== ""; anchors.verticalCenter: parent.verticalCenter; text: chip.label; color: root.text; font.family: root.fontFamily; font.pixelSize: root.px(Style.font.caption) }
    }
    MouseArea { id: chipHit; anchors.fill: parent; hoverEnabled: true; onClicked: chip.clicked() }
  }

  component Caption: Text {
    leftPadding: 4
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }
  component Option: Rectangle {
    id: opt
    property string glyph: ""
    property string label: ""
    property string sub: ""
    property bool current: false
    signal clicked()
    width: parent ? parent.width : 0; height: 36; radius: 8
    color: optHit.containsMouse ? Commons.Util.alpha(root.text, 0.08) : current ? Commons.Util.alpha(root.accent, 0.14) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: opt.glyph; color: opt.current ? root.accent : root.dim; font.family: Style.font.menuFamily || root.fontFamily; font.pixelSize: 15 }
    Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: opt.label; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
    Text { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: opt.sub; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    MouseArea { id: optHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: opt.clicked() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: search
    contentWidth: panel.fittedContentWidth(Style.space(history.dims.width))
    contentHeight: panel.fittedContentHeight(Style.space(history.dims.height))

    Item {
      anchors.fill: parent

      Text {
        id: title
        text: root.settingsOpen ? "Settings" : "Notifications"
        color: root.text
        font.family: root.fontFamily
        font.pixelSize: root.px(Style.font.title)
        font.bold: true
      }
      Row {
        anchors { right: parent.right; verticalCenter: title.verticalCenter }
        spacing: 6
        Chip {
          glyph: history.dnd ? "\u{F009B}" : "\u{F009A}"
          label: "Do Not Disturb"
          on: history.dnd
          onClicked: history.toggleDnd()
        }
        Chip {
          glyph: "\u{F0A7A}"
          label: "Clear"
          visible: !root.settingsOpen && history.entries.length > 0
          onClicked: history.clearAll()
        }
        Chip {  // the settings
          glyph: "\u{F0493}"
          on: root.settingsOpen
          onClicked: { root.settingsOpen = !root.settingsOpen; search.forceActiveFocus() }
        }
      }

      Rectangle {  // search
        id: searchBox
        anchors { top: title.bottom; topMargin: 10; left: parent.left; right: parent.right }
        opacity: root.settingsOpen ? 0 : 1
        height: root.px(34)
        radius: 8
        color: Commons.Util.alpha(root.text, 0.06)
        border.color: Commons.Util.alpha(root.accent, search.activeFocus ? 0.7 : 0.25)
        Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "\u{F0349}"; color: root.dim; font.family: Style.font.menuFamily || root.fontFamily; font.pixelSize: 14 }
        TextInput {
          id: search
          anchors { fill: parent; leftMargin: 32; rightMargin: 10 }
          verticalAlignment: TextInput.AlignVCenter
          color: root.text
          font.family: root.fontFamily
          font.pixelSize: root.px(Style.font.bodySmall)
          clip: true
          Keys.onEscapePressed: { if (root.settingsOpen) root.settingsOpen = false; else if (text) text = ""; else root.close() }
          // Up and Down choose a notification, Enter does what a click on it
          // does, Delete takes it off the list. Typing searches again.
          onTextChanged: notes.chosen = -1
          Keys.onDownPressed: if (!root.settingsOpen && notes.count) notes.chosen = Math.min(notes.count - 1, notes.chosen + 1)
          Keys.onUpPressed: if (!root.settingsOpen && notes.count) notes.chosen = Math.max(0, notes.chosen < 0 ? notes.count - 1 : notes.chosen - 1)
          Keys.onReturnPressed: notes.activateChosen()
          Keys.onEnterPressed: notes.activateChosen()
          Keys.onDeletePressed: function(event) {
            if (notes.chosen < 0) { event.accepted = false; return }
            var at = notes.chosen
            notes.hideChosen()
            Qt.callLater(function() { notes.chosen = Math.min(at, notes.count - 1) })
          }
          Text { visible: !search.text; anchors.verticalCenter: parent.verticalCenter; text: "Search notifications"; color: root.dim; font: search.font }
        }
      }

      NotificationList {
        id: notes
        visible: !root.settingsOpen
        anchors { top: searchBox.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom }
        history: history
        query: search.text
        fontFamily: root.fontFamily
        onActed: root.close()
      }

      // Settings: the size (of the panel and its cards, here and in Start), the count.
      Column {
        visible: root.settingsOpen
        anchors { top: title.bottom; topMargin: 16; left: parent.left; right: parent.right }
        spacing: 6
        Caption { text: "SIZE" }
        Repeater {
          model: history.sizeNames
          Option {
            required property string modelData
            glyph: history.sizeName === modelData ? "\u25c9" : "\u25cb"
            label: history.sizes[modelData].label
            sub: history.sizes[modelData].width + " × " + history.sizes[modelData].height
            current: history.sizeName === modelData
            onClicked: history.saveConfig({ size: modelData })
          }
        }
        Item { width: 1; height: 8 }
        Caption { text: "BELL" }
        Option {
          glyph: history.showCount ? "\u{F0521}" : "\u{F0522}"
          label: "Count of new ones on the bell"
          current: history.showCount
          onClicked: history.saveConfig({ count: !history.showCount })
        }
        Item { width: 1; height: 8 }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "Right click the bell for Do Not Disturb. Kept in ~/.config/omext/bell.json."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
