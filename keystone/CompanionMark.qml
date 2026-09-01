import QtQuick
import "Bloub.js" as Bloub

// The creature, as the bar's icon.
//
// Not a shrunken copy of the desktop body: that one animates, and a bar icon
// that drifts and blinks beside a row of still glyphs is a distraction rather
// than a companion. This holds one pose and repaints only when something it
// draws actually changes.
//
// What it does keep is the identity — the silhouette is whichever shape the
// person chose, so the mark in the bar and the creature on the desktop are
// recognisably the same thing. The face follows the mood where the mood has a
// face for it; the state a mood animates to does not, because half of those
// are a dot or an exclamation mark and neither is legible at seventeen pixels.
Canvas {
  id: mark

  /** Diameter of the body, in pixels. This is INK, not an em box. */
  property int size: 17
  property string shapeId: Bloub.DEFAULT_SHAPE
  property string expressionId: Bloub.DEFAULT_EXPRESSION
  property string mood: "idle"
  /** The bar's own foreground, so the mark themes with every glyph beside it. */
  property color ink: "#ffffff"

  readonly property string shownExpression:
    Bloub.expressionForMood(mood, expressionId)

  // A little room for the outline's own antialiasing, and for a shape whose
  // radius runs past 1 — the squircle's diagonal does.
  readonly property real pad: Math.ceil(size * 0.12)
  implicitWidth: size + pad * 2
  implicitHeight: size + pad * 2

  renderTarget: Canvas.Image
  antialiasing: true

  /**
   * One fixed instant, not a clock.
   *
   * The engine's resting life is a pure function of time, so any date gives a
   * valid frame; this one is chosen because it falls between blinks. Sampling
   * live would mean a timer per bar, per monitor, to animate something the eye
   * should slide over.
   */
  readonly property real pose: 1.0

  function repaintMark() { requestPaint() }
  onSizeChanged: repaintMark()
  onShapeIdChanged: repaintMark()
  onShownExpressionChanged: repaintMark()
  onInkChanged: repaintMark()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)
    ctx.save()
    ctx.translate(width / 2, height / 2)
    var engine = Bloub.createEngine(size / 2, "idle",
                                    Bloub.shapeId(shapeId), shownExpression)
    // Facing front, which the creature on the desktop only does when it looks
    // up at you. At eleven pixels the resting gaze — up and to the right — puts
    // both eyes against the edge of the body, where the outer one is
    // foreshortened to about two thirds and the pair stops reading as a face at
    // all. Turned to the front they are level, equal, and unmistakable.
    //
    // Set well before the sampled instant so the engine's catch-up has finished
    // by then: this is one frozen frame, not an animation arriving.
    engine.setLook(Bloub.lookAt(0, 0, 1), 0)
    Bloub.paintMark(ctx, engine.sample(pose), String(ink))
    ctx.restore()
  }
}
