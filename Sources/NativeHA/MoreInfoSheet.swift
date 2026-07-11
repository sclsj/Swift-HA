import NativeHACore
import SwiftUI

struct MoreInfoSheet: View {
    let entityID: EntityID
    var stateStore: HAStateStore?
    var registryStore: HARegistryStore?
    var onDismiss: () -> Void
    var onServiceCall: (HAServiceCall) async throws -> Void

    var body: some View {
        Group {
            if let stateStore = stateStore, let registryStore = registryStore {
                MoreInfoStoreReader(stateStore: stateStore, registryStore: registryStore) { displayContext in
                    MoreInfoSheetContent(
                        model: model(displayContext: displayContext),
                        onDismiss: onDismiss,
                        onServiceCall: onServiceCall
                    )
                }
            } else {
                MoreInfoSheetContent(
                    model: MoreInfoModel.build(entityID: entityID, states: [:]),
                    onDismiss: onDismiss,
                    onServiceCall: onServiceCall
                )
            }
        }
        .frame(minWidth: 360, idealWidth: 460, minHeight: 420)
    }

    private func model(displayContext: EntityDisplayContext) -> MoreInfoModel {
        MoreInfoModel.build(
            entityID: entityID,
            states: displayContext.states,
            registryEntries: displayContext.registryEntries,
            config: displayContext.config
        )
    }
}

private struct MoreInfoStoreReader<Content: View>: View {
    @ObservedObject var stateStore: HAStateStore
    @ObservedObject var registryStore: HARegistryStore
    let content: (EntityDisplayContext) -> Content

    init(
        stateStore: HAStateStore,
        registryStore: HARegistryStore,
        @ViewBuilder content: @escaping (EntityDisplayContext) -> Content
    ) {
        self.stateStore = stateStore
        self.registryStore = registryStore
        self.content = content
    }

    var body: some View {
        content(
            EntityDisplayContext(
                states: stateStore.states,
                config: stateStore.config,
                registryEntries: registryStore.entities
            )
        )
    }
}

private struct MoreInfoSheetContent: View {
    let model: MoreInfoModel
    var onDismiss: () -> Void
    var onServiceCall: (HAServiceCall) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: HAStyleTokens.space4) {
                    summarySection

                    if let climate = model.climate {
                        ClimateMoreInfoView(
                            model: climate,
                            onServiceCall: onServiceCall
                        )
                    }

                    attributesSection
                }
                .padding(HAStyleTokens.space4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            LovelaceIconView(
                entityID: model.entityID,
                icon: nil,
                color: nil,
                size: 22
            )
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.entityID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(HAStyleTokens.space4)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MoreInfoFieldRow(label: "State", value: model.stateDisplay)
            if let lastChanged = model.lastChangedDisplay {
                MoreInfoFieldRow(label: "Last changed", value: lastChanged)
            }
            if let lastUpdated = model.lastUpdatedDisplay {
                MoreInfoFieldRow(label: "Last updated", value: lastUpdated)
            }
            if model.isMissing {
                Text("This entity is not currently available in the state store.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if model.isUnavailable {
                Text("State is unknown or unavailable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var attributesSection: some View {
        if !model.attributes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Attributes")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.attributes) { attribute in
                        MoreInfoFieldRow(label: attribute.label, value: attribute.value)
                    }
                }
            }
        }
    }
}

private struct MoreInfoFieldRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
    }
}

private struct ClimateMoreInfoView: View {
    let model: ClimateControlModel
    var onServiceCall: (HAServiceCall) async throws -> Void

    @State private var serviceError: String?
    @State private var isSending = false
    @State private var localTarget: Double?
    @State private var debounceTask: Task<Void, Never>?

    private var currentTarget: Double {
        localTarget ?? model.targetTemperature ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Climate")
                .font(.headline)

            climateReadouts

            if model.supportsTargetTemperature, let target = model.targetTemperature {
                temperatureControls(target: target)
            }

            selectionControls

            if let serviceError = serviceError {
                Text(serviceError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(HAStyleTokens.space4)
        .background(HAStyleTokens.cardBorderColor.opacity(0.20))
        .cornerRadius(HAStyleTokens.space2)
    }

    private var climateReadouts: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let currentTemperature = model.currentTemperatureDisplay {
                MoreInfoFieldRow(label: "Current temp", value: currentTemperature)
            }
            if let targetTemperature = model.targetTemperatureDisplay {
                MoreInfoFieldRow(label: "Target temp", value: targetTemperature)
            }
            if let currentHumidity = model.currentHumidityDisplay {
                MoreInfoFieldRow(label: "Current humidity", value: currentHumidity)
            }
            MoreInfoFieldRow(label: "HVAC mode", value: model.hvacMode)
            if let hvacAction = model.hvacAction {
                MoreInfoFieldRow(label: "Action", value: hvacAction)
            }
        }
    }

    private func temperatureControls(target: Double) -> some View {
        HStack(spacing: 10) {
            Button {
                adjustTemperature(delta: -model.targetTemperatureStep)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(model.isUnavailable)

            let displayValue = localTarget != nil
                ? HANumberFormatting.format(currentTarget)
                : (model.targetTemperatureDisplay ?? HANumberFormatting.format(currentTarget))

            Text(displayValue)
                .font(.title3.monospacedDigit())
                .frame(maxWidth: .infinity)

            Button {
                adjustTemperature(delta: model.targetTemperatureStep)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(model.isUnavailable)
        }
    }

    private func adjustTemperature(delta: Double) {
        let base = localTarget ?? model.targetTemperature ?? 0
        let next = model.steppedTemperature(base + delta)
        localTarget = next
        
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else { return }
                
                if let call = model.setTemperatureCall(next) {
                    await send(call)
                }
                
                localTarget = nil
            } catch {
                // Task cancelled
            }
        }
    }

    private var selectionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.hvacModes.isEmpty {
                ClimateModeMenu(
                    title: "HVAC mode",
                    current: model.hvacMode,
                    options: model.hvacModes,
                    disabled: model.isUnavailable || isSending,
                    callForOption: model.setHVACModeCall,
                    onSelect: send
                )
            }
            if !model.presetModes.isEmpty {
                ClimateModeMenu(
                    title: "Preset",
                    current: model.presetMode,
                    options: model.presetModes,
                    disabled: model.isUnavailable || isSending,
                    callForOption: model.setPresetModeCall,
                    onSelect: send
                )
            }
            if !model.fanModes.isEmpty {
                ClimateModeMenu(
                    title: "Fan",
                    current: model.fanMode,
                    options: model.fanModes,
                    disabled: model.isUnavailable || isSending,
                    callForOption: model.setFanModeCall,
                    onSelect: send
                )
            }
            if !model.swingModes.isEmpty {
                ClimateModeMenu(
                    title: "Swing",
                    current: model.swingMode,
                    options: model.swingModes,
                    disabled: model.isUnavailable || isSending,
                    callForOption: model.setSwingModeCall,
                    onSelect: send
                )
            }
            if !model.swingHorizontalModes.isEmpty {
                ClimateModeMenu(
                    title: "Horizontal swing",
                    current: model.swingHorizontalMode,
                    options: model.swingHorizontalModes,
                    disabled: model.isUnavailable || isSending,
                    callForOption: model.setSwingHorizontalModeCall,
                    onSelect: send
                )
            }
        }
    }

    private func send(_ call: HAServiceCall?) {
        guard let call = call else {
            return
        }
        serviceError = nil
        isSending = true

        Task {
            let result = await HAServiceCallExecution.execute(call, executor: onServiceCall)
            await MainActor.run {
                isSending = false
                if result == .failed {
                    serviceError = "Service call failed."
                }
            }
        }
    }
}

private struct ClimateModeMenu: View {
    var title: String
    var current: String?
    var options: [String]
    var disabled: Bool
    var callForOption: (String) -> HAServiceCall?
    var onSelect: (HAServiceCall?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        onSelect(callForOption(option))
                    } label: {
                        HStack {
                            Text(option)
                            if option == current {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(disabled || option == current)
                }
            } label: {
                HStack {
                    Text(current ?? "Select")
                    Image(systemName: "chevron.down")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(disabled)
        }
        .font(.subheadline)
    }
}
