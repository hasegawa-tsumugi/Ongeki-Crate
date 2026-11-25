import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/screens.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 浅色模式「文字是否还看得见」的通用扫描。
///
/// 思路：对每个 Text 的绘制矩形，取矩形内像素的最亮与最暗亮度，
/// 算对比度。文字真被画出来时，矩形里必然既有字形像素也有底色像素；
/// 一旦文字色和底色撞了（例如颜色解析成 null 落到白色），矩形是平的，
/// 对比度接近 1:1 —— 这类问题用「查颜色常量」是抓不到的。
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

  double luminance(int r, int g, int b) {
    double ch(int v) {
      final s = v / 255.0;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
  }

  Future<void> scan(WidgetTester tester, String label, Widget page) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => Directory.systemTemp.path);

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme('official', brightness: Brightness.light),
      home: RepaintBoundary(key: boundary, child: page),
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

    late ByteData data;
    var width = 0, height = 0;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      width = image.width;
      height = image.height;
      data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });

    final failures = <String>[];
    var checked = 0;
    for (final element in find.byType(Text).evaluate()) {
      final text = (element.widget as Text).data;
      if (text == null || text.trim().isEmpty) continue;
      // 直接从 RenderObject 取矩形：页签在树里有两份（可见行 + 被选中
      // 胶囊放大的 accent 副本），`find.byWidget` 会撞到两个而报歧义。
      final box = element.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final left = rect.left.ceil(), top = rect.top.ceil();
      final right = rect.right.floor(), bottom = rect.bottom.floor();
      if (right - left < 3 || bottom - top < 3) continue;
      if (left < 0 || top < 0 || right > width || bottom > height) continue;

      var minL = 1.0, maxL = 0.0;
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final i = (y * width + x) * 4;
          final l = luminance(data.getUint8(i), data.getUint8(i + 1),
              data.getUint8(i + 2));
          if (l < minL) minL = l;
          if (l > maxL) maxL = l;
        }
      }
      final ratio = (maxL + 0.05) / (minL + 0.05);
      checked++;
      // 这里只抓文字几乎与底色同色而「消失」的回归，不要求全页达到 AA。
      // 保留原分类色板与品牌色，不以此扫描推动额外配色改动。
      const minRatio = 2.0;
      if (ratio < minRatio) {
        failures.add('「${text.trim()}」 对比 ${ratio.toStringAsFixed(2)}:1 '
            'rect=${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)}');
      }
    }

    expect(checked, greaterThan(3), reason: '$label 没扫到文字，用例本身失效');
    expect(failures, isEmpty, reason: '$label 有文字与底色几乎同色：\n${failures.join('\n')}');
    // ignore: avoid_print
    print('[$label] 扫描 $checked 段文字，全部可见');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  testWidgets('浅色：筛选面板文字全部可见', (tester) async {
    await scan(
        tester,
        'filter',
        const Scaffold(
          body: FilterSheet(
            initial: SongFilters(),
            genres: ['POPS', 'niconico', 'VARIETY'],
            characters: ['藤沢 柚子', '珠洲島 有栖'],
            releases: ['オンゲキ', 'オンゲキ PLUS'],
          ),
        ));
  });

  testWidgets('浅色：设置页文字全部可见', (tester) async {
    await scan(
        tester,
        'settings',
        SettingsScreen(
            scheme: 'official',
            themeMode: ThemeMode.light,
            onChange: (_) async {},
            onThemeMode: (_) async {}));
  });

  testWidgets('浅色：关于页文字全部可见', (tester) async {
    await scan(
        tester,
        'about',
        AboutScreen(
            dataset: dataset,
            status: '本地曲库已就绪',
            error: null,
            busy: false,
            onUpdate: () async {},
            onClear: () async {},
            loadBytes: () async => 0,
            loadLicense: () async => '许可'));
  });

  testWidgets('浅色：首页文字全部可见', (tester) async {
    await scan(
        tester,
        'home',
        HomeScreen(
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
        ));
  });
}
