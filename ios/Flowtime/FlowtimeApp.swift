import SwiftUI
import UIKit
import UserNotifications

enum TimerAlarmSound {
    static func installIfNeeded() {
        guard let soundsURL else { return }
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: soundsURL, withIntermediateDirectories: true)
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

            case .chime:
                let cycle = time.truncatingRemainder(dividingBy: 2.4)
                let frequencies = [659.25, 783.99, 987.77]
                let noteIndex = min(2, Int(cycle / 0.45))
                let noteTime = cycle - Double(noteIndex) * 0.45
                let isActive = cycle < 1.35 && noteTime < 0.4
                let attack = min(1, noteTime / 0.012)
                let envelope = isActive ? attack * exp(-5.5 * noteTime) : 0
                let frequency = frequencies[noteIndex]
                value = (
                    sin(2 * Double.pi * frequency * time)
                    + 0.28 * sin(2 * Double.pi * frequency * 2 * time)
                ) * 0.28 * envelope

            case .pulse:
                let cycle = time.truncatingRemainder(dividingBy: 1.0)
                let first = pulseEnvelope(cycle, start: 0, duration: 0.16)
                let second = pulseEnvelope(cycle, start: 0.28, duration: 0.16)
                let firstTone = sin(2 * Double.pi * 540 * time) * first
                let secondTone = sin(2 * Double.pi * 760 * time) * second
                value = (firstTone + secondTone) * 0.36

            case .jetLock:
                let cycle = time.truncatingRemainder(dividingBy: 0.68)
                let first = pulseEnvelope(cycle, start: 0, duration: 0.12)
                let second = pulseEnvelope(cycle, start: 0.20, duration: 0.12)
                let localTime = cycle < 0.20 ? cycle : cycle - 0.20
                let sweep = min(1, max(0, localTime / 0.12))
                let frequency = 1_250 + 520 * sweep + 45 * sin(2 * Double.pi * 24 * time)
                let carrier = sin(2 * Double.pi * frequency * time)
                let harmonic = sin(2 * Double.pi * frequency * 2 * time)
                value = (carrier + 0.2 * harmonic) * 0.33 * (first + second)

            case .silent:
                value = 0
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
