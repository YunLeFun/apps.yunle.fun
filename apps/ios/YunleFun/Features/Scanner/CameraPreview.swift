import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(); view.preview.session = session; view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: CameraPreviewView, context: Context) { view.updateOrientation() }
    static func dismantleUIView(_ view: CameraPreviewView, coordinator: ()) { view.preview.session = nil }
}
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var rotationCoordinator: NSObject?
    private var rotationObservation: NSKeyValueObservation?
    override func layoutSubviews() { super.layoutSubviews(); updateOrientation() }
    override func didMoveToWindow() { super.didMoveToWindow(); updateOrientation() }
    func updateOrientation() {
        guard let orientation = window?.windowScene?.interfaceOrientation, let connection = preview.connection else { return }
        if #available(iOS 17, *) {
            if rotationCoordinator == nil,
               let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
                rotationCoordinator = coordinator
                rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                    // AVFoundation delivers this KVO update on the main queue.
                    MainActor.assumeIsolated { self?.applyRotation(coordinator.videoRotationAngleForHorizonLevelPreview) }
                }
            }
            if let coordinator = rotationCoordinator as? AVCaptureDevice.RotationCoordinator {
                applyRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
            }
        } else if connection.isVideoOrientationSupported {
            switch orientation { case .landscapeLeft: connection.videoOrientation = .landscapeLeft
            case .landscapeRight: connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            default: connection.videoOrientation = .portrait }
        }
    }
    @available(iOS 17, *)
    private func applyRotation(_ angle: CGFloat) {
        guard let connection = preview.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

}
