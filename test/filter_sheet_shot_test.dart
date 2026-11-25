import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/screens.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 把筛选面板在浅色 / 深色下各渲染一张 PNG，用来肉眼确认「选项看不看得见」。
///
/// 像素级断言在 `filter_chip_contrast_test.dart` 与
/// `light_mode_legibility_test.dart`，这里只负责出图。
/// 用法：flutter test test/filter_sheet_shot_test.dart
/// 产物：build/shots/filter-{light,dark}.png
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });

  Future<void> shoot(
      WidgetTester tester, String name, Brightness brightness) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme('official', brightness: brightness),
      home: RepaintBoundary(
        key: boundary,
        child: const Scaffold(
          body: FilterSheet(
            initial: SongFilters(genres: {'niconico'}),
            genres: ['POPS', 'niconico', 'VARIETY'],
            characters: ['藤沢 柚子', '珠洲島 有栖', '日向 千夏'],
            releases: ['オンゲキ', 'オンゲキ PLUS', 'オンゲキ SUMMER'],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // 背景网格是 AssetImage，必须在真实事件循环里解码完再截图，否则一片白。
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
      final out = File('build/shots/filter-$name.png');
      await out.create(recursive: true);
      await out.writeAsBytes(png.buffer.asUint8List());
    });
  }

  testWidgets('筛选面板出图：浅色', (tester) async {
    await shoot(tester, 'light', Brightness.light);
  });

  testWidgets('筛选面板出图：深色', (tester) async {
    await shoot(tester, 'dark', Brightness.dark);
  });
}
