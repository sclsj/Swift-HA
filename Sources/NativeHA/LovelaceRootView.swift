import NativeHACore
import SwiftUI

struct LovelaceRootView: View {
    @ObservedObject var store: LovelaceStore

    let selectedDashboardPath: String
    let displayContext: EntityDisplayContext
    var templateSubscriber: MarkdownTemplateSubscribing?
    var userName: String = "Home Assistant"
    var userID: String?
    let onSelectDashboard: (LovelaceDashboardReference) -> Void
    let onSelectView: (LovelaceViewRoute) -> Void
    let onRetry: () -> Void
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            dashboardList
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)

            Divider()

            LovelaceViewHost(
                state: store.state,
                displayContext: displayContext,
                templateSubscriber: templateSubscriber,
                userName: userName,
                userID: userID,
                onSelectView: onSelectView,
                onRetry: onRetry,
                onMoreInfo: onMoreInfo,
                onServiceCall: onServiceCall
            )
        }
        .task(id: userID ?? "") {
            store.setCurrentUserID(userID)
        }
    }

    private var dashboardList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dashboards")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if store.dashboards.isEmpty {
                        dashboardButton(LovelaceDashboardReference(path: selectedDashboardPath, title: selectedDashboardPath))
                    } else {
                        ForEach(store.dashboards, id: \.path) { dashboard in
                            dashboardButton(dashboard)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .background(Color.secondary.opacity(0.06))
    }

    private func dashboardButton(_ dashboard: LovelaceDashboardReference) -> some View {
        Button {
            onSelectDashboard(dashboard)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected(dashboard) ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dashboard.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(dashboard.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected(dashboard) ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ dashboard: LovelaceDashboardReference) -> Bool {
        AppRoute.dashboardPath(dashboard.path) == AppRoute.dashboardPath(selectedDashboardPath)
    }
}
