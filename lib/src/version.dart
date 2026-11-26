/// App 版本标识。
///
/// 唯一来源是 `pubspec.yaml` 的 `version`，这里必须手工保持同步 ——
/// `test/version_sync_test.dart` 会读 pubspec 逐字比对，不同步直接测试失败。
///
/// 为什么要这份常量：`pubspec` 的版本只有打包时用得到，界面里读不到。
/// 之前版本号长期停在 0.0.1+1 从没 bump，导致「装的是哪一版」在手机上
/// 完全无从判断，反复出现「改了没生效」的误判。
///
/// **版本命名规则**（2026-11-24 用户定）：
/// - 平时一律是测试版：`0.1.2-beta1`、`0.1.2-beta2`……beta 数字每次出包 +1
/// - **不再有 build 号**（`+N`），也不在任何地方显示
/// - 用户明确说「出正式版」时才不带 beta，即 `0.1.2`
///
/// 出包前流程：改 pubspec 的 `version` → 改本文件两行 → 构建。
library;

/// 主版本号，例如 `0.1.2`。
const String appVersion = '0.1.3';

/// beta 序号。**0 = 正式版**（versionName 不带 `-beta` 后缀）。
///
/// 改这个数字就是「当前版本的第几个测试包」。正式版把它置 0。
const int appBeta = 1;

/// 完整版本标签，例如 `0.1.2-beta1` / 正式版 `0.1.2`。
///
/// 写成 `const` 而不是 getter：常量插值在编译期折叠成一个完整字面量，
/// AOT 快照里能直接搜到 `0.1.2-beta1`，`tool/check_apk.py` 才能校验包里的版本。
const String appVersionLabel = appBeta > 0 ? '$appVersion-beta$appBeta' : appVersion;
