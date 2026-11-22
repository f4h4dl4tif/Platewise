import AVFoundation
import SwiftUI

/// Captures a still photo from the Mac's camera (built-in, Continuity Camera iPhone, or USB webcam).
final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "platewise.camera")
    @Published var ready = false
    @Published var problem: String?
    var onCapture: ((NSImage) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configure() } else { self.problem = Self.deniedMessage }
                }
            }
        default:
            problem = Self.deniedMessage
        }
    }

    static let deniedMessage = "Camera access is turned off. Turn on Platewise in System Settings > Privacy & Security > Camera, then try again."

    private func configure() {
        queue.async {
            if self.session.inputs.isEmpty {
                let device = AVCaptureDevice.default(for: .video)
                guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
                    DispatchQueue.main.async { self.problem = "No camera found. Connect a camera or use Choose Photo instead." }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                self.session.commitConfiguration()
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.ready = true }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func capture() {
        guard ready else { return }
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = NSImage(data: data) else {
            DispatchQueue.main.async { self.problem = "Couldn't take the photo. Please try again." }
            return
        }
        DispatchQueue.main.async { self.onCapture?(image) }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct CameraSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraModel()
    let onPhoto: (NSImage) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Point the camera at your dish").font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.black)
                if let problem = camera.problem {
                    Text(problem).foregroundStyle(.white).multilineTextAlignment(.center).padding(30)
                } else {
                    CameraPreview(session: camera.session).clipShape(RoundedRectangle(cornerRadius: 12))
                    if !camera.ready { ProgressView().controlSize(.large).tint(.white) }
                }
            }
            .frame(width: 640, height: 480)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    camera.capture()
                } label: {
                    Label("Take Photo", systemImage: "camera.circle.fill").padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!camera.ready || camera.problem != nil)
            }
        }
        .padding(20)
        .onAppear {
            camera.onCapture = { image in
                onPhoto(image)
                dismiss()
            }
            camera.start()
        }
        .onDisappear { camera.stop() }
    }
}
