# BirdSpotter — Meta Wearables Device Access Toolkit Sample

A native SwiftUI sample app that showcases the Meta Wearables Device Access Toolkit
across a realistic app. BirdSpotter is a bird-spotting field guide extended to Meta AI
glasses: capture a bird, listen for its song, use motion data to distinguish canopy from
ground scanning, ask about it by voice, and show results on supported glasses displays.

BirdSpotter also runs against a simulated device through MockDeviceKit, so its wearable
flows can be exercised without physical glasses.

> Bird identification is intentionally simulated. The sample demonstrates device
> capabilities and application structure rather than computer vision or ornithology.

## Capabilities demonstrated

- Camera photo capture and video streaming
- Motion-based head orientation
- Device input events
- On-device speech recognition
- Display content on supported glasses
- MockDeviceKit development and testing

Some capabilities require an eligible SDK release channel. See the
[developer documentation](https://wearables.developer.meta.com/docs/develop/dat/) for
current availability.

## Prerequisites

- macOS with Xcode 16 or newer
- iOS 18 or newer
- A Meta AI glasses device is optional

## Setup

1. Open `BirdSpotter.xcodeproj` in Xcode.
2. Allow Swift Package Manager to resolve the Wearables Device Access Toolkit and GRDB.
3. Select the `birdspotter` target and choose your development team.
4. If necessary, change `com.meta.pixelandtexel.birdspotter` to a bundle identifier registered
   to your team.
5. Select the `birdspotter` scheme and run the app.

The `birdspotter://` callback scheme does not need to change with the bundle identifier.

## Building from the command line

```bash
xcodebuild build \
  -project BirdSpotter.xcodeproj \
  -scheme birdspotter \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

## Bird catalog

The field guide is committed as static data under `SeedData/`. It contains `catalog.db`,
the `birds/` media tree, and the Demo Director preset under `presets/`. No catalog
generation step is required to build the sample.

## Project structure

- `BirdSpotter/`: app source, asset catalogs, fonts, and shared UI
- `BirdSpotterTests/`: unit tests
- `BirdSpotterUITests/`: UI tests
- `SeedData/`: bundled catalog, media, and demo preset
- `licenses/`: attribution and third-party license texts

## Permissions

- Bluetooth: communicate with paired wearable devices
- Camera and microphone: phone-side capture fallbacks
- Location: attach a location to sightings

The app requests permissions when the corresponding feature is used.

## Meta AI glasses

Pair supported glasses in the Meta AI app and enable Developer Mode. In BirdSpotter,
open Settings and choose **Set up your glasses**. The app returns from registration through
the `birdspotter://` callback.

Only one Wearables Device Access Toolkit app can use a device at a time. Stop any other
active sample before starting a BirdSpotter session.

## Troubleshooting

For Wearables Device Access Toolkit issues, see the
[developer documentation](https://wearables.developer.meta.com/docs/develop/dat/) or visit
the [discussion forum](https://github.com/facebook/meta-wearables-dat-ios/discussions).

## License

See [LICENSE](LICENSE). Third-party content is credited in [NOTICE](NOTICE) and
[licenses/](licenses/).
