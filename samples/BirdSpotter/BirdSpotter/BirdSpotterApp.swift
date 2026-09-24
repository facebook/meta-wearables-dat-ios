/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import MWDATCore
import SwiftUI

@main
struct BirdSpotterApp: App {
  /// The composition root, built once for the life of the process.
  ///
  /// Built at the **end** of `init`, not in the property's initializer: the container may
  /// switch the Mock Device Kit on while it is being built, and the kit configures DAT
  /// itself if nothing has — which would make the `Wearables.configure()` below a second
  /// configure, and a crash on every launch with the mock left on.
  @State private var container: AppContainer

  init() {
    // A wrong PostScript name or a missing UIAppFonts entry fails silently — SwiftUI
    // just draws the system font. Fail loudly in debug instead.
    assert(
      BirdSpotterFont.verifyRegistered().isEmpty,
      "Unregistered fonts: \(BirdSpotterFont.verifyRegistered())"
    )
    // Nav and tab bars are UIKit, so the font environment never reaches them.
    BirdSpotterTheme.configureChromeAppearance()

    // DAT reads its MWDAT dictionary out of Info.plist here. A failure is a
    // misconfigured plist, not a runtime condition, so debug fails loudly and release
    // carries on phone-only — the same posture as the fonts above.
    do {
      try Wearables.configure()
    } catch {
      assertionFailure("DAT would not configure: \(error)")
    }

    // After DAT, for the reason on the property.
    _container = State(initialValue: AppContainer())
  }

  var body: some Scene {
    WindowGroup {
      ContentView(container: container)
        .birdSpotterTheme()
        .onOpenURL { url in
          // The way back from the Meta AI handoff at the end of registration, and
          // the way Meta AI opens the app for a voice launch. Logged because a
          // launch that "just opened the app" is diagnosed from this one line: the
          // open by URL arrived, and whether the invocation then arrived on the
          // voice channel is the next line to look for.
          BirdLog.info(.glasses, "opened by URL — \(url.scheme ?? "?")://\(url.host ?? "")\(url.path)")
          // Fire-and-forget, deliberately: the SDK consumes its own URLs, and
          // the outcome lands in registrationStateStream() where Settings is
          // already watching.
          Task { _ = try? await Wearables.shared.handleUrl(url) }
        }
    }
  }
}
