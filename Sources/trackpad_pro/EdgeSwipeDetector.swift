import Foundation

/// 检测"单指从触摸板右边缘起手向内滑动"：开始时回调 onBegan，该手指抬起时回调 onEnded。
/// 纯逻辑，不依赖系统 API，便于测试。
final class EdgeSwipeDetector {
    /// 右边缘判定宽度（占触摸板比例）：手指落下时 x > 1 - edgeWidth 才算从边缘起手。
    var edgeWidth: Float
    /// 向内滑动多少（归一化距离）后触发。
    var activationDistance: Float
    /// 顶部排除高度：起手位置 y > 1 - topExclusion 时不触发（把右上角留给调整大小手势）。
    var topExclusion: Float = 0

    var onBegan: (() -> Void)?
    var onEnded: (() -> Void)?

    private var startPositions: [Int32: (x: Float, y: Float)] = [:]
    private var activeFingerId: Int32?

    init(edgeWidth: Float, activationDistance: Float) {
        self.edgeWidth = edgeWidth
        self.activationDistance = activationDistance
    }

    /// 每帧调用。fingers 为当前所有正在接触的手指。
    func update(_ fingers: [Finger]) {
        let ids = Set(fingers.map { $0.id })

        // 记录新手指的起始位置，清理已抬起的。
        for f in fingers where startPositions[f.id] == nil {
            startPositions[f.id] = (f.x, f.y)
        }
        startPositions = startPositions.filter { ids.contains($0.key) }

        // 已激活：起手的那根手指抬起即结束。
        if let active = activeFingerId {
            if !ids.contains(active) {
                activeFingerId = nil
                onEnded?()
            }
            return
        }

        // 未激活：只在单指时判定，避免和双指滚动、多指手势冲突。
        guard fingers.count == 1, let f = fingers.first, let start = startPositions[f.id] else { return }
        if start.y > 1 - topExclusion { return }
        if start.x > 1 - edgeWidth && f.x < start.x - activationDistance {
            activeFingerId = f.id
            onBegan?()
        }
    }

    /// 强制结束（例如程序退出前）。
    func reset() {
        if activeFingerId != nil {
            activeFingerId = nil
            onEnded?()
        }
        startPositions.removeAll()
    }
}
