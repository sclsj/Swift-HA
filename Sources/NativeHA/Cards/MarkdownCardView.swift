import NativeHACore
import SwiftUI

struct MarkdownCardView: View {
    let config: MarkdownCardConfig
    var templateSubscriber: MarkdownTemplateSubscribing?
    var userName: String = "Home Assistant"
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }

    @State private var renderedContent: String = ""
    @State private var hasRenderedTemplate = false
    @State private var templateError: MarkdownTemplateError?
    @State private var subscription: MarkdownTemplateSubscription?

    var body: some View {
        let content = displayContent

        Group {
            if config.showEmpty == false && content.isEmpty && templateError == nil {
                EmptyView()
            } else if config.textOnly == true {
                markdownContent(content)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
            } else {
                CardChrome {
                    VStack(alignment: .leading, spacing: 10) {
                        if let title = config.title, !title.isEmpty {
                            Text(title)
                                .font(.headline)
                                .lineLimit(2)
                        }

                        if let templateError = templateError {
                            templateErrorView(templateError)
                        }

                        markdownContent(content)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            performTap()
        }
        .task(id: subscriptionID) {
            await subscribeIfNeeded()
        }
        .onDisappear {
            subscription?.cancel()
            subscription = nil
        }
    }

    private var displayContent: String {
        hasRenderedTemplate || templateError != nil ? renderedContent : (config.content ?? "")
    }

    private var subscriptionID: String {
        [
            config.content ?? "",
            config.entityIDs?.joined(separator: ",") ?? "",
            userName
        ].joined(separator: "|")
    }

    private func markdownContent(_ content: String) -> some View {
        Text(content)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func templateErrorView(_ error: MarkdownTemplateError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: error.level == "WARNING" ? "exclamationmark.triangle" : "xmark.octagon")
                .foregroundColor(error.level == "WARNING" ? .orange : .red)
            Text(error.error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    private func performTap() {
        guard config.tapAction != nil || config.holdAction != nil || config.doubleTapAction != nil else {
            return
        }

        CardActionDispatcher(
            entityID: config.entityIDs?.first,
            states: [:],
            onMoreInfo: onMoreInfo,
            onServiceCall: onServiceCall
        )
        .perform(
            tapAction: config.tapAction,
            holdAction: config.holdAction,
            doubleTapAction: config.doubleTapAction
        )
    }

    private func subscribeIfNeeded() async {
        subscription?.cancel()
        subscription = nil
        templateError = nil
        hasRenderedTemplate = false

        guard let content = config.content, !content.isEmpty else {
            renderedContent = ""
            hasRenderedTemplate = true
            return
        }

        guard let templateSubscriber = templateSubscriber else {
            renderedContent = content
            hasRenderedTemplate = true
            return
        }

        let request = MarkdownTemplateRequest(
            template: content,
            entityIDs: config.entityIDs,
            variables: [
                "config": config.raw,
                "user": .string(userName)
            ],
            strict: true,
            reportErrors: false
        )

        do {
            let token = try await templateSubscriber.subscribeRenderTemplate(request) { event in
                DispatchQueue.main.async {
                    switch event {
                    case let .rendered(result):
                        templateError = nil
                        renderedContent = result.result
                        hasRenderedTemplate = true
                    case let .error(error):
                        if error.level == "ERROR" || templateError?.level != "ERROR" {
                            templateError = error
                        }
                    }
                }
            }
            subscription = token
        } catch {
            templateError = MarkdownTemplateError(error: String(describing: error))
            renderedContent = content
            hasRenderedTemplate = true
        }
    }
}
