function clamp01(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return 0
  if (n > 1) return 1
  return n
}

function parseIntSetting(value, fallback, min, max) {
  var n = parseInt(value, 10)
  if (!isFinite(n)) n = fallback
  if (n < min) n = min
  if (n > max) n = max
  return n
}

function parseColorMode(value) {
  var mode = String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  if (mode === "foreground" || mode === "gradient" || mode === "accent") return mode
  return "accent"
}

function parseLevels(line, range, expected) {
  var parts = String(line || "").split(";")
  var max = Math.max(1, Number(range) || 100)
  var count = Math.max(1, Number(expected) || 1)
  var out = []
  for (var i = 0; i < parts.length && out.length < count; i++) {
    if (parts[i] === "") continue
    var n = Number(parts[i])
    if (!isFinite(n)) n = 0
    out.push(clamp01(n / max))
  }
  while (out.length < count) out.push(0)
  return out
}

function peak(levels) {
  var max = 0
  var values = Array.isArray(levels) ? levels : []
  for (var i = 0; i < values.length; i++) {
    var n = Number(values[i])
    if (isFinite(n) && n > max) max = n
  }
  return max
}

function mixColor(fromColor, toColor, t) {
  var a = clamp01(t)
  return Qt.rgba(
    fromColor.r + (toColor.r - fromColor.r) * a,
    fromColor.g + (toColor.g - fromColor.g) * a,
    fromColor.b + (toColor.b - fromColor.b) * a,
    1
  )
}

function barColor(mode, level, accent, muted, foreground) {
  if (mode === "foreground") return foreground
  if (mode === "gradient") return mixColor(muted, accent, clamp01(level))
  return accent
}
