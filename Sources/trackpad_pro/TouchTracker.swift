import CMultitouch
import Foundation

private let stateMakeTouch = Int32(MTTouchStateMakeTouch.rawValue)
private let stateTouching = Int32(MTTouchStateTouching.rawValue)
private let stateBreakTouch = Int32(MTTouchStateBreakTouch.rawValue)

/// 通过私有框架 MultitouchSupport 持续接收触摸板原始触点数据，缓存当前帧。
final class TouchTracker {
    static let shared = TouchTracker()

    private let lock = NSLock()
    private var fingersByDevice: [UnsafeMutableRawPointer: [Finger]] = [:]
    private var lastLifted: Finger?
    private var devices: [UnsafeMutableRawPointer] = []
    private var lastDebugPrint: TimeInterval = 0
    var debug = false

    /// 每帧回调（在触摸板数据线程上调用），参数为所有设备上正在接触的手指。回调必须轻量。
    var onFrame: (([Finger]) -> Void)?

    private init() {}

    /// 枚举所有多点触控设备并开始监听。返回设备数量。
    @discardableResult
    func start() -> Int {
        guard let list = MTDeviceCreateList()?.takeRetainedValue() else { return 0 }
        let count = CFArrayGetCount(list)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            MTRegisterContactFrameCallback(dev, mtContactCallback)
            MTDeviceStart(dev, 0)
            devices.append(dev)
        }
        return devices.count
    }

    func stop() {
        for dev in devices {
            MTUnregisterContactFrameCallback(dev, mtContactCallback)
            MTDeviceStop(dev)
        }
        devices.removeAll()
    }

    fileprivate func update(device: UnsafeMutableRawPointer, touches: UnsafeBufferPointer<MTTouch>, timestamp: Double) {
        let now = Date().timeIntervalSince1970
        var touching: [Finger] = []
        for t in touches {
            let f = Finger(
                id: t.identifier,
                x: t.normalized.position.x,
                y: t.normalized.position.y,
                pressure: t.pressure,
                state: t.state,
                timestamp: now
            )
            switch t.state {
            case stateMakeTouch, stateTouching:
                touching.append(f)
            case stateBreakTouch:
                lock.lock(); lastLifted = f; lock.unlock()
            default:
                break
            }
        }

        lock.lock()
        // 手指全部抬起时框架会给一帧空数据；也有时只给 BreakTouch。此处记录最后一根抬起的手指。
        if touching.isEmpty, let prev = fingersByDevice[device]?.first, lastLifted == nil || lastLifted!.id != prev.id {
            lastLifted = Finger(id: prev.id, x: prev.x, y: prev.y, pressure: prev.pressure, state: prev.state, timestamp: now)
        }
        fingersByDevice[device] = touching
        let all = fingersByDevice.values.flatMap { $0 }
        lock.unlock()
        onFrame?(all)

        if debug, !touching.isEmpty, now - lastDebugPrint > 0.1 {
            lastDebugPrint = now
            let desc = touching.map { String(format: "#%d (x=%.2f y=%.2f p=%.1f)", $0.id, $0.x, $0.y, $0.pressure) }
            print("[touch] \(desc.joined(separator: "  "))")
        }
    }

    /// 当前所有正在接触触摸板的手指。
    func touchingFingers() -> [Finger] {
        lock.lock(); defer { lock.unlock() }
        return fingersByDevice.values.flatMap { $0 }
    }

    /// 用于判定一次点击发生在触摸板的什么位置：
    /// 优先取当前正在接触的手指；若没有（轻点已抬起），回溯最近抬起的手指。
    func fingerForClick(config: Config) -> Finger? {
        if let fake = Self.fakeFinger { return fake }
        let fingers = touchingFingers()
        if config.requireSingleFinger && fingers.count > 1 { return nil }
        if let f = fingers.first { return f }
        lock.lock(); defer { lock.unlock() }
        if let l = lastLifted, Date().timeIntervalSince1970 - l.timestamp < config.tapFallbackInterval {
            return l
        }
        return nil
    }
}

extension TouchTracker {
    /// 仅供自动化测试：TRACKPAD_PRO_FAKE_FINGER="x,y" 时所有点击都视为手指在该归一化坐标。
    static let fakeFinger: Finger? = {
        guard let raw = ProcessInfo.processInfo.environment["TRACKPAD_PRO_FAKE_FINGER"] else { return nil }
        let parts = raw.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return Finger(id: -1, x: parts[0], y: parts[1], pressure: 0, state: 4, timestamp: 0)
    }()
}

/// C 回调：必须是无捕获的全局函数。
private func mtContactCallback(
    device: MTDeviceRef?,
    touches: UnsafeMutablePointer<MTTouch>?,
    numTouches: Int32,
    timestamp: Double,
    frame: Int32
) {
    guard let device else { return }
    let buf = UnsafeBufferPointer(start: touches, count: Int(max(0, numTouches)))
    TouchTracker.shared.update(device: device, touches: buf, timestamp: timestamp)
}
