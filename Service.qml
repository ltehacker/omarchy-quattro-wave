import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null

  property int barCount: 16
  property int framerate: 30
  readonly property int asciiRange: 100
  property var levels: []
  property bool available: true
  property bool alive: false
  property string lastError: ""
  property bool starting: false
  property bool haveSettings: false

  readonly property string helperPath: {
    var url = String(Qt.resolvedUrl("cava-run"))
    return decodeURIComponent(url.indexOf("file://") === 0 ? url.substring(7) : url)
  }
  readonly property real peak: Model.peak(levels)

  function emptyLevels(count) {
    var next = []
    var n = Math.max(1, count)
    for (var i = 0; i < n; i++) next.push(0)
    return next
  }

  // Widget instances are constructed with an empty settings object and have the
  // real one assigned a moment later. A mirrored bar creates one instance per
  // screen, so an empty push can land after a populated one and reset the bar
  // count to the default. Once real settings have been seen, ignore empty ones.
  function applySettings(settings) {
    var hasKeys = false
    if (settings) for (var k in settings) { hasKeys = true; break }
    if (!hasKeys && haveSettings) return
    if (hasKeys) haveSettings = true
    var nextBars = Model.parseIntSetting(settings && settings.bars, 16, 4, 64)
    var nextFps = Model.parseIntSetting(settings && settings.framerate, 30, 10, 60)
    var same = nextBars === barCount && nextFps === framerate
    barCount = nextBars
    framerate = nextFps
    if (levels.length !== barCount) levels = emptyLevels(barCount)
    if (same && (cavaProc.running || starting)) return
    startDebounce.restart()
  }

  function restart() {
    // A restart already in flight must not swallow this one: re-arm the
    // debounce so the newest bar count is what actually gets launched.
    if (starting) { startDebounce.restart(); return }
    available = true
    lastError = ""
    startDebounce.stop()
    starting = true
    cavaProc.running = false
    Qt.callLater(function() {
      cavaProc.command = ["bash", root.helperPath, String(root.barCount), String(root.framerate)]
      cavaProc.running = true
      starting = false
    })
  }

  Component.onCompleted: {
    levels = emptyLevels(barCount)
  }

  Process {
    id: cavaProc
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        root.alive = true
        root.available = true
        root.lastError = ""
        root.levels = Model.parseLevels(line, root.asciiRange, root.barCount)
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var text = String(line || "").trim()
        if (text) root.lastError = text
      }
    }
    onExited: function(exitCode, exitStatus) {
      root.alive = false
      if (exitCode === 127) {
        root.available = false
        if (!root.lastError) root.lastError = "cava is not installed"
      }
    }
  }

  Timer {
    id: startDebounce
    interval: 80
    repeat: false
    onTriggered: root.restart()
  }
}
