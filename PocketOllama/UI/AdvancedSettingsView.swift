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
                    VStack(spacing: 12) {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Engine Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(PocketTheme.devCyan)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
            }
        }
    }

    // MARK: - Compute Section
    private var computeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("METAL GPU & NEURAL ENGINE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Spacer()
                Text("ANE: \(String(format: "%.0f", hardware.aneTOPS)) TOPS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(PocketTheme.terminalGreen.opacity(0.15))
                    .foregroundColor(PocketTheme.terminalGreen)
                    .cornerRadius(4)
                Text("P-Cores: \(config.recommendedThreads)T")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(PocketTheme.devCyan.opacity(0.15))
                    .foregroundColor(PocketTheme.devCyan)
                    .cornerRadius(4)
            }

            Stepper(value: $config.threadCount, in: 1...8) {
                HStack {
                    Text("Inference Threads:")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(PocketTheme.textPrimary)
                    Text("\(config.threadCount) P-Cores")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.devCyan)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prefill Micro-Batch Size (ubatch)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
        .padding(12)
        .devCard(cornerRadius: 8)
    }

    // MARK: - Sampling Section
    private var samplingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAMPLING & REASONING PRESETS")
                .font(.system(size: 9, weight: .black, design: .monospaced))
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

            VStack(spacing: 8) {
                HStack {
                    Text("Temperature: \(String(format: "%.2f", config.temperature))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(PocketTheme.textSecondary)
                    Spacer()
                }
                Slider(value: $config.temperature, in: 0.0...1.5, step: 0.05)
                    .accentColor(PocketTheme.devCyan)

                HStack {
                    Text("Top-P: \(String(format: "%.2f", config.topP))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(PocketTheme.textSecondary)
                    Spacer()
                }
                Slider(value: $config.topP, in: 0.1...1.0, step: 0.05)
                    .accentColor(PocketTheme.devIndigo)

                HStack {
                    Text("Reasoning Token Budget: \(config.reasoningBudgetTokens)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(PocketTheme.textSecondary)
                    Spacer()
                }
                Slider(value: Binding(
                    get: { Double(config.reasoningBudgetTokens) },
                    set: { config.reasoningBudgetTokens = Int($0) }
                ), in: 512...32768, step: 512)
                .accentColor(PocketTheme.terminalGreen)
            }
        }
        .padding(12)
        .devCard(cornerRadius: 8)
    }

    // MARK: - Thermal Section
    private var thermalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THERMAL MANAGEMENT STRATEGY")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(PocketTheme.textMuted)

            Picker("Thermal Profile", selection: $config.thermalProfile) {
                ForEach(ThermalProfile.allCases) { prof in
                    Text(prof.rawValue).tag(prof)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            Text("Current Thermal State: \(thermal.currentThermalTier.rawValue.uppercased())")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(thermal.isThrottled ? PocketTheme.amberWarning : PocketTheme.terminalGreen)
        }
        .padding(12)
        .devCard(cornerRadius: 8)
    }

    // MARK: - Memory Section
    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WIRED MEMORY & EVICTION CONTROLS")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(PocketTheme.textMuted)

            Toggle(isOn: $config.enableMemoryLock) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hardware Memory Lock (mlock)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(PocketTheme.textPrimary)
                    Text("Locks model tensor pages in wired physical RAM")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(PocketTheme.textSecondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: PocketTheme.devCyan))

            Toggle(isOn: $config.enableDarwinBalloonPurge) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Darwin VM Balloon Eviction")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(PocketTheme.textPrimary)
                    Text("Forces OS to compress inactive background app caches")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(PocketTheme.textSecondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: PocketTheme.terminalGreen))
        }
        .padding(12)
        .devCard(cornerRadius: 8)
    }

    // MARK: - Network Section
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NETWORK & GATEWAY BINDING")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(PocketTheme.textMuted)

            HStack {
                Text("Default Port:")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(PocketTheme.textPrimary)
                Spacer()
                Text("\(config.serverPort)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(PocketTheme.devCyan)
            }

            HStack {
                Text("mDNS Hostname:")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(PocketTheme.textPrimary)
                Spacer()
                Text("\(config.serverHostname).local")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(PocketTheme.devIndigo)
            }
        }
        .padding(12)
        .devCard(cornerRadius: 8)
    }
}
