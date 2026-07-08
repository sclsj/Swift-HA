import NativeHACore
import SwiftUI

struct LovelaceViewHost: View {
    let state: LovelaceStoreState
    let displayContext: EntityDisplayContext
    var templateSubscriber: MarkdownTemplateSubscribing?
    var userName: String = "Home Assistant"
    let onSelectView: (LovelaceViewRoute) -> Void
    let onRetry: () -> Void
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }

    private let router = LovelaceRouter()

    var body: some View {
        Group {
            switch state {
            case .idle:
                placeholder(title: "Dashboard", subtitle: "Select a dashboard")
            case let .loading(dashboardPath):
                VStack(spacing: 12) {
                    ProgressView()
                    Text(dashboardPath)
                        .font(.headline)
                    Text("Loading")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .error(error):
                VStack(alignment: .leading, spacing: 12) {
                    Text(error.dashboardPath)
                        .font(.title2)
                    Text(error.message)
                        .foregroundColor(.secondary)
                    Button("Reload", action: onRetry)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case let .loaded(content):
                loadedView(content)
            case let .generatedStrategyPlaceholder(placeholder):
                strategyView(placeholder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadedView(_ content: LovelaceDashboardContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            viewTabs(content)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(content.selectedView?.title ?? content.selectedRoute.routeComponent ?? "View")
                                .font(.title2)
                            Text(content.dashboardPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(layoutTitle(content.selectedView?.layout))
                            .font(.caption)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                    }

                    layoutContent(content)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func viewTabs(_ content: LovelaceDashboardContent) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(content.config.views.enumerated()), id: \.offset) { index, view in
                    if router.isVisible(view) {
                        Button {
                            let route = router.route(
                                dashboardPath: content.dashboardPath,
                                config: content.config,
                                requestedViewPath: view.path,
                                requestedViewIndex: view.path == nil ? index : nil
                            )
                            onSelectView(route)
                        } label: {
                            Text(viewTitle(view, index: index))
                                .font(.subheadline)
                                .lineLimit(1)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(index == content.selectedRoute.selectedViewIndex ? Color.accentColor.opacity(0.16) : Color.clear)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func layoutContent(_ content: LovelaceDashboardContent) -> some View {
        if let view = content.selectedView {
            badges(view.badges)

            switch view.layout {
            case .masonry:
                MasonryLayoutView(
                    cards: view.cards,
                    displayContext: displayContext,
                    templateSubscriber: templateSubscriber,
                    userName: userName,
                    onMoreInfo: onMoreInfo,
                    onServiceCall: onServiceCall
                )
            case .sections:
                SectionsLayoutView(
                    view: view,
                    displayContext: displayContext,
                    templateSubscriber: templateSubscriber,
                    userName: userName,
                    onMoreInfo: onMoreInfo,
                    onServiceCall: onServiceCall
                )
            case .panel:
                PanelLayoutView(
                    view: view,
                    displayContext: displayContext,
                    layout: .panel,
                    templateSubscriber: templateSubscriber,
                    userName: userName,
                    onMoreInfo: onMoreInfo,
                    onServiceCall: onServiceCall
                )
            case .sidebar:
                PanelLayoutView(
                    view: view,
                    displayContext: displayContext,
                    layout: .sidebar,
                    templateSubscriber: templateSubscriber,
                    userName: userName,
                    onMoreInfo: onMoreInfo,
                    onServiceCall: onServiceCall
                )
            case let .custom(type):
                VStack(alignment: .leading, spacing: 12) {
                    ErrorCardView(
                        title: "Unsupported Lovelace view",
                        message: "Native layout fallback for view type: \(type)",
                        rawSummary: nil
                    )
                    MasonryLayoutView(
                        cards: view.cards,
                        displayContext: displayContext,
                        templateSubscriber: templateSubscriber,
                        userName: userName,
                        onMoreInfo: onMoreInfo,
                        onServiceCall: onServiceCall
                    )
                }
            }
        } else {
            EmptyDashboardLayoutView(message: "No selected view")
        }
    }

    @ViewBuilder
    private func badges(_ badges: [LovelaceBadgeConfig]) -> some View {
        if !badges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                        BadgeHostView(
                            badge: badge,
                            displayContext: displayContext,
                            onMoreInfo: onMoreInfo,
                            onServiceCall: onServiceCall
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func strategyView(_ placeholder: LovelaceStrategyPlaceholder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(placeholder.dashboardPath)
                .font(.title2)
            summaryRow(label: "Strategy", value: placeholder.strategy.type.isEmpty ? "unknown" : placeholder.strategy.type)
            Text("Generated dashboard placeholder")
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func placeholder(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
            Text(subtitle)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func viewTitle(_ view: LovelaceViewConfig, index: Int) -> String {
        if let title = view.title, !title.isEmpty {
            return title
        }
        if let path = view.path, !path.isEmpty {
            return path
        }
        return "View \(index)"
    }

    private func layoutTitle(_ layout: LovelaceViewLayout?) -> String {
        guard let layout = layout else {
            return "No view"
        }

        switch layout {
        case .masonry:
            return "Masonry"
        case .sections:
            return "Sections"
        case .panel:
            return "Panel"
        case .sidebar:
            return "Sidebar"
        case let .custom(type):
            return type
        }
    }
}
