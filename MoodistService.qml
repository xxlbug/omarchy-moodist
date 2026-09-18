import QtQuick
import QtQml
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Owns playback. The bar mounts one widget per monitor, so the players live
// here, in the plugin's single service instance, and every widget is a view
// onto it. Otherwise each monitor would play its own copy of the mix.
Item {
  id: root

  property var shell: null

  readonly property string pluginId: "net.2plastic.moodist"
  // No built-in server until the Moodist author has agreed to plugin traffic
  // on the official instance (moodist.mvze.net); users set their own.
  readonly property string defaultInstance: ""
  readonly property string defaultShortcut: "CTRL + XF86AudioPlay"
  // Settings as the widget sees them. Widgets get their settings the moment
  // shell.json changes, so these win when set.
  property var widgetSettings: null
  // This plugin's own bar entry, for when no widget has reported yet
  // (startup). shell.barConfig is refreshed one change late (Omarchy
  // snapshots it before the new config lands), so it is only the fallback.
  readonly property var configuredEntry: {
    var layout = shell && shell.barConfig ? shell.barConfig.layout : null
    if (!layout) return null
    var sections = ["left", "center", "right"]
    for (var i = 0; i < sections.length; i++) {
      var entries = layout[sections[i]] || []
      for (var j = 0; j < entries.length; j++)
        if (entries[j] && entries[j].id === pluginId) return entries[j]
    }
    return null
  }
  readonly property var entry: widgetSettings || configuredEntry || ({})
  readonly property string baseUrl: normalizedBase(entry.instanceUrl)

  // Optional global key for play/pause, e.g. "CTRL + XF86AudioPlay"; empty is
  // off. Registered at runtime through `hyprctl eval`, the way Omarchy's own
  // o.bind does it, since plugins have no keybinding API.
  readonly property string shortcut: validShortcut(entry.shortcut)
  property string appliedShortcut: ""

  // Only key names and "+" reach the Lua string, never quotes.
  function validShortcut(value) {
    var s = String(value || "").trim()
    return /^[A-Za-z0-9_]+( *\+ *[A-Za-z0-9_]+)*$/.test(s) ? s : ""
  }

  function hyprEval(lua) {
    Quickshell.execDetached(["hyprctl", "eval", lua])
  }

  function applyShortcut() {
    if (appliedShortcut === shortcut) return
    if (appliedShortcut) hyprEval('hl.unbind("' + appliedShortcut + '")')
    if (shortcut) hyprEval('hl.bind("' + shortcut + '", hl.dsp.exec_cmd("omarchy-shell moodist toggle"), '
      + '{ description = "Moodist play/pause", locked = true })')
    appliedShortcut = shortcut
  }

  onShortcutChanged: applyShortcut()
  Component.onCompleted: applyShortcut()
  // Removing or reloading the plugin must not leave a key pointing at it.
  Component.onDestruction: if (appliedShortcut) hyprEval('hl.unbind("' + appliedShortcut + '")')

  // A Hyprland config reload drops every runtime binding.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "configreloaded") return
      root.appliedShortcut = ""
      root.applyShortcut()
    }
  }

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
  readonly property bool hasServer: baseUrl !== ""
  readonly property real defaultSoundVolume: 0.5
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/moodist.json"
  property bool stateLoaded: false

  function normalizedBase(url) {
    var s = String(url || "").trim()
    while (s.length > 0 && s.charAt(s.length - 1) === "/") s = s.slice(0, -1)
    return s || defaultInstance
  }

  // Checks that `url` serves Moodist's sounds by asking for the first file of
  // the catalogue. Calls done(ok, message) exactly once.
  function testInstance(url, done) {
    var base = String(url || "").trim()
    while (base.length > 0 && base.charAt(base.length - 1) === "/") base = base.slice(0, -1)
    if (!/^https?:\/\/[^\/\s]+/.test(base)) {
      done(false, "Enter a URL starting with https:// or http://")
      return
    }
    var probe = categories.length > 0 ? categories[0].sounds[0].src : "/sounds/nature/river.mp3"
    var finished = false
    var timeout = Qt.createQmlObject("import QtQuick; Timer { interval: 8000; running: true }", root)
    var xhr = new XMLHttpRequest()
    function finish(ok, message) {
      if (finished) return
      finished = true
      timeout.destroy()
      done(ok, message)
    }
    timeout.triggered.connect(function() {
      xhr.abort()
      finish(false, "No answer within 8 seconds")
    })
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var type = String(xhr.getResponseHeader("Content-Type") || "")
      if (xhr.status === 200 && type.indexOf("audio/") === 0) finish(true, "Moodist sounds found")
      else if (xhr.status === 0) finish(false, "Could not connect")
      else if (xhr.status === 200) finish(false, "Answers, but not with Moodist sounds (" + (type || "no type") + ")")
      else finish(false, "HTTP " + xhr.status + " for " + probe)
    }
    xhr.open("HEAD", base + probe)
    xhr.send()
  }

  function soundUrl(id) {
    var sound = soundsById[id]
    return sound && hasServer ? baseUrl + sound.src : ""
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
    if (hasServer) playing = true
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
    if (!hasMix || !hasServer) return false
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
    function play(): void { if (root.hasMix && root.hasServer) root.playing = true }
    function pause(): void { root.playing = false }
    function add(id: string): void { root.addSound(id) }
    function remove(id: string): void { root.removeSound(id) }
    function clear(): void { root.clearMix() }
    function status(): string {
      return JSON.stringify({
        instance: root.baseUrl,
        playing: root.playing,
        masterVolume: root.masterVolume,
        shortcut: root.appliedShortcut,
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
