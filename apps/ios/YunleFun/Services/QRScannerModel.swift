import AVFoundation
import Combine
import Foundation

enum QRScannerCameraState: Equatable {
    case permissionRequired, checking, running, paused, denied, restricted, unavailable, interrupted, failed
}
@MainActor
final class QRScannerModel: ObservableObject {
    @Published private(set) var cameraState = QRScannerCameraState.paused
    @Published private(set) var torchAvailable = false
    @Published private(set) var torchOn = false
    @Published private(set) var isReadingPhoto = false
    @Published private(set) var candidates: [ScanCandidate] = []
    @Published private(set) var issue: String?
    let purpose: ScanPurpose
    private let permission: CameraPermissionChecking
    private let camera: CameraQRReading
    private let decoder: PhotoQRCodeDecoding
    private var visible = false
    private var sceneActive = true
    private var pickingPhoto = false
    private var cameraID: UUID?
    private var permissionID: UUID?
    private var photoID: UUID?
    private var photoTask: Task<Void, Never>?
    var session: AVCaptureSession { camera.session }

    init(purpose: ScanPurpose, permission: CameraPermissionChecking = CameraPermissionService(),
         camera: CameraQRReading = CameraQRReader(), decoder: PhotoQRCodeDecoding = PhotoQRCodeDecoder()) {
        self.purpose = purpose; self.permission = permission; self.camera = camera; self.decoder = decoder
    }
    deinit { photoTask?.cancel(); camera.stop() }
    func appear() { visible = true; activate() }
    func disappear() {
        visible = false; permissionID = nil; photoID = nil; photoTask?.cancel(); photoTask = nil; isReadingPhoto = false
        pauseCamera()
    }
    func sceneIsActive(_ active: Bool) {
        sceneActive = active
        if active { activate() } else { pauseCamera() }
    }
    func pickerIsPresented(_ presented: Bool) {
        pickingPhoto = presented
        if presented { pauseCamera() }
        // Cancel resumes only when the view confirms there is no selection.
    }
    func pickerCancelled() { pickingPhoto = false; activate() }
    func enableCamera() async {
        guard visible, sceneActive, !pickingPhoto, !isReadingPhoto, candidates.isEmpty, permissionID == nil else { return }
        guard permission.isAvailable else { cameraState = .unavailable; return }
        if permission.status != .notDetermined { activate(); return }
        let id = UUID(); permissionID = id; cameraState = .checking
        let allowed = await permission.request()
        guard permissionID == id, visible else { return }
        permissionID = nil
        if allowed { activate() } else { cameraState = permission.status == .restricted ? .restricted : .denied }
    }
    func continueScanning() {
        pauseCamera()
        candidates = []; issue = nil; photoID = nil; photoTask?.cancel(); photoTask = nil; isReadingPhoto = false
        activate()
    }
    func toggleTorch() { guard cameraState == .running, torchAvailable else { return }; camera.torch(!torchOn) }
    func readPhoto(load: @escaping () async throws -> Data) {
        guard visible else { return }
        pickingPhoto = false; pauseCamera(); permissionID = nil
        photoTask?.cancel()
        let id = UUID(); photoID = id; isReadingPhoto = true; candidates = []; issue = nil
        photoTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.photoID == id { self.isReadingPhoto = false; self.photoTask = nil } }
            do {
                let data = try await load()
                guard self.photoID == id, self.visible, !Task.isCancelled else { return }
                let payloads = try await self.decoder.payloads(in: data)
                guard self.photoID == id, self.visible, !Task.isCancelled else { return }
                self.receive(payloads)
            } catch is CancellationError { }
            catch {
                guard self.photoID == id, self.visible, !Task.isCancelled else { return }
                self.issue = (error as? ScanImageError)?.message ?? "图片暂时无法读取，请重新选择。"
            }
        }
    }
    private func activate() {
        guard visible, sceneActive, !pickingPhoto, !isReadingPhoto, candidates.isEmpty, permissionID == nil else { return }
        guard permission.isAvailable else { cameraState = .unavailable; return }
        switch permission.status {
        case .notDetermined: cameraState = .permissionRequired
        case .denied: cameraState = .denied
        case .restricted: cameraState = .restricted
        case .authorized:
            guard cameraID == nil else { return }
            let id = UUID(); cameraID = id; cameraState = .checking
            camera.start(id: id) { [weak self] id, event in
                Task { @MainActor in self?.receive(id: id, event: event) }
            }
        }
    }
    private func pauseCamera() {
        cameraID = nil; camera.stop(); torchOn = false; torchAvailable = false
        if cameraState == .running || cameraState == .checking || cameraState == .interrupted { cameraState = .paused }
    }
    private func receive(id: UUID, event: CameraReaderEvent) {
        guard cameraID == id, visible, sceneActive, !pickingPhoto, !isReadingPhoto, candidates.isEmpty else { return }
        switch event {
        case .running(let available): cameraState = .running; torchAvailable = available
        case .codes(let payloads): pauseCamera(); receive(payloads)
        case .interrupted: cameraState = .interrupted; torchOn = false; torchAvailable = false
        case .failed: pauseCamera(); cameraState = .failed
        case .torch(let enabled): torchOn = enabled
        case .torchFailed(let currentOn): torchOn = currentOn; issue = "手电筒暂时不可用。"
        }
    }
    private func receive(_ payloads: [String]) {
        var seen = Set<String>()
        candidates = payloads.filter { !$0.isEmpty && $0.utf8.count <= 10_000 && seen.insert($0).inserted }.prefix(20)
            .map { ScanCandidate(payload: $0, result: ScanParser.parse($0, purpose: purpose)) }
        if candidates.isEmpty { issue = ScanImageError.noCode.message }
    }
}
