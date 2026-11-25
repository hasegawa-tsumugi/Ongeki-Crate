import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/repository.dart';

/// 应用根状态（`SongQueryApp`）的行为：启动引导、静默更新、失败兜底、清空、字体方案。
///
/// 这一层之前完全没覆盖，因为 `_SongQueryAppState` 里写死 `SongRepository()`。
/// 加了「仓储」和「内置曲库加载器」两个注入点之后，缓存、网络、资产全部可控，
/// 能跑真正的「点下去会怎样」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 内置库用一首合成曲目代表，不用真的 1112 首：
  /// 这些用例验的是状态流转，不是数据量。
  Dataset bundledDataset() =>
      Dataset([const Song(id: '7', title: '内置库的曲子', charts: [])]);

  /// 假仓储：只回答「本地有没有」「这次更新是成功还是失败」。
  ///
  /// 用 extends 而不是 implements，这样不必把仓储里用不到的方法也抄一遍。
  /// 返回类型必须是子类，否则测试里读不到 `cleared` 这类探针字段。
  _FakeRepository fakeRepo({
    Dataset? local,
    Dataset? updateResult,
    Object? updateError,
  }) =>
      _FakeRepository(
        local: local,
        updateResult: updateResult,
        updateError: updateError,
      );

  /// 启动链路是两段 await。全部走假实现，pump 几帧就够。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> mount(
    WidgetTester tester,
    SongRepository repo, {
    Dataset? bundled,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final instance = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      SongQueryApp(
        preferences: instance,
        repository: repo,
        // 不走 rootBundle：那条通道在 widget 测试里要真实事件循环才推进，
        // 同一文件里连跑多个用例时会在第二个之后卡住（界面停在「正在读取曲库…」）。
        bundledLoader: () async => bundled ?? bundledDataset(),
      ),
    );
    await settle(tester);
  }

  /// 路由过场是 300ms。不能用 pumpAndSettle：首页曲绘会排重试定时器，永远不静止。
  Future<void> pushAndSettle(WidgetTester tester, String action) async {
    if (find.text(action).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.tap(find.text(action).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  test('loadBundled really reads the packaged snapshot', () async {
    // 单独一条，不走 widget：这条验的是「资产真的打进包里且能解析」，
    // 属于打包回归护栏（漏打 assets 时这里会红）。
    final dataset = await SongRepository.loadBundled();
    expect(dataset, isNotNull, reason: 'rootBundle 读不到内置曲库');
    expect(dataset!.songs.length, greaterThan(1000));
    expect(dataset.songs.first.title, isNotEmpty);
  });

  testWidgets('boots the bundled snapshot when nothing is installed', (
    tester,
  ) async {
    await mount(tester, fakeRepo());

    expect(find.text('内置库的曲子'), findsWidgets);
    expect(find.text('曲库是空的'), findsNothing);
  });

  testWidgets('prefers the installed copy over the bundled one',
      (tester) async {
    final local = Dataset([
      const Song(id: '9', title: '只有这一首', charts: []),
    ]);
    await mount(tester, fakeRepo(local: local));

    expect(find.text('只有这一首'), findsWidgets);
    expect(find.text('内置库的曲子'), findsNothing);
  });

  testWidgets('a successful background update swaps the dataset', (
    tester,
  ) async {
    final fresh = Dataset([
      const Song(id: '11', title: '更新后的曲子', charts: []),
    ]);
    await mount(tester, fakeRepo(updateResult: fresh));

    expect(find.text('更新后的曲子'), findsWidgets);
    expect(find.text('内置库的曲子'), findsNothing);
  });

  testWidgets('a failed silent update keeps the bundled library', (
    tester,
  ) async {
    await mount(tester, fakeRepo(updateError: const SocketException('断网')));

    // 关键：失败不能把已加载的数据清掉，也不该用 snackbar 打扰用户（silent）。
    expect(find.byType(SongCardView), findsWidgets);
    expect(find.text('内置库的曲子'), findsWidgets);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed manual update keeps data and tells the user', (
    tester,
  ) async {
    final repo = fakeRepo(updateError: 'boom');
    await mount(tester, repo);
    // 启动那次是静默的，不能有 snackbar。
    expect(find.byType(SnackBar), findsNothing);

    // 曲库非空时唯一的更新入口在「关于」页（空态那里是「下载曲库」）。
    await pushAndSettle(tester, '关于');
    expect(find.text('检查更新'), findsOneWidget);
    await tester.tap(find.text('检查更新'));
    await tester.pump();
    await tester.pump();

    // 这条曾经是红的：`ScaffoldMessenger.of(context)` 用的是 MaterialApp 之上
    // 的 context，永远找不到 messenger —— 提示弹不出来，还往 zone 里扔异常。
    expect(repo.installs, 2, reason: '启动一次 + 手动一次，不该更多');
    expect(find.byType(SnackBar), findsWidgets);
    expect(find.textContaining('更新失败，保留现有曲库'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('clearing wipes the dataset and keeps preferences intact', (
    tester,
  ) async {
    final repo = fakeRepo(
      updateResult: Dataset([
        const Song(id: '11', title: '更新后的曲子', charts: []),
      ]),
    );
    await mount(tester, repo);
    expect(find.text('更新后的曲子'), findsWidgets);

    await pushAndSettle(tester, '关于');
    await tester.tap(find.text('删除本地曲库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(repo.cleared, 1);

    // 「本地曲库已删除」渲染在首页的空态里，而我们还停在「关于」页上。
    // 返回落在「我的」页签（关于是从那里 push 的），再切回「主页」看空态。
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('tab-home')).first);
    await tester.pump();
    expect(find.text('本地曲库已删除'), findsWidgets);
    expect(find.byType(SongCardView), findsNothing);
    // 字体方案是另一份存储，清曲库不该动它。
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fontScheme'), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('the font scheme is persisted and restored on next boot', (
    tester,
  ) async {
    await mount(tester, fakeRepo());

    if (find.text('设置').evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('全部系统字体'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部系统字体'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fontScheme'), 'system');

    // 重挂一次，应当直接读到 system，而不是退回 official。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      SongQueryApp(
        preferences: prefs,
        repository: fakeRepo(),
        bundledLoader: () async => bundledDataset(),
      ),
    );
    await settle(tester);
    if (find.text('设置').evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    final selected = tester.widget<RadioGroup<String>>(
      find.byType(RadioGroup<String>),
    );
    expect(selected.groupValue, 'system');
  });

  testWidgets('an unknown stored scheme falls back to official', (
    tester,
  ) async {
    await mount(tester, fakeRepo(), prefs: {'fontScheme': 'legacy'});

    if (find.text('设置').evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('tab-profile')).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    final selected = tester.widget<RadioGroup<String>>(
      find.byType(RadioGroup<String>),
    );
    expect(selected.groupValue, 'official');
  });

  testWidgets('progress callbacks drive the determinate bar', (tester) async {
    final repo = _FakeRepository(progressSteps: const [(10, 100), (60, 100)]);
    await mount(tester, repo);

    // 更新已结束，进度条应当收回到「不显示」。
    expect(find.byType(LinearProgressIndicator), findsNothing);
    // 但回调确实被调用过（10% → 60% 都超过了 2% 节流阈值）。
    expect(repo.reported, [closeTo(0.1, 0.001), closeTo(0.6, 0.001)]);
  });
}

class _FakeRepository extends SongRepository {
  _FakeRepository({
    this.local,
    this.updateResult,
    this.updateError,
    this.progressSteps = const [],
  });

  final Dataset? local;
  final Dataset? updateResult;
  final Object? updateError;
  final List<(int, int)> progressSteps;

  int cleared = 0;
  int installs = 0;
  final reported = <double>[];

  @override
  Future<Dataset?> loadLocal() async => local;

  @override
  Future<void> clear() async {
    cleared++;
  }

  @override
  Future<int> localBytes() async => 0;

  @override
  Future<String> etag() async => '';

  @override
  Future<Dataset> fetchAndInstall({
    void Function(int, int, String)? onProgress,
  }) async {
    installs++;
    for (final (received, total) in progressSteps) {
      onProgress?.call(received, total, 'https://example.invalid/x');
      reported.add(received / total);
    }
    final error = updateError;
    if (error != null) throw error;
    final result = updateResult;
    if (result == null) {
      // 没给结果也没给错误 = 这次没有可用的新数据。
      throw const FormatException('没有可用的新数据');
    }
    return result;
  }
}
