import SwiftUI

public struct AdvancedSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var config = ConfigEngine.shared
    @ObservedObject var thermal = ThermalGovernor.shared

    let hardware = HardwareAutoTuner.shared.detectProfile()

    public var body: some View {
        NavigationView {
            ZStack {
                PocketTheme.bgDeep.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Section 1: Metal & Compute Tuning
                        computeSection

                        // Section 2: Sampling & Reasoning Presets
                        samplingSection

                        // Section 3: Thermal & Battery Strategy
                        thermalSection

                        // Section 4: Memory Eviction & Lock Policies
                        memorySection

                        // Section 5: Network & Port Gateway
                        networkSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Pro Tuning & Engine Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(PocketTheme.cyan)
                    .font(.system(size: 15, weight: .bold))
                }
            }
        }
    }

    // MARK: - Compute Section
    private var computeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("METAL GPU & THREAD ALLOCATION")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Spacer()
                Text("Rec: \(config.recommendedThreads)T")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PocketTheme.cyan.opacity(0.15))
                    .foregroundColor(PocketTheme.cyan)
                    .cornerRadius(4)
            }

            Stepper(value: $config.threadCount, in: 1...8) {
                HStack {
                    Text("Inference Threads:")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PocketTheme.textPrimary)
                    Text("\(config.threadCount) Threads")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.cyan)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prefill Micro-Batch (ubatch)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PocketTheme.textPrimary)

                Picker("Prefill Batch", selection: $config.prefillBatchSize) {
                    Text("128").tag(128)
                    Text("256 (Rec)").tag(256)
                    Text("512").tag(512)
                    Text("1024").tag(1024)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
        .padding(16)
        .fluidGlass(cornerRadius: 18)
    }

    // MARK: - Sampling Section
    private var samplingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SAMPLING & REASONING PRESETS")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(PocketTheme.textMuted)

            Picker("Preset", selection: $config.selectedPreset) {
                ForEach(SamplingPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: config.selectedPreset) { newPreset in
                config.applyPreset(newPreset)
            }

            VStack(spacing: 12) {
                HStack {
                    Text("Temperature: \(String(format: "%.2f", config.temperature))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(PocketTheme.textSecondary)
                    Spacer()
                }
                Slider(value: $config.temperature, in: 0.0...1.5, step: 0.05)
                    .accentColor(PocketTheme.cyan)

                HStack {
                    Text("Top-P: \(String(format: "%.2f", config.topP))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(PocketTheme.textSecondary)
                    Spacer()
                }
                Slider(value: $config.topP, in: 0.1...1.0, step: 0.05)
                    .accentColor(PocketTheme.purple)

                HStack {
                    Text("Reasoning Token Budget: \(config.reasoningBudgetTokens)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(PocketTheme.textSecondary)
                    Spacer()
                }
                Slider(value: Binding(
                    get: { Double(config.reasoningBudgetTokens) },
                    set: { config.reasoningBudgetTokens = Int($0) }
                ), in: 512...32768, step: 512)
                .accentColor(PocketTheme.emerald)
            }
        }
        .padding(16)
        .fluidGlass(cornerRadius: 18)
    }

    // MARK: - Thermal Section
    private var thermalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("THERMAL GOVERNOR STRATEGY")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(PocketTheme.textMuted)

            Picker("Thermal Profile", selection: $config.thermalProfile) {
                ForEach(ThermalProfile.allCases) { prof in
                    Text(prof.rawValue).tag(prof)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            Text("Current Thermal State: \(thermal.currentThermalTier.rawValue)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(thermal.isThrottled ? PocketTheme.amber : PocketTheme.emerald)
        }
        .padding(16)
        .fluidGlass(cornerRadius: 18)
    }

    // MARK: - Memory Section
    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MEMORY LOCKING & EVICTION")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(PocketTheme.textMuted)

            Toggle(isOn: $config.enableMemoryLock) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hardware Memory Lock (mlock)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PocketTheme.textPrimary)
                    Text("Pins weight pages in wired physical RAM")
                        .font(.system(size: 11))
                        .foregroundColor(PocketTheme.textSecondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: PocketTheme.cyan))

            Toggle(isOn: $config.enableDarwinBalloonPurge) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Darwin VM Balloon Eviction Pulse")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PocketTheme.textPrimary)
                    Text("Signals kernel to purge inactive background apps")
                        .font(.system(size: 11))
                        .foregroundColor(PocketTheme.textSecondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: PocketTheme.emerald))
        }
        .padding(16)
        .fluidGlass(cornerRadius: 18)
    }

    // MARK: - Network Section
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NETWORK & GATEWAY BINDING")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(PocketTheme.textMuted)

            HStack {
                Text("Port:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PocketTheme.textPrimary)
                Spacer()
                Text("\(config.serverPort)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(PocketTheme.cyan)
            }

            HStack {
                Text("mDNS Hostname:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PocketTheme.textPrimary)
                Spacer()
                Text("\(config.serverHostname).local")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(PocketTheme.purple)
            }
        }
        .padding(16)
        .fluidGlass(cornerRadius: 18)
    }
}
