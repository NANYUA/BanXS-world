import CoreText
import Foundation
import UIKit

// MARK: - 可切换的变体

/// 松手之后「滑到位置」这一段动画怎么做。
enum LabSettleCurve: String, CaseIterable, Identifiable {
    case fixedEaseOut
    case velocitySolved
    case spring
    case instant

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .fixedEaseOut:
            "固定 0.28s"
        case .velocitySolved:
            "速度反解"
        case .spring:
            "弹簧"
        case .instant:
            "瞬移"
        }
    }
}

/// 松手之后「三张整页位图」什么时候渲染。
enum LabPrefetchTiming: String, CaseIterable, Identifiable {
    case sameFrame
    case nextRunloop
    case off

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .sameFrame:
            "同帧"
        case .nextRunloop:
            "下一 runloop"
        case .off:
            "关闭"
        }
    }
}

/// 谁去发起落位动画。
enum LabEntryPath: String, CaseIterable, Identifiable {
    case gesture
    case turnRequest

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .gesture:
            "手势直调"
        case .turnRequest:
            "turnRequest"
        }
    }
}

/// 一次实验的全部开关。
struct LabVariant: Equatable {
    var curve: LabSettleCurve = .fixedEaseOut
    var entry: LabEntryPath = .gesture
    var prefetch: LabPrefetchTiming = .sameFrame
    /// 松手时把「换页 + 三格重建」同步做掉（现状），还是推到下一帧再做。
    var commitNextFrame = false
    /// 松手时顺带重算父级派生值（模拟 HUD / 章节列表那一圈）。
    var heavyParentWork = false
    /// 跟手位移是否夹在 ±一页宽（现状夹）。
    var clampsOffset = true
}

/// 翻页方向。
enum LabTurn: Equatable {
    case previous
    case none
    case next

    var step: Int {
        switch self {
        case .previous:
            -1
        case .none:
            0
        case .next:
            1
        }
    }
}

// MARK: - 预设组合（自动 A/B 用）

struct LabPreset: Identifiable {
    let title: String
    let variant: LabVariant

    var id: String {
        title
    }

    /// 逐条对应「松手卡顿」的八条假设，从现状出发一次只改一个面。
    static let all: [LabPreset] = [
        LabPreset(
            title: "现状：固定 0.28s + 同帧提交 + 重算父级 + 同帧预渲染",
            variant: LabVariant()
        ),
        LabPreset(
            title: "假设①：松手不重算父级",
            variant: LabVariant(heavyParentWork: false)
        ),
        LabPreset(
            title: "假设①+：换页推到下一帧",
            variant: LabVariant(commitNextFrame: true)
        ),
        LabPreset(
            title: "假设②：速度反解时长",
            variant: LabVariant(curve: .velocitySolved)
        ),
        LabPreset(
            title: "假设②+：弹簧带初速",
            variant: LabVariant(curve: .spring)
        ),
        LabPreset(
            title: "假设④：预渲染推到下一 runloop",
            variant: LabVariant(prefetch: .nextRunloop)
        ),
        LabPreset(
            title: "假设⑤：不夹跟手位移",
            variant: LabVariant(clampsOffset: false)
        ),
        LabPreset(
            title: "假设⑥：改走 turnRequest",
            variant: LabVariant(entry: .turnRequest)
        ),
        LabPreset(
            title: "全改：下一帧提交 + 速度反解 + 预渲染延后 + 不重算父级",
            variant: LabVariant(
                curve: .velocitySolved,
                prefetch: .nextRunloop,
                commitNextFrame: true
            )
        ),
    ]
}

// MARK: - 内容

enum LabContent {
    static let pageCount = 240

    /// 确定性正文：同一页永远同样长，便于横向比较。
    static func text(at index: Int) -> String {
        let number = ((index % pageCount) + pageCount) % pageCount + 1
        var body = ""
        for paragraph in 1 ... 7 {
            body += "第 \(number) 页 · 第 \(paragraph) 段　"
            body += "这一段故意写满整页，好让排版成本接近真实小说。"
            body += "松手那一下究竟有没有停顿，只看动画看不出来，必须把帧间隔量出来才算数。"
            body += "所以这里既显示「松手到首帧」，也显示落位期间的最大帧间隔。\n"
        }
        return body
    }

    /// 三格：上一页 / 当前页 / 下一页。
    static func slots(around index: Int) -> [String] {
        [-1, 0, 1].map { text(at: index + $0) }
    }
}

// MARK: - 工作量模拟

enum LabWork {
    /// 模拟「松手时父级 body 全量重算」：拼一遍派生文案。
    static func heavyParentWork(around index: Int) {
        var accumulator = ""
        for offset in 0 ..< 2000 {
            accumulator += "第\(index + offset)章·标题\(offset)；"
        }
        if accumulator.isEmpty {
            accumulator = "空"
        }
        _ = accumulator.count
    }

    /// 模拟「同步预渲染三张整页位图」：真跑三次 CoreText 排版。
    static func prefetchPages(_ texts: [String], size: CGSize) -> Int {
        var drawn = 0
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        for text in texts {
            let attributed = LabTypography.attributed(text)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            drawn += CTFrameGetVisibleStringRange(frame).length
        }
        return drawn
    }
}
