/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreBluetooth
import MWDATCore
import SwiftUI

/// Settings — pushed from the Journal toolbar.
///
/// No `NavigationStack` of its own: this is pushed onto the Journal tab's stack, which is
/// where the back button and the title bar come from.
///
/// Three sections. **Glasses** leads: the set-up card until registration has happened, the
/// Meta AI Glasses row after — one doorway at a time, decided by
/// ``SettingsViewModel/registrationState``. **Demo / Developer** holds the Demo Director;
/// its label is the honesty affordance from the design doc. **Journal** sits last, because
/// it holds the one control in the app that empties every entry at once — nothing you were
/// scrolling for should be underneath it.
///
/// The registration raise itself happens here, not in the view model: handing off to Meta AI
/// is bound to whatever is on screen, so the raise stays beside the card (the same divergence
/// ``PermissionsController`` documents).
struct SettingsScreen: View {
  @Environment(\.theme) private var theme
  @State private var model: SettingsViewModel
  @State private var confirmingDeleteAll = false
  @State private var presentedNotice: SetupNotice?

  init(
    glassesSession: any GlassesSessionRepository,
    journal: any JournalRepository,
    mockDevice: any MockDeviceRepository
  ) {
    _model = State(
      initialValue: SettingsViewModel(
        glassesSession: glassesSession,
        journal: journal,
        mockDevice: mockDevice
      ))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: theme.space.section) {
        glassesSection
        demoSection
        journalSection
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.vertical, theme.space.separate)
    }
    .background(theme.colors.paper)
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.observe() }
    .alert("Delete all journal data?", isPresented: $confirmingDeleteAll) {
      Button("Delete everything", role: .destructive) {
        Task { await model.deleteAllJournalData() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes every entry and everything they captured — photos, recordings, and the life list they add up to. It can't be undone.")
    }
    .alert(
      presentedNotice?.title ?? "",
      isPresented: Binding(
        get: { presentedNotice != nil },
        set: { if !$0 { presentedNotice = nil } }
      ),
      presenting: presentedNotice
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { notice in
      Text(notice.message)
    }
  }

  /// One doorway at a time: nothing before the first reading has landed, the set-up
  /// card before registration, the glasses row after it.
  @ViewBuilder
  private var glassesSection: some View {
    switch model.registrationState {
    case nil:
      EmptyView()
    case .registered:
      VStack(alignment: .leading, spacing: theme.space.related) {
        PlateLabel(text: "Glasses", color: theme.colors.gilt)

        NavigationLink(value: Route.glassesSettings) {
          DisclosureRow {
            Text("Meta AI Glasses")
              .font(theme.type.headline)
              .foregroundStyle(theme.colors.textPrimary)
            Text("Status and connection")
              .font(theme.type.label)
              .foregroundStyle(theme.colors.textSecondary)
          }
        }
        .buttonStyle(.plain)
      }
    default:
      setupCard
    }
  }

  /// The invitation, before registration has happened.
  ///
  /// **Tappable in every state it appears in, including the ones that cannot raise Meta
  /// AI.** It swallowed the tap while unavailable once, and a card that reads "Set up your
  /// glasses", is styled like a button and answers a tap with nothing is indistinguishable
  /// from a bug — the support line underneath is not something anyone reads before
  /// tapping. Every tap now lands, and ``setupNotice(for:)`` decides whether it earns a
  /// registration raise or an explanation.
  private var setupCard: some View {
    Button {
      if let notice = setupNotice(for: model.registrationState, bluetooth: bluetoothAccess) {
        presentedNotice = notice
        return
      }
      // The raise itself. Meta AI takes the screen from here; the outcome lands
      // back in registrationStateStream(), which the card is already watching.
      Task {
        // docs:glasses-register:begin
        try? await Wearables.shared.startRegistration()
        // docs:glasses-register:end
      }
    } label: {
      CardSurface {
        VStack(alignment: .leading, spacing: theme.space.tight) {
          PlateLabel(text: "Meta AI Glasses", color: theme.colors.gilt)
          HStack(spacing: theme.space.related) {
            VStack(alignment: .leading) {
              Text(setupTitle)
                .font(theme.type.title)
                .foregroundStyle(theme.colors.textPrimary)
              Text(setupSupport)
                .font(theme.type.label)
                .foregroundStyle(theme.colors.textSecondary)
            }
            Spacer()
            Image(glyph: theme.glyphs.glasses)
              .foregroundStyle(theme.colors.gilt)
          }
        }
        .padding(theme.space.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
  }

  private var setupTitle: String {
    model.registrationState == .registering ? "Finishing up in Meta AI" : "Set up your glasses"
  }

  /// The support line names the same blocker the tap will, so the card is not still
  /// recommending an install while the alert over it talks about Bluetooth.
  private var setupSupport: String {
    switch model.registrationState {
    case .registering:
      "Approve the link there — this card leaves when it lands."
    case .unavailable where bluetoothAccess != .granted:
      "Allow BirdSpotter to use Bluetooth first."
    case .unavailable:
      "Install the Meta AI app and pair your glasses first."
    default:
      "Link BirdSpotter with the Meta AI app to spot through them."
    }
  }

  /// Whether the app may use Bluetooth — the gate underneath every glasses reading, since
  /// glasses are found over the Bluetooth link and nothing else.
  ///
  /// Read on each pass rather than held: the authorization is settled by a system prompt
  /// this screen does not raise, and a stale copy would outlive the answer.
  private var bluetoothAccess: PermissionStatus {
    switch CBManager.authorization {
    case .allowedAlways: .granted
    case .denied, .restricted: .denied
    case .notDetermined: .notDetermined
    @unknown default: .denied
    }
  }

  /// Emptying the Journal, and what it costs — the caption above the button, where it is
  /// read *before* the tap, the way `GlassesSettingsScreen` states the cost of unlinking.
  /// The alert is the second ask; this is the first one.
  private var journalSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Journal", color: theme.colors.gilt)

      Text("Every outing, the photos and recordings they captured, and the life list they add up to.")
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)

      // No disabled state: the sweep is a local delete and over in a blink, and the
      // view model already refuses a second one. The title is the whole feedback.
      ActionButton(
        title: model.isDeletingJournal ? "Deleting…" : "Delete all journal data",
        tone: .destructive
      ) {
        confirmingDeleteAll = true
      }
    }
  }

  private var demoSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Demo / Developer", color: theme.colors.gilt)

      NavigationLink(value: Route.demoDirector) {
        DisclosureRow {
          Text("Demo Director")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
          Text("Scripts what the app identifies")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      .buttonStyle(.plain)

      // "Diagnostics", not "Logs": logging already means the Journal in this app.
      NavigationLink(value: Route.diagnostics) {
        DisclosureRow {
          Text("Diagnostics")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
          Text("What the app did, run by run")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      .buttonStyle(.plain)

      // Here rather than on the glasses screen, because that screen only exists once
      // registration has happened — and the mock is for when it cannot.
      Toggle(
        isOn: Binding(
          get: { model.isMockDeviceEnabled },
          set: { enabled in Task { await model.setMockDeviceEnabled(enabled) } }
        )
      ) {
        VStack(alignment: .leading, spacing: theme.space.tight) {
          Text("Mock Device Kit")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
          Text("Simulated glasses in place of the real SDK. A floating button opens the controls.")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      .tint(theme.colors.verdigris)
      .disabled(model.isMockDeviceFlipping)
    }
  }
}

/// Why the set-up card cannot do the thing it is offering to do — the answer a tap gets
/// when registration is not actually raisable.
private struct SetupNotice {
  let title: String
  let message: String
}

/// The notice a tap earns in `state`, or `nil` when the tap should raise registration
/// instead.
///
/// Neither `nil` nor `.registered` reaches here — Settings shows no card before the first
/// reading lands, and trades it for the glasses row after — but both answer like
/// `.available` rather than inventing extra cases.
///
/// **`bluetooth` is why this takes two arguments.** "Unavailable" is one reading with more
/// than one cause behind it, and a refused Bluetooth authorization produces exactly the same
/// one as a phone with no Meta AI app on it: glasses are reached over the Bluetooth link, so
/// without it nothing can find them, so there is nobody to register with. Blaming Meta AI for
/// that sends someone reinstalling an app that was never the problem, so the authorization —
/// the cause this app can name for certain — is checked first.
private func setupNotice(
  for state: GlassesRegistrationState?,
  bluetooth: PermissionStatus
) -> SetupNotice? {
  switch state {
  case nil, .available, .registered:
    nil
  case .registering:
    SetupNotice(
      title: "Already waiting on Meta AI",
      message: "The link is in flight. Approve it in the Meta AI app — this card leaves on its own when it lands."
    )
  case .unavailable where bluetooth != .granted:
    SetupNotice(
      title: "Bluetooth permission needed",
      message: "Your glasses talk to BirdSpotter over Bluetooth, and the app has not been allowed to use it. Turn Bluetooth on for BirdSpotter in the phone's Settings, then come back here."
    )
  case .unavailable:
    SetupNotice(
      title: "Meta AI app required",
      message: "BirdSpotter reaches your glasses through the Meta AI app, and this phone can't find it. Install Meta AI, pair your glasses, and turn on Developer Mode for that pair — then come back here."
    )
  }
}

#Preview {
  /// Answers like a phone with Meta AI installed and no link yet — the card state.
  struct PreviewGlassesSession: GlassesSessionRepository {
    func registrationStateStream() -> AsyncStream<GlassesRegistrationState> {
      AsyncStream { continuation in
        continuation.yield(.available)
        continuation.finish()
      }
    }
    func deviceInfoStream() -> AsyncStream<GlassesDeviceInfo?> {
      AsyncStream(GlassesDeviceInfo?.self) { $0.finish() }
    }
    func sessionStream() -> AsyncThrowingStream<GlassesSessionState, Error> {
      AsyncThrowingStream { $0.finish() }
    }
    func access(_ permission: GlassesPermission) async -> GlassesAccess { .unknown }
  }

  return NavigationStack {
    SettingsScreen(
      glassesSession: PreviewGlassesSession(),
      journal: PreviewJournal(),
      mockDevice: PreviewMockDevice()
    )
  }
  .birdSpotterTheme()
}
