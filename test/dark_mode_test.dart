import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/repository.dart';
import 'package:songquery_flutter/src/screens.dart';
import 'package:songquery_flutter/src/theme.dart';

const song = Song(
    id: 'dark-test',
    title: '测试曲目',
    artist: '作者',
    titleKana: 'よみ',
    character: '角色',
    isNew: true,
    aliases: [
      '测试别名'
    ],
    charts: [
      Chart(
          difficulty: 0,
          level: 3,
          levelDecimal: 0,
          levelValue: 3,
          enabled: true,
          designer: '测试谱师')
    ]);

class _Repository extends SongRepository {
  @override
  Future<Dataset?> loadLocal() async => Dataset([song]);
  @override
  Future<Dataset> fetchAndInstall(
          {void Function(int, int, String)? onProgress}) async =>
      Dataset([song]);
}

void main() {
  test('官网六分类颜色与五难度顺序精确对应', () {
    expect(genreColors, {
      '01': 0xFFFF0066,
      '02': 0xFFFFD822,
      '03': 0xFFCF3EFF,
      '04': 0xFF00C312,
      '05': 0xFF42B6FF,
      '06': 0xFFFF7DAB,
    });
    expect(
        difficultyNames, ['BASIC', 'ADVANCED', 'EXPERT', 'MASTER', 'LUNATIC']);
    expect(difficultyColors,
        [0xFF16FF47, 0xFFFFBA00, 0xFFFA0667, 0xFFA810FF, 0xFFF8FF2F]);
    expect(difficultyTones.map((color) => color.toARGB32()), difficultyColors);
  });
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} 首页及详情内容卡语义色与纹理', (tester) async {
      final dark = brightness == Brightness.dark;
      final fill = dark ? const Color(0xCC222222) : const Color(0xCCFFFFFF);
      final ink = dark ? Colors.white : const Color(0xFF111111);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme('official', brightness: brightness),
        home: Scaffold(
            body: SongCardView(song: song, reason: '匹配曲名', onTap: () {})),
      ));
      await tester.pumpAndSettle();
      final card = tester
          .widget<Container>(find.byKey(const ValueKey('card-dark-test')));
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, fill);
      expect(decoration.color!.toARGB32(), dark ? 0xCC222222 : 0xCCFFFFFF);
      expect(decoration.color!.a, closeTo(204 / 255, 0.0001));
      expect(
          find.ancestor(
              of: find.text(song.title), matching: find.byType(Opacity)),
          findsNothing);
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(image.opacity, isNull);
        expect(
            find.ancestor(
                of: find.byWidget(image), matching: find.byType(Opacity)),
            findsNothing);
      }
      expect(decoration.image!.image,
          const AssetImage('assets/tex/bg_circuit.webp'));
      // 源图 RGB 全白，以 alpha 保存电路线；不能将透明像素变成整块蒙层。
      expect(
          decoration.image!.colorFilter,
          ColorFilter.matrix([
            0,
            0,
            0,
            0,
            dark ? 255 : 0,
            0,
            0,
            0,
            0,
            dark ? 255 : 0,
            0,
            0,
            0,
            0,
            dark ? 255 : 0,
            0,
            0,
            0,
            dark ? .16 : .05,
            0,
          ]));
      final cardPaint = tester.widget<CustomPaint>(find
          .ancestor(
              of: find.byKey(const ValueKey('card-dark-test')),
              matching: find.byType(CustomPaint))
          .first);
      expect(cardPaint.foregroundPainter, isA<ChamferOutlinePainter>());
      expect(tester.widget<Text>(find.text(song.title)).style!.color, ink);
      expect(tester.widget<Text>(find.text(song.title)).style!.color!.a, 1);
      expect(tester.widget<Text>(find.text('NEW')).style!.color, ink);
      final authorStyle = tester.widget<Text>(find.text('ARTIST: 作者')).style!;
      expect(authorStyle.color,
          dark ? const Color(0xFFBDBDBD) : const Color(0xFF333333));
      expect(authorStyle.fontWeight, dark ? FontWeight.w500 : FontWeight.w600);
      for (final key in ['levels-dark-test', 'character-dark-test']) {
        final inner = tester.widget<Container>(find.byKey(ValueKey(key)));
        expect((inner.decoration! as BoxDecoration).color, Colors.transparent);
      }
      if (!dark) {
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          final color = text.style?.color;
          if (color != null && color != AppPalette.magenta) {
            expect(color.a, 1);
            expect(1.05 / (color.computeLuminance() + .05),
                greaterThanOrEqualTo(7));
          }
          expect(text.style?.shadows, anyOf(isNull, isEmpty));
        }
      }
      final ringText = find.descendant(
          of: find.byType(DifficultyRing), matching: find.byType(Text));
      expect(tester.widget<Text>(ringText).style!.color, ink);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme('official', brightness: brightness),
        home: const DetailScreen(song: song),
      ));
      await tester.pumpAndSettle();
      for (final box in tester.widgetList<Container>(find.descendant(
          of: find.byType(Chamfer), matching: find.byType(Container)))) {
        final d = box.decoration;
        if (d is BoxDecoration && d.color != null) {
          expect(d.color, fill);
          expect(
              d.image!.image, const AssetImage('assets/tex/bg_circuit.webp'));
        }
      }
      expect(tester.widget<Text>(find.text('BASIC')).style!.color, ink);
      expect(
          tester
              .widget<Text>(
                  find.text(song.displayLevel(song.charts.first)).last)
              .style!
              .color,
          ink);
      expect(tester.widget<Text>(find.text('版本')).style!.color,
          dark ? const Color(0xFFBDBDBD) : const Color(0xFF333333));
      expect(tester.widget<Text>(find.text('—').first).style!.color, ink);
      expect(tester.takeException(), isNull);
    });
  }

  Future<void> mount(WidgetTester tester, SharedPreferences prefs) async {
    await tester.pumpWidget(SongQueryApp(
      preferences: prefs,
      repository: _Repository(),
      bundledLoader: () async => Dataset([song]),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('默认跟随系统，关闭强制浅色并保存，重启及重新开启有效', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await mount(tester, prefs);
    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(HomeScreen))).brightness;
    expect(app().themeMode, ThemeMode.system);
    expect(brightness(), Brightness.dark);
    expect(app().darkTheme!.scaffoldBackgroundColor, Colors.black);
    final bars = tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first)
        .value;
    expect(bars.systemNavigationBarColor, Colors.black);
    expect(bars.statusBarIconBrightness, Brightness.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
    await tester.pumpAndSettle();
    await open(tester, '设置');
    expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));
    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.light);
    expect(prefs.getString('themeMode'), 'light');
    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
        Brightness.light);

    await tester.pumpWidget(const SizedBox());
    await mount(tester, prefs);
    expect(app().themeMode, ThemeMode.light);
    expect(brightness(), Brightness.light);
    await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
    await tester.pumpAndSettle();
    await open(tester, '设置');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.dark);
    expect(prefs.getString('themeMode'), 'dark');
    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
        Brightness.dark);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, prefs);
    expect(app().themeMode, ThemeMode.dark);
    expect(brightness(), Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
    await tester.pumpAndSettle();
    await open(tester, '设置');
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
        Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.system);
    expect(prefs.getString('themeMode'), 'system');
    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
        Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧偏好迁移且页面背景仅保留网格', (tester) async {
    SharedPreferences.setMockInitialValues({'followSystemDarkMode': false});
    await mount(tester, await SharedPreferences.getInstance());
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light);
    expect(
        find.descendant(
            of: find.byType(OfficialBackground), matching: find.byType(Image)),
        findsNothing);
    final background = tester.widget<DecoratedBox>(find
        .descendant(
            of: find.byType(OfficialBackground),
            matching: find.byType(DecoratedBox))
        .first);
    expect((background.decoration as BoxDecoration).image!.image,
        const AssetImage('assets/tex/bg_mesh.webp'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('暗色首页、菜单、搜索及详情渲染，黑卡和难度色不变', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({});
    await mount(tester, await SharedPreferences.getInstance());
    expect(find.byType(SongCardView), findsOneWidget);
    final character = tester
        .widget<Container>(find.byKey(const ValueKey('character-dark-test')));
    expect((character.decoration! as BoxDecoration).color, Colors.transparent);
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pumpAndSettle();
    expect(find.text('搜索与筛选'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<TabGroup>).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 灰项（属性）在深色下也要能正常渲染、点不动。
    await tester.tap(find.text('属性').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('キャラクター').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SongCardView));
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(DetailScreen))).brightness,
        Brightness.dark);
    expect(find.text('作者'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(difficultyTones.first, const Color(0xFF16FF47));
  });

  testWidgets('暗色关于、许可、删除确认、筛选抽屉和原生弹窗渲染', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme('official', brightness: Brightness.dark),
      home: AboutScreen(
          dataset: Dataset([song]),
          status: '就绪',
          error: null,
          busy: false,
          onUpdate: () async {},
          onClear: () async {},
          loadBytes: () async => 1024,
          loadLicense: () async => '测试许可全文'),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('查看全文许可'), 250);
    await open(tester, '查看全文许可');
    expect(find.text('测试许可全文'), findsOneWidget);
    await open(tester, '关闭');
    await tester.scrollUntilVisible(find.text('删除本地曲库'), -250);
    await open(tester, '删除本地曲库');
    expect(find.text('删除本地曲库？'), findsOneWidget);
    await open(tester, '取消');
    final context = tester.element(find.byType(AboutScreen));
    showModalBottomSheet<void>(
        context: context,
        builder: (_) => const FilterSheet(
            initial: SongFilters.empty,
            genres: ['分类'],
            characters: ['角色'],
            releases: ['版本']));
    await tester.pumpAndSettle();
    expect(find.text('筛选曲目'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    showDialog<void>(
        context: context,
        builder: (_) =>
            const AlertDialog(title: Text('测试弹窗'), content: Text('测试内容')));
    await tester.pumpAndSettle();
    final dialogContext = tester.element(find.byType(AlertDialog));
    expect(Theme.of(dialogContext).dialogTheme.backgroundColor, Colors.black);
    expect(DefaultTextStyle.of(tester.element(find.text('测试内容'))).style.color,
        Colors.white);
    expect(tester.takeException(), isNull);
  });
}
