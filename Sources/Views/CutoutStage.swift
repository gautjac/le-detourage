import SwiftUI

/// The cutout stage: import a photo, then lift its subject. On iOS/iPadOS the
/// system's press-and-lift affordance is live (tap a subject); on macOS clicking
/// a subject lifts it. A "Lift the subject" button uses VisionKit's detected
/// subjects, and always has a Vision foreground-mask fallback so a cutout can be
/// made from any photo.
struct CutoutStage: View {
    var onLift: (PlatformImage) -> Void

    @Environment(Session.self) private var session
    @StateObject private var lift = SubjectLiftController()
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            header
            TornDivider().padding(.horizontal, 20).padding(.bottom, 8)

            if let image = session.stageImage {
                stage(image)
            } else {
                emptyState
            }
        }
        .onAppear { wireController() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "scissors")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(loc: "lift.title")
                .font(Theme.display(22))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    // MARK: Empty (no photo yet)

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Theme.inkFaint)
            Text(loc: "import.hint")
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            VStack(spacing: 12) {
                PhotoImportButton { session.loadStage($0) }
                Button {
                    Haptics.tap()
                    session.loadSample()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text(loc: "import.sample")
                    }
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.teal)
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .background(Capsule().stroke(Theme.teal, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stage (photo loaded)

    @ViewBuilder
    private func stage(_ image: PlatformImage) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: Theme.stickerShadow, radius: 10, y: 5)

                if #available(iOS 17.0, macOS 14.0, *) {
                    SubjectLiftView(image: image, controller: lift)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(6)
                } else {
                    Image(platform: image)
                        .resizable().scaledToFit()
                        .padding(6)
                }

                if working {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large)
                        Text(loc: "lift.working")
                            .font(Theme.title(14)).foregroundStyle(Theme.ink)
                    }
                }
            }
            .frame(minHeight: 300)
            .padding(.horizontal, 16)

            Text(instructionKey)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                PillButton(titleKey: "lift.auto", systemImage: "wand.and.stars",
                           tint: Theme.accent) {
                    Task { await autoLift(image) }
                }
                HStack(spacing: 10) {
                    PhotoImportButton(titleKey: "import.photo", systemImage: "photo",
                                      tint: Theme.teal, filled: false) {
                        session.loadStage($0)
                    }
                    Button {
                        Haptics.tap(); session.loadSample()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.grape)
                            .frame(width: 46, height: 46)
                            .background(Circle().stroke(Theme.grape, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)

            Spacer(minLength: 0)
        }
        .disabled(working)
    }

    private var instructionKey: String {
        #if os(macOS)
        return L.t("lift.instruction.mac")
        #else
        return L.t("lift.instruction")
        #endif
    }

    // MARK: Lift plumbing

    private func wireController() {
        lift.onLift = { image in
            onLift(image)
        }
    }

    /// The toolbar "lift the subject" action. Prefer VisionKit's detected
    /// subjects; fall back to the Vision foreground-instance mask so every photo
    /// yields a cutout.
    private func autoLift(_ image: PlatformImage) async {
        working = true
        session.isLifting = true
        defer { working = false; session.isLifting = false }

        if #available(iOS 17.0, macOS 14.0, *),
           let vkImage = await lift.liftAllSubjects?() {
            let tight = SubjectMasker.trimTransparentMargins(vkImage)
            onLift(tight)
            return
        }
        // Fallback: Vision foreground-instance mask.
        do {
            let cutout = try await SubjectMasker.lift(from: image)
            onLift(cutout)
        } catch {
            session.flash(L.t("lift.none"))
        }
    }
}
