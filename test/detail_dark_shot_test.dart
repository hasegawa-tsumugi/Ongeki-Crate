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

/// 深色详情页截图：用来目视确认卡片四边包边都在（尤其是左侧那条）。
/// 图片写到 build/detail-dark/，只做人工检查，不做截图比对。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 必须在 setUpAll 里读文件：testWidgets 的 body 跑在 FakeAsync 区域，
  // 直接 await 真实 IO 会一直等下去（这次实测卡了 7 分钟）。
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

  testWidgets('深色详情页截图', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => Directory.systemTemp.path);

    final song = dataset.songs.firstWhere((s) => s.title.contains('Recollect'));
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme('official', brightness: Brightness.dark),
      home: RepaintBoundary(key: boundary, child: DetailScreen(song: song)),
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
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/detail-dark/recollect-dark.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });

    expect(File('build/detail-dark/recollect-dark.png').existsSync(), isTrue);

    // 曲绘走 cached_network_image，它的缓存清理定时器会在树销毁后仍然挂着；
    // 卸载后把时间推过去，否则报 "A Timer is still pending"。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });
}
