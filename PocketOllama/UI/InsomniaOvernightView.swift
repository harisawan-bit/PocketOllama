import SwiftUI

public struct InsomniaOvernightView: View {
    @Binding var isPresented: Bool
    @State private var currentTime = Date()
    @State private var xOffset: CGFloat = 0
    @State private var yOffset: CGFloat = 0
    @ObservedObject var server = LLMServer.shared
    @ObservedObject var telemetry = TelemetryManager.shared
    @ObservedObject var thermal = ThermalGovernor.shared

    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    let shiftTimer = Timer.publish(every: 30.0, on: .main, in: .common).autoconnect()

    public var body: some View {
        ZStack {
            // Pure Black (#000000) for 0% OLED power consumption
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Text(currentTime, style: .time)
                    .font(.system(size: 54, weight: .ultraLight, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.18))

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(server.isRunning ? Color.green.opacity(0.4) : Color.red.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text("PocketOllama Insomnia Engine")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.20))
                    }

                    Text("Speed: \(String(format: "%.1f", telemetry.tokensPerSecond)) t/s • Thermal: \(thermal.currentThermalTier.rawValue)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.12))
                }

                Text("0% OLED Power • Tap anywhere to wake")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.08))
                    .padding(.top, 24)
            }
            .offset(x: xOffset, y: yOffset)
            .onReceive(timer) { input in
                currentTime = input
            }
            .onReceive(shiftTimer) { _ in
                withAnimation(.easeInOut(duration: 2.0)) {
                    xOffset = CGFloat.random(in: -25...25)
                    yOffset = CGFloat.random(in: -25...25)
                }
            }
        }
        .onTapGesture {
            isPresented = false
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}
