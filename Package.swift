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
      name: "MWDATMockDevice",
      targets: ["MWDATMockDevice"]
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
      name: "MWDATMockDevice",
      path: "MWDATMockDevice.xcframework"
    ),
  ]
)
