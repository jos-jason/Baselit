import SwiftUI

/// A camera view that stays open after each capture, calling back on every photo.
/// Uses showsCameraControls = false to bypass the "Use Photo / Retake" confirmation.
/// The parent view provides UI for shutter, count badge, and done via SwiftUI overlays,
/// and triggers captures by calling `takePicture()` on the coordinator.
struct ContinuousCameraView: UIViewControllerRepresentable {
    var onImageCaptured: (UIImage) -> Void
    var coordinator: ContinuousCameraCoordinator

    func makeCoordinator() -> ContinuousCameraCoordinator {
        coordinator
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.showsCameraControls = false

        // Scale the camera preview to fill the screen.
        // Without system controls, the 4:3 preview doesn't fill the taller screen.
        let screenBounds = picker.view.bounds
        let cameraAspectRatio: CGFloat = 4.0 / 3.0
        let previewHeight = screenBounds.width * cameraAspectRatio
        let scale = screenBounds.height / previewHeight
        if scale > 1 {
            picker.cameraViewTransform = CGAffineTransform(scaleX: scale, y: scale)
        }

        context.coordinator.picker = picker

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}

/// Shared coordinator that holds a reference to the picker so the parent SwiftUI
/// view can trigger `takePicture()` from a button action.
class ContinuousCameraCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var onImageCaptured: ((UIImage) -> Void)?
    var onDone: (() -> Void)?
    weak var picker: UIImagePickerController?

    func takePicture() {
        picker?.takePicture()
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        if let image = info[.originalImage] as? UIImage {
            onImageCaptured?(image)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        onDone?()
    }
}
