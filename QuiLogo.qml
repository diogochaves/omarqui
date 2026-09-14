import QtQuick
import qs.Commons

// The Qui mark plus one of nine activity treatments. Everything it draws
// comes in as a property — colours included — so the bar instance and the
// settings previews are the same component with the same inputs, and a tile
// cannot drift away from what the bar shows.
//
// Geometry is laid out on a 16-unit canvas and scaled by `size`.
//
//   Static        nothing changes
//   Pulse         whole mark fades to 45 % and back
//   Dim           idle mark at 42 %, full when transferring
//   Tint          mark takes `tint` while transferring
//   Underline     2-unit line under the mark, left = down, right = up
//   Corners       arrows bottom-left / bottom-right, each while its direction runs
//   BesideUpDown  arrow column next to the mark, up first
//   BesideDownUp  the same column, down first
//   Drift         one arrow slides in its direction and fades
Item {
  id: logo

  property string activity: "Static"
  // "Bar" paints the direction marks in `color`, "State" in the
  // down/up colours below.
  property string arrowColor: "Bar"
  property color tint: Color.accent
  property bool downActive: false
  property bool upActive: false
  property color color: Color.foreground
  property color haloColor: "transparent"
  // Direction colours for arrowColor == "State". They default to the mark
  // colour, so a caller that does not set them just gets the "Bar" look.
  property color downStateColor: logo.color
  property color upStateColor: logo.color
  property real size: Style.bar.iconCanvas
  // Vertical room the logo is centred in (0 = unconstrained). Only the
  // underline reaches past the mark, and it is clamped to stay inside.
  property real availableHeight: 0

  readonly property real u: size / 16
  readonly property bool active: downActive || upActive
  readonly property bool beside: activity === "BesideUpDown" || activity === "BesideDownUp"
  readonly property color downMark: arrowColor === "State" ? downStateColor : color
  readonly property color upMark: arrowColor === "State" ? upStateColor : color
  readonly property color offMark: Util.alpha(color, 0.3)

  implicitWidth: size + (beside ? 9 * u : 0)
  implicitHeight: size

  property real pulsePhase: 1.0
  SequentialAnimation on pulsePhase {
    running: logo.activity === "Pulse" && logo.active
    loops: Animation.Infinite
    NumberAnimation { from: 1.0; to: 0.45; duration: 800; easing.type: Easing.InOutSine }
    NumberAnimation { from: 0.45; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
    onRunningChanged: if (!running) logo.pulsePhase = 1.0
  }

  // Drift runs one arrow at a time. The sweep is a fixed 2.8 s cycle and
  // `driftCycle` alternates which direction owns it, so a direction that
  // starts or stops mid-sweep takes effect at once — a duration bound to
  // downActive/upActive would only apply on the next loop.
  property real driftT: 0
  property int driftCycle: 0
  SequentialAnimation {
    running: logo.activity === "Drift" && logo.active
    loops: Animation.Infinite
    NumberAnimation { target: logo; property: "driftT"; from: 0; to: 1; duration: 2800 }
    ScriptAction { script: logo.driftCycle = (logo.driftCycle + 1) % 2 }
    onRunningChanged: if (!running) { logo.driftT = 0; logo.driftCycle = 0 }
  }
  function driftPhase(isUp) {
    if (isUp ? !logo.upActive : !logo.downActive) return -1
    if (logo.downActive && logo.upActive)
      return logo.driftCycle === (isUp ? 1 : 0) ? logo.driftT : -1
    return logo.driftT
  }
  function driftOpacity(p) {
    if (p < 0) return 0
    return p < 0.3 ? p / 0.3 * 0.85 : (1 - p) / 0.7 * 0.85
  }
  function driftOffset(p, isUp) {
    if (p < 0) return 0
    var d = (p * 2 - 1) * 1.5 * logo.u
    return isUp ? -d : d
  }
  readonly property real driftDown: driftPhase(false)
  readonly property real driftUp: driftPhase(true)

  // The underline halves sit 2 units below the 16-unit mark, which needs 24
  // units of bar to show; on a shorter bar they slide up against the mark
  // instead of being clipped away.
  readonly property real underlineY: logo.availableHeight > 0
    ? Math.min(18 * logo.u, (logo.availableHeight + logo.size) / 2 - 2 * logo.u)
    : 18 * logo.u

  // Every direction treatment draws a down/up pair that differs only in which
  // flag and colour it reads, so the pairing is declared once.
  component UnderlineHalf: Rectangle {
    property bool isUp: false
    visible: logo.activity === "Underline"
    y: logo.underlineY
    width: 6 * logo.u
    height: 2 * logo.u
    radius: logo.u
    color: isUp ? logo.upMark : logo.downMark
    opacity: (isUp ? logo.upActive : logo.downActive) ? 1 : 0
  }

  component DirArrow: QuiArrow {
    property bool isUp: false
    readonly property bool lit: isUp ? logo.upActive : logo.downActive
    up: isUp
    unit: logo.u
    haloColor: logo.haloColor
    color: lit ? (isUp ? logo.upMark : logo.downMark) : logo.offMark
  }

  QuiMark {
    markSize: logo.size
    markColor: logo.activity === "Tint" && logo.active ? logo.tint : logo.color
    opacity: logo.activity === "Pulse" ? logo.pulsePhase
      : logo.activity === "Dim" ? (logo.active ? 1.0 : 0.42)
      : 1.0
  }

  // Underline halves.
  UnderlineHalf { x: 1 * logo.u }
  UnderlineHalf { x: 9 * logo.u; isUp: true }

  // Corner arrows.
  DirArrow {
    visible: logo.activity === "Corners"
    halo: true
    x: -2 * logo.u; y: 12 * logo.u
    opacity: lit ? 1 : 0
  }
  DirArrow {
    visible: logo.activity === "Corners"
    isUp: true
    halo: true
    x: 12 * logo.u; y: 12 * logo.u
    opacity: lit ? 1 : 0
  }

  // Arrow column beside the mark, always present, lit per direction.
  DirArrow {
    visible: logo.beside
    isUp: logo.activity === "BesideUpDown"
    x: 19 * logo.u; y: 1 * logo.u
  }
  DirArrow {
    visible: logo.beside
    isUp: logo.activity === "BesideDownUp"
    x: 19 * logo.u; y: 9 * logo.u
  }

  // Quiet drift.
  DirArrow {
    visible: logo.activity === "Drift"
    halo: true
    x: 13 * logo.u; y: 13 * logo.u + logo.driftOffset(logo.driftDown, false)
    opacity: logo.driftOpacity(logo.driftDown)
  }
  DirArrow {
    visible: logo.activity === "Drift"
    isUp: true
    halo: true
    x: 13 * logo.u; y: 13 * logo.u + logo.driftOffset(logo.driftUp, true)
    opacity: logo.driftOpacity(logo.driftUp)
  }
}
