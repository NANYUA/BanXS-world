import SwiftUI
import UIKit

/// 排版参数集中一处：预渲染与屏幕上那一页用**同一份**属性，
/// 否则「预渲染」测出来的成本不是真实成本。
enum LabTypography {
    static var paragraphStyle: NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 7
        style.alignment = .justified
        style.paragraphSpacing = 8
        return style
    }

    static func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 17),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }
}

/// 一页正文。用 `UILabel`（TextKit）而不是 SwiftUI `Text`：
/// 排版成本与真实阅读页同一量级，且不需要额外的布局容器。
struct LabPageText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = LabTypography.attributed(text)
    }
}
