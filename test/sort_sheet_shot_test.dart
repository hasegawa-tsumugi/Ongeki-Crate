import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 把「搜索与筛选」页的排序卡片按真实 App 渲染出图，确认：
/// 1) 难度条件 chips 的选中态；2) 方向按钮确实没了；3) 状态栏文案不挤爆。
///
/// 逻辑断言在 `app_smoke_test.dart` / `difficulty_sort_test.dart`，这里只负责出图。
/// 用法：flutter test test/sort_sheet_shot_test.dart
/// 产物：build/shots/sort-{light,dark}.png
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dataset real;

  setUpAll(() async {
    final icons = FontLoader('MaterialIcons');
    icons.addFont(Future.value(ByteData.sublistView(await File(
            'D:/FlutterSDK/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
        .readAsBytes())));
    await icons.load();
    for (final entry in {
      'Official': ['JosefinSans-Bold.ttf'],
      'Josefin': ['JosefinSans-Bold.ttf'],
      'MPLUS1p': ['MPLUS1p-Medium.ttf', 'MPLUS1p-Bold.ttf'],
      'MiSans': ['MiSans-Medium.ttf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(Future.value(ByteData.sublistView(
            await File('assets/fonts/$file').readAsBytes())));
      }
      await loader.load();
    }
    // 曲绘走真实网络，在测试里必然失败并排重试定时器，出图时还会闪占位块。
    // 这里把 artwork 抹掉，让 _Jacket 直接走静态占位：图更稳定，也不留待办定时器。
    final raw = jsonDecode(
        await File('assets/songs-2026.10.15.json').readAsString()) as Map;
    for (final song in (raw['songs'] as List)) {
      (song as Map)['artwork'] = null;
    }
    real = Dataset.fromJson(raw);
  });

  Widget host(Dataset dataset, Brightness brightness, {double textScale = 1.0}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme('official', brightness: brightness),
        // 字号必须改在 MaterialApp 内部（builder 里），套在外面会让
        // MediaQuery.size 变成 Size.zero，按屏宽算尺寸的布局直接撞负数断言。
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: HomeScreen(
          dataset: dataset,
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

  Future<void> openSortSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey("search-button")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 背景网格是 AssetImage，必须在真实事件循环里解码完再截图，否则一片白。
  Future<void> capture(
      WidgetTester tester, GlobalKey boundary, String name) async {
    await tester.runAsync(() async {
      for (final asset in [
        'assets/tex/bg_mesh.webp',
        'assets/tex/bg_circuit.webp'
      ]) {
        await precacheImage(AssetImage(asset), boundary.currentContext!);
      }
    });
    await tester.pump();

    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      image.dispose();
      final out = File('build/shots/$name.png');
      await out.create(recursive: true);
      await out.writeAsBytes(png.buffer.asUint8List());
    });
  }

  Future<void> shoot(
      WidgetTester tester, String name, Brightness brightness,
      {String? scrollTo}) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary, child: host(real, brightness)));
    await tester.pump();
    await openSortSheet(tester);

    if (scrollTo != null) {
      // 不能拿 find.byType(Scrollable).last —— 关键词输入框自己也带一个 Scrollable，
      // 拖它会原地不动导致一直滚不到目标。
      await tester.dragUntilVisible(find.text(scrollTo),
          find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 200));
    }

    await capture(tester, boundary, 'sort-$name');

    // 卸载以取消曲绘重试定时器。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  /// 展开「タブ内 楽曲ソート」下拉出图：8 个选项要全是游戏原文，
  /// 且三个没数据的（バトル / テクニカル / プラチナスコア順）是灰的。
  Future<void> shootDropdown(
      WidgetTester tester, String name, Brightness brightness) async {
    tester.view.physicalSize = const Size(390, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundary = GlobalKey();
    await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: host(real, brightness)));
    await tester.pump();
    await openSortSheet(tester);
    await tester
        .tap(find.byType(DropdownButtonFormField<TabSort>), warnIfMissed: false);
    await tester.pumpAndSettle();
    await capture(tester, boundary, 'sort-$name');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  /// 首页不打开筛选页，直接截「分组 + 卡片」的样子。
  Future<void> shootHome(
      WidgetTester tester, String name, Brightness brightness) async {
    tester.view.physicalSize = const Size(390, 1180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundary = GlobalKey();
    await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: host(real, brightness)));
    await tester.pump();
    await capture(tester, boundary, name);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('排序卡片出图：浅色', (tester) async {
    await shoot(tester, 'light', Brightness.light);
  });

  testWidgets('排序卡片出图：深色', (tester) async {
    await shoot(tester, 'dark', Brightness.dark);
  });

  testWidgets('下拉选项原文出图：浅色', (tester) async {
    await shootDropdown(tester, 'options-light', Brightness.light);
  });

  testWidgets('下拉选项原文出图：深色', (tester) async {
    await shootDropdown(tester, 'options-dark', Brightness.dark);
  });

  testWidgets('角色本家/非本家分段出图：浅色', (tester) async {
    await shoot(tester, 'chars-light', Brightness.light, scrollTo: '角色');
  });

  testWidgets('角色本家/非本家分段出图：深色', (tester) async {
    await shoot(tester, 'chars-dark', Brightness.dark, scrollTo: '角色');
  });

  testWidgets('首页分组出图：浅色', (tester) async {
    await shootHome(tester, 'home-groups-light', Brightness.light);
  });

  testWidgets('小屏 320dp / 2.0 倍字号下排序三栏不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(real, Brightness.light, textScale: 2));
    await tester.pump();
    await openSortSheet(tester);
    expect(tester.takeException(), isNull);

    // 选项改成游戏原文之后明显变长（「対戦相手のレベル順」10 个字，
    // 原来的「对手等级」4 个字）。默认值只验证了「ジャンル / オススメ順 /
    // テクニカルスコア」，最长的那个从没上过场 —— 这里逐栏换成最长的选项，
    // 320dp × 2.0 是最坏情况，撑爆会以 overflow 异常冒出来。
    tester
        .widget<DropdownButtonFormField<TabGroup>>(
            find.byType(DropdownButtonFormField<TabGroup>))
        .onChanged!(TabGroup.character);
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<TabSort>>(
            find.byType(DropdownButtonFormField<TabSort>))
        .onChanged!(TabSort.enemyLevel);
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<RivalScore>>(
            find.byType(DropdownButtonFormField<RivalScore>))
        .onChanged!(RivalScore.platinum);
    await tester.pump();
    expect(tester.takeException(), isNull);
    // 选中的最长项真的画出来了，不是被换行吃掉。
    expect(find.text('対戦相手のレベル順'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
