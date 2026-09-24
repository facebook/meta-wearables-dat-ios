/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

final class BirdSpotterUITestsLaunchTests: XCTestCase {

  override class var runsForEachTargetApplicationUIConfiguration: Bool {
    true
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunch() throws {
    let app = XCUIApplication()
    app.launch()

    // Insert steps here to perform after app launch but before taking a screenshot,
    // such as logging into a test account or navigating somewhere in the app
    // XCUIAutomation Documentation
    // https://developer.apple.com/documentation/xcuiautomation

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Launch Screen"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
