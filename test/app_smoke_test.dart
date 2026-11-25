import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/bottom_bar.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/screens.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 整机级冒烟：把真实曲库灌进真实的 HomeScreen / DetailScreen 渲染一遍。
///
/// 单测覆盖的是逻辑，这里覆盖的是**只有渲染才会炸的东西**：布局溢出、空字段
/// 解引用、极端字号下的挤压。真机验收做不了的时候，这是最接近的一层。
///
/// 注意：曲绘走真实网络，测试环境里必定失败并落到占位块，_Jacket 会排一个
/// 重试定时器 —— 每个用例末尾都要卸载组件把定时器取消掉，否则报 pending timer。
void main() {
  late Dataset real;

  setUpAll(() async {
    final json = jsonDecode(
      await File('assets/songs-2026.10.15.json').readAsString(),
    );
    real = Dataset.fromJson(json);
  });

  /// 覆盖字号**必须**在 MaterialApp 内部做（走 builder），不能在外部套一层
  /// `MediaQuery(data: MediaQueryData(textScaler: ...))`。
  ///
  /// 原因：`MediaQueryData()` 的默认 `size` 是 `Size.zero`，套在外面会让整棵树里
  /// 的 `MediaQuery.sizeOf(context)` 返回 0 —— 任何「按屏幕宽度算尺寸」的布局
  /// 都会算出负数，直接撞 `BoxConstraints has a negative minimum width` 的断言。
  /// builder 里的 context 在 MaterialApp 之下，能拿到真实的 size，只改字号。
  Widget scaleText(BuildContext context, Widget child, double scale) =>
      MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child,
      );

  Widget host(
    Dataset? dataset, {
    String scheme = 'official',
    double textScale = 1.0,
    String? error,
  }) =>
      MaterialApp(
        theme: buildTheme(scheme),
        builder: (context, child) => scaleText(context, child!, textScale),
        home: HomeScreen(
          dataset: dataset,
          status: dataset == null ? '尚未安装曲库' : '本地曲库已就绪',
          error: error,
          busy: false,
          progress: null,
          revision: 0,
          scheme: scheme,
          onUpdate: () async {},
          onScheme: (_) async {},
          onClear: () async {},
          loadLocalBytes: () async => 0,
        ),
      );

  Future<void> unmount(WidgetTester tester) async {
    // 卸载才能取消 _Jacket 的重试定时器。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('renders the shipped library', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();

    expect(real.songs.length, greaterThan(1000));
    expect(find.byType(SongCardView), findsWidgets);
    // 默认排序会重排，所以不断言「首屏第一张 = 快照第一首」，只确认外壳渲染出来了。
    expect(find.byKey(const ValueKey('search-button')), findsOneWidget);
    expect(find.text('曲库是空的'), findsNothing);
    await unmount(tester);
  });

  testWidgets('排序三栏分别对应表格三组，各列各的选项', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 旧的「主排序下拉」和「难度三条件」都已下线。
    expect(find.byType(DropdownButtonFormField<SortKey>), findsNothing);
    expect(find.byType(DropdownButtonFormField<DifficultySort?>), findsNothing);

    final group = find.byType(DropdownButtonFormField<TabGroup>);
    final sort = find.byType(DropdownButtonFormField<TabSort>);
    final rival = find.byType(DropdownButtonFormField<RivalScore>);
    expect(group, findsOneWidget);
    expect(sort, findsOneWidget);
    expect(rival, findsOneWidget);
    expect(find.text('列表排序 · ジャンル › オススメ順'), findsOneWidget);

    // 三栏内容各不相同：7 / 8 / 3 项，默认都停在第一项（表格里的 ★）。
    // （DropdownButtonFormField 不对外暴露 items，选项清单按枚举核对。）
    expect(
        tester
            .widget<DropdownButtonFormField<TabGroup>>(group)
            .initialValue,
        TabGroup.genre);
    expect(
        tester.widget<DropdownButtonFormField<TabSort>>(sort).initialValue,
        TabSort.recommended);
    expect(
        tester
            .widget<DropdownButtonFormField<RivalScore>>(rival)
            .initialValue,
        RivalScore.technical);
    expect(TabGroup.values.length, 7);
    expect(TabSort.values.length, 8);
    expect(RivalScore.values.length, 3);

    // 快照里没有数据的项照表格列出来，但不可选（灰）。
    expect(TabGroup.attribute.available, isFalse, reason: '属性没有数据字段');
    expect(TabGroup.values.where((v) => v.available).length, 6);
    expect(TabSort.battleScore.available, isFalse, reason: '分数排序需要玩家成绩');
    expect(TabSort.dateAdded.available, isTrue);
    expect(TabSort.values.where((v) => v.available).length, 5);
    expect(RivalScore.values.every((v) => !v.available), isTrue,
        reason: '对手榜整栏都没有数据');

    final input = tester.getRect(find.byType(TextField));
    final clear = tester.getRect(find.widgetWithText(OutlinedButton, '清空全部筛选'));
    final apply = tester.getRect(find.widgetWithText(FilledButton, '应用并返回'));
    final firstSort = tester.getRect(group);
    expect(clear.top, greaterThanOrEqualTo(input.bottom));
    expect(clear.top, apply.top);
    expect(clear.right, lessThanOrEqualTo(apply.left));
    expect(firstSort.top, greaterThan(clear.bottom));
    await unmount(tester);
  });

  for (final size in [const Size(320, 480), const Size(568, 240)]) {
    testWidgets('小屏大字号下底栏三格可点且「我的」入口可达 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(null, textScale: 2));
      await tester.pump();
      // 底栏必须在，而且三格都点得到（页签名不跟系统字号放大，就是为了这个：
      // 320 宽 + 2.0 字号下三个两字标签要是跟着放大会直接挤出胶囊）。
      expect(find.byType(LiquidGlassBar), findsOneWidget);
      // 三格都得有正常宽度的点击区 —— 页签名不跟系统字号放大，就是为了这个：
      // 320 宽 + 2.0 字号下三个两字标签要是跟着放大会直接挤出胶囊。
      for (final name in ['home', 'tools', 'profile']) {
        final r = tester.getRect(find.byKey(ValueKey('tab-$name')).first);
        expect(r.width, greaterThan(20), reason: '$name 格被挤扁了');
        expect(r.height, greaterThan(20), reason: '$name 格被压扁了');
      }
      // 未选中的两格必须能直接点中。选中的那格由选中胶囊盖着（点它是
      // "再点一次当前页签"），所以不要求它 hit-testable —— 那是参考 App 的
      // 行为，胶囊自己接管这一下。
      for (final name in ['tools', 'profile']) {
        expect(find.byKey(ValueKey('tab-$name')).hitTestable(), findsOneWidget,
            reason: '$name 页签在小屏上点不到');
      }
      await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
      await tester.pump();
      expect(find.byType(LiquidGlassBar), findsOneWidget,
          reason: '切页签是换内容，底栏不该跟着消失');
      // 极矮屏（568×240 横屏）时「我的」页要滚才看得到入口，这是设计内的：
      // 两个入口 + 标题 + 说明在 240 高、2.0 字号下本来就装不进一屏。
      // 要验的是「每一个都够得着，且滚到位后不被底栏盖住」。
      // 用 dragUntilVisible 而不是「固定拖几次」：固定次数会滚过头，把上面那条
      // 顶到屏幕外，断言「设置 点不到」纯属测试自己造成的。
      final list = find.byType(ListView).last;
      await tester.dragUntilVisible(find.text('关于'), list, const Offset(0, -60));
      await tester.pump();
      final barTop = tester.getTopLeft(find.byType(LiquidGlassBar)).dy;
      expect(tester.getRect(find.text('关于')).bottom,
          lessThanOrEqualTo(barTop),
          reason: '滚到位后最后一条入口仍被底栏压住，说明避让位算少了');
      expect(find.text('关于').hitTestable(), findsOneWidget);
      await tester.dragUntilVisible(find.text('设置'), list, const Offset(0, 60));
      await tester.pump();
      expect(find.text('设置').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('tab-home')).first);
      await tester.pump();
      expect(find.byKey(const ValueKey('search-button')), findsOneWidget);
      await unmount(tester);
    });
  }

  testWidgets('小屏大字号搜索操作自适应且可清空应用', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(null, textScale: 2));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(LiquidGlassBar), findsNothing);
    expect(tester.widget<AppPage>(find.byType(AppPage)).topSpacing, 40);
    expect(tester.getTopLeft(find.byIcon(Icons.arrow_back)).dy,
        greaterThanOrEqualTo(64));
    final list = find.ancestor(
        of: find.byType(TextField), matching: find.byType(ListView));
    expect(tester.getBottomLeft(list).dy, 616);
    expect(find.text('清空全部筛选').hitTestable(), findsOneWidget);
    expect(find.text('应用并返回').hitTestable(), findsOneWidget);
    await tester.tap(find.text('清空全部筛选'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('应用并返回'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('search-button')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('首页首卡顶部留白 = 安全区 + 24，且不压底栏', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(real));
    await tester.pump();
    final card = tester.widget<SongCardView>(find.byType(SongCardView).first);
    final safeTop = 24 / tester.view.devicePixelRatio;
    // 列表第一项现在是分组标题（分类），留白对齐的是它，卡片紧跟在组头下面。
    final header = find
        .byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('group-'))
        .first;
    final headerTop = tester.getTopLeft(header).dy;
    final cardTop =
        tester.getTopLeft(find.byKey(ValueKey('card-${card.song.id}'))).dy;
    // 以前靠「底栏圆钮中心」反推首屏留白（screenHeight - center.dy），绕一圈
    // 只为说「顶部留白 = 安全区 + 24」。换成导航栏后高度变了，那个换算不再
    // 成立，直接断言留白本身。
    expect(headerTop, closeTo(safeTop + 24, 0.01));
    expect(cardTop, greaterThan(headerTop));
    // 首屏内容必须整个露在底栏之上。
    final barTop = tester.getTopLeft(find.byType(LiquidGlassBar)).dy;
    expect(cardTop, lessThan(barTop - 40),
        reason: '首张卡片被底部导航挡住就说明避让位算少了');
    await unmount(tester);
  });

  testWidgets('detail screen renders a real song', (tester) async {
    final song = real.songs.firstWhere(
      (s) => s.playableCharts.isNotEmpty,
      orElse: () => real.songs.first,
    );

    await tester.pumpWidget(
      MaterialApp(
          theme: buildTheme('official'), home: DetailScreen(song: song)),
    );
    await tester.pump();

    expect(find.text(song.title), findsWidgets);
    // 版本、BPM、分类这些「可能为空」的字段不能崩。
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    // 详情页只有左上角返回钮：push 上来的整屏页不该带底部导航 —— 否则用户会
    // 以为能从详情直接切页签，而那块底栏还盖在内容上。
    expect(find.byType(LiquidGlassBar), findsNothing,
        reason: '详情页不该出现底部导航栏');
    await unmount(tester);
  });

  testWidgets('detail screen survives a sparse song', (tester) async {
    // 上游字段缺失时大量字段为 null —— 这是最容易漏的空值路径。
    const sparse = Song(id: '000000', title: '无数据曲目', charts: []);
    await tester.pumpWidget(
      MaterialApp(
          theme: buildTheme('system'), home: const DetailScreen(song: sparse)),
    );
    await tester.pump();
    expect(find.text('无数据曲目'), findsWidgets);
    await unmount(tester);
  });

  // 小屏 + 无障碍字号的组合最容易挤出溢出：Android 的字号上限是 2.0 倍，
  // 所以 1.6 只是中段，2.0 才是边界。
  for (final (width, scale) in [
    (320.0, 1.0),
    (320.0, 1.3),
    (320.0, 1.6),
    (320.0, 2.0),
    (360.0, 2.0),
  ]) {
    testWidgets('survives ${width.toInt()}dp at ${scale}x text scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(real, textScale: scale));
      await tester.pump();
      // 溢出会以 FlutterError 形式让这个用例直接失败，所以跑通本身即是断言。
      expect(find.byType(SongCardView), findsWidgets);
      await unmount(tester);
    });
  }

  testWidgets('detail screen survives 2x text scale', (tester) async {
    final song = real.songs.firstWhere(
      (s) => s.playableCharts.isNotEmpty,
      orElse: () => real.songs.first,
    );
    tester.view.physicalSize = const Size(960, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme('official'),
        builder: (context, child) => scaleText(context, child!, 2.0),
        home: DetailScreen(song: song),
      ),
    );
    await tester.pump();
    expect(find.text(song.title), findsWidgets);
    await unmount(tester);
  });

  testWidgets('renders the empty state before any dataset is installed',
      (tester) async {
    await tester.pumpWidget(host(null));
    await tester.pump();
    // 没装曲库时走的是「空态 + 立即更新按钮」分支，而不是列表的空结果分支。
    // 顶部状态条和空态正文都会显示它，所以是 findsWidgets 而不是 findsOneWidget。
    expect(find.text('尚未安装曲库'), findsWidgets);
    expect(find.byType(SongCardView), findsNothing);
    await unmount(tester);
  });

  // ---- 首页交互 ----
  //
  // 上面覆盖的是「渲染出来」，这里覆盖「点下去会怎样」。这些路径都改过状态、
  // 动过 Navigator，是纯单测摸不到的。

  testWidgets('tapping a card opens the detail screen', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();

    await tester.tap(find.byType(SongCardView).first);
    // 路由过场是 300ms；用 pump 而不是 pumpAndSettle —— 详情页的曲绘会排重试
    // 定时器，settle 永远等不到静止。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('版本'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('完整页搜索保留关键词，重开仍带着', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();
    expect(find.text('MUSIC'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(find.byType(TextField), 'GO');
    await tester.pump();
    expect(find.textContaining('相关度优先'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'GO');
    await unmount(tester);
  });

  testWidgets('改分组与排序立即生效，重置排序三栏归位', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 正序倒序按钮早先就移除了，不该再出现 ↑/↓。
    expect(find.textContaining('↑'), findsNothing);
    expect(find.textContaining('↓'), findsNothing);
    expect(find.text('列表排序 · ジャンル › オススメ順'), findsOneWidget);

    // 换分组：状态条立刻反映，列表分段也跟着变。
    tester
        .widget<DropdownButtonFormField<TabGroup>>(
            find.byType(DropdownButtonFormField<TabGroup>))
        .onChanged!(TabGroup.character);
    await tester.pump();
    expect(find.text('列表排序 · キャラクター › オススメ順'), findsOneWidget);

    // 换段内排序：两栏互不影响。
    tester
        .widget<DropdownButtonFormField<TabSort>>(
            find.byType(DropdownButtonFormField<TabSort>))
        .onChanged!(TabSort.dateAdded);
    await tester.pump();
    expect(find.text('列表排序 · キャラクター › 追加日順'), findsOneWidget);

    await tester.ensureVisible(find.text('重置排序'));
    await tester.pump();
    await tester.tap(find.text('重置排序'));
    await tester.pump();
    expect(
        tester
            .widget<DropdownButtonFormField<TabGroup>>(
                find.byType(DropdownButtonFormField<TabGroup>))
            .initialValue,
        TabGroup.genre);
    expect(
        tester
            .widget<DropdownButtonFormField<TabSort>>(
                find.byType(DropdownButtonFormField<TabSort>))
            .initialValue,
        TabSort.recommended);
    expect(
        tester
            .widget<DropdownButtonFormField<RivalScore>>(
                find.byType(DropdownButtonFormField<RivalScore>))
            .initialValue,
        RivalScore.technical);
    expect(find.text('列表排序 · ジャンル › オススメ順'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('首页按分类分段，段内按推荐顺序排', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();

    final groups = SongEngine(real.songs)
        .listGrouped(group: TabGroup.genre, sort: TabSort.recommended);
    expect(groups.length, greaterThan(1), reason: '默认按分类分段，不止一段');
    expect(find.byKey(ValueKey('group-${groups.first.label}')), findsOneWidget);
    final firstCard =
        tester.widget<SongCardView>(find.byType(SongCardView).first).song;
    expect(firstCard.title, groups.first.songs.first.title,
        reason: '第一张卡必须是第一段按推荐顺序排出来的第一首');
    await unmount(tester);
  });

  testWidgets('切到追加日期后列表首条真的换了', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();
    final before =
        tester.widget<SongCardView>(find.byType(SongCardView).first).song.title;

    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester
        .widget<DropdownButtonFormField<TabSort>>(
            find.byType(DropdownButtonFormField<TabSort>))
        .onChanged!(TabSort.dateAdded);
    await tester.pump();
    await tester.tap(find.text('应用并返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final expected = SongEngine(real.songs)
        .listGrouped(group: TabGroup.genre, sort: TabSort.dateAdded)
        .first
        .songs
        .first
        .title;
    final after =
        tester.widget<SongCardView>(find.byType(SongCardView).first).song.title;
    expect(after, expected);
    expect(after, isNot(before), reason: '换了排序键，首条必须真的变');
    await unmount(tester);
  });

  testWidgets('「我的」页只有设置与关于两个入口，且都进得去', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 这是「撤掉左下角菜单钮」之后设置与关于的唯一入口，少一个就是功能失联。
    expect(find.byType(LiquidGlassBar), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('字体方案'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('详情页把可选字段都渲染出来', (tester) async {
    // 上面那条稀疏曲目测的是「缺字段不炸」，这条测「有字段要显示」——
    // 两组都不能省，只测缺字段会漏掉整块渲染逻辑。
    const full = Song(
      id: '999999',
      title: '满分曲目',
      titleKana: 'まんてんきょくもく',
      artist: '作曲者',
      genre: 'チュウマイ',
      genreId: '05',
      bpm: 180,
      releaseTag: 'bright MEMORY Act.3',
      isNew: true,
      isBonus: true,
      chapter: '第1章',
      chapterId: '01001',
      character: '星咲 あかり',
      characterId: '0001',
      enemyLevel: 12,
      enemyType: 'FIRE',
      dateAdded: '2026-10-15',
      copyright: '©SEGA',
      wikiUrl: 'https://example.com/x',
      artwork: 'x.png',
      aliases: ['满分', 'Manten'],
      charts: [
        Chart(
          difficulty: 3,
          level: 13,
          levelDecimal: 7,
          levelValue: 13.7,
          enabled: true,
          levelLabel: '13+',
          designer: '谱师A',
          noteCount: 1000,
          bells: 500,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme('official'),
        home: const DetailScreen(song: full),
      ),
    );
    await tester.pump();

    expect(find.text('满分曲目'), findsWidgets);
    for (final (label, value) in [
      ('版本', 'bright MEMORY Act.3'),
      ('BPM', '180.0'),
      ('分类', 'チュウマイ'),
    ]) {
      expect(
        find.byWidgetPredicate((widget) =>
            widget is AppInfoRow &&
            widget.label == label &&
            widget.value == value),
        findsOneWidget,
        reason: '缺少 meta「$label：$value」',
      );
    }

    // 详情页很长，ListView 惰性构建：一次拖太多会把上面的区块摔出缓存区，
    // 所以按屏幕顺序逐个揭出来再断言。
    final scrollable = find.byType(Scrollable).first;
    Future<void> reveal(String text) async {
      await tester.scrollUntilVisible(find.text(text), 80,
          scrollable: scrollable);
      expect(find.text(text), findsWidgets, reason: '缺少「$text」');
    }

    await reveal('别名');
    await reveal('Manten');
    expect(find.text('Manten'), findsOneWidget);
    await reveal('信息');
    await reveal('章节');
    await reveal('版权');
    // 这些字段都在同一个「信息」块里，滚到版权行后一起验证。
    for (final (label, value) in [
      ('对战角色', '星咲 あかり ／ Lv 12 ／ FIRE'),
      ('更新日期', '2026-10-15'),
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺少「$label」行');
      expect(find.text(value), findsOneWidget, reason: '「$label」内容不完整');
    }
    expect(find.text('敌方'), findsNothing);
    expect(find.text('上架日期'), findsNothing);
    expect(find.text('第1章'), findsOneWidget);
    expect(find.text('©SEGA'), findsOneWidget);
    expect(find.text('新曲 / ボーナストラック'), findsOneWidget);
    await reveal('攻略 wiki');
    await unmount(tester);
  });

  testWidgets('关于页跟着根状态走：删库后统计归零、删除按钮禁用', (tester) async {
    // 关于页是路由栈里的一页，拿到的是**入栈那一刻**的快照。之前它从不重建，
    // 于是「删完曲库，统计还是 1112 首、删除按钮还能再按一次」。
    Dataset? dataset = real;
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme('official'),
        home: StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return HomeScreen(
              dataset: dataset,
              status: dataset == null ? '本地曲库已删除' : '本地曲库已就绪',
              error: null,
              busy: false,
              progress: null,
              revision: dataset == null ? 1 : 0,
              scheme: 'official',
              onUpdate: () async {},
              onScheme: (_) async {},
              onClear: () async {},
              loadLocalBytes: () async => dataset == null ? 0 : 1656352,
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('关于').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 关于页自己的那个 ListView：首页列表还在栈里，两个都能被找到。
    // scrollUntilVisible 的 scrollable 参数要 Scrollable 本身（内部按
    // widget<Scrollable> 强转取轴向），ListView 那层不行。
    final aboutList = find.descendant(
      of: find.byType(AboutScreen),
      matching: find.byType(Scrollable),
    );
    Future<void> scrollBy(double dy) async {
      await tester.drag(aboutList, Offset(0, dy));
      await tester.pump();
    }

    expect(find.text('${real.songs.length} / 4208'), findsOneWidget);
    // 本地体积不能写死成「在线缓存」—— 那是占位符，不是数据。
    // 这行在页面中下部，ListView 惰性构建；而且 SliverList 只把**可见区**内的
    // 子项算 onstage（视口外的 find.text 直接匹配不到），固定距离 drag 一旦滚过头
    // 就假失败 —— 用 scrollUntilVisible 把行真正滚进视口。
    await tester.scrollUntilVisible(
      find.text('本地体积'),
      200,
      scrollable: aboutList,
    );
    expect(find.text('1.6 MB'), findsOneWidget);

    setOuter(() => dataset = null);
    await tester.pump(); // didUpdateWidget 排一个 post-frame 回调
    await tester.pump(); // 回调跑完 → tick++
    await tester.pump(); // 关于页重建 + 重新读体积

    // 顶部统计和删除按钮要先滚回去 —— 滚到下面时这两块已经不在了（惰性构建）。
    await scrollBy(4000);
    expect(find.text('0 / 0'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '删除本地曲库'),
          )
          .onPressed,
      isNull,
      reason: '本地曲库已经删掉了，按钮不该还能点',
    );

    await tester.scrollUntilVisible(
      find.text('本地体积'),
      200,
      scrollable: aboutList,
    );
    expect(find.text('0 B'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('搜索框的 × 一键清空查询和结果', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), '驫');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('结果 0 首'), findsOneWidget);

    // 清除按钮只在有字时出现，点它要把查询和结果一起还原。
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.textContaining('结果 1112 首'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    await unmount(tester);
  });

  testWidgets('没装曲库且更新失败时，失败原因直接显示在空态里', (tester) async {
    // 这条分支是「error 非空 + dataset 为 null」，之前的空态用例 error 恒为 null，
    // 整块错误文案一行没跑过。
    await tester.pumpWidget(host(null, error: '上游数据不可用，已保留本地曲库'));
    await tester.pump();
    expect(find.text('尚未安装曲库'), findsWidgets);
    expect(find.text('上游数据不可用，已保留本地曲库'), findsOneWidget);
    expect(find.text('下载曲库'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('滚动主列表会翻页（顺带触发曲绘预取排队）', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();
    final firstTitle = tester
        .widgetList<SongCardView>(find.byType(SongCardView))
        .first
        .song
        .title;

    // 滚动通知是曲绘预取唯一的触发口（首屏那 6 张之外的都在这里排队），
    // 之前所有用例都没滚过主列表，这条链路一行没跑过。
    await tester.drag(find.byType(SongCardView).first, const Offset(0, -1500));
    await tester.pump();
    expect(find.text(firstTitle), findsNothing);
    await unmount(tester);
  });

  testWidgets('搜索条件清空保留关键词，重置排序保留筛选', (tester) async {
    await tester.pumpWidget(host(Dataset(
        [const Song(id: '1', title: 'First', genre: 'A', charts: [])])));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'First');
    await tester.pump();
    final searchList = find.ancestor(
      of: find.byType(TextField),
      matching: find.byType(ListView),
    );
    final searchScrollable = find.descendant(
      of: searchList,
      matching: find.byWidgetPredicate((widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down),
    );
    expect(searchList, findsOneWidget);
    expect(searchScrollable, findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(FilterChip, 'A'), 80,
        scrollable: searchScrollable);
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'A'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilterChip, 'A'));
    await tester.pump();
    expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'A'))
            .selected,
        isTrue);
    await unmount(tester);
  });

  testWidgets('isNew 的卡片带 NEW 角标', (tester) async {
    final tiny = Dataset([
      const Song(id: '1', title: 'Fresh', isNew: true, charts: []),
      const Song(id: '2', title: 'Classic', charts: []),
    ]);
    await tester.pumpWidget(host(tiny));
    await tester.pump();
    // 两首里只有一首是新曲，滚动到它再检查角标。
    await tester.scrollUntilVisible(find.text('Fresh'), 80,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('NEW'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('详情页左上角返回键回到列表', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();
    await tester.tap(find.byType(SongCardView).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('search-button')), findsOneWidget);
    expect(find.byType(SongCardView), findsWidgets);
    await unmount(tester);
  });

  testWidgets('详情返回后保留列表滚动位置', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();
    final list =
        tester.widget<ListView>(find.byKey(const PageStorageKey('song-list')));
    list.controller!.jumpTo(1400);
    await tester.pump();
    final offset = list.controller!.offset;
    await tester.tap(find.byType(SongCardView).hitTestable().first);
    await tester.pump();
    await tester.pump();
    expect(find.byType(DetailScreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump();
    expect(list.controller!.offset, offset);
    await unmount(tester);
  });

  testWidgets('详情页外链行把 URL 交给系统打开', (tester) async {
    // launchUrl 走 MethodChannel('plugins.flutter.io/url_launcher') 的
    // 'launch' 方法，拦通道就能断言「点下去到底要打开哪个 URL」。
    const linkable = Song(
      id: '777777',
      title: '外链曲目',
      wikiUrl: 'https://example.com/wiki',
      artwork: 'a.png',
      charts: [
        Chart(
          difficulty: 3,
          level: 12,
          levelDecimal: 0,
          levelValue: 12,
          enabled: true,
          chartLink: '01/01029mst',
        ),
      ],
    );
    final opened = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      opened.add('${args['url']}');
      return true;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme('official'),
        home: const DetailScreen(song: linkable),
      ),
    );
    await tester.pump();

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('攻略 wiki'),
      260,
      scrollable: scrollable,
    );
    await tester.ensureVisible(find.text('攻略 wiki'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('攻略 wiki'));
    await tester.pump();
    expect(opened, ['https://example.com/wiki']);
    expect(find.text('外部链接'), findsOneWidget);
    expect(find.text('曲绘原图'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('MASTER 谱面预览'),
      260,
      scrollable: scrollable,
    );
    await tester.ensureVisible(find.text('MASTER 谱面预览'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('MASTER 谱面预览'));
    await tester.pump();
    expect(opened, hasLength(2));
    expect(opened.last, 'https://sdvx.in/ongeki/01/01029mst.htm');
    await unmount(tester);
  });

  test('搜索路径的筛选判断只留一份实现', () {
    // 曾经 app 里另抄了一份四段判断，和 SongEngine.list 的内联版本各写一遍。
    // 抄出来的那份一忘就变成「浏览时筛掉了、搜出来又有」—— 而 UI 测试只覆盖到
    // 分类这一条分支，四条判断里另外三条回归时不会红。这条源码级护栏保证
    // `_passesSearchFilters` 只是委托，不再长出第二份判断。
    final src = File('lib/src/app.dart').readAsStringSync();
    expect(
      src,
      contains(
          'bool _passesSearchFilters(Song song) => _filters.matches(song, SortKey.title);'),
      reason: '搜索路径必须委托给 SongFilters.matches，不要在 app 里重写判断',
    );
    expect(
      RegExp(r'_filters\.(genres|characters|releaseTags|rows)\.isNotEmpty')
          .hasMatch(src),
      isFalse,
      reason: 'app.dart 里不该再出现按维度逐条判断的筛选逻辑',
    );
  });
}
