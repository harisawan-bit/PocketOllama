import SwiftUI

public struct DashboardBentoView: View {
    @ObservedObject var server = LLMServer.shared
    @ObservedObject var telemetry = TelemetryManager.shared
    @ObservedObject var thermal = ThermalGovernor.shared
    @ObservedObject var config = ConfigEngine.shared
    @ObservedObject var logger = RequestLogger.shared
    @ObservedObject var benchmark = BenchmarkEngine.shared

    @State private var showingNightstand = false
    @State private var showingSettings = false
    @State private var showingQRConnect = false
    @State private var copyNotification: String? = nil

    let hardware = HardwareAutoTuner.shared.detectProfile()

    public var body: some View {
        ZStack {
            PocketTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Top System Status Bar
                    topSystemBar

                    // Gateway Endpoint Card & Quick Copy Actions
                    gatewayCard

                    // High-Precision Telemetry Grid
                    telemetryGrid

                    // Active Model & Context Allocation HUD
                    modelContextHUD

                    // On-Device Diagnostic Benchmark HUD
                    benchmarkHUD

                    // Live HTTP Server Console
                    liveConsoleCard

                    // Pro Controls & Insomnia Triggers
                    bottomActionRow
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
        }
        .fullScreenCover(isPresented: $showingNightstand) {
            InsomniaOvernightView(isPresented: $showingNightstand)
        }
        .sheet(isPresented: $showingSettings) {
            AdvancedSettingsView()
        }
        .sheet(isPresented: $showingQRConnect) {
            QRConnectSheet(endpointURL: server.apiEndpointURL, hostname: config.serverHostname)
        }
    }

    // MARK: - Top System Status Bar
    private var topSystemBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(server.isRunning ? PocketTheme.terminalGreen : PocketTheme.roseAlert)
                    .frame(width: 8, height: 8)
                Text(server.isRunning ? "LISTENING" : "STOPPED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(server.isRunning ? PocketTheme.terminalGreen : PocketTheme.roseAlert)
            }

            Spacer()

            Text("\(hardware.socName) • \(String(format: "%.0f", hardware.totalRAMGB))GB • \(String(format: "%.0f", hardware.aneTOPS)) TOPS ANE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(PocketTheme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .devCard(cornerRadius: 8)
    }

    // MARK: - Gateway Endpoint Card
    private var gatewayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("API GATEWAY // HTTP & WEB CONSOLE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Spacer()
                if let notif = copyNotification {
                    Text(notif)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.terminalGreen)
                }
            }

            Text(server.apiEndpointURL)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(PocketTheme.devCyan)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Quick Copy & QR Strip
            HStack(spacing: 8) {
                quickActionButton(label: "QR Connect", icon: "qrcode") {
                    showingQRConnect = true
                }
                quickActionButton(label: "Copy URL", icon: "doc.on.doc") {
                    copyToClipboard(text: server.apiEndpointURL, label: "URL")
                }
                quickActionButton(label: "Copy cURL", icon: "terminal") {
                    copyToClipboard(text: "curl \(server.apiEndpointURL)/models", label: "cURL")
                }
            }

            // Server Start / Stop Toggle Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
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
                        .font(.system(size: 12, weight: .black))
                    Text(server.isRunning ? "Stop AI Server" : "Start Local Server (Port \(config.serverPort))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(server.isRunning ? PocketTheme.roseAlert.opacity(0.15) : PocketTheme.terminalGreen.opacity(0.15))
                .foregroundColor(server.isRunning ? PocketTheme.roseAlert : PocketTheme.terminalGreen)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(server.isRunning ? PocketTheme.roseAlert.opacity(0.4) : PocketTheme.terminalGreen.opacity(0.4), lineWidth: 1)
                )
            }
        }
        .padding(12)
        .devCard(cornerRadius: 10)
    }

    private func quickActionButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(PocketTheme.bgSurfaceHover)
            .foregroundColor(PocketTheme.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(PocketTheme.borderSubtle, lineWidth: 1)
            )
        }
    }

    private func copyToClipboard(text: String, label: String) {
        UIPasteboard.general.string = text
        copyNotification = "Copied \(label)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyNotification = nil }
    }

    // MARK: - Telemetry Grid
    private var telemetryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            telemetryCell(label: "DECODE THROUGHPUT", value: String(format: "%.1f tok/s", telemetry.tokensPerSecond), accent: PocketTheme.devCyan)
            telemetryCell(label: "FREE PROCESS RAM", value: String(format: "%.0f MB", telemetry.ramAvailableMB), accent: PocketTheme.terminalGreen)
            telemetryCell(label: "THERMAL STATE", value: thermal.currentThermalTier.rawValue.uppercased(), accent: thermal.isThrottled ? PocketTheme.amberWarning : PocketTheme.terminalGreen)
            telemetryCell(label: "ACTIVE THREADS", value: "\(thermal.activeThreadCount) P-Cores Active", accent: PocketTheme.textPrimary)
        }
    }

    private func telemetryCell(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(PocketTheme.textMuted)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(accent)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .devCard(cornerRadius: 8)
    }

    // MARK: - Active Model & Context Allocation HUD
    private var modelContextHUD: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CONTEXT ALLOCATION")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Spacer()
                Text("\(config.contextWindowTokens) Tokens")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(PocketTheme.devCyan)
            }

            Slider(
                value: Binding(
                    get: { Double(config.contextWindowTokens) },
                    set: { config.contextWindowTokens = Int($0) }
                ),
                in: 2048...Double(max(2048, config.maxSafeContextTokens)),
                step: 1024
            )
            .accentColor(PocketTheme.devCyan)

            HStack {
                Text("Safe Max: \(config.maxSafeContextTokens) tokens")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(PocketTheme.textSecondary)
                Spacer()
                Text("Est. KV RAM: ~\(Int(config.estimatedKVRAMMB)) MB")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
            }
        }
        .padding(12)
        .devCard(cornerRadius: 10)
    }

    // MARK: - On-Device Diagnostic Benchmark HUD
    private var benchmarkHUD: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ON-DEVICE HARDWARE BENCHMARK")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Spacer()

                Button(action: {
                    Task {
                        _ = await benchmark.runBenchmark()
                    }
                }) {
                    HStack(spacing: 4) {
                        if benchmark.isRunning {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(PocketTheme.devCyan)
                        } else {
                            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        }
                        Text(benchmark.isRunning ? "Testing..." : "Run Test")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PocketTheme.devCyan.opacity(0.12))
                    .foregroundColor(PocketTheme.devCyan)
                    .cornerRadius(4)
                }
                .disabled(benchmark.isRunning)
            }

            if let res = benchmark.lastResult {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TTFT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(PocketTheme.textMuted)
                        Text(String(format: "%.0f ms", res.ttftMs))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(PocketTheme.devCyan)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("THROUGHPUT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(PocketTheme.textMuted)
                        Text(String(format: "%.1f tok/s", res.tokensPerSecond))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(PocketTheme.terminalGreen)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SOC RATING")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(PocketTheme.textMuted)
                        Text(res.socName)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(PocketTheme.textPrimary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .devCard(cornerRadius: 10)
    }

    // MARK: - Live HTTP Server Console
    private var liveConsoleCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LIVE HTTP REQUEST LOG")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Spacer()
                if !logger.recentLogs.isEmpty {
                    Button("Clear") {
                        logger.clear()
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                }
            }

            if logger.recentLogs.isEmpty {
                Text("Waiting for requests from client or playground...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logger.recentLogs.prefix(5)) { entry in
                        HStack(spacing: 6) {
                            Text(entry.formattedTime)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(PocketTheme.textMuted)
                            Text(entry.method)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(PocketTheme.devCyan)
                            Text(entry.path)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(PocketTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.statusCode)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(entry.statusCode == 200 ? PocketTheme.terminalGreen : PocketTheme.roseAlert)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .devCard(cornerRadius: 10)
    }

    // MARK: - Bottom Action Row
    private var bottomActionRow: some View {
        HStack(spacing: 8) {
            Button(action: {
                showingSettings = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Pro Tuning")
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(PocketTheme.bgSurface)
                .foregroundColor(PocketTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PocketTheme.borderSubtle, lineWidth: 1)
                )
            }

            Button(action: {
                showingNightstand = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill")
                    Text("Insomnia Mode")
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(PocketTheme.bgSurface)
                .foregroundColor(PocketTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PocketTheme.borderSubtle, lineWidth: 1)
                )
            }
        }
    }
}
