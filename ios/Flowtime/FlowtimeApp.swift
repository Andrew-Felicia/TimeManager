import SwiftUI
import UIKit
import UserNotifications

enum TimerAlarmSound {
    static let fileName = "flowtime-alarm.wav"

    static func installIfNeeded() {
        let fileManager = FileManager.default
        guard let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let soundsURL = libraryURL.appendingPathComponent("Sounds", isDirectory: true)
        let soundURL = soundsURL.appendingPathComponent(fileName)
        guard !fileManager.fileExists(atPath: soundURL.path) else { return }

        do {
            try fileManager.createDirectory(at: soundsURL, withIntermediateDirectories: true)
            try makeAlarmWaveData().write(to: soundURL, options: .atomic)
        } catch {
            // iOS falls back to its default notification sound if this file cannot be installed.
        }
    }

    private static func makeAlarmWaveData() -> Data {
        let sampleRate: UInt32 = 22_050
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let duration = 29.0
        let sampleCount = Int(Double(sampleRate) * duration)
        var samples = Data(capacity: sampleCount * 2)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let pulse = time.truncatingRemainder(dividingBy: 0.8)
            let active = pulse < 0.58
            let edge = min(min(pulse / 0.015, (0.58 - pulse) / 0.015), 1)
            let envelope = active ? max(0, edge) : 0
            let frequency = pulse < 0.29 ? 880.0 : 740.0
            let sample = Int16(
                sin(2 * Double.pi * frequency * time) * Double(Int16.max) * 0.35 * envelope
            )
            appendLittleEndian(sample, to: &samples)
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
