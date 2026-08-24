import Foundation

/// 一根正在接触触摸板的手指。坐标为归一化坐标：x 0(左)~1(右)，y 0(下)~1(上)。
struct Finger {
    let id: Int32
    let x: Float
    let y: Float
    let pressure: Float
    let state: Int32
    let timestamp: TimeInterval
}
