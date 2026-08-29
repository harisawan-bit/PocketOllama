import SwiftUI
import CoreImage.CIFilterBuiltins

public struct QRConnectSheet: View {
    @Environment(\.presentationMode) var presentationMode
    let endpointURL: String
    let hostname: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

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
                    if let image = generateQRCode(from: endpointURL) {
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
        filter.message = Data(string.utf8)

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
