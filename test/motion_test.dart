import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/motion.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 动效本身的回归：数值被改掉、按压反馈失灵、或者有人再给路由塞过场，
/// 这些用例必须当场变红。
void main() {
  double scaleOf(WidgetTester tester) => tester
      .widget<Transform>(find
          .descendant(
              of: find.byType(AnimatedScale), matching: find.byType(Transform))
          .first)
      .transform
      .storage[0];

  Widget host(Widget child, {bool disableAnimations = false}) => MaterialApp(
        theme: buildTheme('official'),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('按下缩到目标比例，松手回到 100%', (tester) async {
    await tester.pumpWidget(host(const PressScale(
      scale: .9,
      child: ColoredBox(
          color: Color(0xFF333333), child: SizedBox(width: 100, height: 100)),
    )));
    expect(scaleOf(tester), 1.0);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressScale)));
    await tester.pump();
    await tester.pump(Motion.press);
    expect(scaleOf(tester), closeTo(.9, .001), reason: '按下 120ms 后应缩到位');

    await gesture.up();
    await tester.pump();
    await tester.pump(Motion.press);
    expect(scaleOf(tester), closeTo(1.0, .001), reason: '松手应弹回原大小');

    // 动画走完不能留下还在跑的帧，否则列表里每张卡片都会常驻 ticker。
    // 隐式动画换目标时会先插一帧「从当前值起跑」，所以要多泵一帧才算停。
    await tester.pump(Motion.press);
    await tester.pump(Motion.press);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('手指滑走就不缩：滚动列表时卡片不该跟着变形', (tester) async {
    await tester.pumpWidget(host(const PressScale(
      scale: .9,
      child: ColoredBox(
          color: Color(0xFF333333), child: SizedBox(width: 100, height: 100)),
    )));

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressScale)));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await tester.pump(Motion.press);
    await tester.pump(Motion.press);
    expect(scaleOf(tester), 1.0, reason: '位移超过 8dp 视为滚动，必须松开');

    await gesture.up();
    await tester.pump(Motion.press);
    expect(scaleOf(tester), 1.0);
  });

  testWidgets('系统「移除动画」时不产生运动', (tester) async {
    await tester.pumpWidget(host(
      const PressScale(
          scale: .9,
          child: ColoredBox(
              color: Color(0xFF333333),
              child: SizedBox(width: 100, height: 100))),
      disableAnimations: true,
    ));

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressScale)));
    // 一帧就该到位：没有过渡可言。
    await tester.pump();
    expect(scaleOf(tester), closeTo(.9, .001));

    await gesture.up();
    await tester.pump();
    expect(scaleOf(tester), closeTo(1.0, .001));
  });

  testWidgets('Motion.of 在关掉动画时把时长压成 0', (tester) async {
    late Duration plain;
    late Duration reduced;
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        Builder(builder: (context) {
          plain = Motion.of(context, Motion.expand);
          return const SizedBox.shrink();
        }),
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(builder: (context) {
            reduced = Motion.of(context, Motion.expand);
            return const SizedBox.shrink();
          }),
        ),
      ]),
    ));
    expect(plain, Motion.expand);
    expect(reduced, Duration.zero);
  });

  test('时长与曲线是定值，改动必须是有意为之', () {
    expect(Motion.press.inMilliseconds, 120);
    expect(Motion.state.inMilliseconds, 140);
    expect(Motion.expand.inMilliseconds, 180);
    expect(Motion.easeOut, const Cubic(.2, .8, .25, 1));
    // 与 HTML 的 `cubic-bezier(.2,.8,.25,1)` 同值。半程就走完九成是这条曲线的
    // 重点：内置 Curves.easeOut 半程只有七成出头，收尾会明显拖。
    expect(Motion.easeOut.transform(.5), greaterThan(.9));
    expect(Curves.easeOut.transform(.5), lessThan(.8));
  });

  test('路由仍然是瞬时切换：加过场属于交互变更，不在动效范围内', () {
    expect(AppRoute(builder: (_) => const SizedBox()), isA<AppRoute>());
    expect(AppRoute(builder: (_) => const SizedBox()).transitionDuration,
        Duration.zero);
    expect(AppRoute(builder: (_) => const SizedBox()).reverseTransitionDuration,
        Duration.zero);
  });
}
