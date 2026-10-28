#if canImport(UIKit)
import SwiftUI
import UIKit

/// Shared native image viewer for the extension, drafts and private ticket attachments.
/// The navigation controls use the system material; image content stays unobscured.
struct ScreenshotPreview: View {
    let data: Data
    var imageLabel = "截图完整预览"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZoomableScreenshot(data: data, imageLabel: imageLabel)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("截图预览")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Label("完成", systemImage: "checkmark") }
                        .accessibilityIdentifier("feedback.preview.close")
                }
            }
            .preferredColorScheme(.dark)
    }
}

private struct ZoomableScreenshot: UIViewRepresentable {
    let data: Data
    let imageLabel: String
    func makeUIView(context: Context) -> ScreenshotScrollView {
        let view = ScreenshotScrollView()
        view.imageView.image = UIImage(data: data)
        view.imageView.accessibilityLabel = imageLabel
        return view
    }
    func updateUIView(_ view: ScreenshotScrollView, context: Context) {}
}

private final class ScreenshotScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    private var previousSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        delegate = self
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityIdentifier = "feedback.preview.image"
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2; addGestureRecognizer(doubleTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        if previousSize != bounds.size {
            previousSize = bounds.size
            zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size
            minimumZoomScale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            maximumZoomScale = max(minimumZoomScale * 4, 1)
            zoomScale = minimumZoomScale
        }
        centerImage()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    private func centerImage() {
        imageView.center = CGPoint(x: max(contentSize.width, bounds.width) / 2,
                                   y: max(contentSize.height, bounds.height) / 2)
    }
    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.01 { setZoomScale(minimumZoomScale, animated: true) }
        else {
            let scale = min(minimumZoomScale * 2.5, maximumZoomScale)
            let point = gesture.location(in: imageView)
            zoom(to: CGRect(x: point.x - bounds.width / scale / 2, y: point.y - bounds.height / scale / 2,
                            width: bounds.width / scale, height: bounds.height / scale), animated: true)
        }
    }
}
#endif
