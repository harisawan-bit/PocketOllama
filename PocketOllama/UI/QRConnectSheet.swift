import SwiftUI
import CoreImage.CIFilterBuiltins

public struct QRConnectSheet: View {
    @Environment(\.presentationMode) var presentationMode
    let endpointURL: String
    let hostname: String

    private let context = CIContext()

    /// Cached per endpoint. Building the filter during body evaluation re-ran the
    /// generator on every re-render.
    private static var qrCache: (key: String, image: UIImage?) = ("", nil)

    private func qrImage() -> UIImage? {
        if Self.qrCache.key == endpointURL { return Self.qrCache.image }
        let image = generateQRCode(from: endpointURL)
        Self.qrCache = (endpointURL, image)
        return image
    }

    public var body: some View {
        NavigationView {
            ZStack {
                PocketTheme.bgDeep.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("SCAN TO CONNECT LAPTOP")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(PocketTheme.textMuted)
                        Text("Open Web UI or Connect AI Harness")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(PocketTheme.textPrimary)
                    }
                    .padding(.top, 10)

                    // Generated QR Code
                    if let image = qrImage() {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(PocketTheme.devCyan, lineWidth: 2)
                            )
                    }

                    VStack(spacing: 8) {
                        Text(endpointURL)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(PocketTheme.devCyan)

                        VStack(spacing: 3) {
                            Text("Or type the hostname")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(PocketTheme.textMuted)
                            Text("http://\(hostname).local")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(PocketTheme.terminalGreen)
                                .textSelection(.enabled)
                        }
                        .padding(.top, 2)

                        Text("Same Wi-Fi network required")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(PocketTheme.textMuted)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("QR Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(PocketTheme.devCyan)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}
