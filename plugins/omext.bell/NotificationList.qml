import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Commons as Commons

// The notifications, by day, as cards (omext bell): the app's picture, an
// accent stripe (red when it was urgent), who and when, what it said, its
// buttons. A click does what the notification's own click does (or goes to the
// app); ✕ puts one away. Shared with Start, which shows it when bell is here.
Item {
  id: list
  required property var history          // a History
  property string query: ""
  property string fontFamily: Style.font.family
  property color text: Commons.Color.popups.text
  property color accent: Commons.Color.accent
  property color dim: Commons.Util.alpha(text, 0.55)
  property real sizeScale: 0               // a size of the host's own (Start's menu); 0: bell's size setting
  readonly property real k: sizeScale > 0 ? sizeScale : history.dims ? history.dims.scale : 1
  function px(n) { return Math.round(n * k) }
  signal acted()                           // a click did something: close the panel

  readonly property var shown: {
    var q = query.trim().toLowerCase()
    var rows = history.entries
    if (q) rows = rows.filter(e => !history.redacted(e) && [e.app, e.summary, e.body].some(t => String(t || "").toLowerCase().indexOf(q) >= 0))
    return rows.map(e => ({ e: e, day: history.dayOf(e) }))
  }

  ListView {
    id: view
    anchors.fill: parent
    clip: true
    spacing: 8
    boundsBehavior: Flickable.StopAtBounds
    model: list.shown
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    section.property: "day"
    section.delegate: Text {
      required property string section
      width: view.width
      topPadding: 6
      bottomPadding: 2
      leftPadding: 4
      text: section
      color: list.dim
      font.family: list.fontFamily
      font.pixelSize: list.px(Style.font.caption)
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 0.8
    }
    // Arriving cards slide in and fade up; the rest make room smoothly.
    add: Transition {
      ParallelAnimation {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { property: "x"; from: 24; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
      }
    }
    displaced: Transition { NumberAnimation { properties: "x,y"; duration: 220; easing.type: Easing.OutCubic } }

    delegate: Item {
      id: cell
      required property var modelData
      readonly property var e: modelData.e
      readonly property bool urgent: Number(e.urgency || 0) >= 2
      readonly property bool secret: list.history.redacted(e)
      readonly property var deeds: secret ? [] : list.history.actions(e)
      readonly property string icon: list.history.iconFor(e)
      readonly property string glyph: list.history.glyphFor(e)
      width: view.width - 10
      height: card.height + 6

      // A soft shadow under the card: a shape of its own, behind it. (The card
      // itself is not drawn through a layer: on a screen scaled by a fraction
      // that blurs everything in it, the text first.)
      Rectangle {
        x: card.x; y: card.y
        width: card.width; height: card.height
        radius: card.radius
        color: Commons.Color.popups.background
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: "#000000"
          shadowOpacity: 0.35
          shadowBlur: 0.55
          shadowVerticalOffset: 3
        }
      }
      Rectangle {
        id: card
        x: 3; y: 1
        width: parent.width - 6
        height: Math.max(list.px(66), body.y + (body.visible ? body.height : 0) + (deeds.length ? list.px(40) : 12))
        radius: 12
        gradient: Gradient {
          GradientStop { position: 0; color: Commons.Util.alpha(list.text, hit.containsMouse ? 0.11 : 0.075) }
          GradientStop { position: 1; color: Commons.Util.alpha(list.text, hit.containsMouse ? 0.07 : 0.035) }
        }
        border.color: Commons.Util.alpha(cell.urgent ? Commons.Color.urgent : list.text, cell.urgent ? 0.45 : 0.08)

        // The accent stripe.
        Rectangle {
          x: 0; y: 10
          width: 3; height: parent.height - 20
          radius: 2
          color: cell.urgent ? Commons.Color.urgent : list.accent
        }

        // The app's picture (or its glyph, or its initial).
        Rectangle {
          id: pic
          x: 14; y: 12
          width: list.px(40); height: list.px(40)
          radius: list.px(10)
          color: Commons.Util.alpha(cell.urgent ? Commons.Color.urgent : list.accent, 0.16)
          Image {
            anchors.centerIn: parent
            width: 30; height: 30
            visible: cell.icon !== "" && status !== Image.Error
            source: cell.icon
            sourceSize: Qt.size(60, 60)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }
          Text {
            anchors.centerIn: parent
            visible: cell.icon === ""
            text: cell.glyph || list.history.appName(cell.e).charAt(0)
            color: cell.urgent ? Commons.Color.urgent : list.accent
            font.family: cell.glyph ? Style.font.menuFamily || list.fontFamily : list.fontFamily
            font.pixelSize: list.px(cell.glyph ? 20 : 18)
            font.bold: true
          }
        }

        Text {  // who, and when
          id: who
          x: pic.x + pic.width + 12; y: 11
          width: parent.width - x - 40
          text: list.history.appName(cell.e) + (list.history.ago(cell.e) ? "  ·  " + list.history.ago(cell.e) : "")
          color: list.dim
          elide: Text.ElideRight
          font.family: list.fontFamily
          font.pixelSize: list.px(Style.font.caption)
        }
        Text {  // what
          id: what
          x: who.x; y: who.y + who.height + 2
          width: parent.width - x - 14
          text: cell.secret ? "Hidden notification" : String(cell.e.summary || "")
          textFormat: Text.PlainText
          color: list.text
          elide: Text.ElideRight
          font.family: list.fontFamily
          font.pixelSize: list.px(Style.font.body)
          font.bold: true
        }
        Text {  // and the rest
          id: body
          x: who.x; y: what.y + what.height + 2
          width: parent.width - x - 14
          visible: text !== ""
          text: cell.secret ? "" : String(cell.e.body || "").replace(/\s+/g, " ").trim()
          textFormat: Text.PlainText
          color: Commons.Util.alpha(list.text, 0.8)
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
          font.family: list.fontFamily
          font.pixelSize: list.px(Style.font.bodySmall)
        }

        MouseArea {
          id: hit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (list.history.activate(cell.e)) list.acted()
        }

        // Its own buttons (Omarchy's actions: Open, Copy, ...).
        Row {
          x: who.x; y: body.y + (body.visible ? body.height : 0) + 8
          spacing: 6
          visible: cell.deeds.length > 0
          Repeater {
            model: cell.deeds
            Rectangle {
              required property var modelData
              width: dl.implicitWidth + list.px(20); height: list.px(24); radius: list.px(12)
              color: dh.containsMouse ? Commons.Util.alpha(list.accent, 0.35) : Commons.Util.alpha(list.text, 0.08)
              Behavior on color { ColorAnimation { duration: 120 } }
              Text { id: dl; anchors.centerIn: parent; text: parent.modelData.label; color: list.text; font.family: list.fontFamily; font.pixelSize: list.px(Style.font.caption) }
              MouseArea { id: dh; anchors.fill: parent; hoverEnabled: true; onClicked: { list.history.run(parent.modelData.argv); list.acted() } }
            }
          }
        }

        // ✕: put it away (here only; Omarchy's history keeps it).
        Rectangle {
          anchors { right: parent.right; top: parent.top; margins: 8 }
          width: 22; height: 22; radius: 11
          visible: hit.containsMouse || xh.containsMouse
          color: xh.containsMouse ? Commons.Util.alpha(Commons.Color.urgent, 0.35) : Commons.Util.alpha(list.text, 0.1)
          Text { anchors.centerIn: parent; text: "✕"; color: list.text; font.pixelSize: 10 }
          MouseArea { id: xh; anchors.fill: parent; hoverEnabled: true; onClicked: list.history.hide(cell.e.key) }
        }
      }
    }
  }

  Column {  // nothing to show
    anchors.centerIn: parent
    visible: list.shown.length === 0
    spacing: 8
    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "\u{F009A}"; color: Commons.Util.alpha(list.text, 0.25); font.pixelSize: 44 }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: list.query.trim() ? "Nothing matches “" + list.query.trim() + "”" : "No notifications"
      color: list.dim
      font.family: list.fontFamily
      font.pixelSize: list.px(Style.font.bodySmall)
    }
  }
}
