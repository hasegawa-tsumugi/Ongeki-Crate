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

/// 截图输出目录，用 `--dart-define=SHOT_DIR=...` 切换，便于做改前/改后对照。
const shotDir =
    String.fromEnvironment('SHOT_DIR', defaultValue: 'build/card-shots');

/// 列表卡片在极端文本下的自然高度。
///
/// 卡片规矩是「不截断、自然增高」（11-02 定），所以长作者名必然把卡片撑高。
/// 这组用例把高度钉住，避免以后改动把极端卡片撑到离谱而不自知。
///
/// **不要用 ListView 包卡片**：`IntrinsicHeight`（卡片内层）在 ListView 的
/// 无界高度 + 滚动缓存下，会让 `testWidgets` 静默挂死 —— 日志停在用例名之后、
/// 既不报错也不超时（2026-11-09 实测两次，分别等 7 分半和 4 分半）。
/// 改用 `Column` 提供无界高度，布局语义等价，1 秒内跑完。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dataset dataset;
  late Map<String, Song> cases;

  setUpAll(() async {
    dataset = Dataset.fromJson(
        jsonDecode(await File('assets/songs-2026.10.15.json').readAsString()));
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
    final longestArtist = dataset.songs.reduce(
        (a, b) => (a.artist ?? '').length >= (b.artist ?? '').length ? a : b);
    final longestTitle = dataset.songs
        .reduce((a, b) => a.title.length >= b.title.length ? a : b);
    cases = {
      'normal': dataset.songs.firstWhere((s) => s.title.contains('Sugarful')),
      'artist${(longestArtist.artist ?? '').length}': longestArtist,
      'title${longestTitle.title.length}': longestTitle,
    };
  });

  // 测试名保持 ASCII：PowerShell 传中文给 flutter.bat 会乱码，--plain-name 匹配不上。
  for (final width in [320.0, 390.0]) {
    // 2.0 是系统字号上限：卡片不截断，这一档最容易超过一屏。
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('card natural height $width / $scale', (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                (_) async => Directory.systemTemp.path);
        const screenHeight = 844.0;
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        double? normalHeight;
        final boundary = GlobalKey();
        for (final entry in cases.entries) {
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme('official'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            // Column 给子节点无界高度；卡片只受 minHeight 约束，与真实列表一致。
            home: Scaffold(
              body: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  // RepaintBoundary 只包卡片：截图就是卡片本身，不含整屏空白。
                  child: RepaintBoundary(
                    key: boundary,
                    child: SongCardView(song: entry.value, onTap: () {}),
                  ),
                ),
              ]),
            ),
          ));
          // 不 precache 背景纹理：它只是 10% 透明度的底纹，缺了不影响作者名
          // 排版对照；而 precacheImage 会留下未完成的 Timer，让用例在
          // "A Timer is still pending" 上失败。
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull,
              reason: '${entry.key} 在 $width/$scale 下抛异常');

          final rect = tester.getRect(find.byType(SongCardView).first);
          // ignore: avoid_print
          print('CARD_HEIGHT ${entry.key} ${width.toInt()}x$scale -> '
              '${rect.height.toStringAsFixed(1)}dp');

          await tester.runAsync(() async {
            final render = boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$shotDir/${entry.key}_${width.toInt()}_'
                '${scale.toStringAsFixed(1)}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          if (entry.key == 'normal') {
            normalHeight = rect.height;
            // 常规卡片高度随字号近似线性：实测 1.0 约 227/244、1.6 约 361/317、
            // 2.0 约 524/407。按 300 × 字号 设上限，别写死绝对值。
            expect(rect.height, lessThan(300 * scale),
                reason: '常规卡片高度不应超过 300×字号 ($scale)');
          } else {
            // 极端卡片上限按档设定，都紧贴当前实测值以便捕捉回归：
            // - 1.0 / 1.6：实测最坏 611dp，限 95% 屏高（802）
            // - 2.0：实测最坏 868dp，**已经超过屏高 844**（320 宽 + 131 字符
            //   作者 + 系统最大字号三者叠加），限 105% 屏高（886）。
            //   不截断的前提下这没法避免，也不该靠继续缩字号硬压 ——
            //   调大字号的用户要的是看清楚，把它缩到比正文还小是本末倒置。
            final limit =
                scale >= 2.0 ? screenHeight * 1.05 : screenHeight * .95;
            expect(rect.height, lessThan(limit),
                reason: '${entry.key} 在 $width/$scale 下高 ${rect.height}dp，'
                    '超出该档上限 ${limit.toStringAsFixed(1)}dp');
            // 52 字符曲名在 390 宽能被单行容纳，高度与常规卡持平是正常的。
            expect(rect.height, greaterThanOrEqualTo(normalHeight!),
                reason: '长文本卡片不应当比常规卡片矮');
          }
        }
        // 卡片里的曲绘会起一个图片请求 Timer，不推掉的话用例会挂在
        // "A Timer is still pending even after the widget tree was disposed"。
        // 和 detail_extremes_test 一样：卸载树再推进一段时间。
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      });
    }
  }
}
