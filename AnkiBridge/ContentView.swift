import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 290, max: 440)
        } detail: {
            VSplitView {
                ChatView()
                    .frame(minWidth: 480, minHeight: 220)
                CardsPaneView()
                    .frame(minWidth: 480, minHeight: 240)
            }
            .navigationSplitViewColumnWidth(min: 480, ideal: 700)
        }
        .background(WindowAccessor { window in
            // Pin the window's AppKit-level min size. The SwiftUI .frame /
            // .windowResizability modifiers don't reliably reach NSWindow in
            // every configuration, so we set contentMinSize ourselves. This is
            // what makes the sidebar hold its width as the window shrinks: the
            // detail column hits its 480pt floor, the window refuses to go
            // smaller, and the sidebar is never squeezed.
            let minSize = NSSize(width: 900, height: 640)
            window.contentMinSize = minSize
            window.minSize = NSSize(
                width: minSize.width,
                height: minSize.height + window.frame.height - window.contentLayoutRect.height
            )
        })
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Note type", selection: $state.noteKind) {
                    ForEach(NoteKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .help("Choose the type of card the assistant should generate.")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Server & AnkiConnect settings")
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            if !state.statusMessage.isEmpty {
                Text(state.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.bar)
            }
        }
    }
}
