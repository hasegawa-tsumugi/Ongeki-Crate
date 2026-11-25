import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/theme.dart';

void main() {
  const phase =
      String.fromEnvironment('BACKGROUND_PHASE', defaultValue: 'after');
  late Dataset data;
  final results = <Map<String, Object?>>[];
  setUpAll(() async {
    data = Dataset.fromJson(
        jsonDecode(await File('assets/songs-2026.10.15.json').readAsString()));
    for (final entry in {
      'MaterialIcons': [
        'D:/FlutterSDK/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      ],
      'Official': ['assets/fonts/JosefinSans-Bold.ttf'],
      'Josefin': ['assets/fonts/JosefinSans-Bold.ttf'],
      'MPLUS1p': [
        'assets/fonts/MPLUS1p-Medium.ttf',
        'assets/fonts/MPLUS1p-Bold.ttf'
      ],
      'MiSans': ['assets/fonts/MiSans-Medium.ttf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(
            Future.value(ByteData.sublistView(await File(path).readAsBytes())));
      }
      await loader.load();
    }
  });
  tearDownAll(() {
    File('build/background-$phase-checks.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  });
  for (final size in [
    const Size(320, 844),
    const Size(390, 844),
    const Size(400, 869),
    const Size(390, 667),
    const Size(844, 390)
  ]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('真实搜索背景 $phase $size 字号$scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                (_) async => Directory.systemTemp.path);
        final boundary = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme('official'),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: boundary, child: child)),
          home: HomeScreen(
              dataset: data,
              status: '本地曲库已就绪',
              error: null,
              busy: false,
              progress: null,
              revision: 0,
              scheme: 'official',
              onUpdate: () async {},
              onScheme: (_) async {},
              onClear: () async {},
              loadLocalBytes: () async => 0),
        ));
        await tester.runAsync(() async {
          await precacheImage(const AssetImage('assets/tex/bg_mesh.webp'),
              boundary.currentContext!);
          await precacheImage(const AssetImage('assets/tex/bg_circuit.webp'),
              boundary.currentContext!);
        });
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('search-button')));
        await tester.pump();
        await tester.pump();
        expect(find.text('搜索与筛选'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final backdrop = find.byType(MusicBackdrop).last;
        expect(
            find.ancestor(of: backdrop, matching: find.byType(IgnorePointer)),
            findsWidgets);
        final bands =
            find.descendant(of: backdrop, matching: find.byType(Transform));
        expect(bands, findsNWidgets(3));
        List<Offset> corners() => [
              for (final element in bands.evaluate()) ...[
                (element.renderObject! as RenderTransform)
                    .child!
                    .localToGlobal(Offset.zero),
                (element.renderObject! as RenderTransform).child!.localToGlobal(
                    Offset(
                        (element.renderObject! as RenderTransform)
                            .child!
                            .size
                            .width,
                        0)),
                (element.renderObject! as RenderTransform).child!.localToGlobal(
                    Offset(
                        0,
                        (element.renderObject! as RenderTransform)
                            .child!
                            .size
                            .height)),
                (element.renderObject! as RenderTransform).child!.localToGlobal(
                    Offset(
                        (element.renderObject! as RenderTransform)
                            .child!
                            .size
                            .width,
                        (element.renderObject! as RenderTransform)
                            .child!
                            .size
                            .height)),
              ]
            ];
        final beforeScroll = corners();
        final bandData = <Map<String, Object?>>[];
        for (var i = 0; i < 3; i++) {
          final transform = bands.at(i).evaluate().single.widget as Transform;
          final box = bands.at(i).evaluate().single.renderObject! as RenderBox;
          final center = box.localToGlobal(box.size.center(Offset.zero));
          final thickness = [10.0, 30.0, 10.0][i];
          expect(box.size.height, thickness);
          expect(center.dx, closeTo(size.width * .23, .001));
          expect(
              center.dy,
              closeTo(
                  size.height * .64 + [0, 20, 60][i] + thickness / 2, .001));
          expect(transform.transform.entry(0, 0),
              closeTo(.9396926207859084, .000001));
          final points = beforeScroll.sublist(i * 4, i * 4 + 4);
          final endsOutside = points[0].dx < 0 &&
              points[2].dx < 0 &&
              points[1].dx > size.width &&
              points[3].dx > size.width;
          if (phase == 'after') expect(endsOutside, isTrue);
          bandData.add({
            'center': [center.dx, center.dy],
            'width': box.size.width,
            'height': thickness,
            'endsOutside': endsOutside,
            'corners': [
              for (final p in points) [p.dx, p.dy]
            ]
          });
        }
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
              'build/background-screenshots/search-${size.width.toInt()}x${size.height.toInt()}-${scale.toStringAsFixed(1)}-$phase.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.drag(find.byType(ListView).last, const Offset(0, -250));
        await tester.pump();
        expect(corners(), beforeScroll);
        expect(tester.takeException(), isNull);
        results.add({
          'viewport': [size.width, size.height],
          'scale': scale,
          'bands': bandData,
          'fixedAfterScroll': true
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      });
    }
  }
}
