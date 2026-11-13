// Select actual observations from equal active-time buckets, never interpolate.
function bars(session) {
  if (!session || !Array.isArray(session.samples) || !session.samples.length) return []
  var points = session.samples
  if (points.length <= 24) return points
  var duration = Math.max(1, Number(session.elapsed))
  var buckets = {}
  for (var i = 1; i < points.length - 1; i++) {
    var bucket = Math.min(21, Math.floor(points[i].elapsed / duration * 22))
    buckets[bucket] = points[i]
  }
  var result = [points[0]]
  for (var key = 0; key < 22; key++) {
    if (buckets[key]) result.push(buckets[key])
  }
  result.push(points[points.length - 1])
  return result
}

function duration(seconds, translate, format) {
  var minutes = Math.floor(Math.max(0, Number(seconds) || 0) / 60)
  var hours = Math.floor(minutes / 60)
  var fmt = typeof format === "function" ? format : String
  var key = hours > 0 ? "usageHours" : "usageMinutes"
  var text = typeof translate === "function" ? translate(key) : (hours > 0 ? "%1 h %2 min" : "%1 min")
  return text.replace("%1", fmt(hours > 0 ? hours : minutes)).replace("%2", fmt(minutes % 60))
}

// Mean time on battery between recharges: the persisted history plus the
// current session once it has finished. Mirrors usage.py's 5-minute floor.
var MIN_AVERAGE_ELAPSED = 300

function average(session) {
  if (!session) return { seconds: 0, count: 0 }
  var entries = Array.isArray(session.history) ? session.history.slice() : []
  if (!session.active) entries.push(session)
  var total = 0
  var count = 0
  for (var i = 0; i < entries.length; i++) {
    var elapsed = Number(entries[i] && entries[i].elapsed)
    if (!isFinite(elapsed) || elapsed < MIN_AVERAGE_ELAPSED) continue
    total += elapsed
    count++
  }
  return { seconds: count ? total / count : 0, count: count }
}

if (typeof module !== "undefined") module.exports = { bars: bars, duration: duration, average: average }
