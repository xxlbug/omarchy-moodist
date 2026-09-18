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
  readonly property string instanceUrl: setting("instanceUrl", "https://moodist.mvze.net")
  readonly property bool playing: service ? service.playing : false
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  // The service is created by the shell, asynchronously and possibly after
  // this widget, so look it up until it shows up.
  function resolveService() {
    if (!service && bar && bar.shell && typeof bar.shell.serviceFor === "function")
      service = bar.shell.serviceFor(moduleName)
    if (service) service.baseUrl = service.normalizedBase(instanceUrl)
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
  onInstanceUrlChanged: resolveService()

  Timer {
    interval: 250
    repeat: true
    running: root.service === null
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
