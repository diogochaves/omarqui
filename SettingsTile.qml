import QtQuick
import QtQuick.Layouts
import qs.Commons

// One choice in the settings view: a miniature of the bar showing exactly
// what the choice draws (put it in as the default child), with a caption
// underneath. Paints its hover / pressed / selected states like the kit
// Button so it sits with the rest of the panel.
Rectangle {
  id: tile

  property string caption: ""
  property bool selected: false
  property color foreground: Color.foreground
  property color mutedColor: Qt.darker(foreground, 1.45)
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  // The strip behind the preview: the bar's own background, so the miniature
  // sits on what it would sit on up there.
  property color previewBackground: Color.background
  default property alias preview: previewSlot.data
  signal clicked()

  readonly property bool hot: tileMouse.containsMouse
  implicitHeight: tileColumn.implicitHeight + Style.space(12)
  radius: Style.cornerRadius
  color: tileMouse.pressed ? Style.pressedFillFor(tile.foreground, tile.accent)
    : hot ? Style.hoverFillFor(tile.foreground, tile.accent)
    : selected ? Style.selectedFillFor(tile.foreground, tile.accent)
    : "transparent"
  border.width: 1
  border.color: selected ? tile.accent : Util.alpha(tile.foreground, 0.18)

  ColumnLayout {
    id: tileColumn
    anchors.fill: parent
    anchors.margins: Style.space(6)
    spacing: Style.space(4)

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(30)
      radius: Style.cornerRadius
      color: tile.previewBackground
      Item { id: previewSlot; anchors.fill: parent }
    }

    Text {
      Layout.fillWidth: true
      text: tile.caption
      horizontalAlignment: Text.AlignHCenter
      color: tile.selected ? tile.foreground : tile.mutedColor
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: tileMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.clicked()
  }
}
