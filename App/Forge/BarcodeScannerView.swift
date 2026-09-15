import SwiftUI
import VisionKit

struct BarcodeScannerView: UIViewControllerRepresentable {
  var onCode: (String) -> Void

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let scanner = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
      qualityLevel: .balanced,
      recognizesMultipleItems: false,
      isHighlightingEnabled: true)
    scanner.delegate = context.coordinator
    try? scanner.startScanning()
    return scanner
  }

  func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    let onCode: (String) -> Void

    init(onCode: @escaping (String) -> Void) {
      self.onCode = onCode
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
      guard case let .barcode(barcode) = addedItems.first else { return }
      dataScanner.stopScanning()
      onCode(barcode.payloadStringValue ?? "")
    }
  }
}

/// Presents the scanner where supported, manual entry otherwise (simulator).
struct BarcodeScannerSheet: View {
  @Environment(\.dismiss) private var dismiss
  var onCode: (String) -> Void
  @State private var manual = ""

  var body: some View {
    NavigationStack {
      Group {
        if DataScannerViewController.isSupported {
          BarcodeScannerView(onCode: handle)
            .ignoresSafeArea()
        } else {
          VStack(spacing: 14) {
            Image(systemName: "barcode.viewfinder")
              .font(.system(size: 40))
              .foregroundStyle(Theme.textSecondary)
            Text("Camera scanner unavailable here").forgeLabel()
            TextField("Enter barcode", text: $manual)
              .keyboardType(.numberPad)
              .forgeBody()
              .monospacedDigit()
              .padding(12)
              .background(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous).fill(Theme.innerSurface))
            Button("Lookup") { handle(manual) }
              .buttonStyle(PillButtonStyle(minHeight: 44))
              .disabled(manual.isEmpty)
          }
          .padding(Theme.margin)
        }
      }
      .navigationTitle("Scan barcode")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
    }
    .presentationBackground(Theme.page)
  }

  private func handle(_ code: String) {
    guard !code.isEmpty else { return }
    dismiss()
    onCode(code)
  }
}
