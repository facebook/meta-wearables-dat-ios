---
name: motion
description: Stream accelerometer, gyroscope, magnetometer, and orientation samples from connected wearables on iOS
---

# Motion (iOS)

Motion is an experimental capability for streaming inertial sensor samples. Enable it for the app in Wearables Developer Center. It has no runtime `Permission` value.

## Attach, observe, and start

Add Motion only after the `DeviceSession` reaches `.started`. Unlike Inputs, Motion is returned stopped: register observers before calling `start()`.

```swift
import MWDATCore
import MWDATMotion

let motion = try session.addMotion(
  configuration: MotionConfiguration(samplingRate: .hz30)
)
guard let motion else { return }

let samples = motion.samples
let sampleTask = Task {
  for await sample in samples {
    if let acceleration = sample.accelerometer {
      updateAcceleration(x: acceleration.x, y: acceleration.y, z: acceleration.z)
    }
    if let orientation = sample.orientation {
      updateOrientation(orientation.simd)
    }
  }
}
motion.start()
```

Retain the sample task while streaming. Observe `statePublisher` for lifecycle updates and `errorPublisher` for sensor, connection, and closure failures.

Sampling rates are 5, 10, 15, 24, 30, and 60 Hz; 10 Hz is the default. Higher rates use more bandwidth and power.

## Read samples defensively

`MotionSample.timestampNs` uses the device monotonic clock. Accelerometer values are m/s², gyroscope values are rad/s, and magnetometer values are µT. Accelerometer, gyroscope, magnetometer, and orientation are all optional, so use only values present in a sample. `source` distinguishes glasses, Neural Band, and unknown sources.

The sample stream buffers the newest 256 samples. Keep processing off the main actor when it is expensive.

## Stop and remove

`motion.stop()` pauses streaming and the same capability can be started again. Cancel the sample task before calling `session.removeMotion()`; removal is terminal.

## Test with MockDeviceKit

Configure deterministic replay before or during streaming with `glasses.services.motion.setMotionFeed(samples)` or a CSV file URL. Use `glasses.services.motion.isStreaming` only to assert mock behavior; app logic should observe the SDK Motion state.

## Availability

Motion is experimental. Apps can use it for development and beta testing, but cannot publish it to production release channels yet.
