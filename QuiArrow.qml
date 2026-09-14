import QtQuick
import QtQuick.Shapes
import qs.Commons

// Small direction arrow on a 6-unit grid, scaled by `unit`. `halo` paints a
// disc in `haloColor` behind it so it stays readable where it overlaps the
// squirrel's tail; leave it off over a transparent bar, where a solid disc
// would sit on the wallpaper.
Item {
  id: arrow
  property bool up: false
  property color color: Color.foreground
  property bool halo: false
  property color haloColor: "transparent"
  property real unit: 1
  implicitWidth: 6 * unit
  implicitHeight: 6 * unit

  Shape {
    width: 6
    height: 6
    scale: arrow.unit
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: arrow.halo ? arrow.haloColor : "transparent"
      strokeColor: "transparent"
      strokeWidth: 0
      PathSvg { path: "M7 3a4 4 0 1 0 -8 0a4 4 0 1 0 8 0z" }
    }
    ShapePath {
      fillColor: "transparent"
      strokeColor: arrow.color
      strokeWidth: 1.4
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: arrow.up ? "M3 5.3V.7M1 2.6 3 .7l2 1.9" : "M3 .7v4.6M1 3.4 3 5.3l2-1.9" }
    }
  }
}
