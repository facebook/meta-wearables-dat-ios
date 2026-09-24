# Display Access App

A sample iOS application demonstrating integration with Meta Wearables Device Access Toolkit. This app showcases sending visual content to Meta Ray-Ban Display glasses using the DAT SDK Display module, with step-by-step tutorials rendered on the wearable display.

## Features

- Connect to Meta Ray-Ban Display glasses
- Send interactive display views to the glasses
- Navigate step-by-step tutorials on the wearable display
- Manage device registration and connection states
- Open firmware and glasses app update flows when required
- Preview the display experience and interactions on the phone
- Preview an iOS Simulator display session in the Chrome Web App Simulator

## Prerequisites

- iOS 17.2+
- Xcode 26.4+
- Swift 6.3+
- Meta Wearables Device Access Toolkit (included as a dependency)
- A Meta Ray-Ban Display glasses device for testing

The local-XCFramework project also supports developer testing with a simulated
display. On the Samples tab, open **Developer preview**, choose **In app**, and
tap **Preview in app**. The same Display session and click handlers render in
the app without physical glasses. Interact with the preview to advance the
sample.

To preview Display content on the phone, add `MWDATDisplay` and
`MWDATMockDevice`, then enable `MockDeviceKit`. Create the display with
`DeviceSession.addDisplay()`, just as you would for physical glasses.

For desktop developer testing, run the app in an iOS Simulator, open
**Developer preview**, choose **Chrome**, and tap **Start preview server**. Open
the displayed URL in Chrome and enable Meta Ray-Ban Display Simulator. Chrome preview
is not available on a physical iPhone.

## Building the app

- Before running on a device, select your Apple development team and use your own bundle identifier. Developer Mode needs no credentials; for other release channels, set `META_APP_ID` and `CLIENT_TOKEN` using credentials from Wearables Developer Center.

### Using Xcode

1. Clone this repository
1. Open the project in Xcode
1. Select your target device
1. Click the "Build" button or press `Cmd+B` to build the project
1. To run the app, click the "Run" button (▶️) or press `Cmd+R`

## Running the app

1. Turn 'Developer Mode' on in the Meta AI app.
1. Launch the app.
1. Press the "Register" button to complete app registration.
1. Once connected, tap "Try it" on the "Car maintenance guide" sample to send display content to the glasses.
1. The content should be displayed on the glasses.
1. If a firmware update is required, tap "Update firmware" in Settings.
1. If session start reports that the app on the glasses is outdated, the app opens Settings so you can tap "Update app on glasses".

## Troubleshooting

For issues related to the Meta Wearables Device Access Toolkit, please refer to the [developer documentation](https://wearables.developer.meta.com/docs/develop/) or visit our [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions)

## License

This source code is licensed under the license found in the LICENSE file in the root directory of this source tree.
