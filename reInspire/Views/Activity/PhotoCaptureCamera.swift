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

    @Published var captured: UIImage?
    @Published var isAvailable = false
    @Published var permissionDenied = false

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
        sessionQueue.async {
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
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
                if session.canAddOutput(output) { session.addOutput(output) }
                session.commitConfiguration()
                self.configured = true
                self.publish { $0.isAvailable = true }
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
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
