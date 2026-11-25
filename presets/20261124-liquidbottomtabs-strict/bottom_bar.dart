import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'glass_shader.dart';
import 'motion.dart';
import 'theme.dart';

/// 三个主页签。顺序即底部胶囊里从左到右的顺序。
enum AppTab { home, tools, profile }

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

/// 底部导航：左侧一颗「液态玻璃」胶囊（三页签，可拖拽拇指），右侧独立圆钮（搜索）。
///
/// **玻璃与交互严格对齐 Kyant0/AndroidLiquidGlass 的 LiquidBottomTabs**
/// （Apache-2.0，kmp 分支）：三层渲染（面板 / 拖拽拇指 / 按压高光阴影）、
/// DampedDragAnimation 弹簧参数、78/56 按压缩放、速度挤压拉伸、
/// 面板 4dp 拖拽侧倾，全部按源码逐项移植。光学参数取组件实值：
/// 面板 blur(8dp) + lens(24dp, 24dp)，拇指 lens(10dp, 14dp)×press 带色散。
///
/// **几何**（面板 64dp / 拇指 56dp / 图标 28dp / 文字 12sp / 内边距 4dp 为
/// 项目实值；外框比例来自效果图实测 1200×2608）：
///
/// | 项 | 像素 | 占屏宽 |
/// | --- | --- | --- |
/// | 左右外边距 | 127 | 10.6% |
/// | 胶囊高／圆钮直径 | 165 | 64dp（≤ 屏高 14%） |
/// | 胶囊与圆钮间隙 | 39 | 3.3% |
/// | 距屏幕底边 | 73 | 6.0% |
class LiquidGlassBar extends StatelessWidget {
  const LiquidGlassBar({
    super.key,
    required this.current,
    required this.onTab,
    required this.onSearch,
  });

  final AppTab current;
  final ValueChanged<AppTab> onTab;
  final VoidCallback onSearch;

  static double _width(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  /// 左右外边距。
  static double insetOf(BuildContext context) =>
      (_width(context) * .106).clamp(16.0, 56.0);

  /// 胶囊高度 = 右侧圆钮直径 = 项目 LiquidBottomTabs 面板高 64dp。
  ///
  /// 只在横屏（568×240 这类）压一道「不超过屏高 14%」，竖屏永远是 64dp。
  static double heightOf(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return math.min(64.0, size.height * .14).clamp(40.0, 64.0);
  }

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
    // 键盘弹出时不挡输入框，和旧圆钮的规则一致。
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    final padding = MediaQuery.viewPaddingOf(context);
    final height = heightOf(context);
    return Positioned(
      left: insetOf(context) + padding.left,
      right: insetOf(context) + padding.right,
      bottom: bottomOf(context),
      height: height,
      child: Row(
        children: [
          Expanded(
              child: _TabsPill(current: current, onTab: onTab, height: height)),
          SizedBox(width: gapOf(context)),
          _SearchButton(
              key: const ValueKey('search-button'),
              onPressed: onSearch,
              size: height),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 光学与组件常量。全部按 LiquidBottomTabs.kt 的 dp 实值 ÷ 面板高 64dp 折算，
// 这样极端尺寸下整组参数等比缩放、参考机（64dp 面板）上与项目逐 dp 一致。
// ---------------------------------------------------------------------------

/// 面板模糊 σ：`blur(8dp)`。
const double kGlassBlurRadius = 8 / 64;

/// 面板折射带宽：`lens(24dp, 24dp)` 的 refractionHeight。
const double kGlassRefractionHeight = 24 / 64;

/// 面板折射位移：`lens(24dp, 24dp)` 的 refractionAmount（绝对位移 = 带高）。
const double kGlassRefractionAmount = 24 / 64;

/// 拇指折射带宽（按压显现）：`lens(10dp, 14dp, chromaticAberration)`。
const double kThumbRefractionHeight = 10 / 64;

/// 拇指折射位移（按压显现）。注意带宽≠位移，这是项目拇指的实值比例。
const double kThumbRefractionAmount = 14 / 64;

/// 拇指高 / 面板高 = 56/64。
const double kThumbHeightFrac = 56 / 64;

/// 面板行内边距（每侧）/ 面板高 = 4dp。
const double kTabPadFrac = 4 / 64;

/// 页签图标 / 面板高 = 28dp。
const double kTabIconFrac = 28 / 64;

/// 页签文字 / 面板高 = 12dp（sp @ fontScale 1）。
const double kTabLabelFrac = 12 / 64;

/// 图标与文字间距 / 面板高 = 2dp。
const double kTabGapFrac = 2 / 64;

/// 按压时拇指放大到 78dp / 56dp。来源 DampedDragAnimation(pressedScale)。
const double kPressedScale = 78 / 56;

/// 按压时面板整层外扩 16dp / 面板宽。来源面板 drawBackdrop 的 layerBlock。
const double kPanelPressSpread = 16 / 64;

/// Highlight.Default 折算：白 0.5 × |dot(法线, 45°)| ≈ 0.707 平边。
const double kRimInk = .5 * 0.707;

// ---------------------------------------------------------------------------
// DampedDragAnimation.kt 的 Flutter 等价：五组弹簧 + 速度形变 + 吸附。
// ---------------------------------------------------------------------------

class _DampedDrag extends ChangeNotifier {
  _DampedDrag({required TickerProvider vsync, required this.tabsCount})
      : value = AnimationController.unbounded(vsync: vsync),
        press = AnimationController.unbounded(vsync: vsync),
        glow = AnimationController.unbounded(vsync: vsync),
        lean = AnimationController.unbounded(vsync: vsync),
        scaleX = AnimationController.unbounded(vsync: vsync, value: 1),
        scaleY = AnimationController.unbounded(vsync: vsync, value: 1),
        velocity = AnimationController.unbounded(vsync: vsync) {
    value.addListener(_trackVelocity);
    for (final c in [value, press, glow, lean, scaleX, scaleY, velocity]) {
      c.addListener(notifyListeners);
    }
  }

  final int tabsCount;

  /// 当前位置（页签单位，0..tabsCount-1 连续值）。弹簧跟手。
  final AnimationController value;

  /// 按压进度 0..1（拇指层按压显现）。spring(1, 1000)。
  final AnimationController press;

  /// 按压进度（跟手高光）。spring(0.5, 300)，比 press 弹一点。
  final AnimationController glow;

  /// 拖拽侧倾累计位移（物理像素）。松手 spring(1, 300) 回 0。
  final AnimationController lean;

  /// 拇指缩放（78/56 按压 + 速度形变叠在上面）。
  final AnimationController scaleX;
  final AnimationController scaleY;

  /// 平滑后的归一化速度（单位：整段范围/秒）。spring(0.5, 300)。
  final AnimationController velocity;

  static final _valueSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1000, ratio: 1);
  static final _pressSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1000, ratio: 1);
  static final _glowSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 300, ratio: .5);
  static final _scaleXSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 250, ratio: .6);
  static final _scaleYSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 250, ratio: .7);
  static final _velocitySpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 300, ratio: .5);
  static final _leanSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 300, ratio: 1);

  final Stopwatch _clock = Stopwatch()..start();
  double _lastTick = 0;
  double _lastValue = 0;
  bool _releasePending = false;

  /// 参考实现的 targetValue：弹簧当前瞄准的目标。
  double _target = 0;
  double get targetValue => _target;

  /// 按压缩放后的合成形变（含速度挤压拉伸），直接喂 Transform.scale。
  double get deformedScaleX {
    final v = (velocity.value * .75).clamp(-.2, .2);
    return scaleX.value / (1 - v);
  }

  double get deformedScaleY {
    final v = (velocity.value * .25).clamp(-.2, .2);
    return scaleY.value * (1 - v);
  }

  /// 按下：press→1、scale→78/56。对应 DampedDragAnimation.press()。
  void pressDown() {
    _releasePending = false;
    press.animateWith(SpringSimulation(_pressSpring, press.value, 1, 0));
    glow.animateWith(SpringSimulation(_glowSpring, glow.value, 1, 0));
    scaleX.animateWith(
        SpringSimulation(_scaleXSpring, scaleX.value, kPressedScale, 0));
    scaleY.animateWith(
        SpringSimulation(_scaleYSpring, scaleY.value, kPressedScale, 0));
  }

  /// 松手：等值接近目标后 press→0、scale→1。对应 release() 的延迟释放。
  void release() {
    _releasePending = true;
    _maybeRelease();
  }

  void _maybeRelease() {
    if (!_releasePending) return;
    final settled = (value.value - targetValue).abs() <
        (tabsCount - 1) * .025; // 参考阈值 = 值域 2.5%
    if (!settled && value.isAnimating) return;
    _releasePending = false;
    press.animateWith(SpringSimulation(_pressSpring, press.value, 0, 0));
    glow.animateWith(SpringSimulation(_glowSpring, glow.value, 0, 0));
    scaleX.animateWith(SpringSimulation(_scaleXSpring, scaleX.value, 1, 0));
    scaleY.animateWith(SpringSimulation(_scaleYSpring, scaleY.value, 1, 0));
  }

  /// 拖拽中：弹簧追新目标。对应 updateValue()。
  void updateValue(double target) {
    final t = target.clamp(0.0, (tabsCount - 1).toDouble());
    _target = t;
    value.animateWith(SpringSimulation(_valueSpring, value.value, t, _valueVel));
  }

  /// 程序化移动到某页签（点按 / 吸附）：按压脉冲 → 弹过去 → 延迟释放。
  /// 对应 animateToValue()。
  void animateToValue(double target) {
    pressDown();
    updateValue(target);
    release();
  }

  /// 瞬时速度（值单位/秒）。
  double get _valueVel {
    final t = _clock.elapsedMicroseconds / 1e6;
    final dt = t - _lastTick;
    return dt > 1e-4 ? (value.value - _lastValue) / dt : 0;
  }

  void _trackVelocity() {
    final t = _clock.elapsedMicroseconds / 1e6;
    final dt = t - _lastTick;
    if (dt > 1e-4) {
      // 参考：每帧把 value 位置喂 VelocityTracker，除以值域归一化后
      // 再用 spring(0.5, 300) 平滑一遍 —— 形变跟手但不抖。
      final inst = (value.value - _lastValue) / dt / (tabsCount - 1);
      velocity.animateWith(
          SpringSimulation(_velocitySpring, velocity.value, inst, 0));
    }
    _lastTick = t;
    _lastValue = value.value;
    _maybeRelease();
  }

  /// 拖拽结束回弹侧倾。参考 offsetAnimation.animateTo(0, spring(1,300,0.5))。
  void settleLean() {
    lean.animateWith(SpringSimulation(_leanSpring, lean.value, 0, 0));
  }

  @override
  void dispose() {
    value.removeListener(_trackVelocity);
    for (final c in [value, press, glow, lean, scaleX, scaleY, velocity]) {
      c.dispose();
    }
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// 左侧胶囊：面板（三页签）+ 可拖拽玻璃拇指。
// ---------------------------------------------------------------------------

class _TabsPill extends StatefulWidget {
  const _TabsPill(
      {required this.current, required this.onTab, required this.height});

  final AppTab current;
  final ValueChanged<AppTab> onTab;
  final double height;

  @override
  State<_TabsPill> createState() => _TabsPillState();
}

class _TabsPillState extends State<_TabsPill> with TickerProviderStateMixin {
  late final _DampedDrag _drag;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.current.index;
    _drag = _DampedDrag(vsync: this, tabsCount: AppTab.values.length);
  }

  @override
  void didUpdateWidget(_TabsPill old) {
    super.didUpdateWidget(old);
    final i = widget.current.index;
    if (i != _selected) {
      // 外部切页（还原状态等）：拇指弹过去，不回调 onTab。
      setState(() => _selected = i);
      _drag.animateToValue(i.toDouble());
    }
  }

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _commit(int i) {
    if (i == _selected) return;
    setState(() => _selected = i);
    widget.onTab(AppTab.values[i]);
  }

  void _onTapTab(int i) {
    _drag.animateToValue(i.toDouble());
    _commit(i);
  }

  void _onDragStart(DragStartDetails _) => _drag.pressDown();

  void _onDragUpdate(DragUpdateDetails details, double tabWidth) {
    _drag.updateValue(_drag.targetValue + details.delta.dx / tabWidth);
    _drag.lean.value += details.delta.dx;
  }

  void _onDragEnd(DragEndDetails _, double tabWidth) {
    final target =
        _drag.targetValue.round().clamp(0, AppTab.values.length - 1);
    _drag.animateToValue(target.toDouble());
    _drag.settleLean();
    _commit(target);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final h = widget.height;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final pad = h * kTabPadFrac;
      final thumbH = h * kThumbHeightFrac;
      final tabW = (w - 2 * pad) / 3;
      return ListenableBuilder(
        listenable: _drag,
        builder: (context, _) {
          final value = _drag.value.value;
          final press = _drag.press.value;
          final leanFrac =
              (w > 0 ? _drag.lean.value / w : 0.0).clamp(-1.0, 1.0);
          // 参考 panelOffset：4dp × sign × easeOut(|fraction|)。
          final lean = h * kTabPadFrac *
              (leanFrac >= 0 ? 1 : -1) *
              _easeOut.transform(leanFrac.abs());
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // —— 第一层：面板（参考 panel Row）——
              Transform.translate(
                offset: Offset(lean, 0),
                child: Transform.scale(
                  // 参考 layerBlock：按压时整层外扩 16dp/宽。
                  scale: 1 + (h * kPanelPressSpread) / w * press,
                  child: SizedBox(
                    height: h,
                    child: _Glass(
                      key: const ValueKey('tab-pill'),
                      height: h,
                      radius: h / 2,
                      dark: dark,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: _onDragStart,
                        onHorizontalDragUpdate: (d) =>
                            _onDragUpdate(d, tabW),
                        onHorizontalDragEnd: (d) => _onDragEnd(d, tabW),
                        onHorizontalDragCancel: () {
                          _drag.release();
                          _drag.settleLean();
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 跟手高光（InteractiveHighlight）：铺在表面之上、
                            // 内容之下。位置 = 拇指中心（参考的 position lambda）。
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _GlowPainter(
                                    center: Offset(pad + (value + .5) * tabW,
                                        h / 2),
                                    progress: _drag.glow.value,
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (final tab in AppTab.values)
                                  Expanded(
                                    child: _TabButton(
                                      key: ValueKey('tab-${tab.name}'),
                                      tab: tab,
                                      height: h,
                                      onTap: () => _onTapTab(tab.index),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // —— 第二层：可拖拽玻璃拇指（参考 thumb Box）——
              Positioned(
                left: pad + value * tabW + lean,
                top: (h - thumbH) / 2,
                width: tabW,
                height: thumbH,
                child: IgnorePointer(
                child: Transform.scale(
                  scaleX: _drag.deformedScaleX,
                  scaleY: _drag.deformedScaleY,
                  child: _ThumbGlass(
                    key: const ValueKey('tab-thumb'),
                    height: thumbH,
                    radius: thumbH / 2,
                    dark: dark,
                    press: press,
                    dpr: dpr,
                  ),
                ),
                ),
              ),
            ],
          );
        },
      );
    });
  }
}

/// 参考 EaseOut = Cubic(0, 0, .58, 1)。
const Cubic _easeOut = Cubic(0, 0, .58, 1);

// ---------------------------------------------------------------------------
// 页签内容。项目 LiquidBottomTab：Column(spacedBy 2dp) + 28dp 图标 + 12sp 文字，
// 选中强调完全交给玻璃拇指，内容样式统一。
// ---------------------------------------------------------------------------

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.height,
    required this.onTap,
  });

  final AppTab tab;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : const Color(0xFF111111);
    return Semantics(
      button: true,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tab.icon, size: height * kTabIconFrac, color: ink),
            SizedBox(height: height * kTabGapFrac),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: height * kTabLabelFrac,
                height: 1.1,
                fontWeight: FontWeight.w500,
                color: ink,
                leadingDistribution: TextLeadingDistribution.even,
              ),
              // 页签名不跟系统字号放大：底栏高度固定 64dp，
              // 放大字号会先把三个字挤出胶囊。
              textScaler: TextScaler.noScaling,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 面板玻璃：vibrancy ⇒ blur(8dp) ⇒ lens(24dp, 24dp) ⇒ 表面色 ⇒ 描边/高光/阴影。
// 光学管线与「为什么拆两层 BackdropFilter」见 glass.frag 头注。
// ---------------------------------------------------------------------------

class _Glass extends StatefulWidget {
  const _Glass({
    super.key,
    required this.child,
    required this.height,
    required this.radius,
    required this.dark,
  });

  final Widget child;
  final double height;
  final double radius;
  final bool dark;

  @override
  State<_Glass> createState() => _GlassState();
}

class _GlassState extends State<_Glass> {
  ui.FragmentShader? _shader;
  ui.ImageFilter? _filter;
  Size? _shaderSize;
  double? _shaderDpr;

  @override
  void initState() {
    super.initState();
    // 首帧可能还没加载完（加载是异步的）。完成后重画一次；失败是终态，
    // 之后一直走模糊回退，不重试。
    if (!GlassShader.settled) {
      GlassShader.preload().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  /// 折射滤镜。返回 null 表示走纯模糊回退。
  ///
  /// 按 (尺寸, dpr) 缓存：这两个值不变时 uniform 也不必重设，底栏跟着
  /// 列表滚动每帧重建也不会反复分配 shader。
  ui.ImageFilter? _refraction(Size logical, double dpr) {
    if (!ui.ImageFilter.isShaderFilterSupported) return null;
    if (_filter != null && _shaderSize == logical && _shaderDpr == dpr) {
      return _filter;
    }
    final shader = GlassShader.newShader();
    if (shader == null) return null;
    setRefractionUniforms(
      shader,
      logical,
      dpr,
      radius: widget.radius,
      band: logical.height * kGlassRefractionHeight,
      amount: logical.height * kGlassRefractionAmount,
    );
    _shader = shader;
    _shaderSize = logical;
    _shaderDpr = dpr;
    return _filter = ui.ImageFilter.shader(shader);
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final shape = BorderRadius.circular(widget.radius);
    // 表面色照搬 Kyant0 的 LiquidBottomTabs：0xFFFAFAFA / 0xFF121212 @ 40%
    // 平涂。近白 0.92 会把底下的折射整个盖没 —— 液态玻璃的通透感就没了。
    final surface =
        (dark ? const Color(0xFF121212) : const Color(0xFFFAFAFA))
            .withValues(alpha: .4);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final h = widget.height;

    return Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        // Shadow.Default：radius 24dp、offset y 4dp、黑 0.1。
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .1),
            blurRadius: h * 24 / 64,
            offset: Offset(0, h * 4 / 64),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          // 约束无界时算不出比例，直接用 0：模糊与折射都退化成「不处理」。
          final sigma = constraints.hasBoundedHeight && size.height.isFinite
              ? size.height * kGlassBlurRadius
              : 0.0;
          final refraction = constraints.hasBoundedHeight &&
                  constraints.hasBoundedWidth &&
                  sigma > 0
              ? _refraction(size, dpr)
              : null;

          return ClipRRect(
            borderRadius: shape,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 第一层：糊背景。也是没有 shader 时的全部效果。
                BackdropFilter(
                  filter: ui.ImageFilter.blur(
                      sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
                  child: const SizedBox.expand(),
                ),
                // 第二层：折射。它读到的 backdrop 已经是上一层糊过的那张，
                // 于是「先模糊、再掰弯」的顺序天然成立。
                if (refraction != null)
                  BackdropFilter(
                      filter: refraction, child: const SizedBox.expand()),
                // 第三层：表面色 + 内容。
                Container(
                  decoration:
                      BoxDecoration(borderRadius: shape, color: surface),
                  child: widget.child,
                ),
                // 第四层：Highlight.Default 高光沿边（drawContent 之后画，
                // 与参考 HighlightNode 的顺序一致）。
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _RimPainter(
                          radius: widget.radius, alpha: 1, dpr: dpr),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 拖拽拇指玻璃：按压时 lens(10dp, 14dp)×press 带色散 + 按压层
// （Highlight/Shadow/InnerShadow 全部随 press 显现）。表面色见 onDrawSurface。
// ---------------------------------------------------------------------------

class _ThumbGlass extends StatefulWidget {
  const _ThumbGlass({
    super.key,
    required this.height,
    required this.radius,
    required this.dark,
    required this.press,
    required this.dpr,
  });

  final double height;
  final double radius;
  final bool dark;
  final double press;
  final double dpr;

  @override
  State<_ThumbGlass> createState() => _ThumbGlassState();
}

class _ThumbGlassState extends State<_ThumbGlass> {
  ui.FragmentShader? _shader;
  ui.ImageFilter? _filter;

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  /// 按压折射（带色散）。press≈0 时返回 null：参考的 lens 在
  /// refractionHeight ≤ 0 时直接跳过 —— 拇指静止时只是一层表面色。
  ui.ImageFilter? _refraction(Size logical, double dpr) {
    if (!ui.ImageFilter.isShaderFilterSupported) return null;
    final band = logical.height * kThumbRefractionHeight / kThumbHeightFrac *
        widget.press;
    final amount = logical.height *
        kThumbRefractionAmount /
        kThumbHeightFrac *
        widget.press;
    if (band < .5 || amount <= 0) return null;
    if (_filter != null && _shaderSize == logical && _shaderPress == widget.press) {
      return _filter;
    }
    final shader = GlassShader.newShader();
    if (shader == null) return null;
    setRefractionUniforms(
      shader,
      logical,
      dpr,
      radius: widget.radius,
      band: band,
      amount: amount,
      chroma: true,
    );
    _shader?.dispose();
    _shader = shader;
    _shaderSize = logical;
    _shaderPress = widget.press;
    return _filter = ui.ImageFilter.shader(shader);
  }

  Size? _shaderSize;
  double? _shaderPress;

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final p = widget.press;
    final shape = BorderRadius.circular(widget.radius);
    // 参考 onDrawSurface：静止 white0.1（暗）/ black0.1（亮）随 press 淡出，
    // 叠 black 0.03×press。
    final base = (widget.dark ? Colors.white : Colors.black)
        .withValues(alpha: .1 * (1 - p));
    final surface =
        Color.alphaBlend(Colors.black.withValues(alpha: .03 * p), base);

    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      final refraction =
          p > 0.01 ? _refraction(size, widget.dpr) : null;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          // Shadow(alpha = press)：radius 24dp、offset y 4dp、黑 0.1。
          boxShadow: p > 0
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .1 * p),
                    blurRadius: h * 24 / 56,
                    offset: Offset(0, h * 4 / 56),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (refraction != null)
                BackdropFilter(filter: refraction, child: const SizedBox.expand()),
              ColoredBox(color: surface),
              // Highlight.Default × press：沿边高光。
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RimPainter(
                        radius: widget.radius, alpha: p, dpr: widget.dpr),
                  ),
                ),
              ),
              // InnerShadow(radius 8dp×press, offset y = radius, 黑 0.15) × press。
              if (p > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _InnerShadowPainter(
                        radius: widget.radius,
                        blur: h * 8 / 56 * p,
                        alpha: p,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

/// 把 lens 折射 uniform 写进 shader。**第 0、1 位是引擎自己填的纹理尺寸，
/// 不能碰**，从 2 开始：四角半径(2-5)、折射带(6)、位移(7)、景深(8)、色散(9)。
/// [band]、[amount] 传逻辑像素，这里统一乘 dpr 折成物理像素。
void setRefractionUniforms(
  ui.FragmentShader shader,
  Size logical,
  double dpr, {
  required double radius,
  required double band,
  required double amount,
  bool chroma = false,
}) {
  final r = radius * dpr;
  shader
    ..setFloat(2, r)
    ..setFloat(3, r)
    ..setFloat(4, r)
    ..setFloat(5, r)
    ..setFloat(6, band * dpr)
    ..setFloat(7, amount * dpr)
    ..setFloat(8, 0.0)
    ..setFloat(9, chroma ? 1.0 : 0.0);
}

// ---------------------------------------------------------------------------
// 高光 / 阴影画笔。
// ---------------------------------------------------------------------------

/// Highlight.Default 沿边高光：白 0.5 × |dot(法线, 45°)|（平边 ≈ 0.707），
/// 0.5dp 描边 + 0.25dp 模糊，裁在形状内，Plus 混合。
///
/// 参考实现用逐像素 shader 调制强度（圆角弧上有 ±30% 渐变）；这里取平边
/// 等效值 0.5×0.707 均匀描边 —— 圆角弧的细微明暗渐变省略。
class _RimPainter extends CustomPainter {
  _RimPainter({required this.radius, required this.alpha, required this.dpr});

  final double radius;
  final double alpha;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size,
        Radius.circular(math.min(radius, size.shortestSide / 2)));
    final path = Path()..addRRect(rrect);
    // 参考 strokeWidth = ceil(0.5dp)×2，裁剪后可见内半 ≈ 1px。
    final stroke = 2 * (0.5 * dpr).ceilToDouble() / dpr;
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: kRimInk * alpha)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .25),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.alpha != alpha || old.dpr != dpr;
}

/// InnerShadow：形状内、偏移 (0, radius) 的内阴影。做法：铺满阴影色后
/// 用「上移的形状」以 dstOut 抠掉，留下底边一圈柔影。
class _InnerShadowPainter extends CustomPainter {
  _InnerShadowPainter({
    required this.radius,
    required this.blur,
    required this.alpha,
  });

  final double radius;
  final double blur;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0 || blur <= 0) return;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size,
        Radius.circular(math.min(radius, size.shortestSide / 2)));
    final path = Path()..addRRect(rrect);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.clipPath(path);
    canvas.drawPath(
        path, Paint()..color = Colors.black.withValues(alpha: .15 * alpha));
    canvas.drawPath(
      path.shift(Offset(0, -blur)),
      Paint()
        ..blendMode = BlendMode.dstOut
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerShadowPainter old) =>
      old.radius != radius || old.blur != blur || old.alpha != alpha;
}

/// InteractiveHighlight 跟手高光：白 0.08 平涂 + smoothstep 径向白 0.15，
/// Plus 混合，radius = minDimension×1.5，位置 = 拇指中心。
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.center, required this.progress});

  final Offset center;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final p = progress;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.white.withValues(alpha: .08 * p)
        ..blendMode = BlendMode.plus,
    );
    final radius = size.shortestSide * 1.5;
    final shader = ui.Gradient.radial(center, radius, [
      Colors.white.withValues(alpha: .15 * p),
      Colors.white.withValues(alpha: .15 * p),
      Colors.white.withValues(alpha: .15 * .9 * p),
      Colors.white.withValues(alpha: .15 * .55 * p),
      Colors.white.withValues(alpha: .15 * .2 * p),
      Colors.white.withValues(alpha: 0),
    ], [
      .0,
      .5,
      .62,
      .75,
      .88,
      1.0,
    ]);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.plus,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.center != center || old.progress != progress;
}

// ---------------------------------------------------------------------------
// 右侧独立圆钮：搜索。
// ---------------------------------------------------------------------------

class _SearchButton extends StatelessWidget {
  const _SearchButton({super.key, required this.onPressed, required this.size});

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: '搜索',
      child: Tooltip(
        message: '搜索与筛选',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: PressScale(
            scale: .93,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 绿色实心，和效果图那颗拨号盘同心圆一致。
                color: AppPalette.green,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(AppPalette.green, Colors.white, .22)!,
                    AppPalette.green,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.green.withValues(alpha: dark ? .34 : .42),
                    blurRadius: size * .32,
                    offset: Offset(0, size * .12),
                  ),
                ],
              ),
              child: Icon(
                Icons.search_rounded,
                size: size * .46,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
