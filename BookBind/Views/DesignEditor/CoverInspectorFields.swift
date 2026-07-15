import SwiftUI

/// Local-draft number field — avoids cursor jumps from model updates while typing.
struct CoverInspectorNumberField: View {
    let value: Double
    var fractionDigits: Int = 1
    var width: CGFloat = 72
    let onCommit: (Double) -> Void
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .foregroundStyle(Color(nsColor: .textColor))
            .frame(width: width)
            .focused($isFocused)
            .onAppear { syncDraft() }
            .onChange(of: value) { _ in
                if !isFocused { syncDraft() }
            }
            .onChange(of: isFocused) { focused in
                onEditingChanged?(focused)
                if !focused { commitDraft() }
            }
            .onSubmit { commitDraft() }
    }

    private func syncDraft() {
        if fractionDigits == 0 {
            draft = String(Int(value.rounded()))
        } else {
            draft = value.formatted(.number.precision(.fractionLength(fractionDigits)))
        }
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Double(trimmed) else {
            syncDraft()
            return
        }
        let rounded = fractionDigits == 0 ? Double(Int(parsed.rounded())) : parsed
        if abs(rounded - value) > 0.000_1 {
            onCommit(rounded)
        }
    }
}

/// Local-draft text field for inspector strings.
struct CoverInspectorTextField: View {
    let value: String
    var placeholder: String = ""
    var isBold: Bool = false
    let onCommit: (String) -> Void
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .foregroundStyle(Color(nsColor: .textColor))
            .fontWeight(isBold ? .semibold : .regular)
            .focused($isFocused)
            .onAppear { syncDraft() }
            .onChange(of: value) { _ in
                if !isFocused { syncDraft() }
            }
            .onChange(of: isFocused) { focused in
                onEditingChanged?(focused)
                if !focused { commitDraft() }
            }
            .onSubmit { commitDraft() }
    }

    private func syncDraft() {
        draft = value
    }

    private func commitDraft() {
        if draft != value {
            onCommit(draft)
        }
    }
}
