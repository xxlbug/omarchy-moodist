import QtQuick
import QtQml
import QtMultimedia
import Quickshell
import Quickshell.Io

// Owns playback. The bar mounts one widget per monitor, so the players live
// here, in the plugin's single service instance, and every widget is a view
// onto it. Otherwise each monitor would play its own copy of the mix.
Item {
  id: root

  property var shell: null

  readonly property string defaultInstance: "https://moodist.mvze.net"
  property string baseUrl: defaultInstance

  // Catalogue from sounds.json: [{ id, title, sounds: [{ id, label, src }] }]
  property var categories: []
  property var soundsById: ({})

  // Active sound ids, in the order they were added. A ListModel rather than a
  // JS array so adding or removing one sound does not rebuild (and restart)
  // every other player.
  ListModel { id: activeModel }
  property alias activeModel: activeModel
  property var activeIds: []
  property var volumes: ({})
  property real masterVolume: 0.8
  property bool playing: false
  property string lastError: ""

  readonly property bool hasMix: activeIds.length > 0
  readonly property real defaultSoundVolume: 0.5
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/moodist.json"
  property bool stateLoaded: false

  function normalizedBase(url) {
    var s = String(url || "").trim()
    while (s.length > 0 && s.charAt(s.length - 1) === "/") s = s.slice(0, -1)
    return s || defaultInstance
  }

  function soundUrl(id) {
    var sound = soundsById[id]
    return sound ? baseUrl + sound.src : ""
  }

  function isActive(id) {
    return activeIds.indexOf(id) !== -1
  }

  function volumeFor(id) {
    var v = volumes[id]
    return v === undefined || v === null ? defaultSoundVolume : v
  }

  function syncActiveIds() {
    var ids = []
    for (var i = 0; i < activeModel.count; i++) ids.push(activeModel.get(i).soundId)
    activeIds = ids
  }

  function addSound(id) {
    if (!soundsById[id] || isActive(id)) return
    activeModel.append({ soundId: id })
    syncActiveIds()
    // Picking a sound is a request to hear it, as on the Moodist site.
    playing = true
    save()
  }

  function removeSound(id) {
    for (var i = 0; i < activeModel.count; i++) {
      if (activeModel.get(i).soundId === id) {
        activeModel.remove(i)
        break
      }
    }
    syncActiveIds()
    if (!hasMix) playing = false
    save()
  }

  function toggleSound(id) {
    if (isActive(id)) removeSound(id)
    else addSound(id)
  }

  function setSoundVolume(id, value) {
    var next = ({})
    for (var k in volumes) next[k] = volumes[k]
    next[id] = Math.max(0, Math.min(1, value))
    volumes = next
    save()
  }

  function setMasterVolume(value) {
    masterVolume = Math.max(0, Math.min(1, value))
    save()
  }

  function togglePlaying() {
    if (!hasMix) return false
    playing = !playing
    return true
  }

  function clearMix() {
    playing = false
    activeModel.clear()
    syncActiveIds()
    save()
  }

  function loadCatalogue(raw) {
    try {
      var data = JSON.parse(raw)
      var byId = ({})
      for (var c = 0; c < data.categories.length; c++) {
        var sounds = data.categories[c].sounds
        for (var s = 0; s < sounds.length; s++) byId[sounds[s].id] = sounds[s]
      }
      soundsById = byId
      categories = data.categories
    } catch (error) {
      console.warn("moodist: sounds.json is invalid:", error.message)
    }
  }

  function loadState(raw) {
    try {
      var state = JSON.parse(raw)
      if (typeof state.masterVolume === "number") masterVolume = state.masterVolume
      if (state.volumes && typeof state.volumes === "object") volumes = state.volumes
      activeModel.clear()
      var ids = Array.isArray(state.mix) ? state.mix : []
      for (var i = 0; i < ids.length; i++)
        if (soundsById[ids[i]]) activeModel.append({ soundId: ids[i] })
      syncActiveIds()
    } catch (error) {
      console.warn("moodist: state file is invalid, starting empty:", error.message)
    }
    // Restores the mix, not playback: sound starting on its own after a login
    // or a shell restart would be a surprise.
    stateLoaded = true
  }

  function save() {
    if (!stateLoaded) return
    stateFile.setText(JSON.stringify({
      version: 1,
      mix: activeIds,
      volumes: volumes,
      masterVolume: masterVolume
    }, null, 2) + "\n")
  }

  FileView {
    id: catalogueFile
    path: String(Qt.resolvedUrl("sounds.json")).replace(/^file:\/\//, "")
    printErrors: true
    onLoaded: root.loadCatalogue(text())
  }

  FileView {
    id: stateFile
    // Held back until the catalogue is in, so a saved mix is checked against
    // the sounds that actually exist.
    path: root.categories.length > 0 ? root.statePath : ""
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("{}")
  }

  // `omarchy-shell moodist toggle` etc., for keybindings and scripts.
  IpcHandler {
    target: "moodist"

    function toggle(): void { root.togglePlaying() }
    function play(): void { if (root.hasMix) root.playing = true }
    function pause(): void { root.playing = false }
    function add(id: string): void { root.addSound(id) }
    function remove(id: string): void { root.removeSound(id) }
    function clear(): void { root.clearMix() }
    function status(): string {
      return JSON.stringify({
        instance: root.baseUrl,
        playing: root.playing,
        masterVolume: root.masterVolume,
        mix: root.activeIds,
        lastError: root.lastError
      })
    }
  }

  Instantiator {
    model: activeModel

    delegate: MediaPlayer {
      id: player

      required property string soundId

      source: root.soundUrl(soundId)
      loops: MediaPlayer.Infinite
      audioOutput: AudioOutput {
        volume: root.masterVolume * root.volumeFor(player.soundId)
      }

      function sync() {
        if (root.playing) play()
        else pause()
      }

      Component.onCompleted: sync()
      onSourceChanged: sync()
      onErrorOccurred: function(error, errorString) {
        root.lastError = errorString + " (" + source + ")"
        console.warn("moodist:", root.lastError)
      }

      property Connections _playing: Connections {
        target: root
        function onPlayingChanged() { player.sync() }
      }
    }
  }
}
