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

            VStack(spacing: 8) {
                // Subtle Ambient Time
                Text(currentTime, style: .time)
                    .font(.system(size: 28, weight: .thin, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.12))

                // Low-lumen Telemetry
                HStack(spacing: 12) {
                    Circle()
                        .fill(server.isRunning ? PocketTheme.emerald.opacity(0.4) : PocketTheme.rose.opacity(0.4))
                        .frame(width: 6, height: 6)

                    Text("INSOMNIA ACTIVE • \(String(format: "%.1f", telemetry.tokensPerSecond)) t/s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.12))
                }

                Text("Double tap screen to exit")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.06))
                    .padding(.top, 4)
            }
            .offset(x: xOffset, y: yOffset)
            .onReceive(timer) { input in
                currentTime = input
            }
            .onReceive(driftTimer) { _ in
                // Anti-OLED Burn-in Pixel Drift
                withAnimation(.easeInOut(duration: 4.0)) {
                    xOffset = CGFloat.random(in: -20...20)
                    yOffset = CGFloat.random(in: -30...30)
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
