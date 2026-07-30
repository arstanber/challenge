import SwiftUI
@preconcurrency import AVFoundation
import UIKit
import Combine

// MARK: - Live camera session model

final class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "challenge.camera.session")
    private var configured = false   // touched only on sessionQueue
    private var currentInput: AVCaptureDeviceInput?

    @Published var captured: UIImage?
    @Published var isAvailable = false
    @Published var permissionDenied = false
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var canSwitchCamera = false

    // Rotation handling (keeps the preview upright + captures at the right angle
    // when the device rotates -- important on iPad which allows all orientations).
    private var device: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    /// Capture-time rotation angle, kept in sync by the coordinator.
    private var captureAngle: CGFloat = 90

    /// Request access (if needed) and start the session.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.configureAndRun() }
                else { self?.publish { $0.permissionDenied = true } }
            }
        default:
            permissionDenied = true
        }
    }

    func stop() {
        let session = self.session
        sessionQueue.async { if session.isRunning { session.stopRunning() } }
    }

    func capture() {
        let output = self.output
        let angle = captureAngle
        let shouldMirror = position == .front
        sessionQueue.async {
            if let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(angle) {
                conn.videoRotationAngle = angle
            }
            if let conn = output.connection(with: .video), conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = shouldMirror
            }
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, let oldInput = self.currentInput else { return }
            let newPosition: AVCaptureDevice.Position = oldInput.device.position == .back ? .front : .back
            guard
                let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                let newInput = try? AVCaptureDeviceInput(device: newDevice)
            else { return }

            self.session.beginConfiguration()
            self.session.removeInput(oldInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
                self.device = newDevice
                self.session.commitConfiguration()
                self.publish {
                    $0.position = newPosition
                    $0.resetRotationCoordinator()
                }
            } else {
                self.session.addInput(oldInput)
                self.session.commitConfiguration()
            }
        }
    }

    /// Called by the preview view once its layer exists; wires up a rotation
    /// coordinator so the preview and captures track the device orientation.
    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        setupRotationCoordinator()
    }

    private func setupRotationCoordinator() {
        guard rotationCoordinator == nil, let device, let previewLayer else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        applyRotation()
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyRotation() }
        }
    }

    private func applyRotation() {
        guard let coordinator = rotationCoordinator else { return }
        if let conn = previewLayer?.connection {
            let a = coordinator.videoRotationAngleForHorizonLevelPreview
            if conn.isVideoRotationAngleSupported(a) { conn.videoRotationAngle = a }
        }
        captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
    }

    private func resetRotationCoordinator() {
        rotationObservation = nil
        rotationCoordinator = nil
        setupRotationCoordinator()
        updatePreviewMirroring()
    }

    private func updatePreviewMirroring() {
        guard let connection = previewLayer?.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = position == .front
    }

    private func configureAndRun() {
        let session = self.session
        let output = self.output
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(for: .video),
                    let input = try? AVCaptureDeviceInput(device: device),
                    session.canAddInput(input)
                else {
                    session.commitConfiguration()
                    self.publish { $0.isAvailable = false }
                    return
                }
                session.addInput(input)
                self.currentInput = input
                if session.canAddOutput(output) { session.addOutput(output) }
                session.commitConfiguration()
                self.device = device
                self.configured = true
                let canSwitch = AVCaptureDevice.default(
                    .builtInWideAngleCamera,
                    for: .video,
                    position: device.position == .back ? .front : .back
                ) != nil
                self.publish {
                    $0.isAvailable = true
                    $0.position = device.position
                    $0.canSwitchCamera = canSwitch
                    // The preview layer may already be attached; wire rotation now.
                    $0.setupRotationCoordinator()
                    $0.updatePreviewMirroring()
                }
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    private func publish(_ change: @escaping (CameraModel) -> Void) {
        DispatchQueue.main.async { [weak self] in if let self { change(self) } }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in self?.captured = image }
    }
}

// MARK: - Preview layer

struct CameraPreview: UIViewRepresentable {
    let camera: CameraModel

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = camera.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        camera.attachPreviewLayer(view.videoPreviewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
