import SwiftUI
import SwiftData

/// The top-level shell. A friendly two-tab layout: the Atelier (cut out a
/// subject → arrange the collage) and the Tiroir (the saved-sticker drawer).
struct RootView: View {
    @State private var session = Session()

    var body: some View {
        ZStack(alignment: .top) {
            Theme.page.ignoresSafeArea()

            Group {
                switch session.tab {
                case .atelier: AtelierView()
                case .tiroir: DrawerView()
                }
            }

            // Toast.
            if let toast = session.toast {
                ToastView(message: toast)
                    .padding(.top, 14)
                    .zIndex(100)
            }
        }
        .overlay(alignment: .bottom) {
            TabBar(tab: Bindable(session).tab)
                .padding(.bottom, 8)
        }
        .environment(session)
        .animation(.spring(duration: 0.35), value: session.toast != nil)
        .animation(.spring(duration: 0.3), value: session.tab)
        .tint(Theme.accent)
    }
}

/// A rounded, sticker-styled bottom tab bar (used on both platforms so the
/// identity stays consistent).
private struct TabBar: View {
    @Binding var tab: Session.Tab
    @Environment(Session.self) private var session

    var body: some View {
        HStack(spacing: 6) {
            item(.atelier, titleKey: "tab.atelier", icon: "scissors")
            item(.tiroir, titleKey: "tab.tiroir", icon: "tray.full.fill", badge: nil)
        }
        .padding(6)
        .background(
            Capsule().fill(Theme.card)
                .shadow(color: Theme.stickerShadow, radius: 14, y: 6)
        )
        .overlay(Capsule().stroke(Theme.hairline.opacity(0.5), lineWidth: 1))
    }

    private func item(_ value: Session.Tab, titleKey: String, icon: String, badge: Int? = nil) -> some View {
        let selected = tab == value
        return Button {
            Haptics.tap()
            tab = value
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(loc: titleKey)
            }
            .font(Theme.title(15))
            .foregroundStyle(selected ? Color.white : Theme.inkDim)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                Capsule().fill(selected ? Theme.accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
