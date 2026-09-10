import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "itdir.cava"

  // Injected by the host bar. On Omarchy 4.0.3+ this is a scoped facade; a
  // first-party bar's facade can resolve services, a replacement bar's cannot.
  property var shell: null
  property var cavaService: null
  property var localService: null

  readonly property int barCount: Model.parseIntSetting(setting("bars", 16), 16, 4, 64)
  readonly property string colorMode: Model.parseColorMode(setting("color", "accent"))
  readonly property bool hideWhenSilent: setting("hideWhenSilent", false) === true
  readonly property int barThickness: Math.max(2, Style.space(3))
  readonly property int barGap: Math.max(1, Style.space(1))
  readonly property int pad: Style.space(8)
  readonly property var levels: cavaService && cavaService.levels ? cavaService.levels : []
  readonly property bool silent: !cavaService || !cavaService.alive || Model.peak(levels) < 0.04
  readonly property color accentColor: Color.accent
  readonly property color mutedColor: Color.muted
  readonly property color foregroundColor: bar ? bar.barForeground : Color.foreground

  // Omarchy 4.0.3 scopes third-party plugins to their own services, and gives a
  // replacement bar a deliberately service-less entry facade so it cannot reach
  // another plugin's live service object. A widget hosted in such a bar must
  // therefore run its own cava process. Prefer the shared service where it is
  // reachable (first-party bars, and Omarchy before 4.0.3); fall back to a
  // local instance otherwise. `allowMultiple` is false, so this stays one
  // process per bar instance.
  function ensureLocalService() {
    if (localService) return localService
    var comp = Qt.createComponent(Qt.resolvedUrl("Service.qml"))
    if (comp.status === Component.Ready) {
      localService = comp.createObject(root)
    } else if (comp.status === Component.Error) {
      console.warn("itdir.cava: local service failed to load:", comp.errorString())
    }
    return localService
  }

  // Give the host a real chance to hand us the shared service before
  // self-hosting. The host injects `shell` after construction, so an immediate
  // fallback would spawn a second, redundant service: both launch cava-run,
  // the helper's flock lets only one survive, and whichever wins may be the one
  // that never received the widget's settings.
  property int resolveAttempts: 0
  readonly property int resolveGraceTicks: 8   // ~2s at the 250ms retry Timer

  function resolveService() {
    var next = null
    if (shell && typeof shell.serviceFor === "function")
      next = shell.serviceFor("itdir.cava")
    if (!next && bar && bar.shell && typeof bar.shell.serviceFor === "function")
      next = bar.shell.serviceFor("itdir.cava")
    if (!next) {
      resolveAttempts += 1
      if (resolveAttempts < resolveGraceTicks) return
      next = ensureLocalService()
    }
    if (!next || next === cavaService) return
    cavaService = next
    cavaService.applySettings(settings)
  }

  function pushSettings() {
    if (cavaService) cavaService.applySettings(settings)
  }

  function cssColor(c) {
    return "rgb(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ")"
  }

  onBarChanged: resolveService()
  onSettingsChanged: pushSettings()
  Component.onCompleted: resolveService()

  Timer {
    interval: 250
    running: root.cavaService === null
    repeat: true
    onTriggered: root.resolveService()
  }

  visible: !(hideWhenSilent && silent)
  implicitWidth: vertical
    ? barSize
    : pad + barCount * (barThickness + barGap) - barGap
  implicitHeight: vertical
    ? pad + barCount * (barThickness + barGap) - barGap
    : barSize

  Canvas {
    id: canvas
    anchors.fill: parent
    anchors.leftMargin: vertical ? 0 : Math.round(root.pad / 2)
    anchors.rightMargin: vertical ? 0 : Math.round(root.pad / 2)
    anchors.topMargin: vertical ? Math.round(root.pad / 2) : Style.space(4)
    anchors.bottomMargin: vertical ? Math.round(root.pad / 2) : Style.space(4)
    renderTarget: Canvas.FramebufferObject
    renderStrategy: Canvas.Cooperative

    onPaint: {
      var ctx = getContext("2d")
      var w = canvas.width
      var h = canvas.height
      ctx.clearRect(0, 0, w, h)
      if (w < 1 || h < 1) return

      var count = root.barCount
      var values = root.levels
      var gap = root.barGap
      var thickness = root.barThickness
      var available = root.cavaService && root.cavaService.available
      var accent = root.accentColor
      var muted = root.mutedColor
      var foreground = root.foregroundColor
      var mode = root.colorMode
      var isVertical = root.vertical

      for (var i = 0; i < count; i++) {
        var level = 0
        if (values && i < values.length) level = Model.clamp01(values[i])
        var shown = Math.max(level, 0.06)
        var fill = Model.barColor(mode, level, accent, muted, foreground)
        ctx.globalAlpha = available ? 1 : 0.28
        ctx.fillStyle = root.cssColor(fill)
        if (isVertical) {
          var bh = thickness
          var bw = Math.max(1, Math.round(w * shown))
          ctx.fillRect(0, i * (thickness + gap), bw, bh)
        } else {
          var bw2 = thickness
          var bh2 = Math.max(1, Math.round(h * shown))
          ctx.fillRect(i * (thickness + gap), h - bh2, bw2, bh2)
        }
      }
      ctx.globalAlpha = 1
    }
  }

  Connections {
    target: root.cavaService
    function onLevelsChanged() { canvas.requestPaint() }
  }

  onBarCountChanged: canvas.requestPaint()
  onColorModeChanged: canvas.requestPaint()
  onAccentColorChanged: canvas.requestPaint()
  onMutedColorChanged: canvas.requestPaint()
  onForegroundColorChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.RightButton
    cursorShape: Qt.ArrowCursor
    onEntered: {
      if (!root.bar) return
      var text = "Cava"
      if (root.cavaService && !root.cavaService.available)
        text = root.cavaService.lastError || "cava is not running"
      root.bar.showTooltip(root, text)
    }
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onPressed: function(mouse) {
      if (mouse.button === Qt.RightButton && root.cavaService) root.cavaService.restart()
    }
  }
}
