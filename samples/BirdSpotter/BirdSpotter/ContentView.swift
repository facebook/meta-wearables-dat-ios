/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

/// Root view hosting the app's primary bottom tab navigation.
///
/// Each tab holds its own `NavigationStack`, so a tab keeps its stack: pushing Settings
/// inside Journal, wandering off to Explore, and coming back leaves Settings on screen.
///
/// The stacks live here rather than inside the feature screens because a destination is
/// only reachable from the stack that registered it. Bird detail opens from all three tabs,
/// so all three register it. A screen owning its own stack could only ever navigate within
/// itself.
///
/// The shell deliberately owns no title bar. Each screen brings its own, which is why
/// adding a pushed screen never means editing this file's chrome.
struct ContentView: View {
  @Environment(\.theme) private var theme

  let container: AppContainer

  // One path per tab, held here so a tab's stack survives switching away from it.
  @State private var explorePath: [Route] = []
  @State private var identifyPath: [Route] = []
  @State private var journalPath: [Route] = []

  // Which tab is showing. Held as state rather than left to the TabView so a launch from
  // outside the UI — the wearer's own voice — can land the user on Identify.
  @State private var selectedTab: Tab = .explore

  // A voice launch's standing request: raise the session cover already reaching for the
  // glasses. Set here, because the shell is what listens; acted on and cleared by
  // `IdentifyScreen`, because the cover is its to raise.
  @State private var isRealtimeOnGlasses = false

  // The launch moment, held by the shell because the shell is what it overlays. Plain
  // `@State`: a splash belongs to a cold start, and this scene lives for one.
  @State private var isSplashFinished = false

  // The glyphs come from `theme.glyphs` rather than from SF Symbols, and that is a parity
  // decision, not a stylistic one: SF Symbols is licensed for Apple platforms only, so a
  // symbol used here is a drawing this design system cannot own. The bar reads its three
  // roles off `theme.glyphs` like every other icon in the app.
  var body: some View {
    ZStack {
      TabView(selection: $selectedTab) {
        TabStack(path: $explorePath, container: container) {
          ExploreScreen(birdCatalog: container.birdCatalogRepository)
        }
        .tabItem {
          Label("Explore", image: theme.glyphs.explore)
        }
        .tag(Tab.explore)

        TabStack(path: $identifyPath, container: container) {
          IdentifyScreen(
            permissions: container.permissionsController,
            realtime: container.realtimeViewModel,
            startOnGlasses: $isRealtimeOnGlasses
          )
        }
        .tabItem {
          Label("Identify", image: theme.glyphs.identify)
        }
        .tag(Tab.identify)

        TabStack(path: $journalPath, container: container) {
          JournalScreen(
            journal: container.journalRepository,
            birdCatalog: container.birdCatalogRepository,
            mediaFileStore: container.mediaFileStore
          )
        }
        .tabItem {
          Label("Journal", image: theme.glyphs.journal)
        }
        .tag(Tab.journal)
      }
      // The voice launches, acted on for as long as the shell is up. Each one has
      // already been answered by the time it lands here (see GlassesVoiceRepository);
      // this is the acting-on half — the session the wearer asked for, on the device
      // they asked from.
      //
      // **Two effects, deliberately.** The session is started here, directly, because
      // the launch may land with the phone locked in a pocket — no cover can rise and
      // nothing on screen will run — and the wearer still asked for a session. Raising
      // the cover is the second effect, for when there is a screen to raise it on.
      .task {
        for await event in container.glassesVoiceRepository.voiceEventStream() {
          switch event {
          case .launch:
            container.realtimeViewModel.start(onGlasses: true)
            selectedTab = .identify
            isRealtimeOnGlasses = true
          }
        }
      }
      // The mock's floating button and panel, in a window of their own above this one
      // — so they float over the realtime cover and the sheets this window presents,
      // which nothing placed in this ZStack could. Installed from here rather than the
      // app's `init` because this is the first moment a scene exists to attach to.
      .task {
        MockDeviceOverlayHost.install(
          mockDevice: container.mockDeviceRepository,
          settings: container.mockDeviceSettingsStore
        )
      }

      // Over the shell, so the reveal is a dissolve onto a page that is already
      // laid out. The 0.42 / 0 / 0.58 / 1 crossfade curve is `SplashMotion`'s.
      if !isSplashFinished {
        SplashScreen {
          withAnimation(
            .timingCurve(0.42, 0, 0.58, 1, duration: Double(SplashMotion.crossfadeMillis) / 1000)
          ) {
            isSplashFinished = true
          }
        }
        .transition(.opacity)
      }
    }
  }
}

/// One tab: its own `NavigationStack`, registering the whole address book.
///
/// Repeating the registration per tab is not duplication waiting to be factored away — it
/// is what "each tab keeps its own back stack" means. Opening a bird from Journal has to
/// land on Journal's stack, so Journal's stack has to know the address.
private struct TabStack<Root: View>: View {
  @Binding var path: [Route]
  let container: AppContainer
  @ViewBuilder let root: Root

  var body: some View {
    NavigationStack(path: $path) {
      root.navigationDestination(for: Route.self) { route in
        route.destination(container: container)
      }
    }
  }
}

#Preview {
  ContentView(container: AppContainer())
    .birdSpotterTheme()
}
