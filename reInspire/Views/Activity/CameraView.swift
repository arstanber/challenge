import SwiftUI
import UIKit

struct CameraView: View {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.isAvailable {
                CameraPreview(camera: camera).ignoresSafeArea()
            } else if camera.permissionDenied {
                Text("Нет доступа к камере")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Color.clear.frame(width: 56, height: 56)
                    Spacer()
                    Button {
                        Haptics.medium()
                        camera.capture()
                    } label: {
                        ZStack {
                            Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                            Circle().fill(.white).frame(width: 62, height: 62)
                        }
                    }
                    .disabled(!camera.isAvailable)
                    Spacer()
                    if camera.canSwitchCamera {
                        Button {
                            Haptics.tap()
                            camera.switchCamera()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        .accessibilityLabel(String(localized: "Сменить камеру"))
                    } else {
                        Color.clear.frame(width: 56, height: 56)
                    }
                }
                .padding(.horizontal, 42)
                .padding(.bottom, 34)
            }
            .padding(.horizontal, 18)
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onReceive(camera.$captured) { captured in
            guard let captured else { return }
            image = captured
            dismiss()
        }
    }
}
