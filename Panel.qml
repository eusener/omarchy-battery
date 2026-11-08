import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  property bool technicalDetails: false
  property var batteryDetails: []
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates(), Commons.I18n.t)
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Commons.Color.foreground
  }

  function reading(raw) {
    return Model.localizeReading(raw, Commons.I18n.formatNumber)
  }

  readonly property string heroStatusText: modeLabel()

  function refresh() {
    if (!batteryPresent) return

    if (!detailsProc.running) detailsProc.running = true
    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  ShellIpc {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        // Deferred: closing here writes the very property whose change
        // is being notified, which QML reports as a binding loop for
        // Panel.opened on every open attempt without a battery.
        Qt.callLater(function() { root.close() })
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  function detailValue(device, key, unit, decimals) {
    var value = device[key]
    if (value === null || value === undefined || value === "") return strings.t("unavailable")
    if (typeof value === "number") return Commons.I18n.formatNumber(value, decimals || 0) + (unit ? " " + unit : "")
    return String(value)
  }

  Process {
    id: detailsProc
    command: ["python3", Qt.resolvedUrl("battery.py").toString().replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.batteryDetails = JSON.parse(text) } catch (e) { root.batteryDetails = [] }
      }
    }
  }

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.batteryIcon()
    labelText: root.showPercentage && !vertical ? Commons.I18n.formatNumber(Math.round(root.batteryFraction * 100)) + "%" : ""
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias heroStatus: heroStatus
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text, modifiers) {
        if (text.toLowerCase() === "d" && modifiers === Qt.NoModifier) root.technicalDetails = !root.technicalDetails
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        function scrollPage(direction) {
          contentY = Math.max(0, Math.min(contentHeight - height, contentY + direction * height * 0.8))
        }
        Shortcut { sequence: "PgDown"; enabled: root.opened; onActivated: scroller.scrollPage(1) }
        Shortcut { sequence: "PgUp"; enabled: root.opened; onActivated: scroller.scrollPage(-1) }
      Column {
        id: column
        anchors.left: parent.left
        width: scroller.width - Style.space(12)
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: Commons.I18n.t("power.battery")
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText
              color: root.bar.foreground
              opacity: 0.65
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.reading(root.batteryInfo.percentage) || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Style.duration(220) } }


          }
        }

        Row {
          width: parent.width
          spacing: Style.space(10)
          MetricCard {
            width: (parent.width - parent.spacing) / 2
            label: root.chargeThresholdActive ? Commons.I18n.t("power.chargeLimit") : (root.discharging ? Commons.I18n.t("power.timeLeft") : Commons.I18n.t("power.timeToFull"))
            value: root.chargeThresholdActive ? (root.reading(root.batteryInfo.threshold) || "—") : (root.batteryFlowIdle ? "—" : (root.batteryInfo.time || "—"))
          }
          MetricCard {
            width: (parent.width - parent.spacing) / 2
            label: root.chargeThresholdActive ? Commons.I18n.t("power.batteryState") : (root.discharging ? Commons.I18n.t("power.discharging") : Commons.I18n.t("power.charging"))
            value: root.chargeThresholdActive ? Commons.I18n.t("power.holding") : (root.batteryFull ? "—" : (root.reading(root.batteryInfo.rate) || "—"))
          }
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: Commons.I18n.t("power.powerProfile")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: Model.profileLabel(modelData, Commons.I18n.t)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }
        Text {
          visible: root.batteryDetails.length === 0
          width: parent.width
          text: strings.t("empty")
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.bar.foreground
          opacity: 0.65
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Repeater {
          model: root.batteryDetails
          Column {
            id: deviceColumn
            required property var modelData
            width: column.width
            spacing: Style.space(16)

            Item {
              width: parent.width
              implicitHeight: deviceTitle.implicitHeight
              Text {
                id: deviceTitle
                width: parent.width * 0.8
                text: strings.t("condition")
                textFormat: Text.PlainText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                color: root.bar.foreground
                wrapMode: Text.Wrap
              }
              Text {
                anchors.right: parent.right
                text: deviceColumn.modelData.name
                textFormat: Text.PlainText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                color: root.bar.foreground
                opacity: 0.5
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)
              Repeater {
                model: ["health", "degradation", "cycles"]
                MetricCard {
                  required property string modelData
                  width: (deviceColumn.width - Style.space(16)) / 3
                  label: strings.t(modelData)
                  value: deviceColumn.modelData[modelData] === null ? "—" : root.detailValue(deviceColumn.modelData, modelData, modelData === "cycles" ? "" : "%", modelData === "cycles" ? 0 : 1)
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(12)
              Repeater {
                model: ["design", "full", "now"]
                CapacityReading {
                  required property string modelData
                  width: deviceColumn.width
                  label: strings.t(modelData)
                  value: root.detailValue(deviceColumn.modelData, modelData, deviceColumn.modelData.capacity_unit, deviceColumn.modelData.capacity_unit === "Wh" ? 2 : 0)
                  fraction: deviceColumn.modelData.design > 0 && deviceColumn.modelData[modelData] !== null ? Math.min(1, deviceColumn.modelData[modelData] / deviceColumn.modelData.design) : 0
                  fillOpacity: modelData === "design" ? 0.25 : (modelData === "full" ? 0.55 : 1)
                }
              }
              Text {
                width: parent.width
                text: strings.t("capacityNote")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: root.bar.foreground
                opacity: 0.5
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            PanelSeparator { foreground: root.bar.foreground }
            Column {
              width: parent.width
              spacing: Style.space(10)
              DetailLine { label: strings.t("manufacturer"); value: root.detailValue(deviceColumn.modelData, "manufacturer", "", 0) }
              DetailLine { label: strings.t("model"); value: root.detailValue(deviceColumn.modelData, "model", "", 0) }
            }
            Column {
              visible: root.technicalDetails
              width: parent.width
              spacing: Style.space(10)
              Repeater {
                model: ["brand", "part_number", "serial", "technology", "voltage", "power", "temperature"]
                DetailLine {
                  required property string modelData
                  label: strings.t(modelData)
                  value: root.detailValue(deviceColumn.modelData, modelData, modelData === "voltage" ? "V" : (modelData === "power" ? "W" : (modelData === "temperature" ? "°C" : "")), 2)
                }
              }
            }
          }
        }
        Button {
          visible: root.batteryDetails.length > 0
          width: parent.width
          text: root.technicalDetails ? strings.t("hideTechnical") : strings.t("showTechnical")
          tooltipText: strings.t("technicalShortcut")
          iconText: root.technicalDetails ? "−" : "+"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          fontSize: Style.font.bodySmall
          bordered: true
          active: root.technicalDetails
          onClicked: root.technicalDetails = !root.technicalDetails
        }

      }
      }
    }
  }

  component MetricCard: Rectangle {
    id: metric
    property string label: ""
    property string value: ""
    implicitHeight: metricContent.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.045)
    Column {
      id: metricContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(12)
      spacing: Style.space(6)
      Text {
        width: parent.width
        text: metric.label
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.bar.foreground
        opacity: 0.6
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width
        text: metric.value
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
    }
  }

  component DetailLine: Item {
    id: line
    property string label: ""
    property string value: ""
    width: parent.width
    implicitHeight: Math.max(lineLabel.implicitHeight, lineValue.implicitHeight)
    Text {
      id: lineLabel
      width: parent.width * 0.45
      text: line.label
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.bar.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      id: lineValue
      anchors.right: parent.right
      width: parent.width * 0.52
      horizontalAlignment: Text.AlignRight
      text: line.value
      textFormat: Text.PlainText
      wrapMode: Text.WrapAnywhere
      color: root.bar.foreground
      opacity: line.value === strings.t("unavailable") ? 0.4 : 1
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  component CapacityReading: Column {
    id: capacity
    property string label: ""
    property string value: ""
    property real fraction: 0
    property real fillOpacity: 1
    spacing: Style.space(6)
    DetailLine { label: capacity.label; value: capacity.value }
    Rectangle {
      width: parent.width
      height: Style.space(4)
      radius: height / 2
      color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
      Rectangle {
        width: parent.width * capacity.fraction
        height: parent.height
        radius: parent.radius
        color: root.bar.foreground
        opacity: capacity.fillOpacity
        Behavior on width { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
      }
    }
  }
}
