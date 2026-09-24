/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

/// Both expose the same four token sets — `BirdSpotterTheme.colors`, `.type`, `.space` and
/// `.glyphs` — with identical member names.
///
/// Note there is no glasses-display equivalent of this: the DAT display API takes three
/// text presets (heading / body / meta) and two colors, rendered in Meta's own design
/// system. Everything here is the phone app only.
struct BirdSpotterTheme {
  var colors: BirdSpotterColors
  var type: BirdSpotterTypography
  var space: BirdSpotterSpacing
  var glyphs: BirdSpotterGlyphs

  static func resolve(for scheme: ColorScheme) -> BirdSpotterTheme {
    BirdSpotterTheme(
      colors: scheme == .dark ? .dark : .light,
      type: BirdSpotterTypography(),
      space: BirdSpotterSpacing(),
      glyphs: BirdSpotterGlyphs()
    )
  }
}

private struct BirdSpotterThemeKey: EnvironmentKey {
  static let defaultValue = BirdSpotterTheme.resolve(for: .light)
}

extension EnvironmentValues {
  /// Token accessors: `theme.colors.gilt`, `theme.type.plate`, `theme.space.gutter`,
  /// `theme.glyphs.search`.
  var theme: BirdSpotterTheme {
    get { self[BirdSpotterThemeKey.self] }
    set { self[BirdSpotterThemeKey.self] = newValue }
  }
}

/// Applies the palette and type scale, and keeps them in step with light/dark.
/// Wrap the root view once — see `birdspotterApp`.
///
/// SwiftUI has no global typography system to hand a type scale to.
/// What it has is the **font environment**, which cascades: `.font(...)` here becomes the
/// default for every `Text` below that doesn't set its own. That covers SwiftUI-drawn text.
/// It does *not* reach UIKit-backed chrome — navigation bar titles, tab bar labels — which
/// is what `configureChromeAppearance()` is for.
struct BirdSpotterThemeModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  /// Whether the root is painted paper. The app's root is; a root laid *over* the app —
  /// the mock's floating overlay — must not be, or it papers over the whole screen.
  let paintsGround: Bool

  func body(content: Content) -> some View {
    let theme = BirdSpotterTheme.resolve(for: colorScheme)
    content
      .environment(\.theme, theme)
      .font(theme.type.body) // cascades to all descendant Text
      .foregroundStyle(theme.colors.textPrimary)
      .tint(theme.colors.gilt)
      .background(paintsGround ? theme.colors.paper : .clear)
  }
}

extension View {
  func birdSpotterTheme(paintsGround: Bool = true) -> some View {
    modifier(BirdSpotterThemeModifier(paintsGround: paintsGround))
  }
}

// MARK: - UIKit chrome

extension BirdSpotterTheme {

  /// Navigation and tab bars are UIKit views that SwiftUI hosts, so the font environment
  /// never reaches them — they read `UINavigationBar` / `UITabBar` appearance proxies
  /// instead. Call once at launch.
  ///
  /// Colors are `UIColor(dynamicProvider:)` so the bars follow light/dark on their own;
  /// the proxies are global state and shouldn't be rewritten on every render.
  static func configureChromeAppearance() {
    let tabLabel = UIFont(name: BirdSpotterFont.sansMedium, size: 10)

    let nav = paperBarAppearance()
    UINavigationBar.appearance().standardAppearance = nav
    UINavigationBar.appearance().compactAppearance = nav
    UINavigationBar.appearance().scrollEdgeAppearance = nav

    let tab = UITabBarAppearance()
    tab.configureWithOpaqueBackground()
    tab.backgroundColor = dynamic(\.paperRaised)
    tab.shadowColor = dynamic(\.rule)

    for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
      item.normal.titleTextAttributes = attributes(tabLabel, \.textSecondary)
      item.normal.iconColor = dynamic(\.textSecondary)
      item.selected.titleTextAttributes = attributes(tabLabel, \.gilt)
      item.selected.iconColor = dynamic(\.gilt)
    }

    UITabBar.appearance().standardAppearance = tab
    UITabBar.appearance().scrollEdgeAppearance = tab
  }

  /// The app's bar: opaque paper with a hairline under it, and the name in Caslon.
  static func paperBarAppearance() -> UINavigationBarAppearance {
    let nav = UINavigationBarAppearance()
    nav.configureWithOpaqueBackground()
    nav.backgroundColor = dynamic(\.paper)
    nav.shadowColor = dynamic(\.rule)
    nav.titleTextAttributes = attributes(
      UIFont(name: BirdSpotterFont.caslonDisplay, size: 19), \.textPrimary
    )
    nav.largeTitleTextAttributes = attributes(
      UIFont(name: BirdSpotterFont.caslonDisplay, size: 33), \.textPrimary
    )
    return nav
  }

  private static func dynamic(_ token: KeyPath<BirdSpotterColors, Color>) -> UIColor {
    UIColor { traits in
      let palette: BirdSpotterColors = traits.userInterfaceStyle == .dark ? .dark : .light
      return UIColor(palette[keyPath: token])
    }
  }

  private static func attributes(
    _ font: UIFont?,
    _ token: KeyPath<BirdSpotterColors, Color>
  ) -> [NSAttributedString.Key: Any] {
    var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: dynamic(token)]
    if let font { attrs[.font] = font }
    return attrs
  }
}
