import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 「整词换行」的护栏。
///
/// Flutter 只在空格与中日文间隙换行，一段没有空格的拉丁串比行宽还宽时只能从
/// 中间硬断 —— 320 宽 + 2.0 字号的卡片里实测把 `GO!GO!ラブリズム♥` 断成
/// 「GO!G / O!」、`7EVENDAYS⇔HOLIDAYS` 断成「HOLIDA / YS」。这里的测试锁住
/// 三件事：切分规则、缩字比例、以及卡片真的用了它。
void main() {
  group('unbreakableUnits', () {
    test('只在空白与中日文处切开', () {
      // 每个假名/汉字本身就是断点，所以只留下两段非中日文的串。
      expect(unbreakableUnits('GO!GO!ラブリズム♥').toList(), ['GO!GO!', '♥']);
      // 全角英数按拉丁串算：数据里曲名大量使用全角，「ＧＯ！ＧＯ！」被断成
      // 「ＧＯ！Ｇ / Ｏ！」就是这个原因。
      expect(unbreakableUnits('ＧＯ！ＧＯ！ラブリズム♥').toList(),
          ['ＧＯ！ＧＯ！', '♥']);
      expect(unbreakableUnits('bright MEMORY Act.1').toList(),
          ['bright', 'MEMORY', 'Act.1']);
      expect(unbreakableUnits('7EVENDAYS⇔HOLIDAYS').toList(),
          ['7EVENDAYS⇔HOLIDAYS']);
      expect(unbreakableUnits('片霧烈火オンザみんマンション').toList(), isEmpty);
    });
  });

  group('widestUnitScale', () {
    const style = TextStyle(fontSize: 18);

    // 测试环境用的等宽测试字体：每个字形正好 1em，宽度可以直接推算。
    test('放得下就返回 1.0，不做任何缩小', () {
      final scale = widestUnitScale('GO!GO!', style, TextScaler.noScaling, 400);
      expect(scale, 1.0);
    });

    test('放不下时按「最宽单元刚好放下」缩，且留 1% 余量', () {
      // 6 × 18 = 108 > 60 → 60 / 108 ≈ .5556，但低于下限 .72。
      expect(widestUnitScale('GO!GO!', style, TextScaler.noScaling, 90),
          closeTo(90 / 108 * .99, 1e-9));
    });

    test('缩到下限还不够就停在下限，不再继续缩字号', () {
      expect(widestUnitScale('GO!GO!', style, TextScaler.noScaling, 60), .72);
    });

    test('字号放大后按实际 em 判断', () {
      // 2.0 字号下 6 个字符要 216dp，宽 162 放不下。
      final scale = widestUnitScale(
          'GO!GO!ラブリズム♥', style, const TextScaler.linear(2), 162);
      expect(scale, lessThan(1));
      expect(scale, closeTo(162 / 216 * .99, 1e-9));
    });
  });

  group('WordSafeText', () {
    Widget host(String text, {required double width, double textScale = 2}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 844),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: WordSafeText(
                  text,
                  maxWidth: width,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
        );

    testWidgets('长拉丁串降字号，文字一个不少', (tester) async {
      await tester.pumpWidget(host('GO!GO!ラブリズム♥', width: 162));
      await tester.pump();
      final text = tester.widget<Text>(find.text('GO!GO!ラブリズム♥'));
      expect(text.style!.fontSize, lessThan(18));
      expect(text.style!.fontSize, greaterThanOrEqualTo(18 * .72));
    });

    testWidgets('放得下的文本字号原样不动', (tester) async {
      await tester.pumpWidget(host('We Are Us!', width: 300));
      await tester.pump();
      final text = tester.widget<Text>(find.text('We Are Us!'));
      expect(text.style!.fontSize, 18);
    });
  });

  group('列表卡片', () {
    Widget card(String title, {double textScale = 2}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 844),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: SongCardView(
                  song: Song(id: '1', title: title, charts: const []),
                  onTap: () {},
                ),
              ),
            ),
          ),
        );

    testWidgets('320 宽 + 2.0 字号：曲名整词，不被拦腰断开', (tester) async {
      await tester.pumpWidget(card('GO!GO!ラブリズム♥'));
      await tester.pump();
      // 曲名一个字都不能少，也不是 ellipsis。
      final text = tester.widget<Text>(find.text('GO!GO!ラブリズム♥'));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      // 字号被压到能让「GO!GO!」整段放下（18 是 1.0 字号下的基准值）。
      expect(text.style!.fontSize, lessThan(18));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('1.0 字号下曲名字号不变', (tester) async {
      await tester.pumpWidget(card('GO!GO!ラブリズム♥', textScale: 1));
      await tester.pump();
      final text = tester.widget<Text>(find.text('GO!GO!ラブリズム♥'));
      expect(text.style!.fontSize, 17);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
