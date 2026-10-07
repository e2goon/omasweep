pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.e2goon.omasweep"

  property bool popupOpen: false
  property bool scanning: false
  property bool scanned: false
  property bool failed: false
  property bool popoutSwitchClosing: false
  property real lastScanAt: 0
  property real safeBytes: 0
  property real freeBytes: 0
  property var targets: []

  readonly property bool showSize: setting("showSize", false) === true
  readonly property int refreshIntervalMin: Math.max(5, Number(setting("refreshIntervalMin", 30)) || 30)
  readonly property string pluginPath: decodeURIComponent(
    Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string omsPath: pluginPath + "/bin/oms"
  readonly property var readyTargets: targets.filter(function(t) { return t.status === "ready" })
  readonly property var topTargets: readyTargets.slice(0, 6)
  readonly property int safeCount: readyTargets.filter(function(t) { return t.tier === "safe" }).length
  readonly property int busyCount: targets.length - readyTargets.length
  readonly property color dim: Qt.darker(root.bar.foreground, 1.35)

  readonly property bool opened: popupOpen

  function open() {
    popupOpen = true
    if (Date.now() - lastScanAt > 60000) scan()
  }
  function close() { popupOpen = false }
  function toggle() { popupOpen ? close() : open() }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  function humanSize(bytes) {
    var value = Number(bytes)
    if (!isFinite(value) || value < 0) return "?"
    if (value === 0) return "0 B"
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1)
    return (value / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1) + " " + units[i]
  }

  function compactSize(bytes) {
    return humanSize(bytes).replace(" ", "").replace("B", "")
  }

  function scan() {
    if (scanProc.running) return
    scanning = true
    failed = false
    scanProc.running = true
  }

  function acceptScan(text) {
    try {
      var result = JSON.parse(text)
      targets = result.targets || []
      safeBytes = Number(result.safeBytes || 0)
      freeBytes = Number(result.freeBytes || 0)
      failed = false
      scanned = true
      lastScanAt = Date.now()
    } catch (e) {
      failed = true
    }
  }

  function launch(args) {
    var command = ["setsid", "uwsm-app", "--", "xdg-terminal-exec",
      "--app-id=org.omarchy.terminal", "--title=omasweep", "-e", omsPath, "clean", "--hold"]
    Quickshell.execDetached(command.concat(args))
    popupOpen = false
  }

  function statusText() {
    if (scanning && !scanned) return "Scanning…"
    if (failed) return "Scan failed"
    if (safeBytes > 0) return safeCount + " safe items"
    return "Already tidy"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: if (showSize) scan()

  Timer {
    interval: root.refreshIntervalMin * 60000
    running: root.showSize
    repeat: true
    onTriggered: root.scan()
  }

  Process {
    id: scanProc
    command: [root.omsPath, "scan", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptScan(text)
    }
    onExited: function(code) {
      root.scanning = false
      if (code !== 0) root.failed = true
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showSize && root.scanned && root.safeBytes > 0 ? "󰃢 " + root.compactSize(root.safeBytes) : "󰃢"
    tooltipText: root.scanned ? root.humanSize(root.safeBytes) + " safe to sweep" : "omasweep"
    onPressed: function(b) { if (b === Qt.LeftButton) root.toggle() }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      anchors.fill: parent
      spacing: Style.space(12)

      Row {
        width: parent.width
        spacing: Style.space(10)

        Column {
          width: parent.width - refreshButton.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "omasweep"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            text: root.statusText().toUpperCase()
            color: root.dim
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }
        }

        Button {
          id: refreshButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰑐"
          iconSpinning: root.scanning
          foreground: root.bar.foreground
          enabled: !root.scanning
          tooltipText: "Scan again"
          onClicked: root.scan()
        }
      }

      BorderSurface {
        width: parent.width
        height: hero.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.bar.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

        Column {
          id: hero
          anchors.centerIn: parent
          width: parent.width - Style.space(24)
          spacing: Style.space(2)

          Text {
            text: root.scanned ? root.humanSize(root.safeBytes) : "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
          }
          Text {
            text: root.scanned
              ? "safe to sweep · " + root.humanSize(root.freeBytes) + " free"
              : "measuring caches, packages, and Docker"
            color: root.dim
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: root.topTargets.length > 0

        PanelSectionHeader {
          text: "TOP ITEMS"
          color: root.bar.foreground
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Repeater {
          model: root.topTargets

          Item {
            id: targetRow
            required property var modelData
            width: parent.width
            height: rowLabel.implicitHeight

            Text {
              id: rowLabel
              anchors.left: parent.left
              anchors.right: rowSize.left
              anchors.rightMargin: Style.space(8)
              elide: Text.ElideRight
              text: (targetRow.modelData.tier === "safe" ? "●  " : "○  ") + targetRow.modelData.label + (targetRow.modelData.sudo ? "  󰒃" : "")
              color: targetRow.modelData.tier === "safe" ? root.bar.foreground : root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              id: rowSize
              anchors.right: parent.right
              text: root.humanSize(targetRow.modelData.bytes)
              color: targetRow.modelData.bytes >= 1073741824 ? Color.accent : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: targetRow.modelData.bytes >= 1073741824
            }
          }
        }

        Text {
          visible: root.busyCount > 0
          width: parent.width
          text: root.busyCount + " more skipped while their app is open"
          color: root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Button {
          width: (parent.width - parent.spacing) * 0.6
          text: "Sweep"
          iconText: "󰃢"
          foreground: root.bar.foreground
          selected: true
          bordered: true
          verticalPadding: Style.space(9)
          onClicked: root.launch([])
        }
        Button {
          width: (parent.width - parent.spacing) * 0.4
          text: "Preview"
          iconText: "󰈈"
          foreground: root.bar.foreground
          bordered: true
          verticalPadding: Style.space(9)
          onClicked: root.launch(["--dry-run"])
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: "Opens a terminal where you pick and confirm every item."
          color: root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
        Text {
          text: "●  preselected     ○  opt-in     󰒃  asks for sudo"
          color: root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
