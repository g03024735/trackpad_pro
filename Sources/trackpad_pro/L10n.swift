import Foundation

/// 极简本地化：系统首选语言是中文则显示中文，否则英文。
/// 不用 .lproj 资源包——.app 由脚本手工组装，资源包一旦漏拷 Bundle.module 会直接崩溃；
/// 内联双语没有这个风险，且两种文案在调用处并排可见，改动时不易漏翻。
let isChineseUI: Bool = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false

@inline(__always)
func tr(_ zh: String, _ en: String) -> String { isChineseUI ? zh : en }
