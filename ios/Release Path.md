# Daily Widget iOS release path

This native SwiftUI app follows the same Apple distribution lane used for Lilo: **TestFlight first, then App Store review**. It does not use Expo/EAS because the app and WidgetKit extension are native Xcode targets.

## One-time Apple setup

1. Open `DailyWidget.xcodeproj` in Xcode.
2. Select the `DailyWidget` target and choose your Apple Developer Team.
3. Do the same for `DailyWidgetWidget`.
4. Confirm these bundle identifiers are available in your account:
   - `com.guanshiyang.dailywidget`
   - `com.guanshiyang.dailywidget.widget`
5. In **Signing & Capabilities**, enable the App Group in both targets:
   - `group.com.guanshiyang.dailywidget`

## Local device validation

1. Connect your iPhone, select it as the Xcode run destination, and run `DailyWidget`.
2. On the Home Screen, add the Daily Widget widget.
3. In the app, choose the same iCloud Drive `Daily Widget` folder selected in desktop settings.
4. Create, complete, move, resize, and cross a task over midnight; verify the widget reflects today after returning to the app.

## TestFlight build

1. Increment **Build** in Xcode before every upload. Both the app and widget use `CURRENT_PROJECT_VERSION`, so their build numbers stay aligned.
2. Select **Any iOS Device (arm64)**.
3. Choose **Product → Archive**.
4. In Organizer, choose **Distribute App → App Store Connect → Upload**.
5. In App Store Connect, open the Daily Widget app → **TestFlight**.
6. Add the build to an internal tester group first. Test iCloud folder sync and widget refresh on a physical phone.

## Command-line build check

```bash
xcodebuild \
  -project ios/DailyWidget.xcodeproj \
  -scheme DailyWidget \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/daily-widget-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

This verifies compilation. A TestFlight archive requires your selected Apple Developer Team and provisioning profile, so archive/upload should happen through Xcode unless signing automation is deliberately added later.
