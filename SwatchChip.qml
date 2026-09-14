import QtQuick
import qs.Commons

// One colour in the tint picker: a swatch square with its name, painted in
// the same hover / pressed / selected states as SettingsTile.
Rectangle {
  id: chip

  property string label: ""
  property color swatch: Color.foreground
  property bool selected: false
  property color foreground: Color.foreground
  property color mutedColor: Qt.darker(foreground, 1.45)
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  signal clicked()

  readonly property bool hot: chipMouse.containsMouse
  implicitWidth: chipRow.implicitWidth + Style.space(16)
  implicitHeight: chipRow.implicitHeight + Style.space(10)
  radius: Style.cornerRadius
  color: chipMouse.pressed ? Style.pressedFillFor(chip.foreground, chip.accent)
    : hot ? Style.hoverFillFor(chip.foreground, chip.accent)
    : selected ? Style.selectedFillFor(chip.foreground, chip.accent)
    : "transparent"
  border.width: 1
  border.color: selected ? chip.accent : Util.alpha(chip.foreground, 0.18)

  Row {
    id: chipRow
    anchors.centerIn: parent
    spacing: Style.space(6)
    Rectangle {
      width: Style.space(12); height: Style.space(12); radius: 2
      anchors.verticalCenter: parent.verticalCenter
      color: chip.swatch
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: chip.label
      color: chip.selected ? chip.foreground : chip.mutedColor
      font.family: chip.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: chipMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.clicked()
  }
}
