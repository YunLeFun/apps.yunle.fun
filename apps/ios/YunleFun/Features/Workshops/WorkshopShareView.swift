import SwiftUI
import CoreImage.CIFilterBuiltins

struct WorkshopShareView: View {
    let workshop: PersonalWorkshop
    @Environment(\.dismiss) private var dismiss
    private var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(workshop.shareURL.absoluteString.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage, let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(workshop.name).font(.title2.bold())
                    Text("\(workshop.ownerName)的个人工坊").foregroundStyle(.secondary)
                    if let qrImage {
                        Image(uiImage: qrImage).interpolation(.none).resizable().scaledToFit()
                            .padding(20).background(.white).frame(maxWidth: 280).frame(maxWidth: .infinity)
                            .accessibilityLabel("工坊分享二维码，编号 \(workshop.id)")
                    }
                    LabeledContent("工坊编号", value: workshop.id).textSelection(.enabled)
                    Text(workshop.shareURL.absoluteString).textSelection(.enabled).font(.footnote)
                }
                Section {
                    ShareLink(item: workshop.shareURL) { Label("分享工坊链接", systemImage: "square.and.arrow.up") }
                } footer: { Text(workshop.status == .disabled ? "工坊已暂停。" : "加入方式：\(workshop.joinPolicy.label)。工坊链接不会绕过坊主审批。") }
            }
            .navigationTitle("分享工坊").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
