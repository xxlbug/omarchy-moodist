import QtQuick
import qs.Commons
import qs.Ui

// Bar button. Left click plays/pauses the mix (or opens the mixer when there
// is nothing to play yet), right or middle click opens the mixer, scrolling
// changes the master volume.
BarWidget {
  id: root
  moduleName: "net.2plastic.moodist"

  property var service: null
  readonly property bool playing: service ? service.playing : false
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  // The shell creates the service asynchronously, possibly after this widget,
  // and may replace it when the plugin reloads (e.g. `omarchy plugin update`).
  // So keep asking for the current instance instead of holding on to the first.
  function resolveService() {
    var current = bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor(moduleName) : null
    if (current !== service) service = current
    if (service && service.widgetSettings !== settings) service.widgetSettings = settings
    injectPanel()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.service = root.service
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function toggle() { opened ? close() : open() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: resolveService()
  onSettingsChanged: resolveService()

  Timer {
    interval: root.service ? 1000 : 250
    repeat: true
    running: true
    onTriggered: root.resolveService()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("MoodistPanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-headphones
    text: String.fromCodePoint(0xF02CB)
    slotSize: Style.bar.statusSlot
    dimmed: !root.playing
    tooltipText: !root.service ? "Moodist"
      : !root.service.hasServer ? "Moodist: set a server"
      : root.playing ? "Moodist: playing " + root.service.activeIds.length + " sound(s)"
      : root.service.hasMix ? "Moodist: paused"
      : "Moodist: pick sounds"

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) {
        if (!root.service || !root.service.togglePlaying()) root.toggle()
      } else {
        root.toggle()
      }
    }

    onWheelMoved: function(delta) {
      if (!root.service) return
      root.service.setMasterVolume(root.service.masterVolume + (delta > 0 ? 0.05 : -0.05))
    }
  }
}
