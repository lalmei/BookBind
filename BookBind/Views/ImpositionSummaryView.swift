import SwiftUI

/// Sidebar card matching the imposition summary mockup.
struct ImpositionSummaryView: View {
    let summary: ImpositionSummary
    var showsChrome: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if showsChrome {
                Text("IMPOSITION SUMMARY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color(nsColor: .labelColor).opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.7))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
            }

            VStack(spacing: 0) {
                summaryRow(label: "Total PDF Pages", value: "\(summary.totalPDFPages)")
                rowDivider
                summaryRow(label: "Total Signatures", value: "\(summary.totalSignatures)")
                rowDivider
                summaryRow(label: "Sheet Size", value: summary.sheetSizeLabel)
                rowDivider
                summaryRow(label: "Print Sheets Required", value: "\(summary.printSheetsRequired)")
            }
            .padding(.horizontal, showsChrome ? 14 : 0)
            .padding(.vertical, showsChrome ? 4 : 0)
            .padding(.bottom, showsChrome ? 8 : 0)
        }
        .background {
            if showsChrome {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            }
        }
        .overlay {
            if showsChrome {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.45))
            .frame(height: 1)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .labelColor).opacity(0.85))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }
}

#Preview {
    ImpositionSummaryView(
        summary: ImpositionSummary(
            totalPDFPages: 128,
            totalSignatures: 16,
            sheetSizeLabel: "A3 Landscape",
            printSheetsRequired: 32
        )
    )
    .padding()
    .frame(width: 260)
}
