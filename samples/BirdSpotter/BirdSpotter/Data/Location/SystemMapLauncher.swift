/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SystemMapLauncher.swift
//  birdspotter
//

// patternlint-disable-next-line maps-infra-no-third-party-map-sdks
import MapKit

/// The ``MapLauncher`` the app ships: `MKMapItem.openInMaps`, which opens Apple Maps on the point.
///
/// The mirror is ``MapLauncher``, not this class — the `MKMapItem` is precisely the platform
/// plumbing the architecture note keeps idiomatic.
///
/// The item is named with the pin's title so Apple Maps labels the drop the same word the in-app
/// map does, and centred with a span close to the in-app map's neighbourhood zoom so the hand-off
/// doesn't jump scale.
@MainActor
struct SystemMapLauncher: MapLauncher {

  func open(_ location: SightingLocation) {
    let center = CLLocationCoordinate2D(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude
    )
    let item = MKMapItem(placemark: MKPlacemark(coordinate: center))
    item.name = location.title
    item.openInMaps(launchOptions: [
      MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: center),
      MKLaunchOptionsMapSpanKey: NSValue(
        mkCoordinateSpan: MKCoordinateSpan(
          latitudeDelta: 0.02,
          longitudeDelta: 0.02
        )),
    ])
  }
}
