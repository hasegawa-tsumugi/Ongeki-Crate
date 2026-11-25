import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/bottom_bar.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/screens.dart';
import 'package:songquery_flutter/src/theme.dart';

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

  for (final width in [390.0, 320.0, 400.0]) {
    // 2.0 是系统字号上限。卡片那轮就是靠它才查出「LEVEL」被断成「LEVE / L」，
    // 其余页面也必须覆盖，否则同类问题只会在用户机器上出现。
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('官网风格截图与溢出检查 $width / $scale', (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                (_) async => Directory.systemTemp.path);
        tester.view.physicalSize = Size(width, width == 400 ? 869 : 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        Future<void> capture(String name, Widget page,
            {String? openTooltip, Key? openKey, String scheme = 'official'}) async {
          // 字体方案不同，同样的字号下文字宽度也不同：非 official 的截图
          // 加后缀，避免覆盖基准图。
          final tag = scheme == 'official' ? '' : '_$scheme';
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(scheme),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: boundary, child: child),
            ),
            home: page,
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
          if (openKey != null) {
            await tester.tap(find.byKey(openKey).first);
            await tester.pump();
            await tester.pump();
          } else if (openTooltip != null) {
            await tester.tap(find.byTooltip(openTooltip));
            await tester.pump();
            await tester.pump();
          }
          expect(tester.takeException(), isNull,
              reason:
                  '$name 在 ${width.toInt()} 宽 / $scale 字号 / $scheme 字体下抛异常');
          if (name == 'home') {
            expect(find.text('MUSIC'), findsNothing);
            expect(find.byKey(const ValueKey('search-button')), findsOneWidget);
            expect(find.byType(LiquidGlassBar), findsOneWidget);
            expect(find.text('Character : '), findsWidgets);
            expect(find.text('LEVEL'), findsWidgets);
          }
          await tester.runAsync(() async {
            final render = boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
                'build/official-screenshots/$name${tag}_${width.toInt()}_${scale.toStringAsFixed(1)}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            if (name == 'card' || name == 'card_real') {
              final rect = tester.getRect(find.byType(SongCardView));
              final recorder = ui.PictureRecorder();
              final canvas = Canvas(recorder);
              canvas.drawImageRect(image, rect,
                  Rect.fromLTWH(0, 0, rect.width, rect.height), Paint());
              final cropped = await recorder
                  .endRecording()
                  .toImage(rect.width.ceil(), rect.height.ceil());
              final cropBytes =
                  await cropped.toByteData(format: ui.ImageByteFormat.png);
              await File(
                      'build/official-screenshots/$name${tag}_crop_${width.toInt()}_${scale.toStringAsFixed(1)}.png')
                  .writeAsBytes(cropBytes!.buffer.asUint8List());
              cropped.dispose();
            }
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 10));
        }

        await capture(
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
        await capture(
            'card',
            Scaffold(
                body: Stack(children: [
              const Positioned.fill(child: MusicBackdrop()),
              Center(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: SongCardView(
                        song: dataset.songs.firstWhere(
                            (song) => song.title.contains('Sugarful')),
                        height: 250 * scale.clamp(1, 1.5),
                        onTap: () {},
                      ))),
            ])));
        await capture(
            'card_real',
            Scaffold(
                body: Center(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: SongCardView(
                          song: dataset.songs.firstWhere(
                              (song) => song.artwork == '5a9758493362722b.png'),
                          height: 250 * scale.clamp(1, 1.5),
                          onTap: () {},
                        )))));
        await capture(
            'detail',
            DetailScreen(
                song: dataset.songs
                    .firstWhere((s) => s.playableCharts.length >= 4)));
        // 首页 + 切到「工具」「我的」两个页签的样子。原来的 menu 截图对应的
        // 菜单页已经下线（入口改成「我的」里的设置/关于两行）。
        final homePage = HomeScreen(
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
            loadLocalBytes: () async => 0);
        await capture('search', homePage, openKey: const ValueKey("search-button"));
        for (final tab in ['tools', 'profile']) {
          await capture(tab, homePage, openKey: ValueKey('tab-$tab'));
        }
        await capture('settings',
            SettingsScreen(scheme: 'official', onChange: (_) async {}));
        await capture(
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

        // 字体方案维度：只在最坏组合（320 宽 × 2.0 字号）上多跑两档。
        // classic 是 SEGA 圆体、system 是全系统字体，同样字号下字宽不同，
        // 大字号下各自可能溢出。全矩阵 × 3 方案太慢，320@2.0 已是最紧的宽度。
        if (width == 320.0 && scale == 2.0) {
          for (final scheme in ['classic', 'system']) {
            await capture(
                'card',
                Scaffold(
                    body: Stack(children: [
                  const Positioned.fill(child: MusicBackdrop()),
                  Center(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: SongCardView(
                            song: dataset.songs.firstWhere(
                                (song) => song.title.contains('Sugarful')),
                            height: 250 * scale.clamp(1, 1.5),
                            onTap: () {},
                          ))),
                ])),
                scheme: scheme);
            await capture(
                'detail',
                DetailScreen(
                    song: dataset.songs
                        .firstWhere((s) => s.playableCharts.length >= 4)),
                scheme: scheme);
            await capture(
                'search',
                HomeScreen(
                    dataset: dataset,
                    status: '本地曲库已就绪',
                    error: null,
                    busy: false,
                    progress: null,
                    revision: 0,
                    scheme: scheme,
                    onUpdate: () async {},
                    onScheme: (_) async {},
                    onClear: () async {},
                    loadLocalBytes: () async => 0),
                openKey: const ValueKey("search-button"),
                scheme: scheme);
          }
        }
      });
    }
  }
}
