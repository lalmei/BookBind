import SwiftUI

struct SignatureMapView: View {
    let map: SignatureMap

    private var signatureIndices: [Int] {
        Array(Set(map.sides.map(\.signatureIndex))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Signature map")
                    .font(.headline)
                Spacer()
                Text("\(map.plan.sheetCount) sheets · pages are 1-based book order")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if map.sides.isEmpty {
                Text("Add PDFs to see sheet layout.")
                    .foregroundStyle(.secondary)
                    .padding(14)
                Spacer()
            } else {
                List {
                    ForEach(signatureIndices, id: \.self) { sig in
                        Section("Signature \(sig)") {
                            ForEach(map.sides(forSignature: sig)) { side in
                                HStack {
                                    Text("Sheet \(side.sheetIndex) \(side.face.rawValue)")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                    Text(side.label)
                                        .font(.body.monospacedDigit())
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            Text(BindingJob.duplexHintText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}
