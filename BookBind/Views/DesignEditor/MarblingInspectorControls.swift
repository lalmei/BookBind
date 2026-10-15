import SwiftUI

/// Compact marbling parameter controls + entry to the full Marblizer-class editor.
struct MarblingInspectorControls: View {
    @Binding var spec: MarbledPaperSpec
    var onOpenEditor: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let onOpenEditor {
                Button {
                    onOpenEditor()
                } label: {
                    Label("Open Marble editor…", systemImage: "paintbrush.pointed")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if spec.hasEditableHistory {
                Text("\(spec.operations?.count ?? 0) interactive operations")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Style")
                .font(.caption.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(MarblingStyle.allCases) { style in
                    Button {
                        spec.style = style
                        if spec.hasEditableHistory {
                            spec.operations = nil
                        }
                    } label: {
                        Text(style.title)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(spec.style == style ? Color.accentColor : Color.secondary)
                }
            }

            Text("Palette")
                .font(.caption.weight(.semibold))
            ForEach(MarbledPaperPalette.all, id: \.name) { palette in
                Button {
                    spec.palette = palette.colors
                    spec.background = palette.background
                } label: {
                    HStack(spacing: 6) {
                        ForEach(Array(palette.colors.prefix(4).enumerated()), id: \.offset) { _, color in
                            Circle()
                                .fill(color.color)
                                .frame(width: 10, height: 10)
                        }
                        Text(palette.name)
                            .font(.caption)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }

            if !spec.hasEditableHistory {
                slider("Drop size", value: $spec.dropSize, range: 0.35...2.5)
                slider("Density", value: $spec.density, range: 0.1...1)
                slider("Scale", value: $spec.scale, range: 0.35...2.5)
                slider("Comb spacing", value: $spec.combSpacing, range: 0.35...2.5)
                slider("Comb strength", value: $spec.combStrength, range: 0.35...2.5)
                slider("Turbulence", value: $spec.turbulence, range: 0...1)
            }

            HStack {
                Text("Seed \(spec.seed)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Regenerate") {
                    spec.regenerateVariation()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(spec.hasEditableHistory
                      ? "New variation from recipe — clears interactive history"
                      : "New seed; same palette and settings")
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(value: value, in: range)
        }
    }
}
