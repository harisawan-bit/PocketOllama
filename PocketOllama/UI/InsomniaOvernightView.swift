import SwiftUI

public struct InsomniaOvernightView: View {
    @Binding var isPresented: Bool
    @ObservedObject var server = LLMServer.shared
    @ObservedObject var telemetry = TelemetryManager.shared
    
    @State private var xOffset: CGFloat = 0
    @State private var yOffset: CGFloat = 0
    @State private var currentTime = Date()

    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    let driftTimer = Timer.publish(every: 30.0, on: .main, in: .common).autoconnect()

    public var body: some View {
        ZStack {
            // Pure OLED Black (#000000) - Turns OFF all display pixels
            Color.black.ignoresSafeArea()

            VStack(spacing: 6) {
                // Dim Monospaced Time
                Text(currentTime, style: .time)
                    .font(.system(size: 24, weight: .light, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.15))

                // Low-lumen Telemetry Strip
                HStack(spacing: 8) {
                    Circle()
                        .fill(server.isRunning ? PocketTheme.terminalGreen.opacity(0.4) : PocketTheme.roseAlert.opacity(0.4))
                        .frame(width: 5, height: 5)

                    Text("OVERNIGHT ACTIVE // \(String(format: "%.1f", telemetry.tokensPerSecond)) t/s")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.12))
                }

                Text("Double tap screen to unlock")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.06))
                    .padding(.top, 2)
            }
            .offset(x: xOffset, y: yOffset)
            .onReceive(timer) { input in
                currentTime = input
            }
            .onReceive(driftTimer) { _ in
                // Anti-OLED Burn-in Pixel Drift
                withAnimation(.easeInOut(duration: 3.0)) {
                    xOffset = CGFloat.random(in: -20...20)
                    yOffset = CGFloat.random(in: -25...25)
                }
            }
            .onTapGesture(count: 2) {
                isPresented = false
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}
