import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Grok Chief's bar surface is deliberately thin: the service owns all state,
// this instance only presents the state for its monitor and anchors Panel.qml.
BarWidget {
  id: root
  moduleName: "io.github.moerdowo.grokchief"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property string monitorName: {
    var window = button.QsWindow.window
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  readonly property string mood: service
    ? (service.sayMode === "error" ? "error"
      : service.agentSilent === true ? "waiting" : String(service.mood || "idle"))
    : "loading"
  readonly property bool urgent: mood === "error" || mood === "waiting"
  readonly property bool working: service ? service.talkBusy === true : false
  readonly property bool hasAgent: service
    ? ("agentAvailable" in service ? service.agentAvailable === true
      : String(service.agentId || "") !== ""
        && (typeof service.hasAgent !== "function" || service.hasAgent(service.agentId)))
    : false
  readonly property bool shown: service ? service.shown !== false : false
  readonly property bool tucked: service ? service.tucked === true : false
  readonly property string agentLabel: {
    if (!service || !hasAgent) return "No agent selected"
    var id = String(service.agentId || "")
    return typeof service.agentName === "function" ? String(service.agentName(id) || id) : id
  }
  readonly property color stateColor: urgent
    ? (bar ? bar.urgent : Color.urgent)
    : working ? Color.accent
    : shown && hasAgent ? (bar ? bar.barForeground : Color.foreground)
    : Qt.darker(bar ? bar.barForeground : Color.foreground, 1.8)

  readonly property string tooltipText: {
    if (!service) return "Grok Chief · starting"
    var lines = ["Grok Chief · " + stateLabel(), "Agent · " + agentLabel]
    lines.push("Middle-click asks · right-click opens the console")
    return lines.join("\n")
  }

  function stateLabel() {
    if (!service) return "starting"
    if (!hasAgent) return "no agent selected"
    if (mood === "error") return "needs attention"
    if (service.agentSilent === true) return "taking longer"
    if (mood === "waiting") return "waiting"
    if (working) return service.doing ? Model.shapeBubbleText(service.doing, 80) : "working"
    if (!shown) return "hidden"
    if (tucked) return "tucked away"
    return mood
  }

  function askHere() {
    if (service && typeof service.askOn === "function") service.askOn(monitorName)
  }

  function consoleHere() {
    if (service && typeof service.summonConsole === "function") service.summonConsole(monitorName)
  }

  // Bar.findPanelWidget routes shell summon/hide calls through these methods.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: button.labelWidth > 0
    ? button.labelWidth : Style.space(10)

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰚩"
    fontSize: Style.bar.iconFont
    horizontalMargin: 8.5
    active: root.urgent
    tooltipText: root.tooltipText

    // A restrained state mark keeps the creature readable without turning
    // ordinary work into an alarm.
    Rectangle {
      z: 2
      width: Style.space(4)
      height: width
      radius: width / 2
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Style.space(2)
      anchors.bottomMargin: Style.space(2)
      color: root.stateColor
      opacity: root.service ? 0.95 : 0.35
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.askHere()
      else if (buttonCode === Qt.RightButton) root.consoleHere()
      else root.togglePanel()
    }
  }
}
