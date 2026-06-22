import SwiftUI
import AVKit

/// The native AirPlay route picker, bridged into SwiftUI. Tapping it lists
/// AirPlay devices (Apple TV, AirPlay 2 TVs such as recent Sony Bravias, etc.);
/// selecting one mirrors the current `AVPlayer` to that device. Because the app
/// sends the stream to the TV, channels whose codec this Mac can't decode often
/// play there anyway — the TV does the decoding.
struct AirPlayRoutePicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        view.setAccessibilityIdentifier("player.airplay")
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
