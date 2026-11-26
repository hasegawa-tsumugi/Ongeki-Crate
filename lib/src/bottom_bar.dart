import 'dart:math' as math;

import 'package:fluid_glass/fluid_glass.dart';
import 'package:material_ui/material_ui.dart';

/// 三个主页签。顺序即底部胶囊里从左到右的顺序。
enum AppTab { home, tools, profile }

/// 玻璃描边的羽化半径。
///
/// 库的默认值 `Highlight.standard` 是 width 0.5dp / blurRadius 0.25dp ——
/// 那是「一根发丝」的量级，真机上是一条很硬的亮线。这里把羽化放宽到 1dp，
/// 宽度和亮度都不动：描边不会变粗变亮，只是边缘散开、和玻璃融在一起。
const double _rimBlur = 1.0;

/// 底栏两条玻璃（tab 面板 + 右侧圆钮）共用的描边。
///
/// 顶层函数而不是每次 build 现造闭包：`DrawBackdrop` 按标识比较
/// `HighlightGetter`，每帧一个新闭包会一直走「高光变了」那条重绘路径。
Highlight _rim() => Highlight.standard.copyWith(blurRadius: _rimBlur);

extension AppTabInfo on AppTab {
  String get label => switch (this) {
        AppTab.home => '主页',
        AppTab.tools => '工具',
        AppTab.profile => '我的',
      };

  /// 选中/未选中用同一族图标，只换粗细档，避免切换时形状跳变。
  IconData get icon => switch (this) {
        AppTab.home => Icons.home_outlined,
        AppTab.tools => Icons.widgets_outlined,
        AppTab.profile => Icons.person_outline,
      };

  IconData get activeIcon => switch (this) {
        AppTab.home => Icons.home_rounded,
        AppTab.tools => Icons.widgets_rounded,
        AppTab.profile => Icons.person_rounded,
      };
}

/// 底部导航：左侧一颗液态玻璃胶囊（三页签、可拖拽选择），右侧独立圆钮（搜索）。
///
/// **这里不再有手写的玻璃。**
///
/// 整个组件直接由 [`fluid_glass`] 提供 —— 它是 Kyant0/AndroidLiquidGlass
/// （也就是参考 App 用的那个库）的 Flutter 移植，声明「refraction, dispersion,
/// highlight and shadow maths are carried over from the original AGSL and
/// Kotlin sources unchanged」。所以下面这些全部由库给出，而不是本文件近似：
///
/// * 三层结构：面板 `vibrancy + blur(2dp) + lens(24dp, 24dp)`、
///   隐藏的 accent 副本（被选中胶囊放大并染色）、选中胶囊
///   `lens(10dp×p, 14dp×p, chromaticAberration: true)`；
/// * 交互：按压膨胀 78/56、拖拽跟手（DampedDragAnimation 同一组弹簧）、
///   速度挤压拉伸、面板 4dp 侧倾、跟手高光 InteractiveHighlight；
/// * 画序：shadow → backdrop → surface → content → highlight → inner shadow；
/// * 几何：面板 64dp、内边距 4dp、行高 56dp、三格等分；
/// * 表面色：`0xFFFAFAFA` / `0xFF121212` @ 40%（库的 `LiquidGlassColors` 默认，
///   与参考 App 一致）。
///
/// 只有两处不吃库的默认值，都是用户点名要的、且都作用在左右两条玻璃上：
/// 面板模糊 8dp → 2dp（补丁在 `third_party/fluid_glass`，与右侧圆钮的
/// `blur(2)` 对齐），描边羽化 0.25dp → [_rimBlur]（本文件 `_rim`）。
///
/// 曾经的实现是本文件里逐参数手抄一遍（约 800 行），结果是"看着像、实际不像"：
/// 折射在真机上不生效、高光没有法线调制、选中态没有 accent 副本。既然上游库
/// 已有逐行对应的 Flutter 移植，就没有理由再自己近似一遍。
///
/// **调用方必须先把这个组件要折射的内容包进 `BackdropLayer`**，并把同一个
/// `LayerBackdrop` 传进来 —— 玻璃折的是"它下面的东西"，没法凭空造。
class LiquidGlassBar extends StatelessWidget {
  const LiquidGlassBar({
    super.key,
    required this.current,
    required this.onTab,
    required this.onSearch,
    required this.backdrop,
  });

  final AppTab current;
  final ValueChanged<AppTab> onTab;
  final VoidCallback onSearch;

  /// 页面内容被捕获进来的那个 backdrop（`BackdropLayer` 用的同一个实例）。
  final LayerBackdrop backdrop;

  /// 面板高 = 库的 `LiquidBottomTabs.defaultHeight`（64dp），右侧圆钮同高。
  static const double barHeight = LiquidBottomTabs.defaultHeight;

  static double _width(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  /// 左右外边距。
  static double insetOf(BuildContext context) =>
      (_width(context) * .106).clamp(16.0, 56.0);

  /// 胶囊高度 = 右侧圆钮直径 = 库的 `LiquidBottomTabs.defaultHeight`（64dp）。
  ///
  /// **恒为 64dp，不按屏高缩放**。库里的几何是围绕这个值定的：行高 56dp、
  /// 按压膨胀 78/56、内边距 4dp。按屏高比例压小会导致「28dp 图标 + 2dp 间距
  /// + 12sp 文字」装不进行高（实测 844×390 横屏按 14% 折算会溢出 3.4px），
  /// 而且压小后按压膨胀的相对幅度也就跟参考 App 不一致了。
  static double heightOf(BuildContext context) => barHeight;

  /// 胶囊与圆钮之间的间隙。
  static double gapOf(BuildContext context) =>
      (_width(context) * .033).clamp(8.0, 16.0);

  /// 底边距。取比例值与安全区中较大者 —— 三键导航设备的安全区有 48dp，
  /// 按比例算出来的值会被导航栏压住。横屏同理收一道。
  static double bottomOf(BuildContext context) {
    final safe = MediaQuery.viewPaddingOf(context).bottom;
    final size = MediaQuery.sizeOf(context);
    final byWidth = size.width * .0604;
    final byHeight = size.height * .10;
    return math.max(math.min(byWidth, byHeight), safe + 8);
  }

  /// 给滚动列表留的底部避让：底栏顶边再往上 16dp。
  static double clearance(BuildContext context) =>
      bottomOf(context) + heightOf(context) + 16;

  @override
  Widget build(BuildContext context) {
    // 键盘弹出时不挡输入框。
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    final padding = MediaQuery.viewPaddingOf(context);
    final height = heightOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 参考 App 的 tab 内容色：浅色黑、深色白。选中态的强调色由库的
    // accent 副本负责（`LiquidGlassColors.accent`），这里不自己染。
    final content = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

    return Positioned(
      left: insetOf(context) + padding.left,
      right: insetOf(context) + padding.right,
      bottom: bottomOf(context),
      height: height,
      // 玻璃的选中胶囊会画到面板外（按压时放大到 1.39 倍、带投影）。
      // Flutter 的 Stack 一见溢出就裁剪，会把圆角削平 —— 参考实现是
      // Compose 的 Box，不裁剪。
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              Expanded(
                child: LiquidBottomTabs(
                  selectedTabIndex: current.index,
                  onTabSelected: (int index) => onTab(AppTab.values[index]),
                  backdrop: backdrop,
                  tabsCount: AppTab.values.length,
                  height: height,
                  // 系统要求减少动效时：胶囊直接跳过去，不再弹簧/拖拽。
                  isInteractive: !MediaQuery.disableAnimationsOf(context),
                  highlight: _rim,
                  children: [
                    for (final tab in AppTab.values)
                      LiquidBottomTab(
                        // 页签在树里存在两份（可见行 + 被选中胶囊放大的 accent
                        // 副本），所以这个 key 会匹配到两个 element —— 测试里
                        // 用 `.first` 取可见那一行。
                        key: ValueKey('tab-${tab.name}'),
                        onPressed: () => onTab(tab),
                        children: [
                          // 图标 28dp、文字 12sp —— 参考 App 的实值。
                          // 标签与图标的 2dp 间距由 LiquidBottomTab 给。
                          Icon(tab.icon, size: 28, color: content),
                          Text(
                            tab.label,
                            maxLines: 1,
                            style: TextStyle(
                              color: content,
                              fontSize: 12,
                              leadingDistribution: TextLeadingDistribution.even,
                            ),
                            // 底栏高度固定，不跟系统字号放大。
                            textScaler: TextScaler.noScaling,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              SizedBox(width: gapOf(context)),
              // 右侧搜索钮：同一个库的 LiquidButton，圆角胶囊 + 等宽内容 = 正圆。
              // 不传 tint ⇒ 无色玻璃（沿用本项目"按钮不要颜色"的要求），
              // 但按压挤压、跟手高光、拖拽形变都来自库本身。
              //
              // 不传 `tooltip`：库会因此包一层 Tooltip，长按弹出一块文字说明，
              // 这个底栏上不该有（2026-11-26 要求）。无障碍标签改由外层
              // Semantics 提供，读屏仍然读得出这是搜索键。
              Semantics(
                label: '搜索与筛选',
                child: LiquidButton(
                  key: const ValueKey('search-button'),
                  onPressed: onSearch,
                  backdrop: backdrop,
                  height: height,
                  padding: EdgeInsets.zero,
                  isInteractive: !MediaQuery.disableAnimationsOf(context),
                  highlight: _rim,
                  child: SizedBox(
                    width: height,
                    height: height,
                    child: Center(
                      child: Icon(Icons.search_rounded, size: 28, color: content),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
