import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omarchy Companion's bar surface is deliberately thin: the service owns all state,
// this instance only presents the state for its monitor and anchors Panel.qml.
BarWidget {
  id: root
  moduleName: "io.github.moerdowo.omarchycompanion"

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

  // What the creature is wearing, so the bar's mark is the same character as
  // the one on the desktop rather than a stand-in for it.
  readonly property string shapeId: service ? String(service.cfgShape || "") : ""
  readonly property string expressionId: service ? String(service.cfgExpression || "") : ""
  readonly property bool drawn: service ? service.bloubPet === true : true

  // Ink, not an em box. A bar's glyphs carry their drawing inside a font cell
  // that is larger than the ink in it, so a mark drawn at the full icon size
  // comes out visibly bigger than everything beside it.
  readonly property int markSize: Math.max(11, Math.round(Style.bar.iconFont * 0.72))

  readonly property string tooltipText: {
    if (!service) return "Omarchy Companion · starting"
    var lines = ["Omarchy Companion · " + stateLabel(), "Agent · " + agentLabel]
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
    // The mark is drawn rather than typed when the companion is the drawn one;
    // a spritesheet pet keeps the glyph, since there is nothing to draw it
    // from that would survive being seventeen pixels wide.
    text: root.drawn ? "" : "󰚩"
    hasVisualContent: true
    fixedWidth: root.drawn
      ? Math.round(root.markSize + Style.spaceReal(8.5) * 2) : -1
    fontSize: Style.bar.iconFont
    horizontalMargin: 8.5
    active: root.urgent
    tooltipText: root.tooltipText

    CompanionMark {
      anchors.centerIn: parent
      visible: root.drawn
      size: root.markSize
      shapeId: root.shapeId
      expressionId: root.expressionId
      mood: root.mood
      // Exactly what WidgetButton paints its own glyph with, so the mark
      // brightens and dims with the row instead of beside it.
      ink: button.active && button.useActiveColor ? button.activeColor : button.foreground
    }

    // A restrained state mark keeps the creature readable without turning
    // ordinary work into an alarm.
    //
    // It sits ON the creature rather than in the button's corner. A glyph
    // fills most of its cell, so a corner was close enough to read as part of
    // it; the drawn mark is ink only, and a dot left in the corner detached
    // itself and read as a stray pixel in the bar. Measured at the time: the
    // mark's ink ended eleven physical pixels above where the dot began.
    Rectangle {
      z: 2
      width: Style.space(4)
      height: width
      radius: width / 2
      x: root.drawn ? Math.round(parent.width / 2 + root.markSize * 0.24)
                    : parent.width - width - Style.space(2)
      y: root.drawn ? Math.round(parent.height / 2 + root.markSize * 0.16)
                    : parent.height - height - Style.space(2)
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
