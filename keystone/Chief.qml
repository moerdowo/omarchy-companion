import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The chief itself. Pure presentation: the panel tells it the mood, the
// energy, and what to say — this file does the living. Two bodies are
// available: a procedural blob drawn entirely from theme colors, and any
// pet from the Codex/Petdex spritesheet ecosystem, whose directional walk
// rows finally get used for actual walking.
//
// Travel is a dive: `submerged` sinks the body under the bottom edge, the
// panel moves the chief to another screen while nothing is visible, and
// releasing `submerged` raises it out of the ground over there.
Item {
  id: pet

  property int petSize: 56
  // Drawn art is scaled with filtering; pixel art keeps its hard pixels.
  property bool pixelArt: false
  // A pet may be a set of expressions rather than a set of animations. One
  // drawing per mood, nothing moving of its own accord, and the only thing
  // that ever shifts it across the screen is a hand.
  property var faces: null
  property int columns: 8
  readonly property bool still: faces !== null
  // Whether a resting creature is allowed to change its expression on its
  // own, and how readily. Nothing moves either way — it is the difference
  // between a face and a photograph of one.
  // Whether this artwork may be turned around, and whether it is right now.
  property bool mayMirror: false
  readonly property bool mirrored: mayMirror && Model.mirroredAt(px, width)
  onMirroredChanged: mirrorNote.restart()
  Timer { id: mirrorNote; interval: 1; onTriggered: pet.turned() }
  signal turned()
  property bool expressions: true
  property real glanceChance: 0.25
  // What the artist says a resting creature may wear, if they said.
  property var idleFaces: null
  // A closed-eyes drawing, if the artist made one. A still creature blinks
  // with it every few seconds — the cheapest, most constant sign of life —
  // and it is a snap, not a dissolve, because a blink you can watch fade is
  // not a blink.
  property var blinkFace: null
  // The panel on the creature's front is a screen, and a screen that only
  // ever shows a face is being wasted. Artwork that names the panel — as a
  // rectangle in cell fractions, with the slope its top edge is drawn at —
  // can be asked to show something on it.
  // Being repainted for a new theme. The sheet it wore before is kept for
  // the length of the change and drawn over the new one, masked to the part
  // that has not been reached yet — so the colour rises up the creature
  // instead of the whole of it blinking into another shade.
  property url repaintFrom: ""
  property real repaintFill: 1
  function repaint(previous) {
    if (String(previous) === "" || !spriteOk) return
    repaintFrom = previous
    repaintFill = 0
    repaintRise.restart()
  }
  NumberAnimation {
    id: repaintRise
    target: pet
    property: "repaintFill"
    to: 1
    // Quick enough to feel like the colour arriving rather than a wipe
    // being performed, slow enough to see it arrive.
    duration: 300
    easing.type: Easing.OutCubic
    onFinished: pet.repaintFrom = ""
  }

  property var display: null
  property string displayText: ""
  property color screenInk: "#c8ff5a"
  property string screenFont: "monospace"
  property bool blinking: false
  Timer {
    id: blinkStill
    interval: 3000
    repeat: true
    running: pet.onStage && pet.still && !pet.tucked
             && Model.mayBlink(pet.mood, pet.faces, pet.blinkFace)
    onTriggered: {
      blinkStill.interval = 2400 + Math.round(Math.random() * 4200)
      // Not while it is wearing something it means — a wink or a sparkle
      // reads oddly interrupted by a blink — and never mid-grab.
      if (pet.glance !== null || hit.holding || pet.promptOpen) return
      pet.blinking = true
      blinkStillOff.restart()
      // Once in a while a double blink, the way a real one sometimes comes.
      if (Math.random() < 0.22) blinkDouble.restart()
    }
  }
  Timer { id: blinkStillOff; interval: 130; onTriggered: pet.blinking = false }
  Timer {
    id: blinkDouble; interval: 300
    onTriggered: { if (!hit.holding) { pet.blinking = true; blinkStillOff.restart() } }
  }
  property var glance: null
  property string mood: "idle" // idle|tired|working|parked|waiting|success|error|sleeping
  property real energy: 1
  property real activityRate: 1
  property bool roam: false
  property var activities: []
  // How eagerly the creature finds something to do, and how long it rests
  // afterwards before it could do anything again.
  property real activityChance: 0.4
  property int activityRestMs: 90000
  property string lastActivity: ""
  property bool activityRested: true
  // How many times through the row, and how long a performance should last.
  property int activityPasses: 1
  // Which pass of the performance is running. It lives out here because the
  // viewport is a Component — a template — and its ids are not something
  // the outside world can reach into.
  property int activityPass: 0
  property int activityTargetMs: 9000
  property bool active: true   // window visible; gates every timer below
  property bool promptOpen: false
  property bool submerged: false
  property real initialPx: -1
  property string tooltipText: ""
  property string placeholder: "Tell your desktop what to do…"

  // Speech: "" (quiet), "think" (dots while the agent works), "say", "error".
  property string sayMode: ""
  // What the agent is doing while the creature waits on it.
  property string doing: ""
  property string sayText: ""

  // Sprite body (optional). When spriteOk is false the blob takes over.
  property bool spriteOk: false
  property url spriteSource: ""
  property int spriteRows: 9
  property int frameIntervalMs: 140
  // Sprites are artwork first — the ecosystem shows them as drawn, and so do
  // we. Tinting is opt-in and partial, so the drawing survives it, and the
  // color is lifted until it is legible on the theme's own background.
  property real tintStrength: 0
  property int sleepRow: -1
  property int walkFrames: 0
  property var stillRows: []
  // The sheet's own proportions decide the cell shape; until it has loaded,
  // the ecosystem's usual one stands in.
  property real sheetWidth: 0
  property real sheetHeight: 0
  readonly property real cellAspect: Model.cellAspect(sheetWidth, sheetHeight, spriteRows, columns)
  // An idle activity: a row of the atlas played once through, wherever the
  // creature happens to be standing.
  property var activity: null
  // How far above the window's bottom edge the feet land — the same gap
  // Hyprland leaves between a window and the screen.
  property real groundOffset: 3
  readonly property var tintRgb: Model.contrastSafe(
    { r: Color.accent.r, g: Color.accent.g, b: Color.accent.b },
    { r: Color.background.r, g: Color.background.g, b: Color.background.b }, 4.5)

  signal petPressed(int button)
  signal promptSubmitted(string text)
  signal promptDismissed()
  signal bubbleDismissed()
  signal consoleRequested()
  // The sheet on disk can go missing under us — a themed copy is a cache,
  // and caches get cleaned. Saying so is what lets the panel heal it.
  signal spriteLoadFailed()
  signal activityFinished()
  signal draggedTo(real x)

  readonly property Item hitbox: hit

  // Two edges: a wide one a stroll turns around at, and a narrow one that
  // still lets the creature sit right in the corner with its cable running
  // off the screen.
  readonly property real marginX: petSize * 1.2
  readonly property real edgeMargin: petSize * 0.3
  readonly property color bodyColor: Color.accent
  readonly property color inkColor: Color.background
  readonly property color outlineColor: Qt.darker(bodyColor, 1.35)

  // Rising out of the ground: 0 = fully under, 1 = standing on it.
  property real emerge: submerged ? 0 : 1
  Behavior on emerge { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }
  readonly property bool onStage: active && emerge > 0.9

  // ---------------------------------------------------------------- motion

  property real px: width * 0.75
  // Tucked away: slid mostly off its nearest edge so you can read behind it,
  // a sliver left to click it back. A slide, not a jump.
  property bool tucked: false
  // Which way it went: into the floor it stands on, or against one of the
  // sides. Either way its place on the edge is unchanged and only the
  // picture moves, so letting it out puts it back exactly where it was.
  property string tuckSide: "down"
  // Hovering what is left showing lifts it a little — "yes, still here".
  // Only then: during a shove the pointer is on it by definition, and
  // lifting there would hold it back from the hand pushing it.
  readonly property bool peeking: tucked && hit.containsMouse && !hit.dragging && hit.peekArmed
  // Where speech and the order form belong. Normally over the creature;
  // put away, over whatever of it is still showing — it can be talked to
  // while it is out of the way, and an answer that appears below the edge
  // of the screen is no answer.
  readonly property real speakX: tucked ? (hit.leftLimit + hit.rightLimit) / 2
                                        : body.x + body.width / 2
  readonly property real speakTop: tucked ? hit.y : body.y
  // Where the drawing sits inside its cell, as fractions. Artwork that does
  // not say is assumed to fill it.
  property var content: null
  readonly property real contentLeft: content && isFinite(Number(content.left)) ? Number(content.left) : 0
  readonly property real contentRight: content && isFinite(Number(content.right)) ? Number(content.right) : 1
  readonly property real contentTop: content && isFinite(Number(content.top)) ? Number(content.top) : 0
  readonly property real contentBottom: content && isFinite(Number(content.bottom)) ? Number(content.bottom) : 1
  readonly property real peek: Model.peekHeight(petSize)
  // Handed down so timers can hold still while it is out of the way.
  property real tuckAmount: 0
  // Pushed against a side with only a peek of it showing. Not a mode it is
  // put into: it is simply where it stands.

  // Sunk into the edge it stands on, with the top of its head left up.
  // Hovering that lifts it a little — enough to say "yes, still here".
  // One animated value does both moves: the sink and the peek are the same
  // journey, and animating them separately made them fight.
  readonly property real sinkFull: Model.sinkShift(body.groundY, body.height, height, peek, contentTop)
  property real tuckDrop: tuckSide !== "down" ? 0
    : hit.shoving ? Math.max(0, Math.min(sinkFull, hit.handDown))
    : tuckAmount * sinkFull * (pet.peeking ? 0.72 : 1)
  // While the hand is on it, it goes where the hand goes — animating that
  // would put it a quarter-second behind your own gesture, which reads as
  // mush. The easing is for letting go: springing back, or settling away.
  Behavior on tuckDrop {
    enabled: !hit.shoving
    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
  }
  readonly property real slideFull: Model.sideTuckShift(px - body.width / 2, body.width, width,
                                                       peek, contentLeft, contentRight, tuckSide)
  // How far the hand has pushed past the point the creature stopped at.
  readonly property real shoveOver: {
    if (!hit.shoving || tuckSide === "down") return 0
    var edge = petSize * 0.3
    var raw = hit.grabPx + hit.handMoved
    return tuckSide === "left" ? Math.max(0, edge - raw) : Math.max(0, raw - (width - edge))
  }
  property real tuckSlide: tuckSide === "down" ? 0
    : hit.shoving ? (tuckSide === "left" ? -Math.min(-slideFull, shoveOver)
                                         : Math.min(slideFull, shoveOver))
    : tuckAmount * slideFull * (pet.peeking ? 0.78 : 1)
  Behavior on tuckSlide {
    enabled: !hit.shoving
    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
  }
  signal tuckChanged(bool value)
  // Pulling on the sliver is how you fetch it back: without this the offset
  // travels with the creature and it only slides along the edge, still
  // mostly out of sight.
  signal wantsOut()
  // Two taps means "out of the way" — the same thing dragging it against a
  // side means, said with the hand already on it.
  // Shoved far enough to mean "out of the way" — sideways, or downwards.
  signal pushedAside(string side)
  onTuckedChanged: { tuckAmount = tucked ? 1 : 0; tuckChanged(tucked) }
  property bool seeded: false
  onWidthChanged: if (!seeded && width > 0) {
    px = initialPx >= 0 ? Math.max(edgeMargin, Math.min(width - edgeMargin, initialPx)) : width * 0.75
    seeded = true
  }

  property int dir: 1
  readonly property bool walking: walkAnim.running
  property real hop: 0
  property real breathe: 0
  // A slow, always-there breath for a still creature, so resting reads as
  // alive rather than frozen. It is tiny on purpose — a pet that heaves is
  // as wrong as one that never moves — and it stops the moment anything more
  // deliberate takes over, so nothing ever stacks.
  property real rest: 0
  SequentialAnimation {
    running: pet.onStage && pet.spriteOk && !pet.walking && pet.activity === null
             && pet.mood !== "sleeping" && !hit.pressed
    loops: Animation.Infinite
    NumberAnimation { target: pet; property: "rest"; from: 0; to: 1; duration: 1500; easing.type: Easing.InOutSine }
    NumberAnimation { target: pet; property: "rest"; from: 1; to: 0; duration: 1900; easing.type: Easing.InOutSine }
  }

  NumberAnimation {
    id: walkAnim
    target: pet
    property: "px"
    easing.type: Easing.Linear
  }

  // A sprite walks in its own drawing; adding a bounce on top makes it
  // hop rather than walk. Only the blob, which has no gait of its own,
  // gets the synthetic one.
  SequentialAnimation {
    running: pet.active && pet.walking && !pet.spriteOk
    loops: Animation.Infinite
    alwaysRunToEnd: true
    NumberAnimation { target: pet; property: "hop"; from: 0; to: 1; duration: 165; easing.type: Easing.OutQuad }
    NumberAnimation { target: pet; property: "hop"; from: 1; to: 0; duration: 165; easing.type: Easing.InQuad }
  }

  // Working: quick typing squish. Sleeping: slow swell. Amplitudes live in
  // the blob's Scale and follow the mood live; only the tempo is sampled
  // per segment, and the two moods never hand off to each other directly.
  SequentialAnimation {
    running: pet.active && (pet.mood === "sleeping" || pet.mood === "working")
    loops: Animation.Infinite
    NumberAnimation { target: pet; property: "breathe"; from: 0; to: 1; duration: pet.mood === "working" ? 240 : 1600; easing.type: Easing.InOutSine }
    NumberAnimation { target: pet; property: "breathe"; from: 1; to: 0; duration: pet.mood === "working" ? 240 : 1600; easing.type: Easing.InOutSine }
  }

  function wanderTo(tx) {
    walkAnim.stop()
    tx = Math.max(edgeMargin, Math.min(width - edgeMargin, tx))
    var speed = Model.walkSpeed(mood, energy)
    if (speed <= 0) return
    dir = tx >= px ? 1 : -1
    walkAnim.to = tx
    walkAnim.duration = Math.max(250, Math.abs(tx - px) / speed * 1000)
    walkAnim.start()
  }

  function cheer() { if (!walking) soloHop.restart() }
  function stopWalking() { walkAnim.stop() }

  // A quiet moment: sometimes the creature simply finds something to do,
  // right where it stands.
  // A quiet moment: sometimes the creature finds something to do, right
  // where it stands. Never twice the same thing, never while it is busy,
  // and never so often that it stops being a small surprise.
  function idleMoment() {
    if (still) return
    if (!Model.mayPlayActivity({ onStage: onStage, promptOpen: promptOpen, walking: walking,
                                 dragging: hit.dragging, mood: mood, rested: activityRested })) return
    var pick = Model.pickActivity(Math.random, activities, activityChance, lastActivity)
    if (pick) playActivity(pick)
  }

  function playActivity(track) {
    if (still) return false
    // An explicit request skips the rest, but never the interruptions.
    if (!Model.mayPlayActivity({ onStage: onStage, promptOpen: promptOpen, walking: walking,
                                 dragging: hit.dragging, mood: mood, rested: true })) return false
    activity = track
    activityPasses = Model.activityRepeats(track, activityTargetMs, Model.activityDuration(track, frameIntervalMs * 4))
    // Start the count at the beginning, or every performance after the
    // first inherits the last one's finished count and ends after one pass.
    activityPass = 0
    lastActivity = String(track.name || "")
    activityRested = false
    activityRest.restart()
    return true
  }

  // The rest runs from the end of the performance, not its start.
  Timer {
    id: activityRest
    interval: Math.max(1000, Model.activityDuration(pet.activity, pet.frameIntervalMs * 4) * pet.activityPasses) + pet.activityRestMs
    onTriggered: pet.activityRested = true
  }

  // A deliberate walk: pick a spot far enough away to be worth watching,
  // preferring whichever side has more room.
  // Walk back to where the creature lives, or step there directly if the
  // distance is too small to be worth a walk.
  function walkHome(target) {
    activity = null
    var x = Math.max(edgeMargin, Math.min(width - edgeMargin, target))
    if (Math.abs(x - px) < petSize * 0.4) { walkAnim.stop(); px = x; return }
    wanderTo(x)
  }

  function strollNow() {
    if (!onStage || mood === "sleeping" || promptOpen) return false
    var room = petSize * 9
    var toRight = px < width / 2
    var target = toRight ? Math.min(width - marginX, px + room) : Math.max(marginX, px - room)
    if (Math.abs(target - px) < petSize) return false
    wanderTo(target)
    return true
  }

  onMoodChanged: {
    if (mood === "sleeping") walkAnim.stop()
    // Anything that demands attention cuts a performance short, and ends a
    // daydream: a face with news to deliver should be wearing the news.
    if (activity !== null && (mood === "working" || mood === "waiting" || mood === "error")) activity = null
    if (mood !== "idle" && mood !== "parked") glance = null
  }
  onSubmergedChanged: if (submerged) walkAnim.stop()
  onSpriteSourceChanged: { sheetWidth = 0; sheetHeight = 0 }
  onPromptOpenChanged: if (promptOpen) { walkAnim.stop(); activity = null; focusTimer.restart() }

  SequentialAnimation {
    id: soloHop
    NumberAnimation { target: pet; property: "hop"; from: 0; to: 1.3; duration: 185; easing.type: Easing.OutQuad }
    NumberAnimation { target: pet; property: "hop"; from: 1.3; to: 0; duration: 185; easing.type: Easing.InQuad }
  }

  // ----------------------------------------------------------------- brain

  Timer {
    id: brain
    interval: 2500
    repeat: true
    running: pet.onStage && !pet.still && pet.mood !== "sleeping" && !pet.promptOpen
    onTriggered: {
      var a = Model.decideAction(Math.random, pet.mood, pet.activityRate)
      brain.interval = a.nextMs
      if (a.type === "wander" && pet.roam)
        pet.wanderTo(pet.px + (Math.random() - 0.5) * 2 * pet.petSize * 6)
      else if (a.type === "hop" && !pet.walking) soloHop.restart()
      else if (a.type === "sit") pet.idleMoment()
    }
  }

  // Resting is not the same as being frozen. Every so often the creature
  // looks up wearing something else for a few seconds — never while anything
  // is actually happening, and rarely enough that catching it feels like
  // catching something.
  Timer {
    id: glanceOffer
    interval: 9000
    repeat: true
    running: pet.onStage && pet.still && !pet.tucked && pet.expressions && !pet.promptOpen
    onTriggered: {
      // The chance decides how lively it is, so the offer comes at a steady
      // pace and lets it through or not — otherwise a high chance still felt
      // rare because the offers themselves were far apart.
      glanceOffer.interval = 7000 + Math.round(Math.random() * 8000)
      if (pet.glance !== null || hit.holding) return
      var look = Model.idleGlance(Math.random, pet.faces, pet.mood, pet.glanceChance,
                                  pet.idleFaces, pet.spriteRows, pet.columns)
      if (!look) return
      pet.glance = look
      glanceBack.interval = Model.glanceMs(Math.random)
      glanceBack.restart()
    }
  }
  Timer { id: glanceBack; onTriggered: pet.glance = null }
  onExpressionsChanged: if (!expressions) glance = null

  property bool lidsClosed: false
  Timer {
    id: blinkTimer
    interval: 3200
    repeat: true
    running: pet.onStage && pet.mood !== "sleeping"
    onTriggered: {
      pet.lidsClosed = true
      blinkOff.restart()
      blinkTimer.interval = 2200 + Math.random() * 4800
    }
  }
  Timer { id: blinkOff; interval: 130; onTriggered: pet.lidsClosed = false }

  // ------------------------------------------------------------------ body

  Item {
    id: body
    width: pet.spriteOk ? Math.round(pet.petSize * pet.cellAspect) : pet.petSize
    height: pet.spriteOk ? pet.petSize : pet.petSize * 0.82
    x: Math.round(pet.px - width / 2 + pet.tuckSlide)
    // What stands on the line is the creature's feet, not the bottom of the
    // cell it is drawn in. Gritty's cell carries forty empty pixels beneath
    // it, and putting that edge on the line left the creature hovering that
    // far above the corner it is supposed to sit in.
    readonly property real groundY: pet.height - height * pet.contentBottom
                                    - pet.groundOffset - pet.hop * pet.petSize * 0.14
    y: groundY + (1 - pet.emerge) * (pet.height - groundY + 8) + pet.tuckDrop

    // Pixel-art pets keep their silhouette; only the blob gets squashed,
    // stretched, and tilted.
    transform: [
      Rotation {
        origin.x: body.width / 2
        origin.y: body.height
        angle: pet.spriteOk ? 0 : (pet.walking ? pet.dir * 4 : (hit.containsMouse ? -2 : 0))
        Behavior on angle { NumberAnimation { duration: 180 } }
      },
      Scale {
        origin.x: body.width / 2
        origin.y: body.height
        xScale: pet.spriteOk ? (hit.pressed ? 0.95 : 1 - pet.rest * 0.007)
          : (1 - pet.hop * 0.05 + pet.breathe * (pet.mood === "working" ? 0.025 : 0.02)) * (hit.pressed ? 0.94 : 1)
        yScale: pet.spriteOk ? (hit.pressed ? 0.95 : 1 + pet.rest * 0.014)
          : (1 + pet.hop * 0.09 + pet.breathe * (pet.mood === "working" ? -0.05 : 0.045)) * (hit.pressed ? 0.94 : 1)
        Behavior on xScale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Behavior on yScale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
      },
      // Turning around is a turn, not a jump: it pivots on the spot.
      Scale {
        id: facing
        origin.x: body.width / 2
        xScale: pet.mirrored ? -1 : 1
        Behavior on xScale { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }
      }
    ]

    Loader {
      anchors.fill: parent
      sourceComponent: pet.spriteOk ? spriteBody : blobBody
    }
  }

  Component {
    id: blobBody
    Rectangle {
      radius: height * 0.46
      color: pet.bodyColor
      border.color: pet.mood === "error" ? Color.urgent : pet.outlineColor
      border.width: Math.max(1.5, pet.petSize / 34)
      Behavior on color { ColorAnimation { duration: 350 } }

      Item {
        id: eyes
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.28
        width: parent.width * 0.52
        height: eyeH
        readonly property real eyeW: pet.petSize * 0.115
        readonly property real eyeH: pet.petSize * 0.20

        Repeater {
          model: 2
          Rectangle {
            required property int index
            x: index === 0 ? 0 : eyes.width - width
            width: eyes.eyeW
            height: (pet.mood === "sleeping" || pet.lidsClosed) ? eyes.eyeH * 0.12
                  : (pet.mood === "tired" || pet.mood === "error") ? eyes.eyeH * 0.45
                  : eyes.eyeH * ((hit.containsMouse || pet.mood === "waiting") ? 1.15 : 1)
            y: (eyes.eyeH - height) / 2 + ((pet.mood === "tired" || pet.mood === "error") ? eyes.eyeH * 0.18 : 0)
            radius: width / 2
            color: pet.inkColor
            Behavior on height { NumberAnimation { duration: 90 } }
          }
        }
      }
    }
  }

  // One scaled frame of the Codex/Petdex atlas, clipped out of the sheet.
  // Sizing the sheet in multiples of the viewport keeps every offset exact
  // regardless of scale.
  Component {
    id: spriteBody
    Item {
      id: vp
      clip: true

      readonly property var track: pet.activity !== null
        ? pet.activity
        : Model.spriteTrack(pet.mood, pet.walking, pet.dir, pet.sleepRow, pet.walkFrames)
      property int frame: 0

      // Where to look on the sheet: an expression for a still pet, a frame
      // of the current row for an animated one.
      readonly property var face: pet.still
        ? (hit.holding ? Model.faceFor("dragged", pet.faces)
           : pet.blinking && pet.blinkFace !== null ? pet.blinkFace
           : pet.glance !== null ? pet.glance
           : Model.faceFor(pet.mood, pet.faces))
        : null
      readonly property int cellRow: face ? face[0] : vp.track.row
      readonly property int cellCol: face ? face[1] : vp.frame
      // An expression changing is worth a dissolve of its own: the face
      // turns into the next one rather than being swapped for it.
      onFaceChanged: {
        if (!pet.still) return
        vp.fromRow = vp.wasRow
        vp.fromFrame = vp.wasCol
        vp.wasRow = vp.cellRow
        vp.wasCol = vp.cellCol
        // A blink is a snap; expressions fade into one another.
        if (pet.blinking || vp.wasBlink) { dissolve.stop(); vp.mix = 1 }
        else { dissolve.stop(); vp.mix = 0; dissolve.duration = 260; dissolve.start() }
        vp.wasBlink = pet.blinking
      }
      property bool wasBlink: false
      property int wasRow: 0
      property int wasCol: 0

      // The frame being left behind, and how far the new one has come in.
      // Holding on to it is what turns six drawn poses into one motion
      // rather than six cuts.
      property int fromFrame: 0
      property int fromRow: 0
      property real mix: 1

      // How faded the creature is for reasons other than the dissolve.
      readonly property real bodyOpacity: pet.mood === "sleeping" && pet.sleepRow < 0 ? 0.55 : 1

      function stepTo(next) {
        vp.fromFrame = vp.frame
        vp.fromRow = vp.cellRow
        vp.frame = next
        var ms = Model.crossfadeMs(frameTimer.interval)
        if (ms <= 0) { dissolve.stop(); vp.mix = 1; return }
        dissolve.stop()
        vp.mix = 0
        dissolve.duration = ms
        dissolve.start()
      }

      NumberAnimation {
        id: dissolve
        target: vp
        property: "mix"
        to: 1
        easing.type: Easing.InOutQuad
      }

      onTrackChanged: if (!pet.still) { vp.fromRow = vp.track.row; vp.fromFrame = 0; vp.frame = 0; vp.mix = 1 }

      Timer {
        id: frameTimer
        // Walking animates at full clip; a standing chief changes its face
        // slowly, like something alive rather than something looping. An
        // activity sits between the two: a performance, played once through.
        // An activity keeps the timing it was built with: each frame is held
        // as long as the change that follows it deserves, so a screen full of
        // text can be read and a punchline can land.
        interval: pet.activity !== null
          ? Model.activityHold(pet.activity, vp.frame, pet.frameIntervalMs * 4)
          : pet.frameIntervalMs * (pet.walking ? 1 : pet.mood === "tired" ? 10 : 6)
        repeat: true
        // A still row has nothing to animate; leaving the timer running
        // would repaint the same pixels for as long as the desktop is on.
        running: pet.onStage && !pet.still && !Model.isStillRow(pet.stillRows, vp.track.row)
                 && (pet.mood !== "sleeping" || pet.sleepRow >= 0 || pet.activity !== null)
        onTriggered: {
          if (pet.activity !== null && vp.frame + 1 >= vp.track.frames) {
            if (pet.activityPass + 1 >= pet.activityPasses) pet.activityFinished()
            else { pet.activityPass++; vp.stepTo(0) }
          } else vp.stepTo((vp.frame + 1) % vp.track.frames)
        }
      }

      // The frame being left behind, underneath, at full strength. It is
      // the same sheet at a different offset, so it costs one more quad and
      // no extra texture.
      Image {
        id: sheetFrom
        source: pet.spriteSource
        width: vp.width * pet.columns
        height: vp.height * pet.spriteRows
        x: -vp.fromFrame * vp.width
        y: -vp.fromRow * vp.height
        smooth: !pet.pixelArt
        mipmap: !pet.pixelArt
        visible: pet.tintStrength <= 0 && vp.mix < 1
        opacity: vp.bodyOpacity
      }

      Image {
        id: sheet
        source: pet.spriteSource
        width: vp.width * pet.columns
        height: vp.height * pet.spriteRows
        x: -vp.cellCol * vp.width
        y: -vp.cellRow * vp.height
        smooth: !pet.pixelArt
        mipmap: !pet.pixelArt
        onStatusChanged: {
          if (status === Image.Error) pet.spriteLoadFailed()
          else if (status === Image.Ready) {
            pet.sheetWidth = implicitWidth
            pet.sheetHeight = implicitHeight
          }
        }
        visible: pet.tintStrength <= 0
        opacity: vp.bodyOpacity * vp.mix
      }

      // The colours it wore a moment ago, still covering the part of it the
      // new ones have not reached. Clipped from the top down, so the new
      // paint appears to rise from the feet.
      Item {
        id: paintOver
        visible: pet.repaintFrom !== "" && pet.repaintFill < 1
        width: vp.width
        height: Math.round(vp.height * (1 - pet.repaintFill))
        clip: true
        Image {
          source: pet.repaintFrom
          width: vp.width * pet.columns
          height: vp.height * pet.spriteRows
          x: -vp.cellCol * vp.width
          y: -vp.cellRow * vp.height
          smooth: !pet.pixelArt
          mipmap: !pet.pixelArt
          asynchronous: true
          cache: true
        }
      }
      // The waterline: a thin bright edge where the new colour has got to,
      // which is what turns a fade into something being filled.
      Rectangle {
        visible: paintOver.visible
        y: paintOver.height - height
        width: vp.width
        height: Math.max(1, Math.round(vp.height * 0.012))
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
          GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.55) }
        }
      }

      // What the screen is showing instead of a face. Dark enough to read
      // against, sheer enough that the panel underneath still shows through
      // — which is what makes it look like the creature's own display
      // rather than a sticker on its head.
      Item {
        // Not "screen": Quickshell already has one of those in scope, and an
        // id that quietly resolves to somebody else's object turns the shear
        // below into an identity matrix with no warning at all.
        id: readout
        visible: pet.display !== null && pet.displayText !== "" && pet.spriteOk
        x: vp.width * Number(pet.display ? pet.display.x : 0)
        y: vp.height * Number(pet.display ? pet.display.y : 0)
        width: vp.width * Number(pet.display ? pet.display.w : 0)
        height: vp.height * Number(pet.display ? pet.display.h : 0)
        readonly property real slope: Number(pet.display && pet.display.slope !== undefined
                                             ? pet.display.slope : 0)
        transform: Matrix4x4 {
          matrix: Qt.matrix4x4(1, 0, 0, 0,
                               readout.slope, 1, 0, 0,
                               0, 0, 1, 0,
                               0, 0, 0, 1)
        }
        opacity: readout.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        Rectangle {
          anchors.fill: parent
          color: "#000000"
          opacity: 0.78
          radius: Math.round(parent.height * 0.10)
        }
        Text {
          anchors.fill: parent
          anchors.margins: parent.height * 0.04
          text: pet.displayText
          color: pet.screenInk
          font.family: pet.screenFont
          font.pixelSize: Math.round(parent.height * 1.0)
          font.bold: true
          minimumPixelSize: 6
          fontSizeMode: Text.Fit
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          renderType: pet.pixelArt ? Text.NativeRendering : Text.QtRendering
        }
      }

      // The theme-dressed twin: same geometry, partially colorized so the
      // drawing's own shading survives, and brightened by however much the
      // tint had to be lifted to stay readable.
      MultiEffect {
        visible: pet.tintStrength > 0
        source: sheet
        x: sheet.x
        y: sheet.y
        width: sheet.width
        height: sheet.height
        colorization: pet.tintStrength
        colorizationColor: Qt.rgba(pet.tintRgb.r, pet.tintRgb.g, pet.tintRgb.b, 1)
        brightness: pet.tintStrength * 0.12
        opacity: vp.bodyOpacity
      }
    }
  }

  // ------------------------------------------------------------------- zzz

  Repeater {
    model: 3
    delegate: Text {
      required property int index
      visible: pet.onStage && pet.mood === "sleeping"
      text: "z"
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: pet.petSize * (0.24 + index * 0.07)
      color: Color.foreground
      property real t: 0
      x: body.x + body.width * 0.85 + index * pet.petSize * 0.17
      y: body.y - pet.petSize * (0.05 + t * 0.55) - index * pet.petSize * 0.16
      opacity: visible ? (1 - t) * 0.85 : 0
      SequentialAnimation on t {
        running: pet.onStage && pet.mood === "sleeping"
        loops: Animation.Infinite
        PauseAnimation { duration: index * 450 }
        NumberAnimation { from: 0; to: 1; duration: 2400 }
      }
    }
  }

  // ------------------------------------------------------------ mood bubble

  Rectangle {
    id: bubble
    z: 3
    readonly property bool tooltipMode: hit.containsMouse && tooltipDelay.done && !pet.promptOpen && pet.sayMode === ""
    readonly property string moodText: Model.bubbleFor(pet.mood)
    visible: pet.onStage && !pet.promptOpen && pet.sayMode === "" && (tooltipMode || moodText !== "")
    color: Color.popups.background
    border.color: pet.mood === "error" || pet.mood === "waiting" ? Color.urgent : Color.popups.border
    border.width: 1
    radius: Style.space(9)
    width: bubbleText.implicitWidth + Style.space(22)
    height: bubbleText.implicitHeight + Style.space(12)
    x: Math.max(Style.space(4), Math.min(pet.width - width - Style.space(4), pet.speakX - width / 2))
    y: pet.speakTop - height - Style.space(10)
    opacity: tooltipMode ? 1 : 0.6 + pulse * 0.4
    property real pulse: 0
    SequentialAnimation on pulse {
      running: bubble.visible && !bubble.tooltipMode
      loops: Animation.Infinite
      NumberAnimation { from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
      NumberAnimation { from: 1; to: 0; duration: 900; easing.type: Easing.InOutSine }
    }

    Text {
      id: bubbleText
      anchors.centerIn: parent
      text: bubble.tooltipMode ? pet.tooltipText : bubble.moodText
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
    }

    // An urgent "!" is an invitation: the waiting session lives in the
    // console, so the bubble takes you there. Other mood glyphs stay
    // decorative and let the click fall through to the desktop.
    MouseArea {
      anchors.fill: parent
      enabled: !bubble.tooltipMode && pet.mood === "waiting"
      cursorShape: Qt.PointingHandCursor
      onPressed: pet.consoleRequested()
    }
  }

  // ----------------------------------------------------------- speech bubble
  //
  // The chief's voice. While the agent works it thinks in dots; the reply
  // replaces them in place. Clicking the bubble puts it away — the
  // conversation itself lives on in the session.

  Item { visible: false; Text { id: sayMeasure; text: sayBody.text; font.family: Style.font.family; font.pixelSize: Style.font.subtitle } }
  Item { visible: false; Text { id: doingMeasure; text: pet.doing; font.family: Style.font.family; font.pixelSize: Style.font.body } }

  Rectangle {
    id: say
    z: 3
    visible: pet.onStage && !pet.promptOpen && pet.sayMode !== ""
    color: Color.popups.background
    border.color: pet.sayMode === "error" ? Color.urgent : Color.popups.border
    border.width: 1
    radius: Style.space(10)
    width: pet.sayMode === "think"
      ? (pet.doing !== "" ? Math.min(Style.space(400), doingMeasure.implicitWidth + Style.space(40)) : Style.space(54))
      : Math.min(Style.space(400), sayMeasure.implicitWidth + Style.space(26))
    height: sayContent.implicitHeight + Style.space(16)
    x: Math.max(Style.space(8), Math.min(pet.width - width - Style.space(8), pet.speakX - width / 2))
    y: pet.speakTop - height - Style.space(12)

    Item {
      id: sayContent
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(8) }
      implicitHeight: pet.sayMode === "think" ? (pet.doing !== "" ? doingRow.implicitHeight : dots.implicitHeight) : sayCol.implicitHeight

      // While the agent narrates its work, the bubble says what it is doing
      // rather than just that it is doing something.
      Row {
        id: doingRow
        visible: pet.sayMode === "think" && pet.doing !== ""
        spacing: Style.space(8)
        anchors.horizontalCenter: parent.horizontalCenter
        Text {
          id: doingPulse
          text: "●"
          color: Color.accent
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
          SequentialAnimation on opacity {
            running: doingRow.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0.3; to: 1; duration: 500; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0.3; duration: 500; easing.type: Easing.InOutSine }
          }
        }
        Text {
          text: pet.doing
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: Math.min(Style.space(360), implicitWidth)
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        id: dots
        visible: pet.sayMode === "think" && pet.doing === ""
        anchors.horizontalCenter: parent.horizontalCenter
        text: "· · ·"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
        SequentialAnimation on opacity {
          running: dots.visible
          loops: Animation.Infinite
          NumberAnimation { from: 0.25; to: 1; duration: 450; easing.type: Easing.InOutSine }
          NumberAnimation { from: 1; to: 0.25; duration: 450; easing.type: Easing.InOutSine }
        }
      }

      Column {
        id: sayCol
        visible: pet.sayMode !== "think"
        width: parent.width
        spacing: Style.space(4)

        Text {
          id: sayBody
          width: parent.width
          text: pet.sayText
          wrapMode: Text.Wrap
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        Text {
          visible: pet.sayMode === "error"
          text: "console →"
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: pet.sayMode === "say" || pet.sayMode === "error"
      cursorShape: Qt.PointingHandCursor
      onPressed: pet.sayMode === "error" ? pet.consoleRequested() : pet.bubbleDismissed()
    }
  }

  // ------------------------------------------------------------- ask input
  //
  // The whole point of the chief: a one-line order form. Enter files the
  // order, Escape (or clicking elsewhere) puts the pen down but keeps the
  // draft. An empty Enter summons the console.

  MouseArea {
    // While the prompt is open the entire strip is interactive (the panel
    // widens the input mask), so a click anywhere outside the input puts
    // the prompt away.
    anchors.fill: parent
    enabled: pet.promptOpen
    onPressed: pet.promptDismissed()
  }

  Rectangle {
    id: ask
    visible: pet.promptOpen && pet.onStage
    width: Math.min(pet.width - Style.space(24), Style.space(400))
    height: input.implicitHeight + Style.space(18)
    color: Color.popups.background
    border.color: Color.popups.border
    border.width: 1
    radius: Style.space(10)
    x: Math.max(Style.space(12), Math.min(pet.width - width - Style.space(12), pet.speakX - width / 2))
    y: pet.speakTop - height - Style.space(12)

    TextInput {
      id: input
      anchors.fill: parent
      anchors.margins: Style.space(9)
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      clip: true
      verticalAlignment: TextInput.AlignVCenter
      onAccepted: {
        var t = text
        text = ""
        pet.promptSubmitted(t)
      }
      Keys.onEscapePressed: pet.promptDismissed()

      Text {
        visible: input.text === ""
        anchors.verticalCenter: parent.verticalCenter
        text: pet.placeholder
        color: Color.popups.text
        opacity: 0.45
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }
    }
  }
  Timer { id: focusTimer; interval: 90; onTriggered: if (pet.promptOpen) input.forceActiveFocus() }

  // ------------------------------------------------------------------- hit

  MouseArea {
    id: hit
    z: 1
    x: leftLimit
    // The hitbox rises over the bubbles when one of them is clickable, so
    // the mask lets those clicks in; otherwise it hugs the body and the
    // desktop above stays click-through.
    readonly property bool coversBubbles: (pet.mood === "waiting" && pet.sayMode === "")
      || pet.sayMode === "say" || pet.sayMode === "error"
    // Tucked away it must catch clicks on what is left showing and not one
    // pixel more: the whole point of sinking was to hand that area back to
    // the window underneath, and an invisible catcher over it would be a
    // worse obstruction than the creature was.
    // Put away, it may catch what is showing of it and nothing else. The
    // margins that make it comfortable to hit while it stands in the open
    // would reach out over the very window it has just made room for.
    // body.x already carries the slide; adding it again put the hitbox off
    // the screen and left nothing to click, which is a creature you cannot
    // get back. It never narrows below the peek for the same reason.
    readonly property real shownLeft: body.x + body.width * pet.contentLeft
    readonly property real shownRight: body.x + body.width * pet.contentRight
    readonly property real leftLimit: pet.tucked
      ? Math.max(0, Math.min(shownLeft, pet.width - pet.peek))
      : body.x - pet.petSize * 0.18
    readonly property real rightLimit: pet.tucked
      ? Math.max(leftLimit + pet.peek, Math.min(pet.width, shownRight))
      : body.x + body.width + pet.petSize * 0.18
    // Sunk into the floor, the same rule downwards: the top of what is
    // drawn, never a taller catcher than the head that is showing.
    readonly property real shownTop: body.y + body.height * pet.contentTop
    readonly property real shownBottom: body.y + body.height * pet.contentBottom
    y: pet.tucked ? Math.max(0, Math.min(shownTop, pet.height - pet.peek))
       : coversBubbles ? Math.min(body.y - pet.petSize * 0.30, say.visible ? say.y : bubble.visible ? bubble.y : body.y)
                       : body.y - pet.petSize * 0.30
    width: Math.max(0, rightLimit - leftLimit)
    height: pet.tucked ? Math.max(pet.peek, Math.min(pet.height, shownBottom) - y)
                       : body.y + body.height + pet.petSize * 0.04 - y
    hoverEnabled: true
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    // Press, move, release: a drag carries the creature and sets where it
    // lives; anything shorter than a few pixels was meant as a click.
    property real grabX: 0
    property real grabY: 0
    property real grabPx: 0
    property bool dragging: false
    property string pushedTo: ""
    // Which way this drag is shoving, once it has started. Latched for the
    // rest of the drag: a hand does not change its mind halfway, and asking
    // afresh on every mouse move made the creature stutter at the threshold.
    property string shoveSide: ""
    readonly property bool shoving: shoveSide !== ""
    // Hovering the peek lifts it, but not as a consequence of the shove that
    // just put it there — the pointer is still on it at that moment, and
    // lifting then reads as the creature bouncing back out. Armed again once
    // the pointer has left.
    property bool peekArmed: true
    // What the hand has actually done, in pixels. While a shove is under way
    // the creature moves by exactly this and not a pixel more: a creature
    // that outruns the hand pushing it feels cheap, however correct the
    // arithmetic. The rest of the distance is covered on release.
    property real handMoved: 0
    property real handDown: 0
    // Whether a hand is on the creature right now. A release that lands outside
    // the hitbox never reaches onReleased, and a plain flag would stay stuck on
    // — leaving the creature wearing its being-carried face long after it was
    // put down.
    readonly property bool holding: dragging && (pressedButtons & Qt.LeftButton)

    onPressed: function(mouse) {
      if (mouse.button !== Qt.LeftButton) { pet.petPressed(mouse.button); return }
      grabX = mouse.x + x
      grabY = mouse.y + y
      grabPx = pet.px
      dragging = false
      // Reaching for the creature ends a daydream at once: without this a
      // sparkle mid-glance would crossfade under the picked-up face.
      pet.glance = null
      pet.blinking = false
    }
    onPositionChanged: function(mouse) {
      if (!(pressedButtons & Qt.LeftButton)) return
      var moved = (mouse.x + x) - grabX
      var down = (mouse.y + y) - grabY
      if (!dragging && !Model.isDrag(moved) && !Model.isDrag(down)) return
      if (!dragging && pet.tucked) pet.wantsOut()
      dragging = true
      pet.activity = null
      pet.stopWalking()
      pet.px = Model.dragTo(grabPx, moved, pet.width, pet.petSize)
      // Shoved against a side, or pushed down into the floor it stands on.
      // It follows the hand while it happens, so you can see it working
      // instead of guessing where the line is.
      handMoved = moved
      handDown = down
      var shove = Model.shoveProgress(grabPx, grabX, grabY, moved, down,
                                      pet.width, pet.height, pet.petSize, shoveSide)
      if (pet.tucked) { shoveSide = ""; pushedTo = "" }
      else {
        if (shoveSide === "" && shove.progress > 0) shoveSide = shove.side
        if (shoveSide !== "") pet.tuckSide = shoveSide
        pet.tuckAmount = shove.progress
        pushedTo = shove.progress >= 1 ? shoveSide : ""
      }
    }
    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      if (dragging) {
        // Shoved past the side it stands against: that is a request to be
        // put away there, not a drag that overshot.
        if (pushedTo !== "") pet.pushedAside(pushedTo)
        else pet.draggedTo(pet.px)
      } else {
        pet.petPressed(Qt.LeftButton)
      }
      // Not far enough to mean it: it springs back to standing, eased,
      // which is why the shove flag drops before the value does.
      if (pushedTo !== "") peekArmed = false
      shoveSide = ""
      handMoved = 0
      handDown = 0
      if (!pet.tucked) pet.tuckAmount = 0
      dragging = false
      pushedTo = ""
    }
    onCanceled: dragging = false
    onEntered: tooltipDelay.restart()
    onExited: { tooltipDelay.stop(); tooltipDelay.done = false; peekArmed = true }
  }
  Timer { id: tooltipDelay; interval: 600; property bool done: false; onTriggered: done = true }
}
