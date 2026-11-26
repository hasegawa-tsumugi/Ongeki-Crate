import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 详情页 + 曲绘全屏页出图，只做人工目视，不做像素比对。
///
/// 曲绘走网络，测试环境取不到 —— 先往 `DefaultCacheManager` 里塞一张
/// 现画的方形图（cacheKey 与 `_Jacket` 传的一致），这样截出来的是「真的有图」
/// 的全屏页，而不是灰底音符占位。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dataset dataset;

  setUpAll(() async {
    dataset = Dataset.fromJson(
        jsonDecode(await File('assets/songs-2026.10.15.json').readAsString()));
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

  /// 画一张 512² 的占位曲绘（紫→品红→金的斜向渐变 + 两个装饰圆）。
  Future<Uint8List> fakeJacket() async {
    const side = 512.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, side, side),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(side, side),
          [const Color(0xFF2B1B4D), const Color(0xFFB03A8C), const Color(0xFFF2C14E)],
          [0, .58, 1],
        ),
    );
    canvas.drawCircle(const Offset(392, 118),
        96, Paint()..color = const Color(0x33FFFFFF));
    canvas.drawCircle(const Offset(96, 430),
        58, Paint()..color = const Color(0x22FFFFFF));
    final image = await recorder.endRecording().toImage(512, 512);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

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

  testWidgets('详情页 + 曲绘全屏页截图', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => Directory.systemTemp.path);

    final base = dataset.songs.firstWhere(
      (s) => s.title.contains('Recollect'),
      orElse: () => dataset.songs.first,
    );
    // 只换曲绘，其余字段保持真实 —— 版式与真实条目一致。
    final song = Song(
      id: base.id,
      title: base.title,
      charts: base.charts,
      titleKana: base.titleKana,
      artist: base.artist,
      genre: base.genre,
      genreId: base.genreId,
      bpm: base.bpm,
      version: base.version,
      releaseTag: base.releaseTag,
      chapter: base.chapter,
      chapterId: base.chapterId,
      character: base.character,
      characterId: base.characterId,
      enemyLevel: base.enemyLevel,
      enemyType: base.enemyType,
      dateAdded: base.dateAdded,
      artwork: '9999.png',
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await DefaultCacheManager().putFile('9999.png', await fakeJacket());
    });

    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme('official'),
        home: DetailScreen(song: song),
      ),
    ));
    await tester.pump();
    // 磁盘缓存命中 → 解码 → 上屏，全程是真实 IO，要反复在 runAsync 里放行
    // 再 pump 一次，单次 delay 不足以让帧重建。
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
    }

    await capture(tester, boundary, 'detail-jacket');

    await tester.tap(find.byKey(const ValueKey('detail-jacket')));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));

    await capture(tester, boundary, 'jacket-fullscreen');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
