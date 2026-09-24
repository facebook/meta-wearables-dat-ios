/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// CarMaintenanceDisplay.swift
//
// Display views for the Car Maintenance sample — step-by-step vehicle tutorials.
// Sends 3 screen types to the glasses: tutorial list, tutorial detail, and tutorial steps.
//

import MWDATDisplay
import UIKit

struct CarMaintenanceTutorial {
  let title: String
  let duration: String
  let image: Image?
  let icon: Image?
  let steps: [CarMaintenanceTutorialStep]
}

struct CarMaintenanceTutorialStep {
  let description: String
}

private let tutorialVideoUrl =
  "https://github.com/facebook/meta-wearables-dat-android/raw/refs/heads/assets/video_266x150_faststart.mp4"

enum CarMaintenanceDisplay {
  static let tutorials: [CarMaintenanceTutorial] = [
    CarMaintenanceTutorial(
      title: "Oil change",
      duration: "Easy • 45 min",
      image: Image(image: UIImage(resource: .oil), sizePreset: .fill, cornerRadius: .medium),
      icon: Image(image: UIImage(resource: .oilSquare), sizePreset: .fill, cornerRadius: .medium),
      steps: [
        CarMaintenanceTutorialStep(
          description: "Park on level ground and let the engine cool before opening the hood."
        ),
        CarMaintenanceTutorialStep(
          description: "Drain the old oil, replace the filter, and tighten the drain plug."
        ),
        CarMaintenanceTutorialStep(
          description: "Refill with fresh oil, run the engine briefly, and recheck the level."
        ),
      ]
    ),
    CarMaintenanceTutorial(
      title: "Fix a flat tire",
      duration: "Easy • 15 min",
      image: Image(
        uri: "https://www.facebook.com/assets/wearables_dat_display/tire.png",
        sizePreset: .fill,
        cornerRadius: .medium
      ),
      icon: Image(
        uri: "https://www.facebook.com/assets/wearables_dat_display/tire_square.png",
        sizePreset: .fill,
        cornerRadius: .medium
      ),
      steps: [
        CarMaintenanceTutorialStep(
          description: "Park away from traffic, engage the brake, and place the wheel wedges."
        ),
        CarMaintenanceTutorialStep(
          description: "Loosen the lug nuts slightly, raise the car, and remove the flat tire."
        ),
        CarMaintenanceTutorialStep(
          description: "Mount the spare, tighten in a star pattern, and lower the vehicle."
        ),
      ]
    ),
    CarMaintenanceTutorial(
      title: "Replace headlight bulb",
      duration: "Very easy • 5 min",
      image: Image(
        uri: "https://www.facebook.com/assets/wearables_dat_display/light.png",
        sizePreset: .fill,
        cornerRadius: .medium
      ),
      icon: Image(
        uri: "https://www.facebook.com/assets/wearables_dat_display/light_square.png",
        sizePreset: .fill,
        cornerRadius: .medium
      ),
      steps: [
        CarMaintenanceTutorialStep(
          description: "Open the rear access cover and disconnect the bulb connector."
        ),
        CarMaintenanceTutorialStep(
          description: "Release the retaining clip, remove the old bulb, and insert the new one."
        ),
        CarMaintenanceTutorialStep(
          description: "Reconnect power, close the cover, and verify the beam works properly."
        ),
      ]
    ),
    CarMaintenanceTutorial(
      title: "Check engine light",
      duration: "Hard • 2 hours",
      image: Image(
        uri: "https://www.facebook.com/assets/wearables_dat_display/engine.png",
        sizePreset: .fill,
        cornerRadius: .medium
      ),
      icon: Image(
        uri: "https://www.facebook.com/assets/wearables_dat_display/engine_square.png",
        sizePreset: .fill,
        cornerRadius: .medium
      ),
      steps: [
        CarMaintenanceTutorialStep(
          description: "Check whether the light is steady or flashing, and stop driving if it is flashing."
        ),
        CarMaintenanceTutorialStep(
          description: "Tighten the gas cap fully and look for obvious issues like low fluids or overheating."
        ),
        CarMaintenanceTutorialStep(
          description: "Scan for diagnostic codes or schedule service if the light stays on after restarting."
        ),
      ]
    ),
    CarMaintenanceTutorial(
      title: "Change washer fluid",
      duration: "Very easy • 3 min",
      image: Image(
        uri: "https://www.facebook.com/assets/wearables_dat_display/washer.png",
        sizePreset: .fill,
        cornerRadius: .medium
      ),
      icon: Image(
        uri: "https://www.facebook.com/assets/wearables_dat_display/washer_square.png",
        sizePreset: .fill,
        cornerRadius: .medium
      ),
      steps: [
        CarMaintenanceTutorialStep(
          description: "Open the hood and locate the washer fluid reservoir cap with the windshield symbol."
        ),
        CarMaintenanceTutorialStep(
          description: "Pour washer fluid into the reservoir carefully until it reaches the fill line."
        ),
        CarMaintenanceTutorialStep(
          description: "Close the cap securely and test the sprayers to confirm proper flow."
        ),
      ]
    ),
  ]

  /// Screen 1: List of car maintenance tutorials with difficulty and duration.
  static func tutorialList(
    onSelectTutorial: @escaping @Sendable (Int) -> Void
  ) -> FlexBox {
    FlexBox(direction: .column, spacing: 10) {
      for index in tutorials.indices {
        FlexBox(direction: .column) {
          FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
            if let icon = tutorials[index].icon {
              FlexBox(direction: .column) {
                icon
              }
              .flexGrow(1)
            }
            FlexBox(direction: .column) {
              Text(tutorials[index].title, style: .body)
              Text(tutorials[index].duration, style: .meta, color: .secondary)
            }
            .flexGrow(7)
          }
        }
        .padding(24)
        .background(.card)
        .onTap { onSelectTutorial(index) }
      }
    }
  }

  /// Screen 2: Detail card for a selected tutorial with description and action buttons.
  static func tutorialDetail(
    tutorialIndex: Int,
    onBack: @escaping @Sendable () -> Void,
    onStart: @escaping @Sendable () -> Void
  ) -> FlexBox {
    let tutorial = tutorials[tutorialIndex]
    return FlexBox(direction: .column, spacing: 12) {
      FlexBox(direction: .column) {
        if let image = tutorial.image {
          image
        }
        Text(tutorial.title, style: .heading)
        Text(tutorial.duration, style: .meta, color: .secondary)
      }
      .padding(24)
      .background(.card)

      FlexBox(direction: .row, spacing: 8, alignment: .center, crossAlignment: .center, wrap: true) {
        ButtonGroup {
          Button(label: "Back", onClick: onBack)
          Button(label: "Start", onClick: onStart)
        }
      }
    }
  }

  /// A video player for the tutorial demo video.
  static func tutorialVideo() -> VideoPlayer {
    VideoPlayer(provider: .uri(tutorialVideoUrl), codec: .mp4)
  }

  /// Screen 3: Step-by-step view for a tutorial with navigation buttons.
  static func tutorialStep(
    tutorialIndex: Int,
    stepIndex: Int,
    onPrevious: @escaping @Sendable () -> Void,
    onNext: @escaping @Sendable () -> Void,
    onWatchVideo: @escaping @Sendable () -> Void
  ) -> FlexBox {
    let tutorial = tutorials[tutorialIndex]
    let clampedIndex = min(max(stepIndex, 0), tutorial.steps.count - 1)
    let step = tutorial.steps[clampedIndex]
    let isLastStep = clampedIndex == tutorial.steps.count - 1

    return FlexBox(direction: .column, spacing: 12) {
      FlexBox(direction: .column) {
        Text("Step \(clampedIndex + 1)", style: .meta, color: .secondary)
        Text(step.description, style: .body)
      }
      .padding(24)
      .background(.card)

      FlexBox(direction: .row, spacing: 8, alignment: .center, crossAlignment: .center) {
        ButtonGroup {
          Button(label: "Previous", style: .primary, iconName: .triangleLeftVerticalLine, onClick: onPrevious)
          Button(
            label: isLastStep ? "Done" : "Next",
            style: .primary,
            iconName: isLastStep ? .checkmark : .triangleRightVerticalLine,
            onClick: onNext
          )
          .actionRole(.primary)
          Button(label: "Watch video", style: .secondary, iconName: .videoCamera, onClick: onWatchVideo)
        }
      }
    }
  }
}
