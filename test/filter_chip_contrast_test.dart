import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/screens.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 浅色模式下筛选面板的选项曾经整块「消失」：`ChipThemeData.labelStyle` 里
/// 塞的是 `WidgetStateTextStyle`，Material 只读它的 `.color`（为 null）不会调
/// `resolve()`，标签最终落在浅色文字上，白底白字。
/// 这里直接数标签矩形内的像素 —— 只看颜色常量抓不到这类问题。
void main() {
  const values = ['POPS', 'niconico'];

  Future<ByteData> renderSheet(WidgetTester tester, {required bool dark}) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme('official',
          brightness: dark ? Brightness.dark : Brightness.light),
      home: RepaintBoundary(
        key: boundary,
        child: const Scaffold(
          body: FilterSheet(
            initial: SongFilters(),
            genres: values,
            characters: ['藤沢 柚子'],
            releases: ['オンゲキ'],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    late ByteData data;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    return data;
  }

  /// 标签矩形内文字色的像素数量：深色文字取暗、浅色文字取亮。
  int textPixels(ByteData data, int width, Rect rect, {required bool darkInk}) {
    var count = 0;
    for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
      for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
        final i = (y * width + x) * 4;
        final r = data.getUint8(i);
        final g = data.getUint8(i + 1);
        final b = data.getUint8(i + 2);
        final lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
        if (darkInk ? lum < 100 : lum > 190) count++;
      }
    }
    return count;
  }

  testWidgets('浅色筛选面板：每个选项的文字都与底色有对比', (tester) async {
    final data = await renderSheet(tester, dark: false);
    const width = 420;

    final chips = find.byType(FilterChip);
    expect(chips, findsNWidgets(4));

    for (final element in chips.evaluate()) {
      final chip = element.widget as FilterChip;
      final label = (chip.label as Text).data!;
      final rect = tester.getRect(find.byWidget(chip)).deflate(1);
      final darkInk = !chip.selected;
      expect(textPixels(data, width, rect, darkInk: darkInk), greaterThan(20),
          reason: '浅色下「$label」的文字像素几乎不存在（选=${chip.selected}）');
    }
  });

  testWidgets('深色筛选面板：每个选项的文字都与底色有对比', (tester) async {
    final data = await renderSheet(tester, dark: true);
    const width = 420;

    for (final element in find.byType(FilterChip).evaluate()) {
      final chip = element.widget as FilterChip;
      final label = (chip.label as Text).data!;
      final rect = tester.getRect(find.byWidget(chip)).deflate(1);
      expect(textPixels(data, width, rect, darkInk: false), greaterThan(20),
          reason: '深色下「$label」的文字像素几乎不存在（选=${chip.selected}）');
    }
  });
}
