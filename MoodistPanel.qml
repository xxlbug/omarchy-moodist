import QtQuick
import qs.Commons
import qs.Ui
import Quickshell
import Quickshell.Io

// Mixer popup: play/pause, master volume, the current mix with a slider per
// sound, and the full catalogue to add sounds from.
Panel {
  id: root
  moduleName: "net.2plastic.moodist"
  ipcTarget: "net.2plastic.moodist"
  manageIpc: true

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.58)
  readonly property var categories: service ? service.categories : []
  readonly property var activeIds: service ? service.activeIds : []
  readonly property bool hasServer: service ? service.hasServer : false
  readonly property string instanceHost: !service ? ""
    : hasServer ? service.baseUrl.replace(/^https?:\/\//, "")
    : "No server set"

  // Server settings. testState: "idle" | "testing" | "ok" | "failed", always
  // about the URL currently in the field; editing it resets to "idle".
  property bool serverOpen: false
  property string testState: "idle"
  property string testMessage: ""
  property string testedUrl: ""
  property int testSerial: 0

  function openServer() {
    urlField.text = service ? service.baseUrl : ""
    testState = "idle"
    testMessage = ""
    serverOpen = true
  }

  function runTest() {
    if (!service) return
    var url = urlField.text
    var serial = ++testSerial
    testState = "testing"
    testMessage = "Testing..."
    service.testInstance(url, function(ok, message) {
      // A result for a URL that has since been edited is stale.
      if (serial !== root.testSerial) return
      root.testState = ok ? "ok" : "failed"
      root.testMessage = message
      root.testedUrl = url
    })
  }

  // Merges `changes` into this widget's shell.json entry. The shell reports an
  // unchanged entry as a failed update, so callers skip no-op writes.
  function writeSettings(changes) {
    var next = ({})
    for (var k in settings) next[k] = settings[k]
    for (var c in changes) next[c] = changes[c]
    return !!(bar && bar.shell && typeof bar.shell.updateEntryInline === "function"
      && bar.shell.updateEntryInline(moduleName, next))
  }

  readonly property string shortcut: service ? service.shortcut : ""

  function toggleShortcut() {
    if (!service) return
    writeSettings({ shortcut: shortcut ? "" : service.defaultShortcut })
  }

  // Writes instanceUrl to this widget's shell.json entry; the widget picks the
  // change up through its settings and hands it to the service.
  function saveServer() {
    if (testState !== "ok" || !service) return
    var url = service.normalizedBase(testedUrl)
    // Already the configured instance: nothing to write. The shell reports an
    // unchanged entry as a failed update, so it must not be asked.
    if (url === service.baseUrl) {
      serverOpen = false
      return
    }
    if (writeSettings({ instanceUrl: url })) {
      serverOpen = false
    } else {
      testState = "failed"
      testMessage = "Could not save the setting"
    }
  }

  onOpenedChanged: {
    if (opened) {
      // Nothing can play without a server, so start where one is entered.
      if (service && !hasServer) openServer()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
    // Each opening starts with the server row closed, so a stale test result
    // from last time is never shown.
    else serverOpen = false
  }

  // The shell palette has no "success" color and the accent can be any hue
  // (orange in ristretto), so a passed test uses the theme's own green from
  // colors.toml, which every stock theme defines.
  property color okColor: "#8fbf6a"

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var match = text().match(/^green\s*=\s*"(#[0-9a-fA-F]{6})"/m)
      if (match) root.okColor = match[1]
    }
  }

  function labelFor(id) {
    var sound = service ? service.soundsById[id] : null
    return sound ? sound.label : id
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: Style.space(420)
    contentHeight: Style.space(560)

    Item {
      anchors.fill: parent

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        onActivateRequested: if (root.service) root.service.togglePlaying()
        onCloseRequested: root.close()
        onTabRequested: function(direction) { root.switchPanel(direction) }
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: body
          width: scroller.width
          spacing: Style.spacing.lg

          Item {
            width: parent.width
            height: Math.max(titleColumn.implicitHeight, controls.implicitHeight)

            Column {
              id: titleColumn
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Text {
                text: "Moodist"
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Row {
                spacing: Style.spacing.sm

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.instanceHost
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                // nf-md-cog, sized to the address it configures
                Text {
                  id: serverCog
                  anchors.verticalCenter: parent.verticalCenter
                  text: String.fromCodePoint(0xF0493)
                  color: root.serverOpen || cogMouse.containsMouse ? root.fg : root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption

                  MouseArea {
                    id: cogMouse
                    anchors.fill: parent
                    anchors.margins: -Style.spacing.xs
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.serverOpen ? root.serverOpen = false : root.openServer()
                    onContainsMouseChanged: {
                      if (!root.bar) return
                      if (containsMouse) root.bar.showTooltip(serverCog, "Settings")
                      else root.bar.hideTooltip(serverCog)
                    }
                  }
                }
              }
            }

            Row {
              id: controls
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Button {
                text: root.service && root.service.playing ? "Pause" : "Play"
                enabled: root.service ? root.service.hasMix && root.hasServer : false
                opacity: enabled ? 1 : 0.45
                foreground: root.fg
                bordered: true
                onClicked: root.service.togglePlaying()
              }

              Button {
                text: "Clear"
                enabled: root.service ? root.service.hasMix : false
                opacity: enabled ? 1 : 0.45
                foreground: root.fg
                bordered: true
                onClicked: root.service.clearMix()
              }
            }
          }

          Column {
            visible: root.serverOpen
            width: parent.width
            spacing: Style.spacing.sm

            PanelSectionHeader {
              text: "Moodist server"
              foreground: root.fg
            }

            TextField {
              id: urlField
              width: parent.width
              placeholderText: "https://moodist.mvze.net"
              foreground: root.fg
              onTextEdited: {
                root.testSerial++
                root.testState = "idle"
                root.testMessage = ""
              }
              onAccepted: root.runTest()
            }

            Item {
              width: parent.width
              height: Math.max(testRow.implicitHeight, serverButtons.implicitHeight)

              Row {
                id: testRow
                anchors.left: parent.left
                anchors.right: serverButtons.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.sm

                // nf-md-check_circle / nf-md-close_circle / nf-md-help_circle / nf-md-timer_sand
                Text {
                  id: testIcon
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.testState === "ok" ? String.fromCodePoint(0xF05E0)
                    : root.testState === "failed" ? String.fromCodePoint(0xF0159)
                    : root.testState === "testing" ? String.fromCodePoint(0xF051F)
                    : String.fromCodePoint(0xF02D7)
                  color: root.testState === "failed" ? Color.urgent
                    : root.testState === "ok" ? root.okColor
                    : root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - testIcon.width - parent.spacing
                  wrapMode: Text.Wrap
                  text: root.testMessage || "Not tested yet"
                  color: root.testState === "failed" ? Color.urgent : root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              Row {
                id: serverButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.sm

                Button {
                  text: "Default"
                  tooltipText: "Fill in the official instance"
                  foreground: root.fg
                  bordered: true
                  onClicked: {
                    urlField.text = root.service ? root.service.defaultInstance : ""
                    root.runTest()
                  }
                }

                Button {
                  text: "Test"
                  enabled: root.testState !== "testing"
                  opacity: enabled ? 1 : 0.45
                  foreground: root.fg
                  bordered: true
                  onClicked: root.runTest()
                }

                Button {
                  text: "Save"
                  tooltipText: root.testState === "ok" ? "Use this server" : "Test the server first"
                  enabled: root.testState === "ok"
                  opacity: enabled ? 1 : 0.45
                  foreground: root.fg
                  bordered: true
                  onClicked: root.saveServer()
                }
              }
            }
          }

          Column {
            visible: root.serverOpen
            width: parent.width
            spacing: Style.spacing.sm

            PanelSectionHeader {
              text: "Shortcut"
              foreground: root.fg
            }

            Toggle {
              width: parent.width
              label: "Play/pause with a key"
              description: root.shortcut
                ? root.shortcut.replace("XF86AudioPlay", "Play/Pause key").replace(/CTRL/g, "Ctrl").replace(/SHIFT/g, "Shift").replace(/SUPER/g, "Super").replace(/ALT/g, "Alt")
                  + " toggles Moodist; the plain key keeps controlling your music"
                : "Off. Turn on for Ctrl + Play/Pause"
              checked: root.shortcut !== ""
              foreground: root.fg
              onClicked: root.toggleShortcut()
            }
          }

          Row {
            width: parent.width
            spacing: Style.spacing.lg

            Text {
              id: volumeLabel
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(128)
              text: "Volume " + Math.round((root.service ? root.service.masterVolume : 0) * 100) + "%"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            PanelSlider {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - volumeLabel.width - parent.spacing
              bar: root.bar
              value: root.service ? root.service.masterVolume : 0
              onMoved: function(value) { root.service.setMasterVolume(value) }
            }
          }

          Text {
            visible: root.service !== null && root.service.lastError !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: root.service ? root.service.lastError : ""
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          PanelSectionHeader {
            visible: root.activeIds.length > 0
            text: "Mix"
            foreground: root.fg
          }

          Repeater {
            model: root.activeIds

            Row {
              required property string modelData
              width: body.width
              spacing: Style.spacing.lg

              Text {
                id: soundLabel
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(128)
                elide: Text.ElideRight
                text: root.labelFor(modelData)
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              PanelSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - soundLabel.width - removeButton.width - parent.spacing * 2
                bar: root.bar
                value: root.service ? root.service.volumeFor(modelData) : 0
                onMoved: function(value) { root.service.setSoundVolume(modelData, value) }
              }

              Button {
                id: removeButton
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                tooltipText: "Remove from mix"
                foreground: root.fg
                onClicked: root.service.removeSound(modelData)
              }
            }
          }

          Repeater {
            model: root.categories

            Column {
              required property var modelData
              width: body.width
              spacing: Style.spacing.sm

              PanelSectionHeader {
                text: modelData.title
                foreground: root.fg
              }

              Flow {
                width: parent.width
                spacing: Style.spacing.sm

                Repeater {
                  model: modelData.sounds

                  Button {
                    required property var modelData
                    text: modelData.label
                    selected: root.activeIds.indexOf(modelData.id) !== -1
                    bordered: true
                    foreground: root.fg
                    onClicked: root.service.toggleSound(modelData.id)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
