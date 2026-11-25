import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/theme.dart';

Widget _host({
  String status = '尚未安装曲库',
  bool busy = false,
  double? progress,
}) {
  return MaterialApp(
    home: HomeScreen(
      dataset: null,
      status: status,
      error: null,
      busy: busy,
      progress: progress,
      revision: 0,
      scheme: 'official',
      onUpdate: () async {},
      onScheme: (_) async {},
      onClear: () async {},
      loadLocalBytes: () async => 0,
    ),
  );
}

const _seed = Song(
  id: '1',
  title: 'Seed Song',
  titleKana: 'シード',
  artist: 'Artist',
  genre: 'POPS',
  genreId: '01',
  artwork: '5a9758493362722b.png',
  charts: [
    Chart(
      difficulty: 3,
      level: 13,
      levelDecimal: 7,
      levelValue: 13.7,
      enabled: true,
    ),
  ],
);

void main() {
  testWidgets('renders the song query screen without a dataset',
      (tester) async {
    await tester.pumpWidget(_host());

    expect(find.text('曲目查询'), findsNothing);
    expect(find.byKey(const ValueKey("search-button")), findsOneWidget);
    expect(find.text('尚未安装曲库'), findsOneWidget);
  });

  testWidgets('shows a determinate progress bar while updating',
      (tester) async {
    await tester.pumpWidget(_host(busy: true, progress: 0.5));

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5);
  });

  testWidgets('falls back to an indeterminate bar when total is unknown',
      (tester) async {
    await tester.pumpWidget(_host(busy: true));

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);
  });

  testWidgets('hides the progress bar when idle', (tester) async {
    await tester.pumpWidget(_host());

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  test('公共控件共享字体回退、切角与高度', () {
    final theme = buildTheme('official');
    final filled = theme.filledButtonTheme.style!;
    final outlined = theme.outlinedButtonTheme.style!;
    for (final style in [filled, outlined, theme.textButtonTheme.style!]) {
      expect(style.textStyle!.resolve({})!.fontFamilyFallback,
          ['MPLUS1p', 'MiSans']);
      expect(style.textStyle!.resolve({})!.fontSize, AppTokens.controlFontSize);
      expect(style.minimumSize!.resolve({})!.height, AppTokens.controlHeight);
    }
    for (final shape in [
      filled.shape!.resolve({}),
      outlined.shape!.resolve({}),
      theme.chipTheme.shape
    ]) {
      expect(shape, isA<ChamferBorder>());
      expect((shape! as ChamferBorder).size, AppTokens.controlShape.size);
      expect(shape.side.color, const Color(0xFFD5D5D5));
    }
    expect(theme.chipTheme.side, BorderSide.none);
    expect(theme.dialogTheme.contentTextStyle!.fontFamilyFallback,
        ['MPLUS1p', 'MiSans']);
    expect(theme.appBarTheme.titleTextStyle!.color, const Color(0xFF111111));
    expect(
        buildTheme('system')
            .filledButtonTheme
            .style!
            .textStyle!
            .resolve({})!.fontFamilyFallback,
        isNull);
  });

  group('font schemes', () {
    test('map to the same three roles as the RN catalog', () {
      final official = FontRoles.forScheme('official');
      expect(official.content, 'Official');
      expect(official.numeric, 'Josefin');
      expect(official.label, 'Official');

      final classic = FontRoles.forScheme('classic');
      expect(classic.content, 'SEGA');
      expect(classic.numeric, 'Josefin');
      expect(classic.label, isNull);

      final system = FontRoles.forScheme('system');
      expect(system.content, isNull);
      expect(system.numeric, isNull);
      expect(system.label, isNull);

      // 存了非法方案 id 时要退回 official，而不是变成全系统字体。
      expect(
        FontRoles.forScheme('nonsense').content,
        FontRoles.forScheme('official').content,
      );
    });

    /// `MaterialApp` 内部用 `AnimatedTheme` 过渡主题，换方案后要等动画走完，
    /// 否则读到的还是上一套字体角色（lerp 在 t<0.5 时返回端点）。
    Future<void> pumpCard(WidgetTester tester, String scheme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(scheme),
          home: Scaffold(
            body: SongCardView(song: _seed, onTap: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String? titleFont(WidgetTester tester) =>
        tester.widget<Text>(find.text('Seed Song')).style?.fontFamily;

    testWidgets('song titles use the content font unless the scheme is system',
        (tester) async {
      await pumpCard(tester, 'official');
      expect(titleFont(tester), 'Official');

      await pumpCard(tester, 'classic');
      expect(titleFont(tester), 'SEGA');

      await pumpCard(tester, 'system');
      expect(titleFont(tester), isNull);
    });

    testWidgets('no bundled font survives the system scheme', (tester) async {
      await pumpCard(tester, 'system');
      // 难度圈里的数字也必须是系统字体，否则「一个随包字体都不用」不成立。
      const bundled = {'SEGA', 'Josefin', 'MiSans', 'Official', 'MPLUS1p'};
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(bundled.contains(text.style?.fontFamily), isFalse,
            reason: 'unexpected bundled font on "$text"');
      }
    });
  });

  group('jacket cache', () {
    testWidgets('cache key ignores the mirror so all routes share an entry',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SongCardView(song: _seed, onTap: () {})),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      // 默认缓存键就是 URL，换镜像等于换一条记录；这里必须钉在图片文件名上。
      expect(image.cacheKey, _seed.artwork);
      expect(image.imageUrl, endsWith(_seed.artwork!));
      expect(image.imageUrl, isNot(_seed.artwork));

      // 卸载以取消镜像重试定时器，否则测试结束时会报 pending timer。
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
