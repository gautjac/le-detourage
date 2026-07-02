import SwiftUI
import SwiftData

/// The top-level shell: a native two-tab layout — the Atelier (cut out a subject
/// → arrange the collage) and the Tiroir (the saved-sticker drawer). Using a
/// `TabView` gives a real, space-reserving tab bar (bottom on iOS, top segmented
/// on macOS) so it never overlaps the collage.
struct RootView: View {
    @State private var session = Session()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: Bindable(session).tab) {
            AtelierView()
                .background(Theme.page.ignoresSafeArea())
                .tag(Session.Tab.atelier)
                .tabItem { Label(L.t("tab.atelier"), systemImage: "scissors") }

            DrawerView()
                .background(Theme.page.ignoresSafeArea())
                .tag(Session.Tab.tiroir)
                .tabItem { Label(L.t("tab.tiroir"), systemImage: "tray.full.fill") }
        }
        .tint(Theme.accent)
        .environment(session)
        .overlay(alignment: .top) {
            if let toast = session.toast {
                ToastView(message: toast)
                    .padding(.top, 14)
                    .zIndex(100)
            }
        }
        .animation(.spring(duration: 0.35), value: session.toast != nil)
        .onChange(of: scenePhase) { _, phase in
            // Never lose an in-progress collage: flush the working draft the
            // moment the app leaves the foreground.
            if phase != .active { session.flushAutosave() }
        }
    }
}
