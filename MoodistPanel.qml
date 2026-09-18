import QtQuick
import qs.Commons
import qs.Ui

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
  readonly property string instanceHost: service ? service.baseUrl.replace(/^https?:\/\//, "") : ""

  onOpenedChanged: if (opened) Qt.callLater(function() { keyCatcher.forceActiveFocus() })

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

              Text {
                text: root.instanceHost
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              id: controls
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Button {
                text: root.service && root.service.playing ? "Pause" : "Play"
                enabled: root.service ? root.service.hasMix : false
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

          Row {
            width: parent.width
            spacing: Style.spacing.lg

            Text {
              id: volumeLabel
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(96)
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
                width: Style.space(96)
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
