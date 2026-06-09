import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            SidebarView()
                // Set a firm minimum width for the sidebar.
                .frame(minWidth: 220)
                .navigationSplitViewColumnWidth(min: 220, ideal: 290, max: 440)
                // Give the sidebar higher layout priority so it resists shrinking
                .layoutPriority(1)
        } detail: {
            VSplitView {
                ChatView()
                    .frame(minWidth: 320, minHeight: 220)
                CardsPaneView()
                    .frame(minWidth: 320, minHeight: 240)
            }
            // Set a firm minimum width for the detail column.
            .navigationSplitViewColumnWidth(min: 320, ideal: 700)
        }
        .navigationSplitViewStyle(.balanced) // Explicitly set balanced style
        .background(WindowMinSizeSetter())
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

// MARK: - WindowMinSizeSetter

/// A representable view that sets the minimum size of the containing NSWindow.
/// This is more reliable than SwiftUI's .windowResizability for strict minimums.
struct WindowMinSizeSetter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        // We set the min size on the window. This needs to happen after the view
        // is added to the window. We use a DispatchQueue to ensure the view
        // is in the hierarchy.
        DispatchQueue.main.async {
            updateWindowSize(for: view)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        updateWindowSize(for: nsView)
    }
    
    private func updateWindowSize(for view: NSView) {
        guard let window = view.window else { return }
        
        // Define the minimum widths for the columns
        let sidebarMinWidth: CGFloat = 220
        let detailMinWidth: CGFloat = 320
        let dividerWidth: CGFloat = 10 // Approximate width of the split view divider
        
        // Calculate the total minimum content width
        let totalMinWidth = sidebarMinWidth + detailMinWidth + dividerWidth
        
        // Set the window's minimum size
        let minSize = NSSize(width: totalMinWidth, height: 640)
        window.contentMinSize = minSize
        
        // Also set the frame min size to account for the window chrome
        // This ensures the user cannot resize the window smaller than this.
        window.minSize = NSSize(
            width: minSize.width,
            height: minSize.height + window.frame.height - window.contentLayoutRect.height
        )
    }
}
