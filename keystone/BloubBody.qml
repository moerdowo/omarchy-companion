import QtQuick
import "Bloub.js" as Bloub
import "Model.js" as Model

// The bloub character, drawn rather than blitted.
//
// Omarchief's other companions are spritesheets: a grid of drawings, one cell
// shown at a time. This one has no artwork at all. It is a filled shape whose
// outline is computed every frame from a radial profile, with two capsule eyes
// cut out of it — so its shape, its colour and its expression are settings
// rather than pixels, and changing any of them MORPHS instead of cutting,
// which no sheet of drawings can do.
//
// Everything with a number in it lives in Bloub.js. This file is the part that
// a canvas needs and a pure engine must not have: a clock, the desktop's
// palette, and the translation from Omarchief's moods to the bot's states.
Canvas {
  id: canvas

  /** The ball's diameter at rest. The canvas is larger; see `overflow`. */
  property int petSize: 56
  property string mood: "idle"
  property string shapeId: Bloub.DEFAULT_SHAPE
  property string colorId: Bloub.DEFAULT_COLOR
  property string expressionId: Bloub.DEFAULT_EXPRESSION
  /** The accent `theme` resolves to, and the ground the eyes show. */
  property color accent: "#ffffff"
  property color paper: "#000000"
  // The engine reads colours as hex strings and blends two of them by hand for
  // the burst particles' depth haze. A QML colour prints its alpha when it has
  // one — `#ff1a1b26`, eight digits — which that blend would read as a
  // different colour entirely. Drop the alpha here, where the type is still a
  // colour, rather than parsing around it there.
  readonly property string accentHex: Qt.rgba(accent.r, accent.g, accent.b, 1).toString()
  readonly property string paperHex: Qt.rgba(paper.r, paper.g, paper.b, 1).toString()
  property bool reduceMotion: false
  /** Whether a resting creature changes its expression on its own. */
  property bool expressions: true
  property real glanceChance: 0.25
  /** Window visible and creature on stage; gates the clock. */
  property bool active: true
  property bool dragging: false
  /**
   * The standby performance being played, or null: an activity track from the
   * same machinery the spritesheet pets use. The renderer owns when it ENDS,
   * because a drawn performance has no last frame to run out of.
   */
  property var activity: null
  signal performanceFinished()
  /** Pointer offset from the centre, each -1 to 1, or tracking off. */
  property bool pointer: false
  property real pointerX: 0
  property real pointerY: 0

  // The orbits and the comet's ribbons reach past the creature, so the canvas
  // is wider than it on every side and it is the parent's job not to clip it.
  // Chief.qml lowers the ground line by the same amount.
  readonly property real overflow: petSize * Bloub.OVERFLOW
  readonly property real ballRadius: petSize / 2

  anchors.fill: parent
  anchors.margins: -overflow
  renderTarget: Canvas.Image
  antialiasing: true

  /**
   * The mood the creature is actually showing.
   *
   * Being carried outranks everything else: it is the one state the person is
   * causing directly, and answering a drag with last turn's result reads as the
   * creature ignoring them.
   */
  readonly property string shownMood: dragging ? "dragged" : mood
  readonly property string activityName: activity ? String(activity.name || "") : ""

  /**
   * Being carried outranks a performance, which outranks the mood.
   *
   * A performance is only ever offered while the mood is calm, and anything
   * with news to deliver cancels one — so by the time these can disagree, the
   * only thing above a performance is a hand.
   */
  readonly property string shownState: {
    if (dragging) return Bloub.stateForMood("dragged")
    if (activityName !== "") return Bloub.performanceState(activityName)
    return Bloub.stateForMood(mood)
  }

  /**
   * The expression on the resting face: what a mood imposes, else the glance it
   * is wearing on its own, else the chosen one.
   *
   * A mood wins over a glance because a glance is only ever offered while the
   * creature is calm, so a mood arriving mid-glance is news and the glance is
   * not. States that draw their own eyes ignore this entirely.
   */
  readonly property string shownExpression:
    Bloub.expressionForMood(shownMood, glance !== "" ? glance : expressionId)

  /** An expression borrowed for a few seconds while resting. */
  property string glance: ""

  // ---------------------------------------------------------------- clock
  //
  // The engine is a pure function of time, so this is the only clock in the
  // character and nothing else keeps state about where an animation is. Seconds
  // since the component was created, which is what every duration in Bloub.js
  // is expressed in.
  property real epoch: Date.now() / 1000
  property real now: 0

  readonly property bool animating: active && !reduceMotion

  property var engine: null

  Component.onCompleted: {
    engine = Bloub.createEngine(ballRadius, shownState,
                                Bloub.shapeId(shapeId), shownExpression)
    // Reduced motion still gets a picture, just never a moving one: the moment
    // in each state where it reads best, which is the frame bloub's own
    // previews show.
    now = reduceMotion ? Bloub.restingMoment(shownState) : 0
    requestPaint()
  }

  Timer {
    // 30 fps. The creature is small and the outline is 64 points, so this costs
    // little; what it buys is the drift and the blinking, which is the whole of
    // the resting life.
    interval: 33
    repeat: true
    running: canvas.animating && canvas.engine !== null
    onTriggered: {
      canvas.now = Date.now() / 1000 - canvas.epoch
      canvas.driveLook()
      canvas.requestPaint()
    }
  }

  // A creature that has been away comes back where it left off rather than
  // where the wall clock says: the alternative is a jump on every unhide.
  onActiveChanged: if (active) epoch = Date.now() / 1000 - now

  onReduceMotionChanged: {
    if (engine) {
      if (reduceMotion) {
        // Moving `now` back to the resting moment is not enough on its own:
        // the engine measures a state from when that state STARTED, so a
        // creature that has been resting for eight minutes would be asked for
        // a negative local time and show the state's opening frame instead.
        // Restarting it puts the two clocks back in step.
        engine.reset(shownState, 0)
        engine.setLook(null, 0)
        now = Bloub.restingMoment(shownState)
      } else epoch = Date.now() / 1000 - now
    }
    requestPaint()
  }

  // ------------------------------------------------------------- settings
  //
  // Each of these is a dated setter on the engine, never a variable read during
  // a sample: that is what keeps `sample(t)` a pure function of time, and with
  // it the promise that the same date always draws the same picture.

  /**
   * The date to hand a setter so that its morph is already over.
   *
   * With reduced motion the clock does not advance, so a morph started at `now`
   * would be frozen partway through it forever — a shape stuck between a circle
   * and a triangle. Backdating it past the longest morph lands on the value
   * that was asked for, which is what "no motion" should mean.
   */
  function settleAt() { return reduceMotion ? now - 10 : now }

  onShownStateChanged: {
    if (!engine) return
    if (reduceMotion) {
      // A state is an animation, not a value, so it cannot be backdated into
      // place: at t = 10 `alert` has long since finished and `orbit` is still
      // spinning. It is restarted instead, on the moment it reads best frozen.
      engine.reset(shownState, 0)
      now = Bloub.restingMoment(shownState)
    } else engine.setState(shownState, now)
    requestPaint()
  }
  onShapeIdChanged: if (engine) { engine.setShape(Bloub.shapeId(shapeId), settleAt()); requestPaint() }
  onShownExpressionChanged: if (engine) { engine.setExpression(shownExpression, settleAt()); requestPaint() }
  onPetSizeChanged: {
    // The engine holds its scale, so a change of size is a new engine — rebuilt
    // on the state it was already showing rather than reset to resting.
    //
    // A new engine starts its current state at zero, and `now` is not zero, so
    // it is told where the clock has got to. Without that, resizing while an
    // error was on screen would show the end of that run rather than the run.
    if (!engine) return
    var next = Bloub.createEngine(ballRadius, shownState,
                                  Bloub.shapeId(shapeId), shownExpression)
    next.reset(shownState, reduceMotion ? now - Bloub.restingMoment(shownState) : now)
    engine = next
    requestPaint()
  }
  onColorIdChanged: requestPaint()
  onAccentHexChanged: requestPaint()
  onPaperHexChanged: requestPaint()

  // --------------------------------------------------------------- pointer
  //
  // The eyes follow the pointer while it is over the creature. `mix` is ramped
  // by the engine's own catch-up rather than by an animation here, so the gaze
  // never quite reaches a cursor that is still moving — which is what makes it
  // read as looking rather than as being pinned.
  onPointerXChanged: aim()
  onPointerYChanged: aim()
  onPointerChanged: aim()

  function aim() {
    if (!engine || reduceMotion) return
    if (pointer) { engine.setLook(Bloub.lookAt(pointerX, pointerY, 1), now); driving = false }
    // A pointer leaving does not hand the gaze straight back to the pose: a
    // script may still want it, and `driveLook` is what decides.
    else driveLook()
    requestPaint()
  }

  /** Whether a script currently holds the gaze, so it is released exactly once. */
  property bool driving: false

  /**
   * The scripted gaze, evaluated each frame.
   *
   * A real pointer outranks every script: the creature should look at the
   * person rather than through them at where the script says.
   */
  function driveLook() {
    if (!engine || reduceMotion || pointer) return
    if (activityName === "notice") {
      engine.setLook(Bloub.noticeLook(now - activityAt,
                                      Bloub.performanceSeconds(activityName),
                                      Bloub.shapeId(shapeId) === "cercle"), now, 0.05)
      driving = true
      return
    }
    if (shownMood === "working") {
      engine.setLook(Bloub.ponderLook(now), now)
      driving = true
      return
    }
    // Nothing wants it any more. Handing it back every frame would restart the
    // catch-up every frame and the eyes would never quite arrive.
    if (driving) { engine.setLook(null, now); driving = false }
  }

  // ---------------------------------------------------------- performances
  //
  // A spritesheet performance ends when its row runs out of frames. A drawn one
  // has no frames, so its length is declared and this is what enforces it; the
  // service is told the same way the sprite viewport tells it.
  property real activityAt: 0

  onActivityNameChanged: {
    activityAt = now
    performanceEnd.stop()
    if (activityName !== "") {
      performanceEnd.interval = Math.max(400,
        Math.round(Bloub.performanceSeconds(activityName) * 1000))
      performanceEnd.restart()
    } else if (engine && !reduceMotion) engine.setLook(null, now)
    requestPaint()
  }

  Timer { id: performanceEnd; onTriggered: canvas.performanceFinished() }

  // --------------------------------------------------------------- glances
  //
  // The same offer-and-hold cadence the sprite pets use, so a person who
  // changes companion does not also change how lively their desktop is.
  Timer {
    id: glanceOffer
    interval: 7000
    repeat: true
    running: canvas.active && canvas.expressions && !canvas.reduceMotion
    onTriggered: {
      glanceOffer.interval = 7000 + Math.round(Math.random() * 8000)
      if (canvas.glance !== "" || canvas.dragging) return
      // Only while nothing is happening: an expression borrowed for fun while
      // an agent is working would be read as news about the agent.
      if (canvas.mood !== "idle" && canvas.mood !== "parked") return
      if (canvas.glanceChance <= 0 || Math.random() > canvas.glanceChance) return
      canvas.glance = Bloub.idleExpression(Math.random, Bloub.expressionId(canvas.expressionId))
      glanceBack.interval = Model.glanceMs(Math.random)
      glanceBack.restart()
    }
  }
  Timer { id: glanceBack; onTriggered: canvas.glance = "" }
  onExpressionsChanged: if (!expressions) glance = ""
  onMoodChanged: if (mood !== "idle" && mood !== "parked") glance = ""

  // ----------------------------------------------------------------- paint
  onPaint: {
    if (!engine) return
    var ctx = getContext("2d")
    ctx.reset()
    // `reset` returns the drawing STATE to its defaults; what is already on the
    // canvas is not part of that state. Without this the previous frame stays
    // under this one and the creature smears as it moves.
    ctx.clearRect(0, 0, width, height)
    ctx.save()
    // The engine works in a frame centred on the creature; the canvas does not.
    ctx.translate(width / 2, height / 2)
    Bloub.paint(ctx, engine.sample(now),
                Bloub.inkFor(colorId, accentHex), paperHex)
    ctx.restore()
  }
}
