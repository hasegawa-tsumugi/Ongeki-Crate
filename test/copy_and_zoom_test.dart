import 'dart:convert';
import 'dart:io';

import 'package:fluid_glass/fluid_glass.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/screens.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 长按复制 / 点曲绘全屏 / 搜索键不长按弹字。
///
/// 这三条都是**只有交互才会暴露**的功能：静态截图看不出剪贴板里有没有东西，
/// 也看不出长按会不会冒出一块 Tooltip。所以逐条用真实手势走一遍。
void main() {
  late Dataset data;
  late Song song;
  final copied = <String>[];

  setUpAll(() {
    final raw =
        jsonDecode(File('assets/songs-2026.10.15.json').readAsStringSync())
            as Map;
    // 曲绘走真实网络，测试里必定失败并排重试定时器 —— 抹掉后走静态占位，
    // 点开全屏页也不会多出定时器。
    for (final entry in (raw['songs'] as List)) {
      (entry as Map)['artwork'] = null;
    }
    data = Dataset.fromJson(raw);
    // 挑一首字段最全的：有读音、作者、分类、多张谱面 —— 复制文本的每个分支
    // 都能被覆盖到，而不是只验一个曲名。
    song = data.songs.firstWhere(
      (s) =>
          s.titleKana != null &&
          (s.artist ?? '').isNotEmpty &&
          s.genre != null &&
          s.playableCharts.length >= 3,
      orElse: () => data.songs.first,
    );
  });

  setUp(() {
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget home() => MaterialApp(
        theme: buildTheme('official'),
        home: HomeScreen(
          dataset: data,
          status: '本地曲库已就绪',
          error: null,
          busy: false,
          progress: null,
          revision: 0,
          scheme: 'official',
          onUpdate: () async {},
          onScheme: (_) async {},
          onClear: () async {},
          loadLocalBytes: () async => 0,
        ),
      );

  /// SnackBar 带 1.2s 的关闭计时器，不把它走完用例结束会报 pending timer。
  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('主页长按卡片复制曲名', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(home());
    await tester.pump();

    final card = find.byType(SongCardView).first;
    final target = tester.widget<SongCardView>(card).song;
    expect(copied, isEmpty, reason: '只是渲染，不该有复制');

    await tester.longPress(card);
    await tester.pump();

    expect(copied, hasLength(1));
    expect(copied.single, target.title);
    expect(find.text('已复制曲名'), findsOneWidget);

    await drainSnackBar(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('详情页长按曲名区复制整首信息', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme('official'),
      home: DetailScreen(song: song),
    ));
    await tester.pump();

    await tester.longPress(find.text(song.title));
    await tester.pump();

    expect(copied, hasLength(1));
    final text = copied.single;
    expect(text.split('\n').first, song.title, reason: '首行就是曲名，方便粘贴');
    if (song.titleKana != null) expect(text, contains(song.titleKana!));
    if (song.genre != null) expect(text, contains('分类：${song.genre}'));
    if (song.releaseTag != null) {
      expect(text, contains('版本：${song.releaseTag}'));
    }
    expect(text, contains(difficultyNames[song.playableCharts.first.difficulty]));
    expect(find.text('已复制曲目信息'), findsOneWidget);

    await drainSnackBar(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('详情页长按版本卡片也能复制同一份信息', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme('official'),
      home: DetailScreen(song: song),
    ));
    await tester.pump();

    await tester.longPress(find.text('BPM'));
    await tester.pump();

    expect(copied, hasLength(1));
    expect(copied.single.split('\n').first, song.title);

    await drainSnackBar(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('点曲绘进全屏，点关闭回详情', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 这条用例要的正是「有曲绘」：单独造一首，不走 setUpAll 里抹掉的那份。
    final withArt = Song(
      id: song.id,
      title: song.title,
      charts: song.charts,
      artwork: '1234.png',
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme('official'),
      home: DetailScreen(song: withArt),
    ));
    await tester.pump();

    // 全屏页只有它自己带关闭图标，用它判断「已经进去了」。
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.tap(find.byKey(const ValueKey('detail-jacket')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byKey(const ValueKey('detail-jacket')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('没有曲绘时不响应点击（不会进空白全屏页）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme('official'),
      home: DetailScreen(song: song),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('detail-jacket')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('搜索钮没有 tooltip（长按不会弹文字说明）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(home());
    await tester.pump();

    final button = find.byKey(const ValueKey('search-button'));
    expect(button, findsOneWidget);

    // 直接看组件参数：库只在 `tooltip != null` 时才包 Tooltip，所以这一条
    // 等价于「长按不出文字」。用长按去测是不可靠的 —— Tooltip 的
    // waitDuration 与 kLongPressTimeout 同为 500ms，早一帧晚一帧结果就翻。
    expect(tester.widget<LiquidButton>(button).tooltip, isNull,
        reason: '底栏圆钮不该有 tooltip，长按会冒出一块文字说明');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  test('bottom_bar.dart 里没有给圆钮传 tooltip（源码级兜底）', () {
    final source = File('lib/src/bottom_bar.dart').readAsStringSync();
    expect(source, isNot(contains('tooltip:')),
        reason: '组件层断言漏了参数改名之类的情况时，这条兜住');
  });
}
