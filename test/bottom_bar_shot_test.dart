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

/// 底部导航栏出图。逻辑与几何断言在 `corner_layout_test.dart`（36 组尺寸 ×
/// 字号）和 `app_smoke_test.dart`，这里只负责「看起来对不对」。
///
/// 用法：flutter test test/bottom_bar_shot_test.dart
/// 产物：build/shots/bottom-bar-*.png
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
    // 曲绘走网络，测试里必然失败并排重试定时器；抹掉后走静态占位，图更稳。
    final raw = jsonDecode(
        await File('assets/songs-2026.10.15.json').readAsString()) as Map;
    for (final song in (raw['songs'] as List)) {
      (song as Map)['artwork'] = null;
    }
    real = Dataset.fromJson(raw);
  });

  Widget host(Dataset dataset, Brightness brightness) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme('official', brightness: brightness),
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
    WidgetTester tester,
    String name,
    Brightness brightness, {
    Size size = const Size(390, 900),
    String? tab,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundary = GlobalKey();
    await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: host(real, brightness)));
    await tester.pump();
    if (tab != null) {
      await tester.tap(find.byKey(ValueKey('tab-$tab')).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }
    await capture(tester, boundary, name);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('底栏出图：浅色首页', (tester) async {
    await shoot(tester, 'bottom-bar-light', Brightness.light);
  });

  testWidgets('底栏出图：深色首页', (tester) async {
    await shoot(tester, 'bottom-bar-dark', Brightness.dark);
  });

  testWidgets('底栏出图：浅色「我的」页', (tester) async {
    await shoot(tester, 'bottom-bar-profile-light', Brightness.light,
        tab: 'profile');
  });

  testWidgets('底栏出图：深色「我的」页', (tester) async {
    await shoot(tester, 'bottom-bar-profile-dark', Brightness.dark,
        tab: 'profile');
  });

  testWidgets('底栏出图：浅色「工具」页', (tester) async {
    await shoot(tester, 'bottom-bar-tools-light', Brightness.light,
        tab: 'tools');
  });

  testWidgets('底栏出图：窄屏 320', (tester) async {
    await shoot(tester, 'bottom-bar-320-light', Brightness.light,
        size: const Size(320, 720));
  });

  testWidgets('底栏出图：拖拽中（拇指按压态）', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundary = GlobalKey();
    await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: host(real, Brightness.dark)));
    await tester.pump();

    // 在胶囊上按住横拖一截再出图：press 弹簧走满后拇指 78/56 放大、
    // lens(10dp,14dp) 色散折射与跟手高光全部显现 —— 静止图看不到这一层。
    // 选中胶囊就压在当前选中那格上（默认「主页」），从它的中心按下。
    final pillRect =
        tester.getRect(find.byKey(const ValueKey('tab-home')).first);
    final gesture = await tester.startGesture(pillRect.center);
    await tester.pump();
    await gesture.moveBy(const Offset(46, 0));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await capture(tester, boundary, 'bottom-bar-drag-dark');
    await gesture.up();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
