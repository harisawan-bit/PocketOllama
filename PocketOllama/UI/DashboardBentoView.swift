import SwiftUI

public struct DashboardBentoView: View {
    @ObservedObject var server = LLMServer.shared
    @ObservedObject var telemetry = TelemetryManager.shared
    @ObservedObject var thermal = ThermalGovernor.shared
    
    @State private var showingNightstand = false
    @State private var contextSliderValue: Double = 8192
    @State private var selectedKVQuant: String = "q4_0"

    let hardware = HardwareAutoTuner.shared.detectProfile()

    public var body: some View {
        ZStack {
            PocketTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // 1. Dynamic Island Status Hero
                    heroStatusIsland

                    // 2. Server Connection Card
                    serverConnectionCard

                    // 3. Hardware & Telemetry Bento Grid
                    telemetryBentoGrid

                    // 4. Context & KV Cache Allocation
                    contextAllocationCard

                    // 5. Overnight Insomnia Nightstand Launcher
                    insomniaCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .fullScreenCover(isPresented: $showingNightstand) {
            InsomniaOvernightView(isPresented: $showingNightstand)
        }
        .onAppear {
            contextSliderValue = Double(hardware.maxSafeContextTokens)
            selectedKVQuant = hardware.defaultKVQuant
        }
    }

    // MARK: - Hero Status Island
    private var heroStatusIsland: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(server.isRunning ? PocketTheme.emerald.opacity(0.2) : PocketTheme.rose.opacity(0.2))
                    .frame(width: 48, height: 48)
                Circle()
                    .fill(server.isRunning ? PocketTheme.emerald : PocketTheme.rose)
                    .frame(width: 14, height: 14)
                    .shadow(color: server.isRunning ? PocketTheme.emerald : PocketTheme.rose, radius: 8)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(server.isRunning ? "SERVER ONLINE" : "SERVER OFFLINE")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(server.isRunning ? PocketTheme.emerald : PocketTheme.rose)
                    Spacer()
                    Text(hardware.socName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(PocketTheme.cyan.opacity(0.15))
                        .foregroundColor(PocketTheme.cyan)
                        .cornerRadius(6)
                }

                Text(hardware.marketingName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(PocketTheme.textPrimary)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 22, borderColor: server.isRunning ? PocketTheme.emerald.opacity(0.3) : PocketTheme.borderGlass)
    }

    // MARK: - Server Connection Card
    private var serverConnectionCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API GATEWAY (OPENAI COMPATIBLE)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.textMuted)
                    
                    if server.isRunning {
                        Text("http://\(server.localIPAddress):\(server.boundPort)/v1")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundColor(PocketTheme.cyan)
                    } else {
                        Text("Ready to start on Wi-Fi")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(PocketTheme.textSecondary)
                    }
                }
                Spacer()

                if server.isRunning {
                    Button(action: {
                        UIPasteboard.general.string = "http://\(server.localIPAddress):\(server.boundPort)/v1"
                    }) {
                        Image(systemName: "doc.on.doc.fill")
                            .foregroundColor(PocketTheme.cyan)
                            .padding(10)
                            .background(PocketTheme.cyan.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
            }

            Button(action: {
                withAnimation(.spring()) {
                    if server.isRunning {
                        server.stop()
                        UIApplication.shared.isIdleTimerDisabled = false
                    } else {
                        server.start()
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: server.isRunning ? "power.circle.fill" : "bolt.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text(server.isRunning ? "Stop AI Server" : "Start Local AI Server")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(server.isRunning ? PocketTheme.rose : PocketTheme.cyanPurpleGradient)
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: server.isRunning ? PocketTheme.rose.opacity(0.4) : PocketTheme.cyan.opacity(0.3), radius: 12)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    // MARK: - Telemetry Grid
    private var telemetryBentoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            // Speedometer
            VStack(alignment: .leading, spacing: 6) {
                Text("INFERENCE SPEED")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", telemetry.tokensPerSecond))
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(PocketTheme.cyan)
                    Text("t/s")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(PocketTheme.textMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18)

            // RAM Pressure
            VStack(alignment: .leading, spacing: 6) {
                Text("UNIFIED RAM")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", telemetry.ramAvailableMB))
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(PocketTheme.emerald)
                    Text("MB Free")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PocketTheme.textMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18)

            // Thermal State
            VStack(alignment: .leading, spacing: 6) {
                Text("THERMAL GOVERNOR")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Text(thermal.currentThermalTier.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(thermal.isThrottled ? PocketTheme.amber : PocketTheme.emerald)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18)

            // Active Threads
            VStack(alignment: .leading, spacing: 6) {
                Text("METAL THREADS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Text("\(thermal.activeThreadCount) Threads Active")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(PocketTheme.purple)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18)
        }
    }

    // MARK: - Context Allocation
    private var contextAllocationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CONTEXT WINDOW BUDGET")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Spacer()
                Text("\(Int(contextSliderValue)) Tokens")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(PocketTheme.cyan)
            }

            Slider(value: $contextSliderValue, in: 2048...Double(hardware.maxSafeContextTokens), step: 1024)
                .accentColor(PocketTheme.cyan)

            HStack {
                Text("Safe Ceiling: \(hardware.maxSafeContextTokens) tokens")
                    .font(.system(size: 11))
                    .foregroundColor(PocketTheme.textSecondary)
                Spacer()
                Text("KV: \(selectedKVQuant)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(PocketTheme.purple.opacity(0.2))
                    .foregroundColor(PocketTheme.purple)
                    .cornerRadius(4)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    // MARK: - Insomnia Overnight Card
    private var insomniaCard: some View {
        Button(action: {
            showingNightstand = true
        }) {
            HStack(spacing: 16) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 26))
                    .foregroundColor(PocketTheme.amber)
                    .padding(12)
                    .background(PocketTheme.amber.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Enter Insomnia Nightstand Mode")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(PocketTheme.textPrimary)
                    Text("0% OLED power, protects screen & runs all night")
                        .font(.system(size: 12))
                        .foregroundColor(PocketTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(PocketTheme.textMuted)
            }
            .padding(16)
            .glassCard(cornerRadius: 22)
        }
    }
}
