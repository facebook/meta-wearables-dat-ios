# Camera Access App

A sample iOS application demonstrating integration with Meta Wearables Device Access Toolkit. This app walks the SDK's camera lifecycle as explicit steps — start a session, start the preview, capture or record, stop the preview, end the session — on a single full-bleed camera screen.

## Features

- Connect to Meta AI glasses
- Explicit camera lifecycle: start/end a device session and start/stop the live preview
- Stream the camera feed from the device
- Capture photos
- Record video, with optional sound-in-video captured from the glasses' microphone
- Backgrounding the app ends the active preview session and returns the sample to a clean idle state
- Preview and share captured photos and recorded videos
- Open the firmware update flow when required

## Prerequisites

- iOS 17.2+
- Xcode 26.4+
- Swift 6.3+
- Meta Wearables Device Access Toolkit (included as a dependency)
- A Meta AI glasses device for testing (optional for development)

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
1. Press the "Connect" button to complete app registration.
1. Tap "Start Session" to connect to your glasses, then "Preview" to begin the live camera feed.
1. Use the on-screen controls to:
   - Capture photos
   - Record video, toggling the glasses' microphone for sound-in-video
   - Preview and share captured photos and recorded videos
   - Stop the preview, end the session, or disconnect from the device
1. If the app backgrounds while previewing or recording, CameraAccess ends the active session; when you return, start again from "Start Session".
1. If a firmware update is required, tap "Update firmware".
1. If session start reports that the app on the glasses is outdated, tap "Update app on glasses".

## Troubleshooting

For issues related to the Meta Wearables Device Access Toolkit, please refer to the [developer documentation](https://wearables.developer.meta.com/docs/develop/) or visit our [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions)

## License

This source code is licensed under the license found in the LICENSE file in the root directory of this source tree.
