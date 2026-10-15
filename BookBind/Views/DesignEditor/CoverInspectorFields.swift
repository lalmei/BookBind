import SwiftUI

/// Local-draft number field — avoids cursor jumps from model updates while typing.
///
/// Accepts arithmetic (`210-6`, `50%`). With `isLength`, `value` is millimeters: the field shows
/// it in the preferred unit (Settings ▸ Units) and also accepts `6in`, `152mm`, `1p6`, and so on.
struct CoverInspectorNumberField: View {
    let value: Double
    /// Decimal places when shown in millimeters (inches add precision automatically).
    var fractionDigits: Int = 1
    var width: CGFloat = 72
    /// `value` is a length in millimeters.
    var isLength: Bool = false
    let onCommit: (Double) -> Void
    var onEditingChanged: ((Bool) -> Void)? = nil

    @AppStorage(MeasurementUnit.storageKey) private var unitRaw = MeasurementUnit.millimeters.rawValue
    @State private var draft = ""
    @State private var isInvalid = false
    @FocusState private var isFocused: Bool

    private var unit: MeasurementUnit {
        MeasurementUnit(rawValue: unitRaw) ?? .millimeters
    }

    private var displayDigits: Int {
        isLength ? unit.fractionDigits(forMillimeterDigits: fractionDigits) : fractionDigits
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $draft)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(Color(nsColor: .textColor))
                .frame(width: width)
                .focused($isFocused)
                .overlay {
                    if isInvalid {
                        RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .systemRed), lineWidth: 1)
                    }
                }
                .help(isLength ? "Any unit or arithmetic: 6in, 152mm, 1p6, 210-6, 50%" : "Arithmetic allowed: 210-6, 50%")
            if isLength {
                Text(unit.suffix)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { syncDraft() }
        .onChange(of: value) { _ in
            if !isFocused { syncDraft() }
        }
        .onChange(of: unitRaw) { _ in syncDraft() }
        .onChange(of: isFocused) { focused in
            onEditingChanged?(focused)
            if !focused { commitDraft() }
        }
        .onSubmit { commitDraft() }
    }

    private func syncDraft() {
        isInvalid = false
        let shown = isLength ? unit.fromMillimeters(value) : value
        if displayDigits == 0 {
            draft = String(Int(shown.rounded()))
        } else {
            draft = shown.formatted(.number.precision(.fractionLength(0...displayDigits)))
        }
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = isLength
            ? MeasurementExpression.evaluateLength(trimmed, defaultUnit: unit, baseMM: value)
            : MeasurementExpression.evaluateNumber(trimmed, base: value)
        guard !trimmed.isEmpty, let parsed else {
            // Keep the typo visible briefly so it's clear why nothing changed.
            isInvalid = !trimmed.isEmpty
            if !isInvalid { syncDraft() }
            return
        }
        isInvalid = false
        let rounded = !isLength && fractionDigits == 0 ? Double(Int(parsed.rounded())) : parsed
        if abs(rounded - value) > 0.000_1 {
            onCommit(rounded)
        }
        syncDraft()
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
