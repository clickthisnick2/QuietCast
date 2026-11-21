//
//  QuietCastApp.swift
//  QuietCast
//
//  Created by mycomputer on 5/31/26.
//

import SwiftUI
import UIKit

@main
struct QuietCastApp: App {
    @UIApplicationDelegateAdaptor(QuietCastAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var previousBrightness: CGFloat?
    @State private var hasSetupAudioSession = false

    init() {
        // Recreate the background download session on every launch so a transfer
        // that finished while the app was gone can be moved into place.
        _ = DownloadManager.shared
        AppSettings.shared.connectPlaybackReactions()

        // Flush saves on app termination (not always called, but helps when it is)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            PersistenceManager.shared.flushToDisk()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(Color.warmAccent)
        }
        .onChange(of: scenePhase) { _, phase in
            guard
                let screen = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.screen
            else { return }

            switch phase {
            case .active:
                // Set up audio session once the window is available
                if !hasSetupAudioSession {
                    hasSetupAudioSession = true
                    AudioPlayer.shared.setupAudioSession()
                }

                // Re-enable volume lock if a scheduled re-enable time has passed
                AudioPlayer.shared.checkVolumeRangeReenableSchedule()

                // Only dim during nighttime hours (TimeGate.nightHoursText)
                if !TimeGate.searchAllowed() {
                    if previousBrightness == nil {
                        previousBrightness = screen.brightness
                    }
                    let dimmed = max(screen.brightness * 0.3, 0.05)
                    screen.brightness = dimmed
                }

                // Enforce system volume range on app open when the lock is on.
                // VolumeEnforcer applies the nighttime / always-on check itself.
                if AppSettings.shared.systemVolumeCapEnabled {
                    let enforcer = VolumeEnforcer.shared
                    enforcer.installVolumeView()
                    // Small delay to let the volume view attach
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        enforcer.enforceSystemVolumeCap()
                        enforcer.enforceSystemVolumeFloor()
                    }
                }
            case .inactive, .background:
                // Flush any pending saves before the app is suspended
                PersistenceManager.shared.flushToDisk()
                if let prev = previousBrightness {
                    screen.brightness = prev
                    previousBrightness = nil
                }
            @unknown default:
                break
            }
        }
    }
}

/// Receives background URLSession relaunch events for episode downloads.
final class QuietCastAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == "com.quietcast.downloads" else {
            completionHandler()
            return
        }
        // UIKit calls this on the main thread. The session has to exist
        // before we return or the system drops the events.
        MainActor.assumeIsolated {
            DownloadManager.connectBackgroundSession(completionHandler)
        }
    }
}

extension Color {
    /// Warm amber accent — dimmed for night use
    static let warmAccent = Color(red: 0.6, green: 0.45, blue: 0.22)
    /// Muted warm green for "downloaded" indicators
    static let warmGreen = Color(red: 0.35, green: 0.5, blue: 0.3)
    /// Dim warm tone for sleep timer
    static let warmDim = Color(red: 0.5, green: 0.38, blue: 0.24)
}
