import SwiftUI
import PuraMacCore

struct ReviewItem: Identifiable, Hashable {
    let path: String
    let bytes: Int64
    let kind: String

    var id: String { path }
}

/// Nothing is ever removed without this appearing first. It lists the real
/// paths, not a count, so agreeing to a cleanup is an informed act.
struct ReviewSheet: View {
    let title: String
    let items: [ReviewItem]
    let totalBytes: Int64
    let confirmTitle: String
    let note: String
    var isPermanent = false
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text("\(Format.count(items.count, singular: "item")) · \(Format.bytes(totalBytes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            Table(items) {
                TableColumn("Item") { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text((item.path as NSString).lastPathComponent)
                            .lineLimit(1)
                        Text(Format.abbreviate(item.path))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                TableColumn("Kind") { item in
                    Text(item.kind).foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 120)
                TableColumn("Size") { item in
                    Text(Format.bytes(item.bytes)).monospacedDigit()
                }
                .width(min: 80, ideal: 90)
            }
            .frame(minHeight: 220, maxHeight: 340)

            Divider()

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isPermanent ? "exclamationmark.triangle.fill" : "arrow.uturn.backward.circle")
                    .foregroundStyle(isPermanent ? .red : .secondary)
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, role: isPermanent ? .destructive : nil) {
                    dismiss()
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 620)
    }
}
