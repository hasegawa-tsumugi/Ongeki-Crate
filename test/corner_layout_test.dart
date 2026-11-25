import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/bottom_bar.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/screens.dart';
import 'package:songquery_flutter/src/theme.dart';

void main() {
  late Dataset data;
  final geometry = <Map<String, Object?>>[];
  setUpAll(() async {
    data = Dataset.fromJson(
        jsonDecode(File('assets/songs-2026.10.15.json').readAsStringSync()));
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
  tearDownAll(() {
    final f = File('build/corner-layout-geometry.json');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(geometry));
  });
  for (final size in [
    const Size(320, 844),
    const Size(390, 844),
    const Size(400, 869),
    const Size(390, 667)
  ]) {
    for (final scale in [1.0, 1.6]) {
      for (final safe in [0.0, 24.0, 34.0]) {
        testWidgets('底角布局 ${size.width}/${size.height} 字号$scale safe$safe',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(
              theme: buildTheme('official'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      viewPadding: EdgeInsets.only(bottom: safe)),
                  child: child!),
              home: HomeScreen(
                  dataset: data,
                  status: '就绪',
                  error: null,
                  busy: false,
                  progress: null,
                  revision: 0,
                  scheme: 'official',
                  onUpdate: () async {},
                  onScheme: (_) async {},
                  onClear: () async {},
                  loadLocalBytes: () async => 0)));
          await tester.pump();
          // 几何口径（效果图 1200×2608 实测 + LiquidBottomTabs 项目实值）：
          // 外边距 10.6% / 面板高 64dp / 间隙 3.3% / 底距 6.0%。
          // 逐项断言而不是只拍个眼睛觉得差不多 —— 比例一旦被人凭手感改掉，
          // 这里立刻红。
          final bar = tester.getRect(find.byType(LiquidGlassBar));
          final ctx = tester.element(find.byType(LiquidGlassBar));
          final inset = LiquidGlassBar.insetOf(ctx);
          final height = LiquidGlassBar.heightOf(ctx);
          final gap = LiquidGlassBar.gapOf(ctx);
          final bottomGap = LiquidGlassBar.bottomOf(ctx);
          expect(inset, closeTo(size.width * .106, .01),
              reason: '外边距 = 屏宽 10.6%（效果图 127/1200）');
          expect(height, closeTo(64.0, .01),
              reason: '面板高 = 项目 LiquidBottomTabs 的 64dp');
          expect(gap, closeTo(size.width * .033, .01),
              reason: '胶囊与圆钮间隙 = 屏宽 3.3%（效果图 39/1200）');
          expect(
              bottomGap,
              closeTo(
                  math.max(math.min(size.width * .0604, size.height * .10),
                      safe + 8),
                  .01),
              reason: '底距 = 屏宽 6.0%，安全区更大时让位');
          expect(bar.left, closeTo(inset, .01));
          expect(bar.right, closeTo(size.width - inset, .01));
          expect(bar.height, closeTo(height, .01));
          expect(bar.bottom, closeTo(size.height - bottomGap, .01));
          // 左右对称：效果图里胶囊左边距与圆钮右边距是同一个数。
          expect(bar.left, closeTo(size.width - bar.right, .01));

          final searchRect =
              tester.getRect(find.byKey(const ValueKey('search-button')));
          // 圆钮是正圆、直径等于胶囊高度（效果图两者同高）。
          expect(searchRect.width, closeTo(height, .01));
          expect(searchRect.height, closeTo(height, .01));
          expect(searchRect.right, closeTo(bar.right, .01));
          expect(searchRect.center.dy, closeTo(bar.center.dy, .01));

          // 页签区 = 胶囊左缘到圆钮左边再减掉间隙。
          final tabsRight = searchRect.left - gap;
          expect(tabsRight, lessThan(searchRect.left));

          // 三格等分、紧邻、无缝隙，且内缩 4dp 内边距（LiquidBottomTabs
          // 的 `_inset`）。行高 = 面板高 − 2×4dp = 56dp。
          const pad = 4.0;
          var prevRight = bar.left + pad;
          for (final name in ['home', 'tools', 'profile']) {
            final r = tester.getRect(find.byKey(ValueKey('tab-$name')).first);
            expect(r.left, closeTo(prevRight, .01),
                reason: '第 $name 格必须紧接上一格，不留缝');
            expect(r.width, closeTo((tabsRight - bar.left - pad * 2) / 3, .01),
                reason: '三格等分（面板宽 − 2×4dp）/3');
            expect(r.height, closeTo(height - pad * 2, .01),
                reason: '行高 = 面板高 − 2×4dp = 56dp');
            prevRight = r.right;
          }
          expect(prevRight, closeTo(tabsRight - pad, .01));

          final card =
                  tester.widget<SongCardView>(find.byType(SongCardView).first),
              id = card.song.id;
          final cr = tester.getRect(find.byKey(ValueKey('card-$id'))),
              img = tester.getRect(find.byKey(ValueKey('jacket-$id'))),
              info = tester.getRect(find.byKey(ValueKey('info-$id')));
          expect(cr.left, 15);
          expect(cr.width, size.width - 30);
          expect(img.top - cr.top, 12);
          expect(img.left - cr.left, 12);
          expect(img.top, info.top);
          expect(img.width, size.width <= 350 ? 88 : 104);
          if (scale == 1) {
            expect(cr.height,
                greaterThanOrEqualTo(size.width <= 350 ? 215 : 231.6875));
          }
          geometry.add({
            'width': size.width,
            'height': size.height,
            'scale': scale,
            'safe': safe,
            'bar': [bar.left, bar.top, bar.width, bar.height],
            'tabsRight': tabsRight,
            'search': [
              searchRect.left,
              searchRect.top,
              searchRect.width,
              searchRect.height
            ],
            'gap': gap,
            'bottomGap': bottomGap,
            'firstCard': [cr.left, cr.top, cr.width, cr.height],
            'image': [img.left, img.top, img.width, img.height]
          });
          // 切页签：底栏原地不动，内容换页；切回主页后几何完全一致。
          // 每次切完都要等选中胶囊的弹簧走完再点下一个 —— 胶囊停在要切过去
          // 的那一格的上面，动画未停时它会把这一下吃掉（它自己也响应拖拽）。
          await tester.tap(find.byKey(const ValueKey('tab-tools')).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          // 页内说明文字已删（2026-11-24），改成断言占位页本身到位。
          expect(find.byType(ToolsPlaceholderScreen), findsOneWidget);
          expect(tester.getRect(find.byType(LiquidGlassBar)), bar);
          expect(find.byType(SongCardView), findsNothing,
              reason: '切到别的页签，曲库列表应当整页让位而不是叠在下面');
          await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.text('设置'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('tab-home')).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.byType(SongCardView), findsWidgets);
          expect(tester.getRect(find.byType(LiquidGlassBar)), bar);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        });
      }
    }
  }
}
