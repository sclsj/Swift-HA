import SwiftUI

struct ErrorCardView: View {
    var title: String
    var message: String
    var rawSummary: String?

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let rawSummary = rawSummary, !rawSummary.isEmpty {
                    Text(rawSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
    }
}
