import SwiftUI

public struct DashboardBentoView: View {
    @ObservedObject var server = LLMServer.shared
    @ObservedObject var telemetry = TelemetryManager.shared
    @ObservedObject var thermal = ThermalGovernor.shared
    @ObservedObject var config = ConfigEngine.shared

    @State private var showingNightstand = false
    @State private var showingSettings = false
    @State private var copyToast = false

    let hardware = HardwareAutoTuner.shared.detectProfile()

    public var body: some View {
        ZStack {
            PocketTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. Hero Dynamic Island Header
                    heroStatusIsland

                    // 2. Server Connection Gateway Card
                    serverConnectionCard

                    // 3. Telemetry Bento Grid
                    telemetryBentoGrid

                    // 4. Dynamic Model-Aware Context Window & KV Quant Card
                    dynamicContextCard

                    // 5. Actions: Pro Settings & Insomnia Mode
                    actionsRow
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .fullScreenCover(isPresented: $showingNightstand) {
            InsomniaOvernightView(isPresented: $showingNightstand)
        }
        .sheet(isPresented: $showingSettings) {
            AdvancedSettingsView()
        }
    }

    // MARK: - Hero Dynamic Island
    private var heroStatusIsland: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(server.isRunning ? PocketTheme.emerald.opacity(0.15) : PocketTheme.rose.opacity(0.15))
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(server.isRunning ? PocketTheme.emerald : PocketTheme.rose)
                    .frame(width: 12, height: 12)
                    .shadow(color: server.isRunning ? PocketTheme.emerald : PocketTheme.rose, radius: 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(server.isRunning ? "SERVER ONLINE" : "SERVER OFFLINE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(server.isRunning ? PocketTheme.emerald : PocketTheme.rose)
                    Spacer()
                    Text(hardware.socName)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(PocketTheme.cyan.opacity(0.15))
                        .foregroundColor(PocketTheme.cyan)
                        .cornerRadius(5)
                }

                Text(hardware.marketingName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(PocketTheme.textPrimary)
            }
        }
        .padding(14)
        .fluidGlass(cornerRadius: 18, borderColor: server.isRunning ? PocketTheme.emerald.opacity(0.25) : PocketTheme.borderGlass)
    }

    // MARK: - Server Gateway Card
    private var serverConnectionCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("API ENDPOINT")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(PocketTheme.textMuted)

                    if server.isRunning {
                        Text("http://\(server.localIPAddress):\(server.boundPort)/v1")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(PocketTheme.cyan)
                    } else {
                        Text("Ready to start server")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(PocketTheme.textSecondary)
                    }
                }
                Spacer()

                if server.isRunning {
                    Button(action: {
                        UIPasteboard.general.string = "http://\(server.localIPAddress):\(server.boundPort)/v1"
                        copyToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copyToast = false }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: copyToast ? "checkmark" : "doc.on.doc")
                            Text(copyToast ? "Copied" : "Copy IP")
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PocketTheme.cyan.opacity(0.15))
                        .foregroundColor(PocketTheme.cyan)
                        .cornerRadius(8)
                    }
                }
            }

            Button(action: {
                withAnimation(.spring()) {
                    if server.isRunning {
                        server.stop()
                        UIApplication.shared.isIdleTimerDisabled = false
                    } else {
                        server.start(preferredPort: config.serverPort)
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: server.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .black))
                    Text(server.isRunning ? "Stop Server" : "Start Local AI Server")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(server.isRunning ? PocketTheme.roseGradient : PocketTheme.cyanPurpleGradient)
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: server.isRunning ? PocketTheme.rose.opacity(0.3) : PocketTheme.cyan.opacity(0.25), radius: 8)
            }
        }
        .padding(14)
        .fluidGlass(cornerRadius: 18)
    }

    // MARK: - Telemetry Bento Grid
    private var telemetryBentoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Speedometer
            VStack(alignment: .leading, spacing: 4) {
                Text("GENERATION SPEED")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", telemetry.tokensPerSecond))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(PocketTheme.cyan)
                    Text("t/s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.textMuted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fluidGlass(cornerRadius: 16)

            // RAM Pressure
            VStack(alignment: .leading, spacing: 4) {
                Text("UNIFIED RAM FREE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.0f", telemetry.ramAvailableMB))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(PocketTheme.emerald)
                    Text("MB")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.textMuted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fluidGlass(cornerRadius: 16)

            // Thermal State
            VStack(alignment: .leading, spacing: 4) {
                Text("THERMAL GOVERNOR")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Text(thermal.currentThermalTier.rawValue)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(thermal.isThrottled ? PocketTheme.amber : PocketTheme.emerald)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fluidGlass(cornerRadius: 16)

            // Active Threads
            VStack(alignment: .leading, spacing: 4) {
                Text("METAL THREADS")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Text("\(thermal.activeThreadCount) Threads Active")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(PocketTheme.purple)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fluidGlass(cornerRadius: 16)
        }
    }

    // MARK: - Dynamic Model-Aware Context Window Card
    private var dynamicContextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DYNAMIC CONTEXT WINDOW")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(PocketTheme.textMuted)
                    Text("\(config.contextWindowTokens) Tokens")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(PocketTheme.cyan)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Safe Max: \(config.maxSafeContextTokens)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.emerald)
                    Text("KV RAM: ~\(Int(config.estimatedKVRAMMB)) MB")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(PocketTheme.textMuted)
                }
            }

            // Dynamic Slider scaling up to 262,144 tokens
            Slider(
                value: Binding(
                    get: { Double(config.contextWindowTokens) },
                    set: { config.contextWindowTokens = Int($0) }
                ),
                in: 2048...Double(max(2048, config.maxSafeContextTokens)),
                step: 1024
            )
            .accentColor(PocketTheme.cyan)

            HStack {
                Text("KV Cache Quant:")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PocketTheme.textSecondary)
                Spacer()
                Picker("KV Quant", selection: $config.kvQuantization) {
                    Text("Q4_0 (Rec)").tag("q4_0")
                    Text("Q8_0").tag("q8_0")
                    Text("FP16").tag("f16")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(maxWidth: 200)
            }
        }
        .padding(14)
        .fluidGlass(cornerRadius: 18)
    }

    // MARK: - Actions Row
    private var actionsRow: some View {
        HStack(spacing: 12) {
            // Pro Tuning Button
            Button(action: {
                showingSettings = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Pro Tuning")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(PocketTheme.bgCardHover)
                .foregroundColor(PocketTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PocketTheme.borderGlass, lineWidth: 0.75)
                )
            }

            // Insomnia Nightstand Button
            Button(action: {
                showingNightstand = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .foregroundColor(PocketTheme.amber)
                    Text("Insomnia Mode")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(PocketTheme.bgCardHover)
                .foregroundColor(PocketTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PocketTheme.borderGlass, lineWidth: 0.75)
                )
            }
        }
    }
}
