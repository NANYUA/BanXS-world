import QuartzCore
import UIKit

/// 一次「松手 → 落位完成」的测量结果。
struct LabReading: Equatable {
    /// 松手那一刻 → 下一个屏幕帧。**这是「停一下」最直接的证据**。
    var releaseToFirstFrameMS: Double?
    /// 松手 → 动画结束回调。
    var animatedMS: Double?
    /// 落位期间的最大帧间隔（120Hz 下正常约 8.3ms）。
    var maxGapMS: Double
    /// 帧间隔超过正常值 1.6 倍的次数。
    var hitches: Int
    /// 动画结束 → 之后第一个屏幕帧。落地那一帧有没有被预渲染拖住，看这个。
    var landingGapMS: Double?
    /// 本次统计覆盖的帧数。
    var frames: Int
}

/// 用 `CADisplayLink` 量帧，**不参与布局**：它只是旁观者，读数只在一轮结束时回传一次。
final class LabMeter: NSObject {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var releaseTime: CFTimeInterval?
    private var animationEndTime: CFTimeInterval?
    private var releaseToFirstFrame: Double?
    private var animatedMS: Double?
    private var landingGap: Double?
    private var maxGap: Double = 0
    private var hitches = 0
    private var frames = 0
    private var pendingPublish = 0

    /// 一轮结束（动画结束后的第 3 帧）回调一次。
    var onFinish: ((LabReading) -> Void)?

    var reading: LabReading {
        LabReading(
            releaseToFirstFrameMS: releaseToFirstFrame,
            animatedMS: animatedMS,
            maxGapMS: maxGap,
            hitches: hitches,
            landingGapMS: landingGap,
            frames: frames
        )
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = 0
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func reset() {
        releaseTime = nil
        animationEndTime = nil
        releaseToFirstFrame = nil
        animatedMS = nil
        landingGap = nil
        maxGap = 0
        hitches = 0
        frames = 0
        pendingPublish = 0
    }

    /// 必须在松手回调的**第一行**调用：同帧里之后做的任何重算都会落在「松手 → 首帧」上。
    func armRelease() {
        reset()
        releaseTime = CACurrentMediaTime()
    }

    /// 动画结束回调里调用。
    func noteAnimationEnd() {
        let now = CACurrentMediaTime()
        if let releaseTime {
            animatedMS = (now - releaseTime) * 1000
        }
        animationEndTime = now
        pendingPublish = 3
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard lastTimestamp > 0 else { return }

        let gap = (now - lastTimestamp) * 1000
        let nominal = max((link.targetTimestamp - link.timestamp) * 1000, 1000.0 / 120.0)
        frames += 1
        if gap > nominal * 1.6 {
            hitches += 1
        }
        if gap > maxGap {
            maxGap = gap
        }
        if let releaseTime, releaseToFirstFrame == nil {
            releaseToFirstFrame = max((now - releaseTime) * 1000, 0)
        }
        if let animationEndTime, landingGap == nil {
            landingGap = max((now - animationEndTime) * 1000, 0)
        }
        if pendingPublish > 0 {
            pendingPublish -= 1
            if pendingPublish == 0 {
                onFinish?(reading)
            }
        }
    }
}
