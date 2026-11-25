import SwiftUI
import UIKit
import UserNotifications

enum TimerAlarmSound {
    private static let retiredSoundFileNames = [
        "flowtime-chime.wav",
        "flowtime-pulse.wav",
        "flowtime-jet-lock.wav",
        "flowtime-rwr-lock.wav",
        "flowtime-tws-launch-2.wav",
        "flowtime-master-caution.wav"
    ]

    static func installIfNeeded() {
        guard let soundsURL else { return }
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: soundsURL, withIntermediateDirectories: true)
            for fileName in retiredSoundFileNames {
                let retiredURL = soundsURL.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: retiredURL.path) {
                    try fileManager.removeItem(at: retiredURL)
                }
            }

            for alert in TimerEndAlert.allCases {
                guard let fileName = alert.soundFileName else { continue }
                let soundURL = soundsURL.appendingPathComponent(fileName)
                guard !fileManager.fileExists(atPath: soundURL.path) else { continue }
                try makeWaveData(for: alert).write(to: soundURL, options: .atomic)
            }
        } catch {
            // iOS falls back to its default notification sound if a custom tone cannot be installed.
        }
    }

    static func fileURL(for alert: TimerEndAlert) -> URL? {
        guard let fileName = alert.soundFileName, let soundsURL else { return nil }
        installIfNeeded()
        let url = soundsURL.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static var soundsURL: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    private static func makeWaveData(for alert: TimerEndAlert) -> Data {
        let sampleRate: UInt32 = 22_050
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let duration = 28.5
        let sampleCount = Int(Double(sampleRate) * duration)
        var samples = Data(capacity: sampleCount * 2)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let value: Double

            switch alert {
            case .defaultSound:
                let cycle = time.truncatingRemainder(dividingBy: 0.8)
                let envelope = pulseEnvelope(cycle, start: 0, duration: 0.58)
                let frequency = cycle < 0.29 ? 880.0 : 740.0
                value = sin(2 * Double.pi * frequency * time) * 0.35 * envelope

            case .tws:
                let cycle = time.truncatingRemainder(dividingBy: 1.18)
                let first = pulseEnvelope(cycle, start: 0, duration: 0.085)
                let second = pulseEnvelope(cycle, start: 0.135, duration: 0.085)
                let third = pulseEnvelope(cycle, start: 0.31, duration: 0.12)
                let lowTone = sin(2 * Double.pi * 930 * time) * first
                let middleTone = sin(2 * Double.pi * 1_180 * time) * second
                let highTone = sin(2 * Double.pi * 1_460 * time) * third
                value = (lowTone + middleTone + highTone) * 0.36

            case .masterCaution:
                let cycle = time.truncatingRemainder(dividingBy: 2.15)
                let first = pulseEnvelope(cycle, start: 0, duration: 0.17)
                let second = pulseEnvelope(cycle, start: 0.25, duration: 0.17)
                let third = pulseEnvelope(cycle, start: 0.50, duration: 0.17)
                let fourth = pulseEnvelope(cycle, start: 0.75, duration: 0.20)
                let envelope = first + second + third + fourth
                let carrier = sin(2 * Double.pi * 740 * time)
                let harmonic = sin(2 * Double.pi * 1_480 * time)
                value = (carrier + 0.20 * harmonic) * 0.34 * envelope

            case .missileLaunch:
                let cycle = time.truncatingRemainder(dividingBy: 0.48)
                let sweep = cycle / 0.48
                let frequency = 1_350 + 950 * (1 - abs(2 * sweep - 1))
                let urgency = 0.72 + 0.28 * sin(2 * Double.pi * 16 * time)
                let carrier = sin(2 * Double.pi * frequency * time)
                let harmonic = sin(2 * Double.pi * frequency * 1.5 * time)
                value = (carrier + 0.18 * harmonic) * 0.32 * urgency

            case .rwr:
                let cycle = time.truncatingRemainder(dividingBy: 0.78)
                let first = pulseEnvelope(cycle, start: 0, duration: 0.19)
                let second = pulseEnvelope(cycle, start: 0.30, duration: 0.19)
                let activeEnvelope = first + second
                let frequency = 1_040 + 70 * sin(2 * Double.pi * 22 * time)
                let carrier = sin(2 * Double.pi * frequency * time)
                let harmonic = sin(2 * Double.pi * frequency * 2 * time)
                value = (carrier + 0.22 * harmonic) * 0.34 * activeEnvelope
            }

            let clamped = min(1, max(-1, value))
            appendLittleEndian(Int16(clamped * Double(Int16.max)), to: &samples)
        }

        let byteRate = sampleRate * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)
        var wave = Data()
        wave.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(UInt32(36 + samples.count), to: &wave)
        wave.append(contentsOf: "WAVE".utf8)
        wave.append(contentsOf: "fmt ".utf8)
        appendLittleEndian(UInt32(16), to: &wave)
        appendLittleEndian(UInt16(1), to: &wave)
        appendLittleEndian(channelCount, to: &wave)
        appendLittleEndian(sampleRate, to: &wave)
        appendLittleEndian(byteRate, to: &wave)
        appendLittleEndian(blockAlign, to: &wave)
        appendLittleEndian(bitsPerSample, to: &wave)
        wave.append(contentsOf: "data".utf8)
        appendLittleEndian(UInt32(samples.count), to: &wave)
        wave.append(samples)
        return wave
    }

    private static func pulseEnvelope(
        _ phase: Double,
        start: Double,
        duration: Double
    ) -> Double {
        let local = phase - start
        guard local >= 0, local < duration else { return 0 }
        let attack = min(1, local / 0.008)
        let release = min(1, (duration - local) / 0.018)
        return max(0, min(attack, release))
    }

    private static func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

final class FlowtimeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UserDefaults.standard.removeObject(forKey: "flowtime.language")
        TimerAlarmSound.installIfNeeded()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let timerCategory = UNNotificationCategory(
            identifier: TimerNotificationConstants.categoryIdentifier,
            actions: [],
            intentIdentifiers: []
        )
        center.setNotificationCategories([timerCategory])
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: TimerNotificationConstants.allRequestIdentifiers)
            center.removeDeliveredNotifications(withIdentifiers: TimerNotificationConstants.allRequestIdentifiers)
            UserDefaults.standard.set(true, forKey: TimerNotificationConstants.stopRequestStorageKey)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .flowtimeStopTimerAlarm, object: nil)
            }
        }
        completionHandler()
    }
}

@main
struct FlowtimeApp: App {
    @UIApplicationDelegateAdaptor(FlowtimeAppDelegate.self) private var appDelegate
    @StateObject private var store = FlowtimeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .tint(Color(red: 0.31, green: 0.49, blue: 0.95))
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.reconcileClocks() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .flowtimeStopTimerAlarm)) { _ in
                    store.stopTimerAlarm()
                }
        }
    }
}
