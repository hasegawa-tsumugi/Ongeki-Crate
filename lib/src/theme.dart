import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'motion.dart';

/// 页面与内容卡语义颜色跟随主题；分类与难度保留固定色板。
extension AppColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get canvas => isDark ? Colors.black : AppPalette.canvas;
  Color get ink => isDark ? Colors.white : AppPalette.ink;
  Color get inkMuted => isDark ? const Color(0xFFBDBDBD) : AppPalette.inkMuted;
  Color get inkFaint => isDark ? const Color(0xFFAAAAAA) : AppPalette.inkFaint;
  Color get card => isDark ? AppPalette.card : const Color(0xCCFFFFFF);
  Color get controlSurface => isDark ? const Color(0xDD222222) : Colors.white;
  Color get cardActive =>
      isDark ? const Color(0xEE2E2E2E) : const Color(0xFFF5F5F5);
  Color get outline =>
      isDark ? const Color(0xFF888888) : const Color(0xFFD5D5D5);
  Color get cardInk => isDark ? Colors.white : const Color(0xFF111111);
  Color get cardMuted =>
      isDark ? const Color(0xFFBDBDBD) : const Color(0xFF333333);
  Color get cardFaint =>
      isDark ? const Color(0xFFAAAAAA) : const Color(0xFF4A4A4A);
  Color get characterInk => isDark ? Colors.white : const Color(0xFF111111);
  Color get characterMuted =>
      isDark ? const Color(0xFFAAAAAA) : const Color(0xFF4A4A4A);
  double get meshOpacity => isDark ? .08 : .5;
  double get circuitOpacity => isDark ? .16 : .05;
  ColorFilter get circuitFilter => ColorFilter.matrix([
        0,
        0,
        0,
        0,
        isDark ? 255 : 0,
        0,
        0,
        0,
        0,
        isDark ? 255 : 0,
        0,
        0,
        0,
        0,
        isDark ? 255 : 0,
        0,
        0,
        0,
        circuitOpacity,
        0,
      ]);
  DecorationImage get cardCircuit => DecorationImage(
        image: const AssetImage('assets/tex/bg_circuit.webp'),
        repeat: ImageRepeat.repeat,
        alignment: Alignment.centerLeft,
        colorFilter: circuitFilter,
      );
  SystemUiOverlayStyle get systemBars => SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: canvas,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: canvas,
        systemNavigationBarContrastEnforced: false,
      );
}

abstract final class AppPalette {
  static const canvas = Color(0xFFFFFFFF),
      card = Color(0xCC222222),
      cardActive = Color(0xEE2E2E2E),
      magenta = Color(0xFFE84A92),
      yellow = Color(0xFFFAFF00),
      green = Color(0xFF32C63A),
      ink = Color(0xFF000000),
      inkMuted = Color(0xFF494949),
      inkFaint = Color(0xFF6B6B6B),
      onCard = Color(0xFFFFFFFF),
      onCardMuted = Color(0xA8FFFFFF),
      onCardFaint = Color(0x6BFFFFFF),
      line = Color(0x1A000000),
      danger = Color(0xFFFF3B5C);
}

class ChamferBorder extends OutlinedBorder {
  const ChamferBorder(
      {required this.size,
      super.side = const BorderSide(color: Color(0xFFD5D5D5))});
  final double size;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  Path _path(Rect rect) => Path()
    ..moveTo(rect.left, rect.top)
    ..lineTo(rect.right - size, rect.top)
    ..lineTo(rect.right, rect.top + size)
    ..lineTo(rect.right, rect.bottom)
    ..lineTo(rect.left, rect.bottom)
    ..close();

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(1));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    const inset = .5;
    const diagonalInset = math.sqrt2 * inset;
    final inner = rect.deflate(inset);
    final path = Path()
      ..moveTo(inner.left, inner.top)
      ..lineTo(rect.right - size - diagonalInset + inset, inner.top)
      ..lineTo(inner.right, rect.top + size + diagonalInset - inset)
      ..lineTo(inner.right, inner.bottom)
      ..lineTo(inner.left, inner.bottom)
      ..close();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = side.color;
    canvas.drawPath(path, paint);
  }

  @override
  ChamferBorder copyWith({BorderSide? side}) =>
      ChamferBorder(size: size, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) =>
      ChamferBorder(size: size * t, side: side.scale(t));
}

abstract final class AppTokens {
  static const controlHeight = 48.0;
  static const controlFontSize = 12.0;
  static const bodyFontSize = 12.0;
  static const captionFontSize = 11.0;
  static const sectionFontSize = 17.0;
  static const pagePadding = 16.0;
  static const controlShape = ChamferBorder(size: 7);
  static const panelShape = ChamferBorder(size: 10);
}

class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(title,
            style: const TextStyle(
                color: AppPalette.magenta,
                fontSize: AppTokens.sectionFontSize,
                fontWeight: FontWeight.bold)),
      );
}

/// 一段文字里「不能被断开」的单元：连续的非中日文、非空白字符。
///
/// Flutter 的换行只认空格与中日文间隙——中日文之间处处可断，拉丁串内部不可断。
/// 所以只有拉丁/数字/符号连成的串会出问题，切出来单独量。
///
/// 全角英数（`ＧＯ！ＧＯ！`，U+FF01–FF5E）要按拉丁串算：它们和半角一样是一个
/// 词，断在中间就等于把词劈开。数据里的曲名恰好大量使用全角，320@2.0 实测
/// 「ＧＯ！ＧＯ！ラブリズム♥」被切成「ＧＯ！Ｇ / Ｏ！ラブ」。半角片假名
/// （U+FF61–FF9F）与全角符号（U+FFE0–FFEE）仍是中日文那一侧，可断。
final _cjkOrSpace = RegExp(
  r'[\u3000-\u303f\u3040-\u309f\u30a0-\u30ff\u3400-\u4dbf\u4e00-\u9fff'
  r'\uf900-\ufaff\uff61-\uff9f\uffe0-\uffee\s]',
);

Iterable<String> unbreakableUnits(String text) =>
    text.split(_cjkOrSpace).where((unit) => unit.isNotEmpty);

/// 让最宽的单元刚好放进 [maxWidth] 所需的字号比例；1.0 表示不用缩。
///
/// 只量「可能超宽」的单元：一个字符最多占 1em，短到 `长度 × em ≤ maxWidth`
/// 的单元不可能超宽，跳过它省掉一次 TextPainter。绝大多数文本因此一次都不量。
double widestUnitScale(
  String text,
  TextStyle style,
  TextScaler scaler,
  double maxWidth, [
  double minScale = .72,
]) {
  if (!maxWidth.isFinite || maxWidth <= 0) return 1;
  final em = scaler.scale(style.fontSize ?? 14);
  if (em <= 0) return 1;
  var widest = 0.0;
  for (final unit in unbreakableUnits(text)) {
    if (unit.length * em <= maxWidth) continue;
    final painter = TextPainter(
      text: TextSpan(text: unit, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: scaler,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  if (widest <= maxWidth) return 1;
  final ratio = maxWidth / widest;
  // .99 是留给字宽取整的余量：刚好等于行宽的话，一个像素的进位就又会断开。
  if (ratio >= minScale) return ratio * .99;
  return minScale;
}

/// 不在拉丁词中间断行的 [Text]。
///
/// `GO!GO!ラブリズム♥`、`7EVENDAYS⇔HOLIDAYS` 这类没有空格的串一旦比行宽还宽，
/// Flutter 只能从中间硬断（320 宽 + 2.0 字号的卡片里实测断成「GO!G / O!」、
/// 「HOLIDA / YS」）。这里既不插软连字符也不截断（11-02 定的「不截断」规矩），
/// 而是把字号压到「最宽的那段刚好放得下」，换行点于是只落在空格与中日文之间。
///
/// [minScale] 是字号下限：缩到那儿还放不下就照旧断开——再缩字比正文还小，
/// 标题层级就没了（数据集里 22 位的纯数字曲名属于这种）。
///
/// [maxWidth] 显式传入时不会包 LayoutBuilder。卡片内部套着 `IntrinsicHeight`，
/// 里面再出现 LayoutBuilder 会在测量阶段抛「不支持 intrinsic dimensions」，
/// 所以卡片必须自己算好宽度传进来。
class WordSafeText extends StatelessWidget {
  const WordSafeText(
    this.text, {
    super.key,
    required this.style,
    this.maxWidth,
    this.textAlign,
    this.minScale = .72,
  });
  final String text;
  final TextStyle style;
  final double? maxWidth;
  final TextAlign? textAlign;
  final double minScale;
  @override
  Widget build(BuildContext context) {
    final width = maxWidth;
    if (width != null) return _build(context, width);
    // 没有 intrinsic 测量问题的位置（详情页的 ListView 里）可以自己量。
    return LayoutBuilder(builder: (context, constraints) {
      return _build(context, constraints.maxWidth);
    });
  }

  Widget _build(BuildContext context, double width) {
    final scale = widestUnitScale(
      text,
      style,
      MediaQuery.textScalerOf(context),
      width,
      minScale,
    );
    final fitted = scale >= 1
        ? style
        : style.copyWith(fontSize: (style.fontSize ?? 14) * scale);
    return Text(text, style: fitted, textAlign: textAlign);
  }
}

class AppInfoRow extends StatelessWidget {
  const AppInfoRow(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 88,
              child: Text(label,
                  style: TextStyle(
                      color: context.cardMuted,
                      fontSize: AppTokens.captionFontSize,
                      height: 1.7))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: context.cardInk,
                      fontSize: AppTokens.bodyFontSize,
                      height: 1.7))),
        ]),
      );
}

class OfficialTitle extends StatelessWidget {
  const OfficialTitle({super.key, required this.english, required this.label});
  final String english, label;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 76 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.5),
        child: Stack(alignment: Alignment.center, children: [
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(english,
                  maxLines: 1,
                  style: TextStyle(
                      fontFamily: FontRoles.of(context).numeric,
                      fontSize:
                          MediaQuery.sizeOf(context).width <= 350 ? 50 : 65,
                      height: 1,
                      fontWeight: FontWeight.bold,
                      color: AppPalette.green.withValues(alpha: .2)))),
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(label,
                  style: TextStyle(
                      fontSize:
                          MediaQuery.sizeOf(context).width <= 350 ? 16 : 20,
                      height: 1,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold))),
        ]),
      );
}

class OfficialBackground extends StatelessWidget {
  const OfficialBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: context.canvas,
            image: DecorationImage(
                image: const AssetImage('assets/tex/bg_mesh.webp'),
                opacity: context.meshOpacity,
                colorFilter: context.isDark
                    ? const ColorFilter.matrix([
                        -1,
                        0,
                        0,
                        0,
                        255,
                        0,
                        -1,
                        0,
                        0,
                        255,
                        0,
                        0,
                        -1,
                        0,
                        255,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ])
                    : null,
                repeat: ImageRepeat.repeat)),
        child: child,
      );
}


/// 页面路由：**过场保持 0ms**。
///
/// Material 默认的缩放过渡和街机风对不上，早先就是因此关掉的；而导航是每次
/// 操作都会走的路径，240ms 的过场等于把每次进详情、进设置、返回都拖慢一截，
/// 现有布局基线（斜带位置、底角按钮、小屏无滚动）也都建立在「切页即到位」上。
/// 想要过场的话属于交互语义变更，得连这批断言一起改，不在「补动效」的范围内。
class AppRoute<T> extends MaterialPageRoute<T> {
  AppRoute({required super.builder});
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

class AppPage extends StatelessWidget {
  const AppPage(
      {super.key,
      required this.title,
      required this.child,
      this.menuAction,
      this.topSpacing = 80});
  final String title;
  final Widget child;

  /// 旧版这里决定要不要在左下角画菜单圆钮。换成底部导航栏之后，Root 页以外
  /// 一律不画常驻底栏（push 上来的页面整屏都是内容），参数只为兼容旧调用点。
  final VoidCallback? menuAction;
  final double topSpacing;
  @override
  Widget build(BuildContext context) => Scaffold(
          body: Stack(children: [
        const Positioned.fill(child: IgnorePointer(child: MusicBackdrop())),
        SafeArea(
            child: Column(children: [
          Padding(
              padding: EdgeInsets.fromLTRB(14, topSpacing, 70, 16),
              child: Row(children: [
                PressScale(
                    scale: .94,
                    child: SizedBox(
                        width: 48,
                        height: 48,
                        child: FilledButton(
                            style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: context.controlSurface,
                                foregroundColor: context.cardInk),
                            onPressed: () => Navigator.pop(context),
                            child: const Icon(Icons.arrow_back)))),
                const SizedBox(width: 12),
                // 标题单行缩放：320 宽 + 2.0 字号下「搜索与筛选」放不进 176dp，
                // 会折成「搜索与筛 / 选」，末字孤零零占一行。缩放比折行好看。
                Expanded(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)))),
              ])),
          Expanded(child: child),
        ])),
      ]));
}

class MusicBackdrop extends StatelessWidget {
  const MusicBackdrop({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, bounds) => Stack(children: [
            const Positioned.fill(
                child: OfficialBackground(child: SizedBox.expand())),
            for (final band in [
              (0.0, 10.0, AppPalette.yellow),
              (20.0, 30.0, AppPalette.green),
              (60.0, 10.0, AppPalette.yellow)
            ])
              Positioned(
                  left: bounds.maxWidth * .23 - bounds.maxWidth * 1.5,
                  top: bounds.maxHeight * .64 + band.$1,
                  width: bounds.maxWidth * 3,
                  height: band.$2,
                  child: Transform.rotate(
                      angle: -20 * math.pi / 180,
                      child: Container(
                          color: context.isDark
                              ? band.$3.withValues(alpha: .22)
                              : band.$3))),
          ]));
}

const spaces = <double>[4, 8, 12, 16, 24, 32];
const difficultyTones = <Color>[
  Color(0xFF16FF47),
  Color(0xFFFFBA00),
  Color(0xFFFA0667),
  Color(0xFFA810FF),
  Color(0xFFF8FF2F),
];

class Chamfer extends StatelessWidget {
  const Chamfer({
    super.key,
    required this.child,
    this.size = 10,
    this.fill,
    this.padding = const EdgeInsets.all(12),
    this.edge = false,
  });
  final Widget child;
  final double size;
  final Color? fill;
  final EdgeInsetsGeometry padding;
  final bool edge;
  @override
  Widget build(BuildContext context) => ClipPath(
        clipper: _ChamferClipper(size),
        child: CustomPaint(
          foregroundPainter: ChamferOutlinePainter(
            size,
            edge ? AppPalette.magenta : context.outline,
            edge ? 1.2 : 1,
          ),
          child: Container(
            decoration: BoxDecoration(
              color:
                  fill == null || fill == AppPalette.card ? context.card : fill,
              image: fill == null ||
                      fill == AppPalette.card ||
                      fill == context.controlSurface
                  ? context.cardCircuit
                  : null,
            ),
            padding: padding,
            child: child,
          ),
        ),
      );
}

class _ChamferClipper extends CustomClipper<Path> {
  const _ChamferClipper(this.s);
  final double s;
  @override
  Path getClip(Size z) => Path()
    ..moveTo(0, 0)
    ..lineTo(z.width - s, 0)
    ..lineTo(z.width, s)
    ..lineTo(z.width, z.height)
    ..lineTo(0, z.height)
    ..close();
  @override
  bool shouldReclip(_ChamferClipper old) => old.s != s;
}

class ChamferOutlinePainter extends CustomPainter {
  const ChamferOutlinePainter(this.size, this.color, this.width);
  final double size, width;
  final Color color;
  @override
  void paint(Canvas canvas, Size bounds) {
    final inset = width / 2;
    final diagonalInset = math.sqrt2 * inset;
    final inner = Rect.fromLTWH(
      inset,
      inset,
      math.max(0, bounds.width - width),
      math.max(0, bounds.height - width),
    );
    final path = Path()
      ..moveTo(inner.left, inner.top)
      ..lineTo(bounds.width - size - diagonalInset + inset, inner.top)
      ..lineTo(inner.right, size + diagonalInset - inset)
      ..lineTo(inner.right, inner.bottom)
      ..lineTo(inner.left, inner.bottom)
      ..close();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ChamferOutlinePainter old) =>
      old.size != size || old.width != width || old.color != color;
}

/// 字体角色 → 字体族。对齐 RN 版 `catalog.ts` 的三套 scheme。
///
/// 为什么不只在 `ThemeData.fontFamily` 上写一个值：一套方案里三个角色可能
/// 各自是随包字体或系统字体（`system` 全是 null）。组件如果各自写死字体名，
/// 切到 `system` 时数字仍然会渲染成 Josefin —— 「一个随包字体都不用」就不成立。
class FontRoles extends ThemeExtension<FontRoles> {
  const FontRoles({this.content, this.numeric, this.label});

  /// 曲目内容：曲名、读音。
  final String? content;

  /// 数字与拉丁装饰字：定数、物量、难度标号。
  final String? numeric;

  /// 中文界面文案。
  final String? label;

  /// 与 RN `CATALOG.schemes` 一一对应；未知方案按 `official` 处理。
  factory FontRoles.forScheme(String scheme) => switch (scheme) {
        'classic' => const FontRoles(content: 'SEGA', numeric: 'Josefin'),
        'system' => const FontRoles(),
        _ => const FontRoles(
            content: 'Official',
            numeric: 'Josefin',
            label: 'Official',
          ),
      };

  static FontRoles of(BuildContext context) =>
      Theme.of(context).extension<FontRoles>() ??
      FontRoles.forScheme('official');

  /// 切换字体方案不做过场动画，`lerp` 直接取端点；`copyWith` 只用于覆盖非空值。
  @override
  FontRoles copyWith({String? content, String? numeric, String? label}) =>
      FontRoles(
        content: content ?? this.content,
        numeric: numeric ?? this.numeric,
        label: label ?? this.label,
      );

  @override
  FontRoles lerp(ThemeExtension<FontRoles>? other, double t) =>
      t < 0.5 ? this : (other is FontRoles ? other : this);
}

ThemeData buildTheme(String scheme,
    {Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final canvas = dark ? Colors.black : AppPalette.canvas;
  final ink = dark ? Colors.white : AppPalette.ink;
  final outline = dark ? const Color(0xFF888888) : const Color(0xFFD5D5D5);
  final surface = dark ? const Color(0xDD222222) : Colors.white;
  final cardInk = dark ? Colors.white : const Color(0xFF111111);
  final controlShape = ChamferBorder(size: 7, side: BorderSide(color: outline));
  final panelShape = ChamferBorder(size: 10, side: BorderSide(color: outline));
  final disabledFill = dark ? const Color(0xFF3B3B3B) : const Color(0xFFE5E5E5);
  final disabledInk = dark ? const Color(0xFFAAAAAA) : const Color(0xFF666666);
  final roles = FontRoles.forScheme(scheme);
  final label = roles.label;
  final fallback = scheme == 'official' ? const ['MPLUS1p', 'MiSans'] : null;
  final controlText = TextStyle(
      fontFamily: label,
      fontFamilyFallback: fallback,
      fontSize: AppTokens.controlFontSize,
      fontWeight: FontWeight.bold,
      height: 1.4);
  final bodyText = TextStyle(
      fontFamily: label,
      fontFamilyFallback: fallback,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.7,
      color: ink);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: canvas,
    colorScheme:
        (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: AppPalette.magenta,
      surface: canvas,
      onSurface: ink,
      error: AppPalette.danger,
    ),
    fontFamily: label,
    fontFamilyFallback:
        scheme == 'official' ? const ['MPLUS1p', 'MiSans'] : null,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: cardInk,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
          fontFamily: label,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: cardInk,
          fontFamilyFallback:
              scheme == 'official' ? const ['MPLUS1p', 'MiSans'] : null),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
      backgroundColor: AppPalette.magenta,
      foregroundColor: Colors.white,
      disabledBackgroundColor: disabledFill,
      disabledForegroundColor: disabledInk,
      overlayColor: ink,
      minimumSize: const Size(48, AppTokens.controlHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: controlShape,
      textStyle: controlText,
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
      foregroundColor: cardInk,
      backgroundColor: surface,
      disabledForegroundColor: disabledInk,
      disabledBackgroundColor: disabledFill,
      overlayColor: ink,
      minimumSize: const Size(48, AppTokens.controlHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      side: BorderSide(color: outline, width: 2),
      shape: controlShape,
      textStyle: controlText,
    )),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
      foregroundColor: AppPalette.magenta,
      minimumSize: const Size(48, 48),
      textStyle: controlText,
    )),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      disabledColor: disabledFill,
      selectedColor: AppPalette.magenta,
      // ChipThemeData.labelStyle 是普通 TextStyle，Material 不会对
      // WidgetStateTextStyle 调 resolve()，写进去等于「颜色为 null」，
      // 浅色下标签最终落到白色 → 白底白字看不见。这里给确定值。
      labelStyle: controlText.copyWith(color: cardInk),
      secondaryLabelStyle: controlText.copyWith(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      checkmarkColor: Colors.white,
      side: BorderSide.none,
      shape: controlShape,
    ),
    dialogTheme: DialogThemeData(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        titleTextStyle:
            bodyText.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: bodyText,
        shape: panelShape),
    bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: canvas,
        modalBackgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        shape: panelShape),
    inputDecorationTheme: const InputDecorationTheme(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(vertical: 12),
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppPalette.magenta),
    dividerTheme: const DividerThemeData(color: Color(0xFF888888)),
    textTheme: ThemeData.light()
        .textTheme
        .apply(
          bodyColor: ink,
          displayColor: ink,
          fontFamily: label,
          fontFamilyFallback:
              scheme == 'official' ? const ['MPLUS1p', 'MiSans'] : null,
        )
        .copyWith(
          titleMedium:
              bodyText.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
          bodyLarge: bodyText.copyWith(fontSize: 14),
          bodyMedium: bodyText,
          bodySmall: bodyText.copyWith(fontSize: 12),
          labelLarge: controlText,
          labelMedium: controlText,
          labelSmall: controlText.copyWith(fontSize: 11),
        ),
    extensions: <ThemeExtension<dynamic>>[roles],
  );
}
