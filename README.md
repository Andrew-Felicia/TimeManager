# Flowtime for iPhone

Flowtime is a native SwiftUI iPhone app for tasks, calendar planning, focus timers, a stopwatch, and local focus analytics.

The app is standalone: tasks, events, settings, timer state, and completed focus sessions are stored locally on the device. No web server or Node.js runtime is required.

## Open and run

1. Open `ios/Flowtime.xcodeproj` in Xcode.
2. Select the `Flowtime` scheme and your iPhone.
3. In **Signing & Capabilities**, select your Apple development team if needed.
4. Press **Run**.

The project targets iOS 17 or newer. `ios/project.yml` can be used to regenerate the Xcode project with XcodeGen if necessary.
