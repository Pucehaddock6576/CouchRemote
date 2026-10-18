// UIState.swift — state for the settings window.
// Kept in one shared object instead of SwiftUI's @State, because @State needs a compiler
// plugin that only ships with full Xcode, not the free Command Line Tools.
import Foundation
import Combine
import AppKit

final class UIState: ObservableObject {
    static let shared = UIState()

    @Published var pane: Pane? = .overview
    @Published var profileID: UUID?          // profile being edited on the Buttons screen
    @Published var profileSelection: UUID?   // profile selected on the App Profiles screen
    @Published var devices: [TouchDeviceInfo] = []
    @Published var stepsText = ""
    @Published var backupMessage = ""
    @Published var calibrating = false       // the tap/swipe calibration wizard is showing
    @Published var gestureMode: TouchMode = .remote   // which touch mode the per-mode gesture list is showing

    // Shortcut recorder: only one row records at a time
    @Published var recordingID: String?
    var keyMonitor: Any?

    func stopRecording() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        recordingID = nil
    }
}
