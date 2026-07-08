import SwiftUI

struct CardFallbackView: View {
    var descriptor: LovelaceCardDescriptor

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 8) {
                Text("Unsupported Lovelace card")
                    .font(.headline)
                ForEach(descriptor.debugHints, id: \.self) { hint in
                    Text(hint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }
}
