import QtQuick
import QtQuick.Effects

// Fixed materialize effect shared by the application grid and the panels that
// open above the dock. It deliberately ignores the dock's animMode/animSpeed:
// sub-panels always sharpen from a blur, never inherit slide/bounce/zoom.
MultiEffect {
  id: effect

  property bool shown: false
  property int duration: 180

  blurEnabled: true
  blurMax: 32
  blur: 0.6

  // An explicit NumberAnimation is used instead of `Behavior on blur`: a
  // MultiEffect used as layer.effect only repaints reliably with an explicit
  // target/property animation, while a Behavior can leave the first frame sharp.
  NumberAnimation {
    target: effect
    property: "blur"
    from: 0.6
    to: 0
    duration: effect.duration
    easing.type: Easing.OutCubic
    running: effect.shown
  }
}
