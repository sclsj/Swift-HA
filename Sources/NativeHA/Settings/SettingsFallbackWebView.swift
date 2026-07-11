import NativeHACore
import SwiftUI

struct SettingsFallbackWebView: View {
    var item: SettingsNavigationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.title2)
            Text(item.subtitle)
                .foregroundColor(.secondary)
            if let url = item.fallbackURL {
                Link("Open in Home Assistant", destination: url)
            } else {
                Text(item.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
