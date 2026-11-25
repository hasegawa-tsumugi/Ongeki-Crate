import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/theme.dart';

/// 包边必须有完整四边。此前的路径没有 `close()`，左侧一条边会整段消失，
/// 而在真机上只表现为「卡片左边框没了」——布局测试全是绿的。
/// 所以这里直接取渲染像素断言，而不是断言源码字符串。
Future<ByteData> _raster(Size size, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return data!;
}

int _alpha(ByteData data, int width, int x, int y) =>
    data.getUint8((y * width + x) * 4 + 3);

/// 抗锯齿会让单点采样落在半覆盖像素上，取一小块的最大值才稳定。
int _maxAlpha(ByteData data, int width, int x0, int x1, int y0, int y1) {
  var best = 0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final a = _alpha(data, width, x, y);
      if (a > best) best = a;
    }
  }
  return best;
}

void main() {
  const size = Size(60, 40);
  const color = Color(0xFFFFFFFF);

  test('ChamferBorder paints all four edges', () async {
    final data = await _raster(size, (canvas) {
      const ChamferBorder(size: 10, side: BorderSide(color: color, width: 1))
          .paint(canvas, Offset.zero & size);
    });
    final w = size.width.toInt();
    final h = size.height.toInt();

    // 左、上、下三条边的中点；右侧走 x = w - 1。
    expect(_alpha(data, w, 0, h ~/ 2), greaterThan(200), reason: 'left edge');
    expect(_alpha(data, w, w ~/ 2, 0), greaterThan(200), reason: 'top edge');
    expect(_alpha(data, w, w ~/ 2, h - 1), greaterThan(200), reason: 'bottom edge');
    expect(_alpha(data, w, w - 1, h ~/ 2), greaterThan(200), reason: 'right edge');
    // 右上斜边：45° 的 1px 描边会被抗锯齿拆到两个像素，是半覆盖，
    // 所以门槛比直边低，但仍远高于「完全没画」的 0。
    expect(_maxAlpha(data, w, w - 11, w - 4, 3, 7), greaterThan(120),
        reason: 'diagonal');
    // 卡片内部不应被填充。
    expect(_alpha(data, w, w ~/ 2, h ~/ 2), equals(0), reason: 'interior');
  });

  test('ChamferOutlinePainter paints all four edges', () async {
    final data = await _raster(size, (canvas) {
      const ChamferOutlinePainter(10, color, 1).paint(canvas, size);
    });
    final w = size.width.toInt();
    final h = size.height.toInt();

    expect(_alpha(data, w, 0, h ~/ 2), greaterThan(200), reason: 'left edge');
    expect(_alpha(data, w, w ~/ 2, 0), greaterThan(200), reason: 'top edge');
    expect(_alpha(data, w, w ~/ 2, h - 1), greaterThan(200), reason: 'bottom edge');
    expect(_alpha(data, w, w - 1, h ~/ 2), greaterThan(200), reason: 'right edge');
    expect(_alpha(data, w, w ~/ 2, h ~/ 2), equals(0), reason: 'interior');
  });

  // 组件层：真实卡片是 ClipPath + CustomPaint 组合出来的，
  // 这里直接渲染 `Chamfer` 并看左侧那一列有没有描边色（#888888），
  // 卡片填充只有 #222222 —— 少了左边就是 34 而不是 136。
  testWidgets('Chamfer surface keeps its left border', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme('official', brightness: Brightness.dark),
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: const Chamfer(
            size: 10,
            padding: EdgeInsets.zero,
            child: SizedBox(width: 120, height: 70),
          ),
        ),
      ),
    ));
    await tester.pump();

    late ByteData data;
    var width = 0;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      width = image.width;
      data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    expect(width, 120);

    final leftRed = data.getUint8((35 * width) * 4);
    final innerRed = data.getUint8((35 * width + 60) * 4);
    expect(leftRed, greaterThan(90), reason: 'left border stroke colour');
    expect(innerRed, lessThan(60), reason: 'card fill stays dark');
    expect(leftRed, greaterThan(innerRed + 50), reason: 'border vs fill');
  });
}
