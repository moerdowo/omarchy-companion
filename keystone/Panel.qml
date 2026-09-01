import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Bloub.js" as Bloub

// A monitor-local control surface over the single Grok Chief service.
// The panel never shells out and never mirrors state through a file: every
// label and action talks to the same object that owns the desktop creature.
Panel {
  id: root
  moduleName: "io.github.moerdowo.grokchief"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property var barIdentity: hostWidget || root
  readonly property string monitorName: hostWidget ? String(hostWidget.monitorName || "") : ""
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.45)

  readonly property bool ready: service !== null
  readonly property bool working: ready && service.talkBusy === true
  readonly property bool shown: ready && service.shown !== false
  readonly property bool tucked: ready && service.tucked === true
  readonly property string mood: ready
    ? (service.sayMode === "error" ? "error"
      : service.agentSilent === true ? "waiting" : String(service.mood || "idle"))
    : "loading"
  readonly property string agentId: ready ? String(service.agentId || "") : ""
  readonly property string chiefMonitor: ready ? String(service.worldMonitor || "") : ""
  readonly property bool hasAgent: ready
    && ("agentAvailable" in service ? service.agentAvailable === true
      : agentId !== "" && (typeof service.hasAgent !== "function" || service.hasAgent(agentId)))
  // Asking belongs to the companion itself. The overview only grows a
  // primary action when there is an exceptional job to do: finish starting,
  // choose a missing agent, or stop a running turn.
  readonly property bool showPrimaryAction: !ready || !hasAgent || working
  readonly property var agents: ready && Array.isArray(service.installedAgents)
    ? service.installedAgents : []
  readonly property var pets: ready && Array.isArray(service.installedPets)
    ? service.installedPets : []
  // The picker represents the requested companion. `spritePetId` may be the
  // bundled fallback while that request is missing or still loading.
  readonly property string petId: ready ? String(service.cfgPet || "") : ""
  readonly property string pinnedScreen: ready ? String(service.cfgScreen || "") : ""
  // A drawn companion is nothing but expressions, so it always has them; a
  // sprite one only when its artist drew faces it may borrow.
  readonly property bool drawnPet: ready && service.bloubPet === true
  readonly property bool hasFaces: drawnPet || (ready && Model.glanceFaces(
    service.spriteFaces, service.spriteIdleFaces, service.spriteRows, service.spriteColumns).length > 0)
  readonly property bool canBubble: ready && hasAgent && Model.canTalkTo(agentId)
  readonly property bool canWalk: ready && service.stillPet !== true
  readonly property bool canTheme: ready && service.spriteThemeable !== null
  // One authority decides whether a performance can begin. Mirroring the
  // Chief's individual guards here made a visible button become a silent
  // no-op whenever the stage, prompt, drag, walk, or mood changed.
  readonly property bool hasActivities: ready && service.canPlayActivity === true
  readonly property bool inConversation: ready && !working
    && service.consoleLaunchPending !== true
    && String(service.sessionId || "") !== ""
  readonly property int energyPercent: ready && isFinite(Number(service.energy))
    ? Math.round(Math.max(0, Math.min(1, Number(service.energy))) * 100) : 0

  property string view: "overview"
  property string focusId: "primary"
  property bool cursorActive: false
  property int quickCursor: 0
  // Utility actions can appear and disappear while this panel is open.
  // Remember the action, not its position, so inserting Play before Fresh
  // never turns the next Enter press into a different command.
  property string utilityAction: "play"
  property int conversationCursor: 0
  property int oftenCursor: 1
  property int sizeCursor: 1
  property var previousNavIds: []
  readonly property string navSignature: navIds().join("\u001f")
  readonly property var conversationPresets: [
    { value: "-1", label: "one ask" },
    { value: "60", label: "1 hour" },
    { value: "0", label: "ongoing" }
  ]
  readonly property var conversationOptions: withCustomOption(
    conversationPresets,
    ready ? String(service.cfgSessionIdleMin) : "0",
    ready ? "Custom · " + String(service.cfgSessionIdleMin) + " min" : "")
  readonly property var oftenPresets: [
    { value: "0.1", label: "rarely" },
    { value: "0.25", label: "sometimes" },
    { value: "0.5", label: "often" }
  ]
  readonly property var oftenOptions: withCustomOption(
    oftenPresets,
    oftenValue(),
    ready ? "Custom · " + Math.round(Number(service.cfgGlanceChance) * 100) + "%" : "")
  // A companion is company, not a window. These were sized for the drawn
  // spritesheets, whose faces need pixels to read at all; the drawn companion
  // is two capsules on a shape and stays legible far smaller, so the whole
  // scale comes down and S is genuinely small rather than merely smallest.
  readonly property var sizePresets: [
    { value: "48", label: "S" },
    { value: "64", label: "M" },
    { value: "88", label: "L" },
    { value: "120", label: "XL" }
  ]
  readonly property var sizeOptions: withCustomOption(
    sizePresets,
    ready ? String(service.petSize) : "150",
    ready ? "Custom · " + String(service.petSize) + " px" : "")
  readonly property var agentOptions: {
    var desktopAgent = ready ? String(service.defaultAgentId || "") : ""
    var configuredAgent = ready ? String(service.cfgAgent || "") : ""
    var foundConfigured = configuredAgent === ""
    var desktopLabel = "Follow desktop default"
    if (desktopAgent !== "") desktopLabel += " · " + agentName(desktopAgent)
    var out = [{ value: "", label: desktopLabel }]
    for (var i = 0; i < agents.length; i++) {
      var entry = agents[i]
      var id = entry && typeof entry === "object" ? String(entry.id || "") : String(entry || "")
      // Following Omarchy's default remains future-proof because its own
      // launcher owns that command. An explicit override is only offered when
      // Grok Chief can actually build the corresponding console command.
      if (id !== "" && Model.canOpenConsole(id)) {
        if (id === configuredAgent) foundConfigured = true
        out.push({
          value: id,
          label: agentName(id) + (Model.canTalkTo(id) ? "" : " · console only")
        })
      }
    }
    if (!foundConfigured)
      out.splice(1, 0, { value: configuredAgent, label: "Unavailable · " + agentName(configuredAgent) })
    return out
  }

  readonly property var petOptions: {
    var out = []
    var foundConfigured = false
    for (var i = 0; i < pets.length; i++) {
      var entry = pets[i]
      if (!entry) continue
      var id = typeof entry === "object" ? String(entry.id || "") : String(entry)
      if (id === "") continue
      if (id === petId) foundConfigured = true
      out.push({ value: id, label: cleanLabel(typeof entry === "object" ? entry.name : id, id) })
    }
    if (petId !== "" && !foundConfigured)
      out.unshift({ value: petId, label: "Missing · " + cleanLabel(petId, "companion") })
    return out
  }

  // The drawn companion's three catalogues. They come from Bloub.js rather
  // than from the service so that the panel shows every choice the character
  // actually has, in the character's own order, and never a stale copy.
  readonly property var shapeOptions: Bloub.panelOptions(Bloub.SHAPES)
  readonly property var colorOptions: Bloub.panelOptions(Bloub.COLORS)
  readonly property var expressionOptions: Bloub.panelOptions(Bloub.EXPRESSIONS)
  readonly property string shapeId: ready ? String(service.cfgShape || "") : ""
  readonly property string colorId: ready ? String(service.cfgColor || "") : ""
  readonly property string expressionId: ready ? String(service.cfgExpression || "") : ""

  readonly property var screenOptions: {
    var out = [{ value: "", label: "Not pinned" }]
    var foundPinned = pinnedScreen === ""
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var name = String(Quickshell.screens[i].name || "")
      if (name !== "") {
        if (name === pinnedScreen) foundPinned = true
        out.push({ value: name, label: name })
      }
    }
    if (!foundPinned)
      out.splice(1, 0, { value: pinnedScreen, label: "Missing · " + cleanLabel(pinnedScreen, "screen") })
    return out
  }

  readonly property bool dropdownOwnsKeys: agentDropdown.popupOpen
    || petDropdown.popupOpen || screenDropdown.popupOpen
    || shapeDropdown.popupOpen || colorDropdown.popupOpen
    || expressionDropdown.popupOpen

  function cleanLabel(value, fallback) {
    var text = String(value || fallback || "").replace(/[\r\n\t]+/g, " ").trim()
    return text.replace(/</g, "‹").replace(/>/g, "›").slice(0, 64)
  }

  function withCustomOption(presets, value, label) {
    var out = presets.slice()
    if (value === "" || optionIndex(out, value) >= 0) return out
    out.push({ value: value, label: label })
    return out
  }

  function syncDropdownValues() {
    agentDropdown.value = ready && service.agentIsDefault ? "" : agentId
    petDropdown.value = petId
    screenDropdown.value = pinnedScreen
    shapeDropdown.value = shapeId
    colorDropdown.value = colorId
    expressionDropdown.value = expressionId
  }

  function agentName(id) {
    if (service && typeof service.agentName === "function")
      return cleanLabel(service.agentName(id), id)
    for (var i = 0; i < agents.length; i++) {
      var entry = agents[i]
      if (entry && String(entry.id || "") === String(id)) return cleanLabel(entry.name, id)
    }
    return cleanLabel(id, "")
  }

  function stateLabel() {
    if (!ready) return "starting"
    if (!hasAgent) return "no agent"
    if (mood === "error") return "needs attention"
    if (service.agentSilent === true) return "taking longer"
    if (mood === "waiting") return "waiting"
    if (working) return "working"
    if (!shown) return "hidden"
    if (tucked) return "tucked away"
    return mood
  }

  function stateGlyph() {
    if (!ready) return "○"
    if (mood === "error") return "×"
    if (mood === "waiting") return "!"
    if (working) return "◌"
    if (!shown) return "◦"
    if (mood === "sleeping") return "☾"
    return "●"
  }

  function stateColor() {
    return mood === "error" || mood === "waiting" ? urgent : Color.accent
  }

  function heroMeta() {
    var who = hasAgent ? agentName(agentId) : "Agent not selected"
    var where = chiefMonitor !== "" ? " · " + chiefMonitor : ""
    return who + " · " + stateLabel() + where
  }

  function contextTitle() {
    if (!ready) return "Starting Grok Chief"
    if (!hasAgent) return "Choose an agent to take orders"
    if (mood === "error") return "The agent could not finish"
    if (service.agentSilent === true) return "Still working"
    if (working) return service.doing ? String(service.doing) : "Working on it"
    if (String(service.lastAnswer || "") !== "") return "Last reply"
    return shown ? "Ready when you are" : "Hidden from the desktop"
  }

  function contextBody() {
    if (!ready) return "The desktop service is loading."
    if (!hasAgent) return "Pick Omarchy's default agent, then ask from here or the creature."
    if (mood === "error") return String(service.sayText || "The agent could not finish this turn.")
    if (service.agentSilent === true) return "This turn is taking longer than usual. You can stop it safely."
    if (working) return "You can stop this turn without starting another one."
    var answer = String(service.lastAnswer || "")
    if (answer !== "") return answer
    return "Middle-click the bar icon to ask without opening this panel."
  }

  function oftenValue() {
    var chance = ready ? Number(service.cfgGlanceChance) : 0.25
    return String(isFinite(chance) ? chance : 0.25)
  }

  function optionIndex(options, value) {
    for (var i = 0; i < options.length; i++)
      if (String(options[i].value) === String(value)) return i
    return 0
  }

  function setSetting(key, value) {
    if (service && typeof service.setConfig === "function") service.setConfig(key, value)
  }

  function setShown(value) {
    if (!service) return
    if (typeof service.setShown === "function") service.setShown(value)
    else service.shown = value
  }

  function setTucked(value) {
    if (!service) return
    if (typeof service.setTucked === "function") service.setTucked(value)
    else service.tucked = value
  }

  function askHere() {
    if (!service || working) return
    root.close()
    if (typeof service.askOn === "function") service.askOn(monitorName)
  }

  function pickDesktopAgent() {
    root.close()
    if (service && typeof service.chooseAgent === "function") service.chooseAgent()
    else if (bar) bar.run("omarchy-menu summon setup.default.agent")
  }

  function primaryAction() {
    if (!ready) return
    if (working) {
      if (typeof service.stopOrder === "function") service.stopOrder()
    } else if (!hasAgent) root.pickDesktopAgent()
    else root.askHere()
  }

  function consoleHere() {
    if (!service) return
    root.close()
    if (typeof service.summonConsole === "function") service.summonConsole(monitorName)
  }

  function playRandom() {
    if (service && typeof service.playRandom === "function") service.playRandom()
  }

  function startFresh() {
    if (service && typeof service.freshConversation === "function") service.freshConversation()
  }

  function open() {
    root.view = "overview"
    root.focusId = root.showPrimaryAction ? "primary" : "quick"
    root.cursorActive = false
    if (service && typeof service.refreshChoices === "function") service.refreshChoices()
    root.controller.show()
  }

  function closeDropdowns() {
    agentDropdown.close()
    petDropdown.close()
    screenDropdown.close()
    shapeDropdown.close()
    colorDropdown.close()
    expressionDropdown.close()
  }

  function close() {
    closeDropdowns()
    root.controller.hide()
  }

  function toggle() { opened ? close() : open() }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function showView(name) {
    closeDropdowns()
    view = name === "settings" ? "settings" : "overview"
    focusId = view === "settings" ? "back" : "primary"
    cursorActive = true
    if (panelScroll.contentItem) panelScroll.contentItem.contentY = 0
    Qt.callLater(function() { root.syncGroupCursor(); root.ensureCursorVisible(root.navItem(root.focusId)) })
  }

  function navIds() {
    if (view === "overview") {
      var overview = ["settings"]
      if (showPrimaryAction) overview.push("primary")
      overview.push("quick")
      if (hasActivities || inConversation) overview.push("utility")
      overview.push("shown")
      return overview
    }

    var settingsIds = ["back", "agent"]
    if (!ready) return settingsIds
    if (canBubble) settingsIds.push("talk")
    if (canBubble && service && service.cfgTalk) settingsIds.push("conversation")
    if (petOptions.length > 1) settingsIds.push("pet")
    if (drawnPet) {
      settingsIds.push("shape")
      settingsIds.push("color")
      settingsIds.push("expression")
    }
    if (canTheme) settingsIds.push("theme")
    if (hasFaces) {
      settingsIds.push("expressions")
      if (service.cfgExpressions) settingsIds.push("often")
    }
    if (ready && Number(service.petSize) > 0) settingsIds.push("size")
    if (screenOptions.length > 1) settingsIds.push("screen")
    if (canWalk && pinnedScreen === "") settingsIds.push("follow")
    settingsIds.push("fullscreen")
    settingsIds.push("motion")
    return settingsIds
  }

  function navItem(id) {
    switch (id) {
      case "settings": return overviewHero
      case "back": return settingsHero
      case "primary": return primaryButton
      case "quick": return quickCursor === 0 ? consoleButton : tuckButton
      case "utility": {
        var action = currentUtilityAction()
        return action === "play" ? playButton : action === "fresh" ? freshButton : null
      }
      case "shown": return shownToggle
      case "agent": return agentDropdown.visible ? agentDropdown : pickAgentButton
      case "talk": return talkToggle
      case "conversation": return conversationGroup
      case "pet": return petDropdown
      case "shape": return shapeDropdown
      case "color": return colorDropdown
      case "expression": return expressionDropdown
      case "theme": return themeToggle
      case "expressions": return expressionsToggle
      case "often": return oftenGroup
      case "size": return sizeGroup
      case "screen": return screenDropdown
      case "follow": return followToggle
      case "fullscreen": return fullscreenToggle
      case "motion": return motionToggle
    }
    return null
  }

  function utilityActions() {
    var actions = []
    if (hasActivities) actions.push("play")
    if (inConversation) actions.push("fresh")
    return actions
  }

  function currentUtilityAction() {
    var actions = utilityActions()
    if (actions.indexOf(utilityAction) >= 0) return utilityAction
    return actions.length > 0 ? actions[0] : ""
  }

  function syncUtilityAction() {
    var next = currentUtilityAction()
    if (utilityAction !== next) utilityAction = next
  }

  function setUtilityIndex(index) {
    var actions = utilityActions()
    if (actions.length === 0) { utilityAction = ""; return }
    var bounded = Math.max(0, Math.min(actions.length - 1, Number(index) || 0))
    utilityAction = actions[bounded]
  }

  function syncGroupCursor() {
    if (focusId === "quick") quickCursor = Math.max(0, Math.min(1, quickCursor))
    else if (focusId === "utility") syncUtilityAction()
    else if (focusId === "conversation")
      conversationCursor = optionIndex(conversationOptions, String(service.cfgSessionIdleMin))
    else if (focusId === "often") oftenCursor = optionIndex(oftenOptions, oftenValue())
    else if (focusId === "size") sizeCursor = optionIndex(sizeOptions, String(service.petSize))
  }

  function repairNavFocus() {
    var ids = navIds()
    if (cursorActive && ids.length > 0 && ids.indexOf(focusId) < 0) {
      var oldIndex = previousNavIds.indexOf(focusId)
      focusId = ids[Math.max(0, Math.min(ids.length - 1, oldIndex < 0 ? 0 : oldIndex))]
      syncGroupCursor()
      ensureCursorVisible(navItem(focusId))
    }
    previousNavIds = ids
  }

  function setCursor(id, item, groupIndex) {
    cursorActive = true
    focusId = id
    if (groupIndex !== undefined) {
      if (id === "quick") quickCursor = groupIndex
      else if (id === "utility") {
        var actions = utilityActions()
        if (typeof groupIndex === "string" && actions.indexOf(groupIndex) >= 0)
          utilityAction = groupIndex
        else setUtilityIndex(groupIndex)
      }
      else if (id === "conversation") conversationCursor = groupIndex
      else if (id === "often") oftenCursor = groupIndex
      else if (id === "size") sizeCursor = groupIndex
    } else syncGroupCursor()
    ensureCursorVisible(item || navItem(id))
  }

  function revealCursor() {
    if (cursorActive) return false
    cursorActive = true
    syncGroupCursor()
    ensureCursorVisible(navItem(focusId))
    return true
  }

  function moveCursor(delta) {
    var ids = navIds()
    if (ids.length === 0) return
    // Native Omarchy panels start with no painted keyboard cursor. The first
    // arrow reveals the current action; only the next one moves away from it.
    if (revealCursor()) return
    var index = ids.indexOf(focusId)
    if (index < 0) index = 0
    else index = Math.max(0, Math.min(ids.length - 1, index + delta))
    focusId = ids[index]
    syncGroupCursor()
    ensureCursorVisible(navItem(focusId))
  }

  function moveGroupCursor(options, cursor, delta) {
    return Math.max(0, Math.min(options.length - 1, cursor + delta))
  }

  function moveHorizontal(delta) {
    if (revealCursor()) return
    if (focusId === "quick") quickCursor = Math.max(0, Math.min(1, quickCursor + delta))
    else if (focusId === "utility") {
      var actions = utilityActions()
      var here = actions.indexOf(currentUtilityAction())
      setUtilityIndex((here < 0 ? 0 : here) + delta)
    } else if (focusId === "conversation")
      conversationCursor = moveGroupCursor(conversationOptions, conversationCursor, delta)
    else if (focusId === "often") oftenCursor = moveGroupCursor(oftenOptions, oftenCursor, delta)
    else if (focusId === "size") sizeCursor = moveGroupCursor(sizeOptions, sizeCursor, delta)
  }

  function activateCursor() {
    if (!cursorActive) return
    switch (focusId) {
      case "settings": showView("settings"); break
      case "back": showView("overview"); break
      case "primary": primaryAction(); break
      case "quick":
        if (quickCursor === 0) consoleHere()
        else setTucked(!tucked)
        break
      case "utility":
        if (currentUtilityAction() === "play") playRandom()
        else if (currentUtilityAction() === "fresh") startFresh()
        break
      case "shown": setShown(!shown); break
      case "agent": agentDropdown.visible ? agentDropdown.toggle() : pickDesktopAgent(); break
      case "talk": setSetting("talk", !service.cfgTalk); break
      case "conversation": setSetting("sessionIdleMin", Number(conversationOptions[conversationCursor].value)); break
      case "pet": petDropdown.toggle(); break
      case "shape": shapeDropdown.toggle(); break
      case "color": colorDropdown.toggle(); break
      case "expression": expressionDropdown.toggle(); break
      case "theme": setSetting("theme", !service.cfgTheme); break
      case "expressions": setSetting("expressions", !service.cfgExpressions); break
      case "often": setSetting("expressionChance", Number(oftenOptions[oftenCursor].value)); break
      case "size": setSetting("size", Number(sizeOptions[sizeCursor].value)); break
      case "screen": screenDropdown.toggle(); break
      case "follow": setSetting("followFocus", !service.cfgFollow); break
      case "fullscreen": setSetting("hideOnFullscreen", !service.cfgHideFullscreen); break
      case "motion": setSetting("reduceMotion", !service.cfgReduceMotion); break
    }
  }

  function ensureCursorVisible(item) {
    if (!item || !panelScroll || !panelScroll.contentItem) return
    Qt.callLater(function() {
      if (!item || !panelScroll.contentItem) return
      var flick = panelScroll.contentItem
      var point = item.mapToItem(flick.contentItem || flick, 0, 0)
      var margin = Style.space(10)
      var top = point.y
      var bottom = top + item.height
      if (top < flick.contentY + margin) flick.contentY = Math.max(0, top - margin)
      else if (bottom > flick.contentY + flick.height - margin)
        flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height),
                                  bottom + margin - flick.height)
    })
  }

  onOpenedChanged: if (opened) {
    if (service && typeof service.refreshChoices === "function") service.refreshChoices()
    syncDropdownValues()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onServiceChanged: Qt.callLater(syncDropdownValues)
  onFocusIdChanged: if (cursorActive) ensureCursorVisible(navItem(focusId))
  onNavSignatureChanged: Qt.callLater(repairNavFocus)
  onHasActivitiesChanged: if (focusId === "utility") Qt.callLater(syncGroupCursor)
  onInConversationChanged: if (focusId === "utility") Qt.callLater(syncGroupCursor)

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onAgentIdChanged() { root.syncDropdownValues() }
    function onAgentIsDefaultChanged() { root.syncDropdownValues() }
    function onCfgPetChanged() { root.syncDropdownValues() }
    function onCfgScreenChanged() { root.syncDropdownValues() }
    function onCfgSessionIdleMinChanged() {
      if (root.focusId === "conversation") root.syncGroupCursor()
    }
    function onCfgGlanceChanceChanged() {
      if (root.focusId === "often") root.syncGroupCursor()
    }
    function onPetSizeChanged() {
      if (root.focusId === "size") root.syncGroupCursor()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380), Style.space(380))
    contentHeight: panel.fittedContentHeight(contentBody.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.dropdownOwnsKeys
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveHorizontal(dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.view === "settings" ? root.showView("overview") : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if ((text === "s" || text === "S") && root.view === "overview") root.showView("settings")
        else if ((text === "a" || text === "A") && root.view === "overview" && !root.working) root.askHere()
      }

      ScrollView {
        id: panelScroll
        anchors.fill: parent
        clip: true
        // Qt's attached scrollbar overlays the viewport. Reserve a slim
        // right-hand rail so it stays at the panel edge instead of painting
        // over cards, dropdowns, and toggles.
        rightPadding: root.view === "settings" ? Style.space(10) : 0
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: contentBody.implicitHeight > height
          ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Item {
          id: contentBody
          width: panelScroll.availableWidth
          implicitHeight: root.view === "settings"
            ? settingsColumn.implicitHeight : overviewColumn.implicitHeight
          height: implicitHeight

          Column {
            id: overviewColumn
            visible: root.view === "overview"
            width: parent.width
            spacing: Style.space(10)

            PanelHero {
              id: overviewHero
              width: parent.width
              title: "Grok Chief"
              meta: root.heroMeta()
              detail: root.ready ? root.energyPercent + "%" : ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconComponent: Component {
                Text {
                  text: root.stateGlyph()
                  color: root.stateColor()
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
              trailingControl: Component {
                PanelActionButton {
                  iconText: "󰒓"
                  tooltipText: "Settings"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusId === "settings"
                  onHovered: function(on) { if (on) root.setCursor("settings", overviewHero) }
                  onClicked: root.showView("settings")
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            BorderSurface {
              width: parent.width
              implicitHeight: contextColumn.implicitHeight + Style.spacing.rowPaddingX * 2
              color: root.mood === "error"
                ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              borderSpec: root.mood === "error"
                ? Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.35), 1)
                : Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)
              radius: Style.cornerRadius

              Column {
                id: contextColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                spacing: Style.spacing.xs

                Text {
                  width: parent.width
                  text: root.contextTitle()
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.contextBody()
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  maximumLineCount: 4
                  elide: Text.ElideRight
                }
              }
            }

            Button {
              id: primaryButton
              visible: root.showPrimaryAction
              width: parent.width
              text: !root.ready ? "Starting…"
                : root.working ? "Stop current turn"
                : "Choose desktop agent…"
              iconText: root.working ? "󰓛" : "󰒓"
              bordered: true
              enabled: root.ready
              foreground: root.working ? root.urgent : root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              hasCursor: root.cursorActive && root.focusId === "primary"
              onHovered: function(on) { if (on) root.setCursor("primary", primaryButton) }
              onClicked: root.primaryAction()
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              readonly property real cellWidth: (width - spacing) / 2

              Button {
                id: consoleButton
                width: parent.cellWidth
                text: "Console"
                iconText: "󰆍"
                bordered: true
                enabled: root.ready
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                hasCursor: root.cursorActive && root.focusId === "quick" && root.quickCursor === 0
                onHovered: function(on) { if (on) root.setCursor("quick", consoleButton, 0) }
                onClicked: root.consoleHere()
              }

              Button {
                id: tuckButton
                width: parent.cellWidth
                text: root.tucked ? "Return" : "Tuck"
                iconText: root.tucked ? "󰁍" : "󰆾"
                bordered: true
                enabled: root.ready
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                hasCursor: root.cursorActive && root.focusId === "quick" && root.quickCursor === 1
                onHovered: function(on) { if (on) root.setCursor("quick", tuckButton, 1) }
                onClicked: root.setTucked(!root.tucked)
              }
            }

            Row {
              visible: root.hasActivities || root.inConversation
              width: parent.width
              spacing: Style.spacing.md

              Button {
                id: playButton
                visible: root.hasActivities
                width: root.inConversation ? (parent.width - parent.spacing) / 2 : parent.width
                text: "Do something"
                iconText: "󰐊"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                hasCursor: root.cursorActive && root.focusId === "utility"
                  && root.currentUtilityAction() === "play"
                onHovered: function(on) { if (on) root.setCursor("utility", playButton, "play") }
                onClicked: root.playRandom()
              }

              Button {
                id: freshButton
                visible: root.inConversation
                width: root.hasActivities ? (parent.width - parent.spacing) / 2 : parent.width
                text: "Start fresh"
                iconText: "󰑐"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                hasCursor: root.cursorActive && root.focusId === "utility"
                  && root.currentUtilityAction() === "fresh"
                onHovered: function(on) {
                  if (on) root.setCursor("utility", freshButton, "fresh")
                }
                onClicked: root.startFresh()
              }
            }

            Toggle {
              id: shownToggle
              enabled: root.ready
              width: parent.width
              label: "On the desktop"
              description: root.shown ? "Visible on its monitor" : "Hidden until you call it back"
              checked: root.shown
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "shown"
              onHovered: function(on) { if (on) root.setCursor("shown", shownToggle) }
              onClicked: root.setShown(!root.shown)
            }
          }

          Column {
            id: settingsColumn
            visible: root.view === "settings"
            width: parent.width
            spacing: Style.space(8)

            PanelHero {
              id: settingsHero
              width: parent.width
              title: "Grok Chief"
              meta: "Settings · changes apply immediately"
              detail: root.monitorName
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconComponent: Component {
                Text {
                  text: "󰒓"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
              trailingControl: Component {
                PanelActionButton {
                  iconText: "󰁍"
                  tooltipText: "Back"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusId === "back"
                  onHovered: function(on) { if (on) root.setCursor("back", settingsHero) }
                  onClicked: root.showView("overview")
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            Text {
              visible: root.service && String(root.service.settingError || "") !== ""
              width: parent.width
              text: root.service ? String(root.service.settingError || "") : ""
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            PanelSectionHeader { text: "AGENT"; foreground: root.foreground; fontFamily: root.fontFamily }

            Dropdown {
              id: agentDropdown
              visible: root.agentOptions.length > 1
              width: parent.width
              label: "Answers with"
              value: ""
              options: root.agentOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "agent"
              onHovered: function(on) { if (on) root.setCursor("agent", agentDropdown) }
              onChanged: function(value) {
                root.setSetting("agent", value)
                Qt.callLater(root.syncDropdownValues)
              }
            }

            Button {
              id: pickAgentButton
              visible: !agentDropdown.visible
              width: parent.width
              text: "Choose desktop agent…"
              iconText: "󰒓"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "agent"
              onHovered: function(on) { if (on) root.setCursor("agent", pickAgentButton) }
              onClicked: root.pickDesktopAgent()
            }

            Toggle {
              id: talkToggle
              visible: root.canBubble
              enabled: root.ready
              width: parent.width
              label: "Answer in a bubble"
              description: service && service.cfgTalk
                ? "Runs the order unattended and replies beside the creature"
                : "Opens every order in the console"
              checked: service ? service.cfgTalk : false
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "talk"
              onHovered: function(on) { if (on) root.setCursor("talk", talkToggle) }
              onClicked: root.setSetting("talk", !service.cfgTalk)
            }

            Column {
              visible: root.canBubble && service !== null && service.cfgTalk
              width: parent.width
              spacing: Style.spacing.xs

              Text {
                text: "ONE CONVERSATION LASTS"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              ButtonGroup {
                id: conversationGroup
                options: root.conversationOptions
                value: service ? String(service.cfgSessionIdleMin) : "0"
                foreground: root.foreground
                fontFamily: root.fontFamily
                cursorIndex: root.cursorActive && root.focusId === "conversation"
                  ? root.conversationCursor : -1
                onHovered: function(index, on) {
                  if (on) root.setCursor("conversation", conversationGroup, index)
                }
                onChanged: function(value) { root.setSetting("sessionIdleMin", Number(value)) }
              }
            }

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader { text: "COMPANION"; foreground: root.foreground; fontFamily: root.fontFamily }

            Dropdown {
              id: petDropdown
              visible: root.petOptions.length > 1
              width: parent.width
              label: "Companion"
              value: ""
              options: root.petOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "pet"
              onHovered: function(on) { if (on) root.setCursor("pet", petDropdown) }
              onChanged: function(value) {
                root.setSetting("pet", value)
                Qt.callLater(root.syncDropdownValues)
              }
            }

            // A drawn companion has no artwork to recolour, so the choices a
            // sheet cannot offer are offered instead: its outline, its colour
            // and the face it wears when nothing is happening. Each change
            // morphs on screen rather than cutting, which is the whole reason
            // a drawn body is worth having.
            Dropdown {
              id: shapeDropdown
              visible: root.drawnPet
              width: parent.width
              label: "Shape"
              value: ""
              options: root.shapeOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "shape"
              onHovered: function(on) { if (on) root.setCursor("shape", shapeDropdown) }
              onChanged: function(value) {
                root.setSetting("shape", value)
                Qt.callLater(root.syncDropdownValues)
              }
            }

            Dropdown {
              id: colorDropdown
              visible: root.drawnPet
              width: parent.width
              label: "Colour"
              value: ""
              options: root.colorOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "color"
              onHovered: function(on) { if (on) root.setCursor("color", colorDropdown) }
              onChanged: function(value) {
                root.setSetting("color", value)
                Qt.callLater(root.syncDropdownValues)
              }
            }

            Dropdown {
              id: expressionDropdown
              visible: root.drawnPet
              width: parent.width
              label: "Resting expression"
              value: ""
              options: root.expressionOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "expression"
              onHovered: function(on) { if (on) root.setCursor("expression", expressionDropdown) }
              onChanged: function(value) {
                root.setSetting("expression", value)
                Qt.callLater(root.syncDropdownValues)
              }
            }

            Toggle {
              id: themeToggle
              visible: root.canTheme
              width: parent.width
              label: "Wear the current theme"
              description: "Recolors supported artwork with Omarchy's palette"
              checked: service ? service.cfgTheme : false
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "theme"
              onHovered: function(on) { if (on) root.setCursor("theme", themeToggle) }
              onClicked: root.setSetting("theme", !service.cfgTheme)
            }

            Toggle {
              id: expressionsToggle
              visible: root.hasFaces
              width: parent.width
              label: "Idle expressions"
              description: "Changes expression occasionally while resting"
              checked: service ? service.cfgExpressions : false
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "expressions"
              onHovered: function(on) { if (on) root.setCursor("expressions", expressionsToggle) }
              onClicked: root.setSetting("expressions", !service.cfgExpressions)
            }

            Column {
              visible: root.hasFaces && service && service.cfgExpressions
              width: parent.width
              spacing: Style.spacing.xs

              Text {
                text: "HOW OFTEN"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              ButtonGroup {
                id: oftenGroup
                options: root.oftenOptions
                value: root.oftenValue()
                foreground: root.foreground
                fontFamily: root.fontFamily
                cursorIndex: root.cursorActive && root.focusId === "often" ? root.oftenCursor : -1
                onHovered: function(index, on) { if (on) root.setCursor("often", oftenGroup, index) }
                onChanged: function(value) { root.setSetting("expressionChance", Number(value)) }
              }
            }

            Column {
              visible: root.ready && Number(service.petSize) > 0
              width: parent.width
              spacing: Style.spacing.xs

              Text {
                text: "SIZE"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              ButtonGroup {
                id: sizeGroup
                options: root.sizeOptions
                value: service ? String(service.petSize) : "150"
                foreground: root.foreground
                fontFamily: root.fontFamily
                cursorIndex: root.cursorActive && root.focusId === "size" ? root.sizeCursor : -1
                onHovered: function(index, on) { if (on) root.setCursor("size", sizeGroup, index) }
                onChanged: function(value) { root.setSetting("size", Number(value)) }
              }
            }

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader { text: "PLACEMENT"; foreground: root.foreground; fontFamily: root.fontFamily }

            Dropdown {
              id: screenDropdown
              visible: root.screenOptions.length > 1
              width: parent.width
              label: "Lives on"
              value: ""
              options: root.screenOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "screen"
              onHovered: function(on) { if (on) root.setCursor("screen", screenDropdown) }
              onChanged: function(value) {
                root.setSetting("screen", value)
                Qt.callLater(root.syncDropdownValues)
              }
            }

            Toggle {
              id: followToggle
              visible: root.canWalk && root.pinnedScreen === ""
              width: parent.width
              label: "Follow focus"
              description: "Moves to the monitor where you are working"
              checked: service ? service.cfgFollow : false
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "follow"
              onHovered: function(on) { if (on) root.setCursor("follow", followToggle) }
              onClicked: root.setSetting("followFocus", !service.cfgFollow)
            }

            Toggle {
              id: fullscreenToggle
              enabled: root.ready
              width: parent.width
              label: "Step aside for fullscreen"
              description: "Hides on its monitor while an app is fullscreen"
              checked: service ? service.cfgHideFullscreen : false
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "fullscreen"
              onHovered: function(on) { if (on) root.setCursor("fullscreen", fullscreenToggle) }
              onClicked: root.setSetting("hideOnFullscreen", !service.cfgHideFullscreen)
            }

            Toggle {
              id: motionToggle
              enabled: root.ready
              width: parent.width
              label: "Reduce motion"
              description: "Skips travel and ambient movement animations"
              checked: service ? service.cfgReduceMotion : false
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusId === "motion"
              onHovered: function(on) { if (on) root.setCursor("motion", motionToggle) }
              onClicked: root.setSetting("reduceMotion", !service.cfgReduceMotion)
            }

          }
        }
      }
    }
  }
}
