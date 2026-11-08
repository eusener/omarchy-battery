import QtQuick
import qs.Commons
import qs.Commons as Commons
import "UsageModel.js" as UsageModel

Item {
  id: chart
  property var session: null
  property color foreground: "white"
  property string fontFamily: "sans-serif"
  property string accessibleLabel: ""
  readonly property var points: UsageModel.bars(session)
  readonly property real elapsed: session ? Math.max(0, session.elapsed) : 0
  implicitHeight: Style.space(166)
  Accessible.role: Accessible.Graphic
  Accessible.name: accessibleLabel

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  function duration(seconds) {
    return UsageModel.duration(seconds, strings.t, Commons.I18n.formatNumber)
  }

  Item {
    id: plot
    anchors.left: parent.left
    anchors.leftMargin: Style.space(42)
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: Style.space(8)
    height: Style.space(126)
    Repeater {
      model: [100, 50, 0]
      Item {
        required property int modelData
        width: plot.width
        y: plot.height * (1 - modelData / 100)
        Rectangle {
          width: parent.width
          height: 1
          color: chart.foreground
          opacity: 0.15
        }
        Text {
          anchors.right: parent.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.top
          text: Commons.I18n.formatNumber(modelData) + "%"
          textFormat: Text.PlainText
          color: chart.foreground
          opacity: 0.65
          font.family: chart.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
    Repeater {
      model: chart.points
      Rectangle {
        required property var modelData
        required property int index
        readonly property real slotWidth: plot.width / 24
        readonly property real timeScale: chart.elapsed > 0 ? (plot.width - slotWidth) / chart.elapsed : 0
        readonly property real previousGap: index > 0 ? (modelData.elapsed - chart.points[index - 1].elapsed) * timeScale : slotWidth
        readonly property real nextGap: index < chart.points.length - 1 ? (chart.points[index + 1].elapsed - modelData.elapsed) * timeScale : slotWidth
        // Time determines position; compacting old observations cannot compress time.
        x: modelData.elapsed * timeScale
        y: plot.height - height
        width: Math.max(1, Math.min(slotWidth, previousGap, nextGap) - Style.space(3))
        height: plot.height * Math.max(0, Math.min(100, modelData.percentage)) / 100
        radius: Style.space(2)
        color: chart.foreground
        opacity: index === chart.points.length - 1 ? 1 : 0.55
      }
    }
  }
  Row {
    anchors.left: plot.left
    anchors.right: plot.right
    anchors.top: plot.bottom
    anchors.topMargin: Style.space(10)
    Repeater {
      model: [0, chart.elapsed / 2, chart.elapsed]
      Text {
        required property real modelData
        required property int index
        width: plot.width / 3
        text: chart.duration(modelData)
        textFormat: Text.PlainText
        horizontalAlignment: index === 0 ? Text.AlignLeft : (index === 1 ? Text.AlignHCenter : Text.AlignRight)
        color: chart.foreground
        opacity: 0.65
        font.family: chart.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
