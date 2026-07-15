import SwiftUI

/// Fill section parallel to stroke — None / Solid now; gradients reserved later.
struct FillControls: View {
    let fill: CoverPaint
    var defaultSolid: CodableColor
    var onChange: (CoverPaint) -> Void

    private enum FillMode: String, CaseIterable, Identifiable {
        case none
        case solid

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "None"
            case .solid: return "Solid"
            }
        }
    }

    private var mode: FillMode {
        fill.isFilled ? .solid : .none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: modeBinding) {
                ForEach(FillMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Fill type. Additional types (gradient, pattern) can be added later.")

            if case let .solid(color) = fill {
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { color.color },
                        set: { onChange(.solid(CodableColor(color: $0))) }
                    ),
                    supportsOpacity: true
                )
                .labelsHidden()
                .help("Fill color")
            }
        }
    }

    private var modeBinding: Binding<FillMode> {
        Binding(
            get: { mode },
            set: { newMode in
                switch newMode {
                case .none:
                    onChange(.none)
                case .solid:
                    onChange(.solid(fill.solidColor ?? defaultSolid))
                }
            }
        )
    }
}
