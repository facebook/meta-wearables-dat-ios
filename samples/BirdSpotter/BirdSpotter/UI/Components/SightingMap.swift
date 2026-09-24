/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SightingMap.swift
//  birdspotter
//

// patternlint-disable-next-line maps-infra-no-third-party-map-sdks
import MapKit
import SwiftUI

/// How close the map sits to its pin, named by what you'd see rather than by a raw zoom number.
///
/// The unit is the divergence: MapKit frames by a span in metres, Google counts zoom in
/// power-of-two steps, so a shared number would mean two different framings. The role —
/// `neighborhood`, `city`, `region` — is what both platforms agree on; each maps it to its own
/// engine's number.
enum SightingMapZoom {
  case neighborhood
  case city
  case region

  /// The edge of the framed square, in metres — what `MKCoordinateRegion` wants.
  var spanMeters: CLLocationDistance {
    switch self {
    case .neighborhood: 1_500
    case .city: 9_000
    case .region: 60_000
    }
  }
}

/// A sighting's location as a small map with one pin.
///
/// Non-interactive by default: the map takes no gestures, so it sits inside the sighting page's
/// scroll without fighting it for drags, and a tap calls `onTap` — which the page routes to the
/// platform maps app — rather than panning. Pass `interactive` only when a screen genuinely wants
/// pan and zoom in place.
///
/// The tiles are pulled toward one quiet look. MapKit exposes no palette control, so the
/// styling is everything `mapStyle` does offer: muted emphasis, no POI badges, no traffic.
/// Tiles can only be nudged, though, where the marker is drawn outright — so the brand rides
/// ``SightingPin``, not the cartography.
///
/// The parameter list is the mirrored surface; the engine and its gesture plumbing are the
/// platform detail the architecture note keeps idiomatic.
struct SightingMap: View {
  let location: SightingLocation
  var interactive: Bool = false
  var zoom: SightingMapZoom = .neighborhood
  var onTap: (() -> Void)?

  var body: some View {
    Map(initialPosition: .region(region), interactionModes: interactive ? .all : []) {
      Annotation(location.title, coordinate: coordinate, anchor: .bottom) {
        SightingPin()
      }
      // The name would render as a caption under the pin, and the screen already states
      // the place in text.
      .annotationTitles(.hidden)
    }
    // The whole of MapKit's styling surface: tone the cartography down and clear the POI
    // badges, so the one brass pin is the only mark on the plate. Traffic is off by default.
    .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
    .overlay {
      // A tap on the static map hands off rather than panning — but only when it isn't
      // already a live map the user is meant to drag.
      if !interactive, let onTap {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture(perform: onTap)
      }
    }
  }

  private var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude
    )
  }

  private var region: MKCoordinateRegion {
    MKCoordinateRegion(
      center: coordinate,
      latitudinalMeters: zoom.spanMeters,
      longitudinalMeters: zoom.spanMeters
    )
  }
}

/// The pin's drawing, in numbers `SightingPin` on both platforms copies exactly. Not spacing:
/// these are the strokes of one drawing, and no more come from `theme.space` than the glyphs'
/// paths do.
private enum SightingPinMetrics {
  static let badgeDiameter: CGFloat = 34
  static let ringWidth: CGFloat = 2
  static let glyphSize: CGFloat = 18
  static let tailWidth: CGFloat = 12
  static let tailHeight: CGFloat = 7
  /// How far the tail tucks up under the badge, so the join can never open into a seam.
  static let tailOverlap: CGFloat = 3
}

/// The sighting marker both platforms draw stroke for stroke: the swallow on a brass badge,
/// ringed in raised paper, over a short tail that puts a point on the coordinate.
///
/// The badge is `gilt` because the pin is the map's one accent — the palette's own rule — and the
/// palette already keeps gilt legible on its mode's ground, so the same tokens carry both schemes:
/// brass reads dark on the light map and light on the dark one. The stock markers were the loudest
/// mismatch between the two apps (Apple's balloon against Google's teardrop); this replaces both.
private struct SightingPin: View {
  @Environment(\.theme) private var theme

  var body: some View {
    ZStack(alignment: .top) {
      // The tail first, so it sits behind the badge; its tip is the annotation's anchor.
      SightingPinTail()
        .fill(theme.colors.gilt)
        .frame(
          width: SightingPinMetrics.tailWidth,
          height: SightingPinMetrics.tailHeight + SightingPinMetrics.tailOverlap
        )
        .offset(y: SightingPinMetrics.badgeDiameter - SightingPinMetrics.tailOverlap)
      Circle()
        .fill(theme.colors.gilt)
        .overlay {
          Circle().strokeBorder(
            theme.colors.paperRaised,
            lineWidth: SightingPinMetrics.ringWidth
          )
        }
        .overlay {
          Image(glyph: theme.glyphs.identify)
            .resizable()
            .scaledToFit()
            .frame(
              width: SightingPinMetrics.glyphSize,
              height: SightingPinMetrics.glyphSize
            )
            .foregroundStyle(theme.colors.ink)
        }
        .frame(
          width: SightingPinMetrics.badgeDiameter,
          height: SightingPinMetrics.badgeDiameter
        )
    }
    .frame(
      width: SightingPinMetrics.badgeDiameter,
      height: SightingPinMetrics.badgeDiameter + SightingPinMetrics.tailHeight,
      alignment: .top
    )
  }
}

/// An isosceles triangle pointing down — the tail under the badge.
private struct SightingPinTail: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

#Preview {
  SightingMap(
    location: SightingLocation(
      coordinate: Coordinate(latitude: 39.1031, longitude: -84.5120),
      title: "American Robin",
      subtitle: "Eden Park"
    )
  )
  .frame(height: 180)
  .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
  .padding()
  .birdSpotterTheme()
}
