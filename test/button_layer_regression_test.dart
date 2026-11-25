import 'package:fluid_glass/fluid_glass.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/bottom_bar.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/repository.dart';
import 'package:songquery_flutter/src/screens.dart';
import 'package:songquery_flutter/src/theme.dart';

class _Repo extends SongRepository {
  @override
  Future<Dataset?> loadLocal() async => Dataset([]);
  @override
  Future<Dataset> fetchAndInstall(
          {void Function(int, int, String)? onProgress}) async =>
      Dataset([]);
  @override
  Future<int> localBytes() async => 0;
}

void main() {
  for (final mode in ['light', 'dark']) {
    testWidgets('$mode 页面往返、按钮状态与主题切换', (tester) async {
      SharedPreferences.setMockInitialValues({'themeMode': mode});
      await tester.pumpWidget(SongQueryApp(
          preferences: await SharedPreferences.getInstance(),
          repository: _Repo()));
      await tester.pumpAndSettle();
      void colors() {
        final context = tester.element(find.byType(Scaffold).last);
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        expect(theme.outlinedButtonTheme.style!.backgroundColor!.resolve({}),
            dark ? const Color(0xDD222222) : Colors.white);
        expect(theme.dialogTheme.backgroundColor,
            dark ? Colors.black : Colors.white);
        expect(theme.bottomSheetTheme.backgroundColor,
            dark ? Colors.black : Colors.white);
        final style = theme.filledButtonTheme.style!;
        expect(style.backgroundColor!.resolve({WidgetState.disabled}),
            dark ? const Color(0xFF3B3B3B) : const Color(0xFFE5E5E5));
        expect(style.foregroundColor!.resolve({}), Colors.white);
        // chip 的普通态文字必须是确定的颜色：早先塞的是 WidgetStateTextStyle，
        // Material 不会对它调 resolve()，浅色下等于「没有颜色」→ 白底白字。
        final chipLabel = theme.chipTheme.labelStyle!;
        expect(chipLabel, isNot(isA<WidgetStateTextStyle>()));
        expect(chipLabel.color, context.cardInk);
        expect(theme.chipTheme.secondaryLabelStyle!.color, Colors.white);
        for (final icon
            in tester.widgetList<Icon>(find.byIcon(Icons.arrow_back))) {
          expect(icon.color, anyOf(isNull, context.cardInk));
        }
      }

      colors();
      expect(find.byType(LiquidGlassBar), findsOneWidget);
      // 切「我的」：底栏留在原地，内容区换成占位页。
      // 页签在树里有两份（可见行 + 被选中胶囊放大的 accent 副本），取可见那份。
      await tester.tap(find.text('我的').first);
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassBar), findsOneWidget);
      // 页内说明文字已删（2026-11-24），改成断言占位页本身到位。
      expect(find.byType(ProfilePlaceholderScreen), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      colors();
      // 设置是从「我的」push 上去的整屏页，底栏不该跟着过去。
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassBar), findsNothing);
      colors();
      await tester.tap(find.text(mode == 'light' ? '深色' : '浅色'));
      await tester.pumpAndSettle();
      colors();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassBar), findsOneWidget,
          reason: '从设置返回应落在「我的」页签，底栏必须还在');
      // 底栏得真是玻璃：每件玻璃都是一个 DrawBackdrop（内部走
      // BackdropFilterLayer 把底下的内容滤镜进图层），不是纯色块。
      // 三件：胶囊面板、选中胶囊、右侧搜索钮。多一件就是重复叠了模糊。
      expect(
          find.descendant(
              of: find.byType(LiquidGlassBar),
              matching: find.byType(DrawBackdrop)),
          findsNWidgets(3));
      final context = tester.element(find.byType(HomeScreen));
      expect(context.controlSurface.toARGB32(),
          context.isDark ? 0xDD222222 : 0xFFFFFFFF);
      await tester.tap(find.byKey(const ValueKey('search-button')));
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassBar), findsNothing);
      expect(find.text('清空全部筛选'), findsOneWidget);
      colors();
      // 三栏对应表格三组；用第一栏（分组）验证弹出菜单盖在按钮之上。
      await tester.tap(find.byType(DropdownButtonFormField<TabGroup>).first);
      await tester.pumpAndSettle();
      expect(find.text('应用并返回').hitTestable(), findsNothing);
      await tester.tap(find.text('キャラクター').last);
      await tester.pumpAndSettle();
      expect(find.text('列表排序 · キャラクター › オススメ順'), findsOneWidget);
      await tester.tap(find.text('应用并返回'));
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$mode 关于删除确认取消及许可页隔离', (tester) async {
      var clears = 0;
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme('official',
              brightness: mode == 'dark' ? Brightness.dark : Brightness.light),
          home: AboutScreen(
              dataset: Dataset([]),
              status: '就绪',
              error: null,
              busy: false,
              onUpdate: () async {},
              onClear: () async {
                clears++;
              },
              loadBytes: () async => 0,
              loadLicense: () async => '测试许可')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除本地曲库'));
      await tester.pumpAndSettle();
      expect(find.text('删除本地曲库？'), findsOneWidget);
      expect(find.byType(LiquidGlassBar), findsNothing);
      expect(find.text('检查更新').hitTestable(), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(clears, 0);
      await tester.scrollUntilVisible(find.text('查看全文许可'), 300);
      await tester.tap(find.text('查看全文许可'));
      await tester.pumpAndSettle();
      expect(find.text('测试许可'), findsOneWidget);
      expect(find.byType(LiquidGlassBar), findsNothing);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('测试许可'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$mode dialog 与 sheet 阻断底层点击并可关闭', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme('official',
              brightness: mode == 'dark' ? Brightness.dark : Brightness.light),
          home: Builder(
              builder: (context) => Scaffold(
                      body: Column(children: [
                    TextButton(
                        onPressed: () => taps++, child: const Text('底层')),
                    TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (c) => AlertDialog(
                                    title: const Text('弹窗'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(c),
                                          child: const Text('关闭'))
                                    ])),
                        child: const Text('打开弹窗')),
                    TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            builder: (c) => SizedBox(
                                height: 200,
                                child: TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('关闭抽屉')))),
                        child: const Text('打开抽屉')),
                  ])))));
      final point = tester.getCenter(find.text('底层'));
      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('底层').hitTestable(), findsNothing);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开抽屉'));
      await tester.pumpAndSettle();
      expect(find.text('底层').hitTestable(), findsNothing);
      await tester.tap(find.text('关闭抽屉'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('底层'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
