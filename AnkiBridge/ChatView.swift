import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if state.messages.isEmpty {
                            placeholder
                        }
                        ForEach(state.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if state.isSending {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Thinking…").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: state.messages.count) {
                    if let last = state.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()
            inputArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.image, .pdf, .plainText, .text, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { state.addAttachments(urls) }
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Describe what you want to study.")
                .font(.title3).bold()
            Text("Attach images, PDFs, or notes for context. The assistant asks clarifying questions, then generates \(state.noteKind.rawValue) cards into the panel below.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            if !state.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.pendingAttachments) { att in
                            AttachmentChip(attachment: att) { state.removeAttachment(att.id) }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showingImporter = true
                } label: {
                    Image(systemName: "paperclip").font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Attach images, PDFs, or files as context")

                ZStack(alignment: .topLeading) {
                    ChatInputTextView(
                        text: $state.draft,
                        onSubmit: { Task { await state.sendDraft() } },
                        onPasteImage: { image in Task { @MainActor in state.addPastedImage(image) } }
                    )
                    .frame(minHeight: 22, maxHeight: 120)

                    if state.draft.isEmpty {
                        Text("Message the model… (↩ to send, ⇧↩ for newline)")
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))

                Button {
                    Task { await state.sendDraft() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .buttonStyle(.borderless)
                .disabled(state.isSending || (state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.pendingAttachments.isEmpty))
            }

            Toggle(isOn: $settings.constrainToContext) {
                Text("Use only attached context (no outside knowledge)")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }
}

// MARK: - AppKit-backed input (reliable Enter-to-send + image paste)

/// An NSTextView wrapper that submits on Return (Shift+Return = newline) and
/// intercepts pasted images, handing them to `onPasteImage` instead of inserting.
private struct ChatInputTextView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onPasteImage: (NSImage) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onPasteImage = onPasteImage
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? PasteAwareTextView else { return }
        textView.onSubmit = onSubmit
        textView.onPasteImage = onPasteImage
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: ChatInputTextView
        init(_ parent: ChatInputTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

private final class PasteAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onPasteImage: ((NSImage) -> Void)?

    // Advertise image types so the Paste menu item / ⌘V stay enabled when the
    // clipboard only contains an image. NSTextView with isRichText=false would
    // otherwise report no readable types and disable Paste.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.png, .tiff]
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(paste(_:)),
           NSPasteboard.general.availableType(from: [.png, .tiff]) != nil {
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        // Prefer image data whenever the pasteboard carries any (screenshots,
        // images copied from a browser, Preview, etc.). Many sources also place
        // a URL or HTML alongside the image; we still want to attach the image
        // rather than insert that text into the field.
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        if pb.availableType(from: imageTypes) != nil,
           let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !images.isEmpty {
            for image in images { onPasteImage?(image) }
            return
        }
        super.paste(sender)
    }

    override func keyDown(with event: NSEvent) {
        // Return (keyCode 36) / keypad Enter (76) submits unless Shift is held or
        // an IME composition is in progress.
        if (event.keyCode == 36 || event.keyCode == 76),
           !event.modifierFlags.contains(.shift),
           !hasMarkedText() {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Attachment chip

private struct AttachmentChip: View {
    let attachment: Attachment
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            if attachment.isImage, let img = NSImage(data: attachment.data) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: attachment.symbolName).foregroundStyle(.secondary)
            }
            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 160)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: ChatMessage
    @State private var showReasoning = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "You" : "Assistant")
                    .font(.caption2).foregroundStyle(.secondary)

                if !isUser && !message.reasoning.isEmpty {
                    reasoningBox
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isUser ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                        )
                }

                if !message.attachments.isEmpty {
                    FlowAttachments(attachments: message.attachments)
                }

                if !isUser && !message.model.isEmpty {
                    Text(message.model)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: 620, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var reasoningBox: some View {
        DisclosureGroup(isExpanded: $showReasoning) {
            Text(message.reasoning)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label("Thinking", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .underPageBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    }
}

/// Wraps attachment chips for a sent message.
private struct FlowAttachments: View {
    let attachments: [Attachment]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(attachments) { att in
                if att.isImage, let img = NSImage(data: att.data) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    AttachmentChip(attachment: att)
                }
            }
        }
    }
}
