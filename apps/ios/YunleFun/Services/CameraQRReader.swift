import AVFoundation
import Foundation

// All capture configuration, start/stop and torch changes use one serial queue.
// Only the preview layer reads the stable session reference on the main thread.
enum CameraPermission { case notDetermined, authorized, denied, restricted }
protocol CameraPermissionChecking {
    var isAvailable: Bool { get }
    var status: CameraPermission { get }
    func request() async -> Bool
}
struct CameraPermissionService: CameraPermissionChecking {
    var isAvailable: Bool { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }
    var status: CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notDetermined
        }
    }
    func request() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
}
enum CameraReaderEvent {
    case running(torchAvailable: Bool)
    case codes([String])
    case interrupted
    case failed
    case torch(Bool)
    case torchFailed(currentOn: Bool)
}
protocol CameraQRReading: AnyObject {
    var session: AVCaptureSession { get }
    func start(id: UUID, receive: @escaping (UUID, CameraReaderEvent) -> Void)
    func stop()
    func torch(_ enabled: Bool)
}
final class CameraQRReader: NSObject, CameraQRReading, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "fun.yunle.apps.qr-camera", qos: .userInitiated)
    private var device: AVCaptureDevice?
    private var configured = false
    private var activeID: UUID?
    private var receive: ((UUID, CameraReaderEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] notification in
                guard let self else { return }
                self.queue.async {
                    guard self.activeID != nil else { return }
                    if notification.name == AVCaptureSession.interruptionEndedNotification {
                        if !self.session.isRunning { self.session.startRunning() }
                        if self.session.isRunning { self.emit(.running(torchAvailable: self.device?.isTorchAvailable == true)) }
                        else { self.emit(.failed) }
                    } else {
                        self.setTorch(false)
                        self.emit(notification.name == AVCaptureSession.runtimeErrorNotification ? .failed : .interrupted)
                    }
                }
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func start(id: UUID, receive: @escaping (UUID, CameraReaderEvent) -> Void) {
        queue.async {
            self.activeID = id; self.receive = receive
            do {
                if !self.configured { try self.configure() }
                if !self.session.isRunning { self.session.startRunning() }
                if self.session.isRunning { self.emit(.running(torchAvailable: self.device?.isTorchAvailable == true)) }
                else { self.emit(.failed) }
            } catch { self.emit(.failed) }
        }
    }
    func stop() {
        queue.async {
            self.activeID = nil; self.receive = nil
            self.setTorch(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
    func torch(_ enabled: Bool) {
        queue.async {
            guard self.activeID != nil, self.session.isRunning else { return }
            do {
                guard let device = self.device, device.hasTorch, device.isTorchAvailable else { throw ScanImageError.invalidImage }
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                device.torchMode = enabled ? .on : .off
                self.emit(.torch(device.torchMode == .on))
            } catch { self.emit(.torchFailed(currentOn: self.device?.isTorchActive == true)) }
        }
    }
    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw ScanImageError.invalidImage }
        let input = try AVCaptureDeviceInput(device: device), output = AVCaptureMetadataOutput()
        session.beginConfiguration(); defer { session.commitConfiguration() }
        // A failed configuration must not leave inputs that make retry fail.
        for old in session.inputs { session.removeInput(old) }
        for old in session.outputs { session.removeOutput(old) }
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        guard session.canAddInput(input) else { throw ScanImageError.invalidImage }
        session.addInput(input)
        guard session.canAddOutput(output) else { throw ScanImageError.invalidImage }
        session.addOutput(output)
        guard output.availableMetadataObjectTypes.contains(.qr) else { throw ScanImageError.invalidImage }
        output.metadataObjectTypes = [.qr]
        output.setMetadataObjectsDelegate(self, queue: queue)
        self.device = device; configured = true
    }
    private func setTorch(_ enabled: Bool) {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = enabled ? .on : .off; device.unlockForConfiguration()
    }
    private func emit(_ event: CameraReaderEvent) {
        guard let id = activeID, let receive else { return }
        DispatchQueue.main.async { receive(id, event) }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard activeID != nil, session.isRunning else { return }
        var seen = Set<String>()
        let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            .filter { !$0.isEmpty && $0.utf8.count <= 10_000 && seen.insert($0).inserted }
        if !codes.isEmpty { emit(.codes(Array(codes.prefix(20)))) }
    }
}
