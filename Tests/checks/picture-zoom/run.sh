#!/bin/bash
# PictureZoom (iOSClient/PictureZoom.swift) on its own: the device's own zoom of the picture, a pinch
# about the point between the fingers, the move, the hold that keeps the pane covered, the spring
# back, the double tap, and the one map the display view and the overlay both draw with.
#   Tests/checks/picture-zoom/run.sh             compile and run the check
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O iOSClient/PictureZoom.swift "$here/main.swift" -o "$out/check"
"$out/check"
