import SwiftUI

/// 翻页落位实验室：把「松手那一下」拆成可切换的开关，并当场把帧间隔量出来。
///
/// 用法：真机跑起来 → 慢拖 30% 松手，看左上角「松手 → 首帧」；
/// 或者直接按「自动 A/B」，让九组预设各跑八次取中位数。
struct LabView: View {
    @State private var variant = LabVariant()
    @State private var index = 1
    @State private var offset: CGFloat = 0
    @State private var displayedOffset: CGFloat = 0
    @State private var isMoving = false
    @State private var axisLocked = false
    @State private var slots = LabContent.slots(around: 1)
    @State private var pageSize: CGSize = .zero

    @State private var turnRequest = 0
    @State private var pendingTurn: LabTurn = .none
    @State private var pendingVelocity: CGFloat = 0

    @State private var reading: LabReading?
    @State private var decisionText = "—"
    @State private var recentLines: [String] = []

    @State private var isSweeping = false
    @State private var sweepLines: [String] = []
    @State private var sweepTask: Task<Void, Never>?

    @State private var showsPanel = true
    @State private var meter = LabMeter()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                pageArea(size: geometry.size)
                if showsPanel {
                    panel
                        .transition(.move(edge: .bottom))
                }
            }
            .onAppear {
                pageSize = geometry.size
                meter.onFinish = { newReading in
                    reading = newReading
                    recentLines.insert(summary(of: newReading), at: 0)
                    if recentLines.count > 6 {
                        recentLines.removeLast()
                    }
                }
                meter.start()
            }
            .onDisappear {
                meter.stop()
                sweepTask?.cancel()
            }
            .onChange(of: geometry.size) { _, newSize in
                pageSize = newSize
            }
            .onChange(of: turnRequest) { _, _ in
                guard pendingTurn != .none else { return }
                commit(pendingTurn, velocity: pendingVelocity)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
    }

    // MARK: - 页面

    private func pageArea(size: CGSize) -> some View {
        HStack(spacing: 0) {
            ForEach(slots.indices, id: \.self) { position in
                pageCell(text: slots[position], size: size)
            }
        }
        .frame(width: size.width * 3, height: size.height)
        .offset(x: offset)
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(dragGesture(size: size))
        .overlay(alignment: .topLeading) {
            hud
                .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsPanel.toggle()
                }
            } label: {
                Image(systemName: showsPanel ? "chevron.down" : "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
            }
            .padding(8)
        }
    }

    private func pageCell(text: String, size: CGSize) -> some View {
        LabPageText(text: text)
            .padding(.top, 26)
            .padding(.horizontal, 22)
            .padding(.bottom, 26)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(uiColor: .systemBackground))
    }

    // MARK: - 手势

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = value.translation.width
                if !isMoving {
                    guard abs(dx) > 8 else { return }
                    axisLocked = true
                    isMoving = true
                    displayedOffset = offset
                }
                guard axisLocked else { return }
                let raw = displayedOffset + dx
                offset = variant.clampsOffset
                    ? min(max(raw, -size.width), size.width)
                    : raw
            }
            .onEnded { value in
                isMoving = false
                guard axisLocked else { return }
                axisLocked = false
                let dx = value.translation.width
                let settled = displayedOffset + value.predictedEndTranslation.width
                let velocity = value.velocity.width
                let turn = decide(
                    settled: settled,
                    dx: dx,
                    velocity: velocity,
                    width: size.width
                )
                if turn == .none {
                    decisionText = "回弹"
                    meter.armRelease()
                    animateSettle(velocity: velocity)
                } else {
                    decisionText = turn == .next ? "下一页" : "上一页"
                    request(turn, velocity: velocity)
                }
            }
    }

    /// 与真实阅读器同一套判据：越中线 → 翻；否则看甩动速度。
    private func decide(settled: CGFloat, dx: CGFloat, velocity: CGFloat, width: CGFloat) -> LabTurn {
        if abs(settled) > width / 2 {
            return settled < 0 ? .next : .previous
        }
        let strongEnough = abs(velocity) > 500 && abs(dx) > width * 0.08
        let sameDirection = (velocity < 0) == (dx < 0)
        if strongEnough, sameDirection {
            return velocity < 0 ? .next : .previous
        }
        return .none
    }

    // MARK: - 提交与落位

    private func request(_ turn: LabTurn, velocity: CGFloat) {
        if variant.entry == .turnRequest {
            pendingTurn = turn
            pendingVelocity = velocity
            turnRequest += 1
        } else {
            commit(turn, velocity: velocity)
        }
    }

    private func commit(_ turn: LabTurn, velocity: CGFloat) {
        // 第一行就起表：之后同帧里的任何重算都会算进「松手 → 首帧」。
        meter.armRelease()
        pendingTurn = .none
        if variant.heavyParentWork {
            LabWork.heavyParentWork(around: index)
        }
        index += turn.step
        slots = LabContent.slots(around: index)
        offset += turn == .next ? pageSize.width : -pageSize.width
        if variant.commitNextFrame {
            DispatchQueue.main.async {
                animateSettle(velocity: velocity)
            }
        } else {
            animateSettle(velocity: velocity)
        }
    }

    private func animateSettle(velocity: CGFloat) {
        guard offset != 0 else {
            finishSettle()
            return
        }
        switch variant.curve {
        case .fixedEaseOut:
            withAnimation(.easeOut(duration: 0.28)) {
                offset = 0
            } completion: {
                finishSettle()
            }
        case .velocitySolved:
            withAnimation(.easeOut(duration: solvedDuration(velocity: velocity))) {
                offset = 0
            } completion: {
                finishSettle()
            }
        case .spring:
            withAnimation(
                .interpolatingSpring(
                    stiffness: 220,
                    damping: 26,
                    initialVelocity: Double(abs(velocity)) / 1000
                )
            ) {
                offset = 0
            } completion: {
                finishSettle()
            }
        case .instant:
            offset = 0
            finishSettle()
        }
    }

    /// 剩余距离 ÷ 手指速度，夹在 0.12–0.42s：甩得快就短、拖得久就长。
    private func solvedDuration(velocity: CGFloat) -> Double {
        let remaining = max(abs(offset), 1)
        let speed = max(abs(velocity), 260)
        return min(max(Double(remaining / speed), 0.12), 0.42)
    }

    private func finishSettle() {
        meter.noteAnimationEnd()
        switch variant.prefetch {
        case .sameFrame:
            _ = LabWork.prefetchPages(slots, size: pageSize)
        case .nextRunloop:
            let texts = slots
            let size = pageSize
            DispatchQueue.main.async {
                _ = LabWork.prefetchPages(texts, size: size)
            }
        case .off:
            break
        }
    }

    // MARK: - 读数

    private var hud: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let reading {
                Text("松手 → 首帧 \(milliseconds(reading.releaseToFirstFrameMS))")
                Text("落位期间最大间隔 \(milliseconds(reading.maxGapMS))")
                Text("动画时长 \(milliseconds(reading.animatedMS))")
                Text("落地后首帧 \(milliseconds(reading.landingGapMS))")
                Text("掉帧 \(reading.hitches) / \(reading.frames) 帧")
            } else {
                Text("松手 → 首帧 —")
                Text("落位期间最大间隔 —")
            }
            Text("判定 \(decisionText)")
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9))
    }

    private func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f ms", value)
    }

    private func summary(of reading: LabReading) -> String {
        let first = milliseconds(reading.releaseToFirstFrameMS)
        let gap = milliseconds(reading.maxGapMS)
        let animated = milliseconds(reading.animatedMS)
        return "首帧 \(first) · 最大间隔 \(gap) · 动画 \(animated) · 掉帧 \(reading.hitches)"
    }

    // MARK: - 面板

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                presetPicker
                Divider()
                curvePicker
                HStack(spacing: 12) {
                    entryPicker
                    prefetchPicker
                }
                Toggle("松手时重算父级（模拟 HUD / 章节列表）", isOn: $variant.heavyParentWork)
                Toggle("换页推到下一帧再做", isOn: $variant.commitNextFrame)
                Toggle("跟手位移夹在 ±一页宽", isOn: $variant.clampsOffset)
                Divider()
                sweepControls
                if !sweepLines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sweepLines.indices, id: \.self) { position in
                            Text(sweepLines[position])
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
                if !recentLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近几次手动拖拽")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(recentLines.indices, id: \.self) { position in
                            Text(recentLines[position])
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
            }
            .font(.footnote)
            .padding(14)
        }
        .frame(maxHeight: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var presetPicker: some View {
        Picker("预设", selection: presetBinding) {
            ForEach(LabPreset.all) { preset in
                Text(preset.title).tag(preset.title)
            }
        }
        .pickerStyle(.menu)
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: {
                LabPreset.all.first { $0.variant == variant }?.title ?? "自定义"
            },
            set: { title in
                if let preset = LabPreset.all.first(where: { $0.title == title }) {
                    variant = preset.variant
                }
            }
        )
    }

    private var curvePicker: some View {
        Picker("落位动画", selection: $variant.curve) {
            ForEach(LabSettleCurve.allCases) { curve in
                Text(curve.title).tag(curve)
            }
        }
        .pickerStyle(.segmented)
    }

    private var entryPicker: some View {
        Picker("发起", selection: $variant.entry) {
            ForEach(LabEntryPath.allCases) { path in
                Text(path.title).tag(path)
            }
        }
        .pickerStyle(.menu)
    }

    private var prefetchPicker: some View {
        Picker("预渲染", selection: $variant.prefetch) {
            ForEach(LabPrefetchTiming.allCases) { timing in
                Text(timing.title).tag(timing)
            }
        }
        .pickerStyle(.menu)
    }

    private var sweepControls: some View {
        HStack(spacing: 10) {
            Button {
                runSweep()
            } label: {
                Label(isSweeping ? "正在跑…" : "自动 A/B（九组 × 8 次）", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSweeping)

            Button("停止") {
                sweepTask?.cancel()
                isSweeping = false
            }
            .buttonStyle(.bordered)
            .disabled(!isSweeping)
        }
    }

    // MARK: - 自动 A/B

    private func runSweep() {
        guard !isSweeping, pageSize.width > 0 else { return }
        isSweeping = true
        sweepLines = []
        sweepTask = Task { @MainActor in
            for preset in LabPreset.all {
                variant = preset.variant
                var firstFrames: [Double] = []
                var maxGaps: [Double] = []
                for _ in 0 ..< 8 {
                    if Task.isCancelled {
                        break
                    }
                    offset = -pageSize.width * 0.3
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    decisionText = "自动"
                    request(.next, velocity: 900)
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    let snapshot = meter.reading
                    if let first = snapshot.releaseToFirstFrameMS {
                        firstFrames.append(first)
                    }
                    maxGaps.append(snapshot.maxGapMS)
                }
                if Task.isCancelled {
                    break
                }
                let line = "\(preset.title)\n  首帧 \(medianText(firstFrames)) · 最大间隔 \(medianText(maxGaps))"
                sweepLines.append(line)
            }
            isSweeping = false
        }
    }

    private func medianText(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "—" }
        let sorted = values.sorted()
        return String(format: "%.1f ms", sorted[sorted.count / 2])
    }
}

#Preview {
    LabView()
}
