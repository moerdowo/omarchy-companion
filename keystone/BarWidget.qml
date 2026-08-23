import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.daventhedude.omarchief"
  // Every first-party popout answers to an IPC name; this one does too.
  ipcTarget: "omarchief.menu"

  // Panel is a bare Item: without these the bar lays the widget out at zero
  // size and it never shows up. The button measures itself; the widget is
  // exactly as wide as its face, the way every first-party widget is.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string statusPath: stateHome + "/omarchy/omarchief/status.json"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var status: ({})
  property double nowMs: Date.now()
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property string statusMood: String(status.mood || "idle")
  readonly property real statusEnergy: {
    var value = Number(status.energy)
    return isFinite(value) ? Math.max(0, Math.min(1, value)) : 0
  }
  readonly property string statusAgent: String(status.agent || "none")
  readonly property string statusMonitor: String(status.monitor || "—")
  readonly property var statusAgents: Array.isArray(status.agents) ? status.agents : []
  readonly property string statusAgentDefault: String(status.agentDefault || "")
  readonly property bool statusAgentFollows: status.agentFollowsDefault !== false
  // The agents the creature can hold a conversation with; the rest still
  // work, but an order opens the console instead of coming back in a bubble.
  // Asked of the same place the order itself is built, so an agent gains a
  // headless adapter and this answer changes with it. The list used to live
  // here as three names typed out, which would have gone on saying "console
  // only" about an agent that had learned to speak.
  function canTalkTo(id) { return Model.canTalkTo(id) }
  readonly property bool statusShown: status.shown === undefined ? true : !!status.shown
  readonly property bool statusStale: {
    var updated = Number(status.updatedAtEpoch)
    return !isFinite(updated) || nowMs / 1000 - updated > 60
  }
  readonly property bool urgentMood: statusMood === "waiting" || statusMood === "error" || agentSilent
  readonly property color moodColor: urgentMood ? Color.urgent : Color.accent
  readonly property int statusActivities: {
    var v = Number(status.activities)
    return isFinite(v) && v > 0 ? v : 0
  }
  readonly property bool agentSilent: status.agentSilent === true
  readonly property string statusDoing: String(status.doing || "")
  // The hero at the top of the popout: who it answers with, how it is, and
  // the last thing it did or said.
  readonly property string heroTitle: statusAgent === "none" ? "Omarchief" : agentName(statusAgent)
  readonly property string heroMeta: agentSilent ? "not answering"
    : statusDoing !== "" ? statusDoing
    : statusMood + " · " + Math.round(statusEnergy * 100) + "%"
  readonly property string heroDetail: lastAnswer !== "" ? lastAnswer : "on " + statusMonitor
  readonly property string moodGlyph: agentSilent ? "◒"
    : statusMood === "working" ? "◕"
    : statusMood === "waiting" ? "!"
    : statusMood === "success" ? "✓"
    : statusMood === "error" ? "✕"
    : statusMood === "sleeping" ? "☾"
    : statusMood === "tired" ? "◔" : "●"
  readonly property string lastAnswer: String(status.lastAnswer || "")
  readonly property bool statusHasFaces: status.canGlance === true
  readonly property bool statusExpressions: status.expressions !== false
  readonly property string statusPet: String(status.pet || "")
  readonly property var statusPets: Array.isArray(status.pets) ? status.pets : []
  readonly property bool statusTheme: status.theme !== false
  readonly property bool statusTalk: status.talk !== false
  readonly property bool statusHooks: status.hooks === true
  readonly property bool statusCanHook: status.canHook === true
  readonly property bool statusShy: status.hideFullscreen !== false
  readonly property bool statusTucked: status.tucked === true
  readonly property int statusTimer: Number(status.timer) > 0 ? Math.round(Number(status.timer)) : 0
  readonly property bool statusHasReadout: status.hasReadout === true
  readonly property string statusConsoleAt: status.consoleAt === "chief" ? "chief" : "quake"
  readonly property bool statusWalks: status.walks === true
  readonly property bool statusFollow: status.follow === true
  // Empty means it may move; a name means that screen is where it lives.
  readonly property string statusPinned: String(status.screen || "")
  readonly property string statusScreen: {
    var v = String(status.readout || "timer")
    return v === "face" || v === "clock" ? v : "timer"
  }
  readonly property string timerLong: statusTimer <= 0 ? ""
    : statusTimer < 60 ? statusTimer + "s left"
    : Math.ceil(statusTimer / 60) + " min left"
  readonly property string timerShort: statusTimer <= 0 ? ""
    : statusTimer < 60 ? String(statusTimer) + "s"
    : String(Math.ceil(statusTimer / 60)) + "m"
  readonly property string buttonTooltip: {
    var lines = [statusAgent === "none" ? "Omarchief" : "Omarchief · " + agentName(statusAgent)]
    if (agentSilent) lines.push("not answering")
    else if (statusDoing !== "") lines.push(statusDoing)
    else lines.push(statusMood + " · " + Math.round(statusEnergy * 100) + "%")
    if (statusTimer > 0)
      lines.push(statusTimer < 60 ? statusTimer + "s left"
                 : Math.ceil(statusTimer / 60) + " min left")
    if (!statusShown) lines.push("hidden")
    else if (statusTucked) lines.push("tucked away")
    lines.push("middle-click asks · right-click opens the console")
    return lines.join("\n")
  }
  readonly property int statusConversation: {
    var v = Number(status.conversation)
    return isFinite(v) && v > 0 ? Math.round(v) : 0
  }
  readonly property bool statusInConversation: String(status.session || "") !== ""
  readonly property bool statusCanTheme: status.canTheme === true
  readonly property real statusChance: {
    var v = Number(status.chance)
    return isFinite(v) ? v : 0.25
  }
  readonly property int statusSize: {
    var v = Number(status.size)
    return isFinite(v) && v > 0 ? Math.round(v) : 0
  }
  function oftenName(c) { return Model.oftenName(c) }
  // The panel sends what Omarchy calls each agent; a status file written by
  // an older version still carries bare ids, so read either shape.
  function agentId(entry) { return typeof entry === "string" ? entry : String(entry.id || "") }
  function agentName(id) {
    for (var i = 0; i < root.statusAgents.length; i++) {
      var e = root.statusAgents[i]
      if (root.agentId(e) === id) return typeof e === "string" ? e : String(e.name || e.id || id)
    }
    return id
  }
  // Every row is a label and the command it runs. Keeping the two together
  // means the list can grow without anybody having to recount indices.
  readonly property var actions: {
    // Things to do, then who and what, then how it behaves. Choices with
    // more than a couple of answers are a dropdown rather than a row each:
    // three screens, five pets and nine agents would otherwise be
    // seventeen lines of list to walk past on the way to "Ask".
    var list = [
      { label: "Ask", command: "omarchy-shell omarchief ask" },
      { label: "Console", command: "omarchy-shell omarchief summon" },
      { label: "Come home", command: "omarchy-shell omarchief home" }
    ]
    if (root.statusActivities > 0)
      list.push({ label: "Do something", command: "omarchy-shell omarchief play ''" })
    if (root.statusInConversation)
      list.push({ label: "Start fresh", description: "End this conversation and begin another",
                  command: "omarchy-shell omarchief fresh" })
    list.push({ label: root.statusTucked ? "Bring it back" : "Tuck to the edge",
                description: root.statusTucked ? "Stand it back where it was"
                             : "Slide it mostly off its edge, to read what is behind it",
                command: "omarchy-shell omarchief tuck " + (root.statusTucked ? "off" : "on") })
    list.push({ label: root.statusShown ? "Hide" : "Show", command: "omarchy-shell omarchief toggle" })
    // The creature has a screen for a face; a timer is the obvious thing to
    // put on it, and the obvious lengths are the ones people actually ask for.
    // It goes under the doing, not among it: setting one is a thing you do,
    // but the row is a dial and the rows above are buttons.
    list.push({ kind: "heading",
                label: root.statusTimer > 0 ? "Timer · " + root.timerLong : "Timer" })
    list.push({ kind: "buttons", label: "",
                value: root.statusTimer === 0 ? "off"
                  : root.statusTimer <= 5 * 60 ? "5m"
                  : root.statusTimer <= 15 * 60 ? "15m" : "25m",
                options: [{ value: "5m", label: "5 min" },
                          { value: "15m", label: "15 min" },
                          { value: "25m", label: "25 min" },
                          { value: "off", label: "off" }],
                prefix: "omarchy-shell omarchief timer " })

    // Which of the several things on this desktop it belongs to. A heading,
    // because three dropdowns in a row with no name over them read as a form
    // somebody forgot to finish. It only earns its line when there is more
    // than one of anything to choose between.
    if (Quickshell.screens.length > 1 || root.statusPets.length > 1
        || root.statusAgents.length > 1)
      list.push({ kind: "heading", label: "Where and who" })

    var screens = Quickshell.screens
    if (screens.length > 1) {
      // One control for where it belongs, rather than a "go there now" that
      // forgets by morning beside a setting nothing could reach. Naming a
      // screen keeps it there; "wherever I work" hands it back to focus.
      var where = [{ value: "any", label: "wherever I work" }]
      for (var i = 0; i < screens.length; i++)
        where.push({ value: screens[i].name, label: screens[i].name })
      list.push({ kind: "dropdown", label: "Lives on",
                  value: root.statusPinned === "" ? "any" : root.statusPinned,
                  options: where, prefix: "omarchy-shell omarchief screen " })
    }

    if (root.statusPets.length > 1) {
      var who = []
      for (var p = 0; p < root.statusPets.length; p++)
        who.push({ value: root.statusPets[p].id, label: root.statusPets[p].name || root.statusPets[p].id })
      list.push({ kind: "dropdown", label: "Who stands there", value: root.statusPet,
                  options: who, prefix: "omarchy-shell omarchief pet " })
    }

    if (root.statusAgents.length > 0) {
      // Following the desktop's own choice is the first option and the
      // sensible one; the rest are for putting the chief on something other
      // than what you type into a terminal all day. The ones it can only
      // hand to the console say so.
      var agents = [{ value: "any", label: "Follow the default"
                        + (root.statusAgentDefault !== "" ? " (" + root.agentName(root.statusAgentDefault) + ")" : "") }]
      for (var a = 0; a < root.statusAgents.length; a++) {
        var id = root.agentId(root.statusAgents[a])
        agents.push({ value: id, label: root.agentName(id)
                        + (root.canTalkTo(id) ? "" : " — console only") })
      }
      list.push({ kind: "dropdown", label: "Which agent",
                  value: root.statusAgentFollows ? "any" : root.statusAgent,
                  options: agents, prefix: "omarchy-shell omarchief agent " })
    }

    list.push({ label: "Settings", kind: "heading" })
    // An order answered in the bubble is an agent running with its approval
    // prompts turned off, out of sight. That is the whole point of it, and
    // it is also the one thing somebody might reasonably not want, so it
    // says so rather than hiding behind the word "talk".
    list.push({ label: "Answer in a bubble", kind: "toggle", checked: root.statusTalk,
                description: root.statusTalk ? "Orders run unattended, out of sight"
                                             : "Every order opens the console instead",
                command: "omarchy-shell omarchief speak " + (root.statusTalk ? "off" : "on") })
    if (root.statusCanHook)
      list.push({ label: "See the console agent", kind: "toggle", checked: root.statusHooks,
                  description: root.statusHooks ? "Five hooks in ~/.claude/settings.json tell it what claude does"
                                                : "Adds five hooks to ~/.claude/settings.json; off takes them out",
                  command: "omarchy-shell omarchief hooks " + (root.statusHooks ? "off" : "on") })
    list.push({ label: "Step aside for fullscreen", kind: "toggle", checked: root.statusShy,
                description: "Hide while something is fullscreen on its screen",
                command: "omarchy-shell omarchief shy " + (root.statusShy ? "off" : "on") })
    if (root.statusTalk)
      list.push({ kind: "buttons", label: "One conversation lasts",
                  value: String(root.statusConversation),
                  options: [{ value: "0", label: "until you end it" },
                            { value: "60", label: "an hour" },
                            { value: "1", label: "each order" }],
                  prefix: "omarchy-shell omarchief conversation " })
    if (root.statusCanTheme)
      list.push({ label: "Wear your theme", kind: "toggle", checked: root.statusTheme,
                  description: root.statusTheme ? "Repainted in your theme's colours"
                                                : "Keeping the colours it was drawn in",
                  command: "omarchy-shell omarchief theme " + (root.statusTheme ? "off" : "on") })
    list.push({ kind: "buttons", label: "The console opens", value: root.statusConsoleAt,
                options: [{ value: "quake", label: "from the top" },
                          { value: "chief", label: "over the chief" }],
                prefix: "omarchy-shell omarchief consoleAt " })
    // Only a pet that can walk has anywhere to walk to.
    if (root.statusWalks && root.statusPinned === "")
      list.push({ label: "Follow my focus", kind: "toggle", checked: root.statusFollow,
                  description: root.statusFollow ? "Walks over to the screen you are working on"
                                                 : "Stays on the screen you left it on",
                  command: "omarchy-shell omarchief follow " + (root.statusFollow ? "off" : "on") })
    // Only pets drawn with a panel on them can show anything there.
    if (root.statusHasReadout)
      list.push({ kind: "buttons", label: "Its screen shows", value: root.statusScreen,
                  options: [{ value: "face", label: "its face" },
                            { value: "timer", label: "a timer" },
                            { value: "clock", label: "the clock" }],
                  prefix: "omarchy-shell omarchief readout " })
    if (root.statusHasFaces) {
      list.push({ label: "Idle expressions", kind: "toggle", checked: root.statusExpressions,
                  description: "Look up wearing something else now and then",
                  command: "omarchy-shell omarchief expressions " + (root.statusExpressions ? "off" : "on") })
      if (root.statusExpressions)
        list.push({ kind: "buttons", label: "How often", value: root.oftenName(root.statusChance),
                    options: [{ value: "rarely", label: "rarely" },
                              { value: "now and then", label: "now and then" },
                              { value: "often", label: "often" }],
                    prefix: "omarchy-shell omarchief often " })
    }
    if (root.statusSize > 0)
      list.push({ kind: "buttons", label: "Size", value: String(root.statusSize),
                  options: [{ value: "96", label: "S" }, { value: "130", label: "M" },
                            { value: "150", label: "L" }, { value: "190", label: "XL" }],
                  prefix: "omarchy-shell omarchief bigger " })
    list.push({ label: "Pick the desktop's agent…", command: "omarchy-menu summon setup.default.agent" })
    return list
  }

  function isPickable(index) {
    var a = root.actions[index]
    return !!a && a.kind !== "heading"
  }

  // Bring a row fully inside the scrolled view, moving as little as possible.
  function revealRow(y, h) {
    if (!scroller.contentItem) return
    var view = scroller.height
    if (view <= 0 || column.implicitHeight <= view) return
    var top = scroller.contentItem.contentY
    var pad = Style.space(8)
    if (y - pad < top) scroller.contentItem.contentY = Math.max(0, y - pad)
    else if (y + h + pad > top + view)
      scroller.contentItem.contentY = Math.min(column.implicitHeight - view, y + h + pad - view)
  }

  function selectAction(index) {
    var count = root.actions.length
    if (count === 0) {
      root.selectedIndex = 0
      return
    }
    // A heading is a label, not a choice: keep going in the direction the
    // arrow key was pointing rather than landing on one.
    var step = index < root.selectedIndex ? -1 : 1
    var next = ((index % count) + count) % count
    for (var i = 0; i < count && !root.isPickable(next); i++)
      next = ((next + step) % count + count) % count
    root.selectedIndex = next
    root.cursorActive = true
  }

  // A chosen value goes over IPC as exactly one argument, whatever is in it.
  // "now and then" is three words and "follow the default" is none at all,
  // and Quickshell counts a call's arguments before it looks at them: an
  // unquoted value is how a row ends up saying "too few arguments provided"
  // to nobody, since the popout has already closed.
  function runValue(prefix, v) {
    root.run(prefix + "'" + String(v).replace(/'/g, "'\\''") + "'")
  }

  // One way to run something, whether it came from a row or a mouse button.
  function run(command) {
    if (!root.bar) return
    root.bar.run(command)
    root.close()
  }

  function activateAction(index) {
    if (index < 0 || index >= root.actions.length) return
    if (!root.isPickable(index)) return
    root.run(root.actions[index].command)
  }

  // The status file is the creature's own account of itself; a half-written
  // one is simply ignored until the next write lands.
  function parseStatus(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      root.status = parsed && typeof parsed === "object" ? parsed : ({})
    } catch (e) {
      root.status = ({})
    }
  }

  FileView {
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseStatus(text())
    onLoadFailed: root.status = ({})
  }

  Timer {
    interval: 30000
    running: root.opened || !root.statusShown
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    selectedIndex = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A timer is the one thing worth reading from across the room, so while
    // one runs the button shows it instead of the creature's glyph.
    text: root.statusTimer > 0 ? root.timerShort : "󰚩"
    active: root.urgentMood || root.statusTimer > 0
    // Every first-party widget says what it is and what its other buttons
    // do; this one used to say nothing at all.
    tooltipText: root.buttonTooltip

    Rectangle {
      z: 2
      visible: !(root.statusStale && !root.statusShown)
      width: Style.space(5)
      height: width
      radius: width / 2
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Style.space(2)
      anchors.bottomMargin: Style.space(2)
      color: root.moodColor
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.run("omarchy-shell omarchief ask")
      else if (buttonCode === Qt.RightButton) root.run("omarchy-shell omarchief summon")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    // No cap of our own: the list is long and the helper already stops at
    // what the screen can hold, where the ScrollView takes over.
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.selectAction(root.selectedIndex + dy)
        else if (dx !== 0) root.selectAction(root.selectedIndex + dx)
      }
      onActivateRequested: root.activateAction(root.selectedIndex)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // The settings outgrew the card long ago; without this the list simply
      // drew past the bottom of the panel and off the screen. Same shape the
      // audio and bluetooth panels use.
      ScrollView {
        id: scroller
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scroller.contentItem
          property: "interactive"
          value: column.implicitHeight > scroller.height
        }

      Column {
        id: column
        width: scroller.availableWidth
        spacing: Style.spacing.sm

        // The creature at a glance: who it is answering with, how it is, and
        // the last thing it did or said. Same hero the first-party panels use.
        PanelHero {
          width: parent.width
          title: root.heroTitle
          meta: root.heroMeta
          detail: root.heroDetail
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: root.moodGlyph
              color: root.agentSilent ? Color.urgent : Color.accent
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        Repeater {
          model: root.actions

          Loader {
            required property var modelData
            required property int index

            width: parent.width
            sourceComponent: modelData.kind === "separator" ? separatorRow
              : modelData.kind === "heading" ? headingRow
              : modelData.kind === "toggle" ? toggleRow
              : modelData.kind === "dropdown" ? dropdownRow
              : modelData.kind === "buttons" ? buttonsRow : actionRow

            // Walking the selection with the keyboard must not walk it out
            // of sight.
            onYChanged: if (root.cursorActive && root.selectedIndex === index) root.revealRow(y, height)
            Component {
              id: separatorRow
              PanelSeparator { width: parent ? parent.width : 0; foreground: root.foreground }
            }

            Component {
              id: dropdownRow
              Dropdown {
                width: parent ? parent.width : 0
                label: modelData.label
                value: modelData.value
                options: modelData.options
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.cursorActive && root.selectedIndex === index
                onHovered: function(isHovered) {
                  if (isHovered) { root.cursorActive = true; root.selectedIndex = index }
                }
                onChanged: function(v) { root.runValue(modelData.prefix, v) }
              }
            }

            Component {
              id: buttonsRow
              Column {
                width: parent ? parent.width : 0
                spacing: Style.spacing.xs
                Text {
                  text: modelData.label
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                ButtonGroup {
                  width: parent.width
                  options: modelData.options
                  value: modelData.value
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  cursorIndex: root.cursorActive && root.selectedIndex === index ? 0 : -1
                  onChanged: function(v) { root.runValue(modelData.prefix, v) }
                  onHovered: function(i, isHovered) {
                    if (isHovered) { root.cursorActive = true; root.selectedIndex = index }
                  }
                }
              }
            }

            Component {
              id: headingRow
              PanelSectionHeader {
                width: parent ? parent.width : 0
                text: modelData.label
              }
            }

            Component {
              id: actionRow
              Button {
                width: parent ? parent.width : 0
                text: modelData.label
                // Some of these want a word of explanation and none of them
                // has room for one; the first-party button renders it on
                // hover, so it costs the row nothing.
                tooltipText: modelData.description || ""
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                leftAlign: true
                selected: root.selectedIndex === index
                hasCursor: root.cursorActive && root.selectedIndex === index
                onHovered: function(isHovered) {
                  if (isHovered) { root.cursorActive = true; root.selectedIndex = index }
                }
                onClicked: root.activateAction(index)
              }
            }

            Component {
              id: toggleRow
              Toggle {
                width: parent ? parent.width : 0
                label: modelData.label
                description: modelData.description || ""
                checked: modelData.checked === true
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.cursorActive && root.selectedIndex === index
                onHovered: function(isHovered) {
                  if (isHovered) { root.cursorActive = true; root.selectedIndex = index }
                }
                onClicked: root.activateAction(index)
              }
            }
          }
        }
      }
      }
    }
  }
}
