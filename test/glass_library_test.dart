import 'dart:convert';
import 'dart:io';

import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:songquery_flutter/src/bottom_bar.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 底栏必须**由 `fluid_glass`（参考 App 那个库的 Flutter 移植）实现**，
/// 不是本仓库再手写一遍玻璃。
///
/// 为什么值得一条单独的护栏：2026-11-24 之前 `bottom_bar.dart` 里是 800 行
/// 逐参数手抄的仿制品 —— 折射在真机上不生效、高光没有法线调制、选中态没有
/// accent 副本，改了十几轮都不像。这种回退是**静默**的：界面照样出图、测试
/// 照样全绿，只有真机上看着不对。所以这里从三个层面钉死：
///
/// 1. 组件层：底栏里真有 `LiquidBottomTabs`（3 格）与 `LiquidButton`；
/// 2. 源码层：`bottom_bar.dart` 里不再出现自绘玻璃的痕迹；
/// 3. 依赖层：`pubspec.yaml` 里 `fluid_glass` 还在。
void main() {
  Widget host() {
    final backdrop = LayerBackdrop();
    addTearDown(backdrop.dispose);
    return MaterialApp(
      theme: buildTheme('official'),
      home: Scaffold(
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: BackdropLayer(
                backdrop: backdrop,
                child: const ColoredBox(color: Color(0xFF3366CC)),
              ),
            ),
            LiquidGlassBar(
              current: AppTab.home,
              onTab: (_) {},
              onSearch: () {},
              backdrop: backdrop,
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('底栏用的是 fluid_glass 的 LiquidBottomTabs / LiquidButton', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump();

    final tabs = tester.widget<LiquidBottomTabs>(
        find.byType(LiquidBottomTabs));
    expect(tabs.tabsCount, 3, reason: '主页 / 工具 / 我的');
    expect(tabs.selectedTabIndex, 0);
    expect(tabs.height, LiquidBottomTabs.defaultHeight,
        reason: '面板高必须用库的 64dp 默认值 —— 行高 56dp、按压 78/56 '
            '都是围绕它定的，改了就不是参考 App 的比例');
    expect(find.byType(LiquidBottomTab), findsNWidgets(6),
        reason: '每格在树里两份：可见行 + 被选中胶囊放大的 accent 副本');
    expect(find.byType(LiquidButton), findsOneWidget, reason: '右侧搜索钮');
    expect(tester.takeException(), isNull);
  });

  testWidgets('点未选中的页签会回调，点选中的那格由胶囊接管', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    AppTab? picked;
    final backdrop = LayerBackdrop();
    addTearDown(backdrop.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme('official'),
      home: Scaffold(
        body: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: BackdropLayer(
              backdrop: backdrop,
              child: const ColoredBox(color: Color(0xFF3366CC)),
            ),
          ),
          LiquidGlassBar(
            current: AppTab.home,
            onTab: (tab) => picked = tab,
            onSearch: () {},
            backdrop: backdrop,
          ),
        ]),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('tab-tools')).first);
    await tester.pump();
    expect(picked, AppTab.tools);
  });

  test('bottom_bar.dart 里没有自绘玻璃的痕迹', () {
    final src = File('lib/src/bottom_bar.dart').readAsStringSync();
    // 自绘玻璃的三个标志物：背景滤镜、自定义画笔、手写的 shader uniform。
    expect(src, isNot(contains('BackdropFilter')),
        reason: '玻璃不该再自己搭 BackdropFilter —— 那是 fluid_glass 的内部实现');
    expect(src, isNot(contains('CustomPainter')),
        reason: '高光/内阴影/跟手高光都该由库画，不该再写画笔');
    expect(src, isNot(contains('setFloat(')),
        reason: 'uniform 由库写，本文件不该再碰 shader');
    expect(src, isNot(contains('FragmentShader')),
        reason: 'shader 实例由库缓存复用');
  });

  test('pubspec 仍然依赖 fluid_glass', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('fluid_glass:'),
        reason: '底栏的玻璃全部来自这个包，删了依赖就等于把效果一起删了');
  });

  // ---- 本地补丁：tab 的模糊半径必须和右侧 LiquidButton 一致 --------------
  //
  // 上游把 `LiquidBottomTabs` 面板的模糊写死成 `..blur(8)`，而
  // `LiquidButton` 是 `..blur(2)` —— 同一个底栏上，左边明显比右边雾。
  // 上游没有开参数，所以本仓库在 `third_party/fluid_glass` 里改了这两处
  // （见该目录 PATCHES.md），并用 `dependency_overrides` 钉住。
  //
  // 这三个断言防的都是**静默回退**：把路径覆盖删掉、或把依赖升回 hosted
  // 版本，界面照样出图、别的测试照样全绿，只有真机上左右两边雾度不一样。

  final buttonSource =
      File('third_party/fluid_glass/lib/src/components/liquid_button.dart');
  final tabsSource =
      File('third_party/fluid_glass/lib/src/components/liquid_bottom_tabs.dart');

  double firstBlurRadius(File file) {
    final match = RegExp(r'\.\.blur\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)')
        .firstMatch(file.readAsStringSync());
    expect(match, isNotNull,
        reason: '${file.path} 里找不到数字字面量的 ..blur(...)');
    return double.parse(match!.group(1)!);
  }

  test('tab 面板的模糊半径和右侧按钮一致', () {
    expect(firstBlurRadius(tabsSource), firstBlurRadius(buttonSource),
        reason: '左边三格 tab 和右边搜索钮在同一个底栏上，雾度不一致一眼能看出来');
  });

  test('选中胶囊底下那份 accent 副本用同一个模糊半径', () {
    final match = RegExp(r'static const double blurRadius = ([0-9.]+);')
        .firstMatch(tabsSource.readAsStringSync());
    expect(match, isNotNull, reason: 'blurRadius 常量没了，补丁要重新对一遍');
    expect(double.parse(match!.group(1)!), firstBlurRadius(tabsSource),
        reason: '胶囊里的副本比面板更糊，选中态会像换了一种玻璃');
  });

  test('编译器实际链接的是本地补丁版，而不是 hosted 上的原版', () {
    final config = File('.dart_tool/package_config.json');
    expect(config.existsSync(), isTrue,
        reason: '先 flutter pub get，否则这个断言无从谈起');
    final packages =
        (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
    final entry = packages.cast<Map>().firstWhere(
          (map) => map['name'] == 'fluid_glass',
          orElse: () => throw StateError('package_config 里没有 fluid_glass'),
        );
    expect(entry['rootUri'] as String, contains('third_party/fluid_glass'),
        reason: 'path 覆盖丢了：pub get 会把底栏换回 blur(8) 的原版');
  });

  // ---- 描边：左右两条玻璃共用一个「更柔」的 Highlight --------------------
  //
  // 库默认 Highlight.standard 是 width 0.5 / blurRadius 0.25，羽化几乎是 0，
  // 真机上是一根很硬的亮线。用户要求「边框模糊一点」，并且明确要两条一起软。
  // 这里钉住两件事：两条用的是同一个 getter；只放宽羽化，不加粗也不提亮。

  testWidgets('左右两条玻璃传的是同一个描边，且比库默认更柔', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump();

    final tabs = tester.widget<LiquidBottomTabs>(find.byType(LiquidBottomTabs));
    final button = tester.widget<LiquidButton>(find.byType(LiquidButton));

    expect(tabs.highlight, isNotNull, reason: '面板没传描边就是库那根硬边');
    expect(button.highlight, isNotNull, reason: '圆钮没传描边就是库那根硬边');
    expect(identical(tabs.highlight, button.highlight), isTrue,
        reason: '左右必须共用一个 getter，否则以后改了一边另一条不跟');

    final Highlight rim = tabs.highlight!()!;
    expect(rim.blurRadius, greaterThan(Highlight.standard.blurRadius),
        reason: '羽化没放宽 = 边框还是那根硬线');
    expect(rim.width, Highlight.standard.width,
        reason: '只柔化、不加粗 —— 描边变粗属于另一处视觉改动');
    expect(rim.alpha, Highlight.standard.alpha, reason: '只柔化、不提亮');
  });
}
