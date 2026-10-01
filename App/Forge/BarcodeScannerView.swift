import AVFoundation
import SwiftUI
import VisionKit

struct BarcodeScannerView: UIViewControllerRepresentable {
  var onCode: (String) -> Void
  /// Fires when `startScanning()` throws, so the sheet can fall back to manual entry.
  var onUnavailable: (() -> Void)? = nil

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let scanner = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
      qualityLevel: .balanced,
      recognizesMultipleItems: false,
      isHighlightingEnabled: true)
    scanner.delegate = context.coordinator
    if DataScannerViewController.isAvailable {
      do {
        try scanner.startScanning()
      } catch {
        Task { @MainActor in onUnavailable?() }
      }
    } else {
      // A first-use "Don't Allow" surfaces here too, not only through the delegate.
      Task { @MainActor in onUnavailable?() }
    }
    return scanner
  }

  func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onUnavailable: onUnavailable ?? {}) }

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    let onCode: (String) -> Void
    let onUnavailable: () -> Void

    init(onCode: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
      self.onCode = onCode
      self.onUnavailable = onUnavailable
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
      guard case let .barcode(barcode) = addedItems.first else { return }
      dataScanner.stopScanning()
      onCode(barcode.payloadStringValue ?? "")
    }

    func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
      Task { @MainActor in onUnavailable() }
    }
  }
}

/// Presents the scanner where supported, manual entry otherwise (simulator).
struct BarcodeScannerSheet: View {
  @Environment(\.dismiss) private var dismiss
  /// Food search pushes the scanner inside its own stack with this false.
  var showsOwnNavigationStack = true
  var onCode: (String) -> Void
  /// Fires when `startScanning()` throws, so the sheet can fall back to manual entry.
  var onUnavailable: (() -> Void)? = nil
  @State private var manual = ""
  @State private var cameraUnavailable = false

  /// Denied or restricted: the Settings toggle is the only way forward.
  private var cameraBlocked: Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    return status == .denied || status == .restricted
  }

  var body: some View {
    if showsOwnNavigationStack {
      NavigationStack { content }
    } else {
      content
    }
  }

  private var content: some View {
    Group {
      if DataScannerViewController.isSupported && !cameraBlocked && !cameraUnavailable {
        ZStack(alignment: .bottom) {
          BarcodeScannerView(onCode: handle, onUnavailable: { cameraUnavailable = true })
            .ignoresSafeArea()
          Text("Point the camera at a barcode")
            .forgeLabel()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.ring))
            .padding(.bottom, 24)
        }
      } else {
        fallback
      }
    }
    .navigationTitle("Scan barcode")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if showsOwnNavigationStack {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationBackground(Theme.page)
  }

  /// Camera off or unavailable: say how to turn it on, and keep the manual path open.
  private var fallback: some View {
    VStack(spacing: 14) {
      if cameraBlocked || cameraUnavailable {
        Text("Camera access is off. Turn it on in Settings to scan barcodes.")
          .forgeLabel()
          .multilineTextAlignment(.center)
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        }
        .buttonStyle(PillButtonStyle(minHeight: 44))
      } else {
        Image(systemName: "barcode.viewfinder")
          .scaledSystemFont(40)
          .foregroundStyle(Theme.textSecondary)
        Text("Camera scanner unavailable here").forgeLabel()
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("Enter barcode").forgeCaption()
        TextField("Enter barcode", text: $manual)
          .keyboardType(.numberPad)
          .forgeBody()
          .monospacedDigit()
          .padding(12)
          .background(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous).fill(Theme.innerSurface))
      }
      Button("Lookup") { handle(manual) }
        .buttonStyle(PillButtonStyle(minHeight: 44))
        .disabled(manual.isEmpty)
    }
    .padding(Theme.margin)
  }

  private func handle(_ code: String) {
    guard !code.isEmpty else { return }
    dismiss()
    onCode(code)
  }
}
