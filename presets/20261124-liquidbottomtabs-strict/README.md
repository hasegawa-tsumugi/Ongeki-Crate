# Preset: liquidbottomtabs-strict (2026-11-24)

Kyant0/AndroidLiquidGlass `LiquidBottomTabs` 严格对齐版存档（用户要求保留，后面要用）。

## 光学参数（本档特征）

- 面板：`vibrancy + blur(8dp) + lens(24dp, 24dp)`，表面色 40%（0xFFFAFAFA / 0xFF121212）
- 拇指（按压显现）：`lens(10dp×p, 14dp×p, chromaticAberration = true)` —— **有色散**
- 拖拽拇指弹簧（DampedDragAnimation 逐项移植）、按压放大 78/56、面板外扩 16dp、侧倾 4dp
- 几何：面板 64dp / 拇指 56dp / 图标 28dp / 文字 12sp，inset=w×.106、gap=w×.033

## 文件

- `bottom_bar.dart` —— 对应 `lib/src/bottom_bar.dart`
- `glass.frag` —— 对应 `assets/shader/glass.frag`（含 uChroma 七采样色散分支）

## 恢复方法

把两个文件按上面的对应关系拷回，然后 `flutter clean && flutter test`。
