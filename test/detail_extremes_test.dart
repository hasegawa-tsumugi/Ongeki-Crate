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

/// 用数据集里真实存在的极端值渲染详情页：
/// - 最长 artist（``曲：…／歌：…[CV：…]、…`` 这种，131 字符）
/// - 最长 title（52 字符）
/// - 最长谱师名（64 字符，含句号与空格）
/// - 字段全缺、没有谱面的歌
/// 断言不出现 RenderFlex overflow，并把截图落盘供目视。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dataset dataset;

  setUpAll(() async {
    dataset = Dataset.fromJson(
        jsonDecode(await File('assets/songs-2026.10.15.json').readAsString()));
    final icons = FontLoader('MaterialIcons');
    final iconBytes = await File(
            'D:/FlutterSDK/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
        .readAsBytes();
    icons.addFont(Future.value(ByteData.sublistView(iconBytes)));
    await icons.load();
    for (final entry in {
      'Official': ['JosefinSans-Bold.ttf'],
      'Josefin': ['JosefinSans-Bold.ttf'],
      'MPLUS1p': ['MPLUS1p-Medium.ttf', 'MPLUS1p-Bold.ttf'],
      'MiSans': ['MiSans-Medium.ttf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        final bytes = await File('assets/fonts/$file').readAsBytes();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });

  Song extreme(Song Function(Song, Song) pick) => dataset.songs.reduce(pick);

  for (final width in [320.0, 390.0, 400.0]) {
    // 2.0 是系统字号上限。删掉全部 ellipsis 之后，这一档最容易溢出，
    // 必须覆盖 —— 1.0/1.6 通过不代表 2.0 安全。
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('详情页极端数据 $width / $scale', (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                (_) async => Directory.systemTemp.path);
        tester.view.physicalSize = Size(width, width == 400 ? 869 : 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final longestArtist = extreme((a, b) =>
            (a.artist ?? '').length >= (b.artist ?? '').length ? a : b);
        final longestTitle =
            extreme((a, b) => a.title.length >= b.title.length ? a : b);
        final longestDesigner = extreme((a, b) {
          int longest(Song s) => s.charts.fold(
              0,
              (m, c) => (c.designer ?? '').length > m
                  ? (c.designer ?? '').length
                  : m);
          return longest(a) >= longest(b) ? a : b;
        });
        const minimal = Song(id: 'min', title: 'A', charts: []);

        final cases = <String, Song>{
          'artist${(longestArtist.artist ?? '').length}': longestArtist,
          'title${longestTitle.title.length}': longestTitle,
          'designer': longestDesigner,
          'minimal': minimal,
        };

        final boundary = GlobalKey();
        for (final entry in cases.entries) {
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme('official'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: boundary, child: child),
            ),
            home: DetailScreen(song: entry.value),
          ));
          await tester.runAsync(() async {
            for (final asset in [
              'assets/tex/bg_mesh.webp',
              'assets/tex/bg_circuit.webp'
            ]) {
              await precacheImage(AssetImage(asset), boundary.currentContext!);
            }
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // overflow 会以异常形式冒出来；这里就是护栏
          expect(tester.takeException(), isNull,
              reason: '${entry.key} 在 $width/$scale 下抛异常（多半是 overflow）');

          await tester.runAsync(() async {
            final render = boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
                'build/extreme-screenshots/${entry.key}_${width.toInt()}_${scale.toStringAsFixed(1)}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 10));
        }
      });
    }
  }
}
