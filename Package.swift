// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MetaWearablesDAT",
  products: [
    .library(
      name: "MWDATCamera",
      targets: ["MWDATCamera"]
    ),
    .library(
      name: "MWDATCore",
      targets: ["MWDATCore"]
    ),
    .library(
      name: "MWDATDisplay",
      targets: ["MWDATDisplay"]
    ),
    .library(
      name: "MWDATInputs",
      targets: ["MWDATInputs"]
    ),
    .library(
      name: "MWDATMockDevice",
      targets: ["MWDATMockDevice"]
    ),
    .library(
      name: "MWDATMockDeviceTestClient",
      targets: ["MWDATMockDeviceTestClient"]
    ),
    .library(
      name: "MWDATMotion",
      targets: ["MWDATMotion"]
    ),
    .library(
      name: "MWDATSpeech",
      targets: ["MWDATSpeech"]
    ),
  ],
  targets: [
    .binaryTarget(
      name: "MWDATCamera",
      path: "MWDATCamera.xcframework"
    ),
    .binaryTarget(
      name: "MWDATCore",
      path: "MWDATCore.xcframework"
    ),
    .binaryTarget(
      name: "MWDATDisplay",
      path: "MWDATDisplay.xcframework"
    ),
    .binaryTarget(
      name: "MWDATInputs",
      path: "MWDATInputs.xcframework"
    ),
    .binaryTarget(
      name: "MWDATMockDevice",
      path: "MWDATMockDevice.xcframework"
    ),
    .binaryTarget(
      name: "MWDATMockDeviceTestClient",
      path: "MWDATMockDeviceTestClient.xcframework"
    ),
    .binaryTarget(
      name: "MWDATMotion",
      path: "MWDATMotion.xcframework"
    ),
    .binaryTarget(
      name: "MWDATSpeech",
      path: "MWDATSpeech.xcframework"
    ),
  ]
)
