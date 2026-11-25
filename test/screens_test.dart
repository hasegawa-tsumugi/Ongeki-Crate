import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/bottom_bar.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/screens.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 三个独立页面的整机级渲染：筛选抽屉、设置、关于。
///
/// 这几页在 HomeScreen 的冒烟里只是被「打开」，内部交互（切换字体方案、
/// 应用筛选、删除确认）从没跑过 —— 而它们恰好都带 Navigator / 对话框 /
/// 异步回调，是最容易出「点了没反应」的地方。
void main() {
  late Dataset real;

  setUpAll(() async {
    final json = jsonDecode(
      await File('assets/songs-2026.10.15.json').readAsString(),
    );
    real = Dataset.fromJson(json);
  });

  group('FilterSheet', () {
    /// 用合成的小列表，避免为了点到「版本」组而在 ListView 里滚半天。
    Widget host({
      required SongFilters initial,
      required void Function(SongFilters?) onResult,
    }) =>
        MaterialApp(
          theme: buildTheme('official'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await showModalBottomSheet<SongFilters>(
                      context: context,
                      builder: (_) => FilterSheet(
                        initial: initial,
                        genres: const ['POPS', 'VARIETY'],
                        characters: const ['茜', '柚鳥'],
                        releases: const ['R1', 'R2'],
                      ),
                    );
                    onResult(result);
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );

    /// 抽屉里的「版本」组在视口之外：ListView 只负责裁剪，Text 组件其实已经在树里，
    /// 直接 tap 会命中别的东西（flutter_test 只会警告，测试照样"过"）。
    /// 先 ensureVisible 把它滚进来，再点。
    Future<void> tapChip(WidgetTester tester, String label) async {
      final chip = find.text(label);
      await tester.scrollUntilVisible(chip, 120,
          scrollable: find.byType(Scrollable).last);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();
    }

    testWidgets('returns the toggled chip', (tester) async {
      SongFilters? result;
      await tester.pumpWidget(
        host(initial: SongFilters.empty, onResult: (r) => result = r),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('筛选曲目'), findsOneWidget);
      // 未选任何项时计数是 0。
      expect(find.text('应用筛选（0）'), findsOneWidget);

      await tapChip(tester, 'POPS');
      expect(find.text('应用筛选（1）'), findsOneWidget);

      await tester.tap(find.text('应用筛选（1）'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.genres, {'POPS'});
      expect(result!.characters, isEmpty);
    });

    testWidgets('toggles a chip off on second tap', (tester) async {
      SongFilters? result;
      await tester.pumpWidget(
        host(initial: SongFilters.empty, onResult: (r) => result = r),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      await tapChip(tester, 'R1');
      // 必须断言中间态：否则「点不到」也会让下面的 0 通过（这条一开始就是这么假过的）。
      expect(find.text('应用筛选（1）'), findsOneWidget);

      await tapChip(tester, 'R1');
      expect(find.text('应用筛选（0）'), findsOneWidget);

      await tester.tap(find.text('应用筛选（0）'));
      await tester.pumpAndSettle();
      expect(result!.releaseTags, isEmpty);
    });

    testWidgets('clear-all keeps the row filter', (tester) async {
      SongFilters? result;
      await tester.pumpWidget(
        host(
          // 行筛选不应该被「全部清除」抹掉：它由排序决定，不属于抽屉。
          initial: const SongFilters(
            genres: {'POP'},
            characters: {'茜'},
            releaseTags: {'R2'},
            rows: {'あ行'},
          ),
          onResult: (r) => result = r,
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('应用筛选（3）'), findsOneWidget);

      await tester.tap(find.text('全部清除'));
      await tester.pump();
      expect(find.text('应用筛选（0）'), findsOneWidget);

      await tester.tap(find.text('应用筛选（0）'));
      await tester.pumpAndSettle();
      expect(result!.genres, isEmpty);
      expect(result!.characters, isEmpty);
      expect(result!.releaseTags, isEmpty);
      expect(result!.rows, {'あ行'});
    });
  });

  group('SettingsScreen', () {
    Widget host({
      String scheme = 'official',
      required List<String> log,
    }) =>
        MaterialApp(
          theme: buildTheme(scheme),
          home: SettingsScreen(
            scheme: scheme,
            onChange: (value) async => log.add(value),
          ),
        );

    testWidgets('renders every scheme and the preview card', (tester) async {
      await tester.pumpWidget(host(log: []));
      await tester.pump();
      expect(find.text('字体方案'), findsOneWidget);
      expect(find.byType(LiquidGlassBar), findsNothing);
      expect(tester.getTopLeft(find.byIcon(Icons.arrow_back)).dy, 55);
      expect(tester.getBottomLeft(find.byType(ListView)).dy,
          tester.view.physicalSize.height / tester.view.devicePixelRatio);
      expect(find.text('官方混排'), findsOneWidget);
      expect(find.text('旧版游戏圆体 · 系统界面字'), findsOneWidget);
      expect(find.text('全部系统字体'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('We Are Us!'), 80,
          scrollable: find.byType(Scrollable).first);
      // 预览卡里的曲名与数值都要在。
      expect(find.text('We Are Us!'), findsOneWidget);
      expect(find.text('うぃーあーあす'), findsOneWidget);
      expect(find.text('13.7'), findsOneWidget);
    });

    // 背景的三条黄绿斜带固定钉在视口 .64H，和滚动位置无关 —— 文字只要露在
    // 背景上，列表一动就会被横穿。320@2.0 下实测「官方混排」的说明被劈成两半。
    testWidgets('all text sits inside an opaque card', (tester) async {
      await tester.pumpWidget(host(log: []));
      await tester.pump();
      final texts = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Text),
      );
      expect(texts, findsWidgets);
      for (final element in texts.evaluate()) {
        var inCard = false;
        element.visitAncestorElements((ancestor) {
          inCard = ancestor.widget is Chamfer;
          return !inCard;
        });
        expect(
          inCard,
          isTrue,
          reason: '「${(element.widget as Text).data}」露在背景上，'
              '滚动时会被黄绿斜带横穿',
        );
      }
    });

    testWidgets('switching a scheme notifies and retypes the preview', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(host(log: log));
      await tester.pump();

      await tester.scrollUntilVisible(find.text('We Are Us!'), 80,
          scrollable: find.byType(Scrollable).first);
      // official：曲名用随包的 SEGA。
      expect(
        tester.widget<Text>(find.text('We Are Us!')).style!.fontFamily,
        FontRoles.forScheme('official').content,
      );

      await tester.ensureVisible(find.text('全部系统字体'));
      await tester.tap(find.text('全部系统字体'));
      await tester.pump();

      expect(log, ['system']);
      await tester.scrollUntilVisible(find.text('We Are Us!'), 80,
          scrollable: find.byType(Scrollable).first);
      // 预览要跟着**当前选择**走，而不是主题里已生效的方案。
      expect(
        tester.widget<Text>(find.text('We Are Us!')).style!.fontFamily,
        isNull,
      );
    });

    testWidgets('survives an unknown scheme', (tester) async {
      // 存量设置里可能有旧方案名；forScheme 的兜底不能崩。
      await tester.pumpWidget(host(scheme: 'legacy-scheme', log: []));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('We Are Us!'), 80,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('We Are Us!'), findsOneWidget);
    });
  });

  group('AboutScreen', () {
    Widget host({
      Dataset? dataset,
      String status = '本地曲库已就绪',
      String? error,
      bool busy = false,
      VoidCallback? onUpdate,
      VoidCallback? onClear,
      int bytes = 0,
      int revision = 0,
      Future<String> Function()? loadLicense,
    }) =>
        MaterialApp(
          theme: buildTheme('official'),
          home: AboutScreen(
            dataset: dataset,
            status: status,
            error: error,
            busy: busy,
            revision: revision,
            loadBytes: () async => bytes,
            loadLicense: loadLicense ?? () async => '许可全文占位',
            onUpdate: () async => onUpdate?.call(),
            onClear: () async => onClear?.call(),
          ),
        );

    testWidgets('shows the real local size instead of a placeholder', (
      tester,
    ) async {
      // 这一行原来是写死的「在线缓存」——占位符冒充数据。
      // 「本地体积」在页面中部，ListView 惰性构建，而且 SliverList 只把可见区的
      // 子项算 onstage —— 固定距离 drag 滚过头就假失败，滚到行为止。
      Future<void> show(Widget tree) async {
        await tester.pumpWidget(tree);
        await tester.pump();
        await tester.scrollUntilVisible(
          find.text('本地体积'),
          200,
          scrollable: find.byType(Scrollable),
        );
      }

      await show(host(bytes: 1656352, revision: 0));
      expect(find.text('1.6 MB'), findsOneWidget);
      expect(find.text('在线缓存'), findsNothing);

      // 换量级也要对得上（KB / B）。revision 跟着变 —— 体积是靠它触发重取的。
      await show(host(bytes: 51200, revision: 1));
      expect(find.text('50 KB'), findsOneWidget);

      await show(host(bytes: 0, revision: 2));
      expect(find.text('0 B'), findsOneWidget);
    });

    testWidgets('counts songs and charts from the real library', (
      tester,
    ) async {
      await tester.pumpWidget(host(dataset: real));
      await tester.pump();

      final charts = real.songs.fold<int>(
        0,
        (sum, song) => sum + song.playableCharts.length,
      );
      expect(find.text('${real.songs.length} / $charts'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);

      expect(find.byType(LiquidGlassBar), findsNothing);
      await tester.scrollUntilVisible(find.text('查看全文许可'), 100,
          scrollable: find.byType(Scrollable));
      expect(find.text('GitHub Raw'), findsOneWidget);
      expect(find.textContaining('兜底'), findsNothing);
      expect(find.text('定数覆盖'), findsNothing);
      expect(find.text('字体许可'), findsNothing);
      expect(find.text('songquery Flutter 重写版 · Android'), findsNothing);
    });

    testWidgets('busy disables the update button', (tester) async {
      await tester.pumpWidget(host(dataset: real, busy: true));
      await tester.pump();

      expect(find.text('下载中'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '正在下载…'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('surfaces the last error', (tester) async {
      await tester.pumpWidget(host(dataset: null, error: '线路全部失败'));
      await tester.pump();
      expect(find.text('线路全部失败'), findsOneWidget);
      // 没有曲库时删除按钮不可点。
      await tester.scrollUntilVisible(find.text('删除本地曲库'), 80,
          scrollable: find.byType(Scrollable).first);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '删除本地曲库'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('delete asks for confirmation first', (tester) async {
      var cleared = 0;
      await tester.pumpWidget(
        host(dataset: real, onClear: () => cleared++),
      );
      await tester.pump();

      await tester.tap(find.text('删除本地曲库'));
      await tester.pumpAndSettle();
      expect(find.text('删除本地曲库？'), findsOneWidget);

      // 取消不该触发回调 —— 这是「误触一下就把 54MB 曲绘缓存外的曲库删了」的最后一道闸。
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cleared, 0);

      await tester.tap(find.text('删除本地曲库'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(cleared, 1);
    });

    testWidgets('renders without a dataset', (tester) async {
      await tester.pumpWidget(host(dataset: null));
      await tester.pump();
      // 没有曲库时统计数字要退化成 0 / —，不能让 null 解引用。
      expect(find.text('0 / 0'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('states the MiSans attribution required by its license', (
      tester,
    ) async {
      await tester.pumpWidget(host(dataset: real));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('查看全文许可'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('查看全文许可'));
      await tester.pumpAndSettle();
      expect(find.text('本软件使用了 MiSans 字体。'), findsOneWidget);
      expect(find.text('许可全文占位'), findsOneWidget);
    });

    testWidgets('shows the full license text in a dialog', (tester) async {
      // 许可全文走注入的加载器 —— rootBundle 在 flutter_test 里有顺序依赖，
      // 真实读取在 loadFontLicenseText（app.dart 传入），这里用假实现断言弹窗。
      await tester.pumpWidget(
        host(
          dataset: real,
          loadLicense: () async => 'OFL 1.1 全文测试占位',
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('查看全文许可'), 80,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('查看全文许可'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看全文许可'));
      await tester.pumpAndSettle();
      expect(find.text('OFL 1.1 全文测试占位'), findsOneWidget);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('OFL 1.1 全文测试占位'), findsNothing);
    });
  });

  group('FontRoles', () {
    test('copyWith only overrides non-null fields', () {
      const base = FontRoles(content: 'SEGA', numeric: 'Josefin', label: null);
      final replaced = base.copyWith(numeric: 'MiSans');
      expect(replaced.content, 'SEGA');
      expect(replaced.numeric, 'MiSans');
      expect(replaced.label, isNull);
      // 全传 null 等于原样复制 —— label 为 null 的方案（system/classic）不能被写成空串。
      expect(base.copyWith().label, isNull);
    });

    test('lerp takes endpoints instead of interpolating font names', () {
      const a = FontRoles(content: 'SEGA');
      const b = FontRoles(content: 'MiSans');
      expect(a.lerp(b, 0).content, 'SEGA');
      expect(a.lerp(b, 0.49).content, 'SEGA');
      expect(a.lerp(b, 0.5).content, 'MiSans');
      // other 不是 FontRoles 时保持自己，不让字体名被插值成半个字符串。
      expect(a.lerp(null, 0.9).content, 'SEGA');
    });
  });
}
