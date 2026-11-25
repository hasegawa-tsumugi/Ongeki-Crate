// 一次性性能基准探针（不属于回归套件，跑完删除）。
//
// 目的：把「滚动卡顿」从观感变成可比的数字。同一份脚本在优化前后各跑一次，
// 只看相对变化 —— flutter test 是 debug + Skia，绝对值不代表真机，但
// UI 线程的 build/layout 成本比例与真机接近。
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/theme.dart';

void main() {
  late Dataset real;

  setUpAll(() async {
    final json = jsonDecode(
      await File('assets/songs-2026.10.15.json').readAsString(),
    );
    real = Dataset.fromJson(json);
  });

  Widget host(Dataset dataset) => MaterialApp(
        theme: buildTheme('official'),
        home: HomeScreen(
          dataset: dataset,
          status: '本地曲库已就绪',
          error: null,
          busy: false,
          progress: null,
          revision: 0,
          scheme: 'official',
          onUpdate: () async {},
          onScheme: (_) async {},
          onClear: () async {},
          loadLocalBytes: () async => 0,
        ),
      );

  /// 数当前挂载了多少个 SongCardView element（= 已构建入树的卡片）。
  int countCards(WidgetTester tester) {
    var n = 0;
    for (final e in tester.allElements) {
      if (e.widget is SongCardView) n++;
    }
    return n;
  }

  testWidgets('BENCH 滚动基准', (tester) async {
    await tester.pumpWidget(host(real));
    await tester.pump();

    final cards0 = countCards(tester);
    // ignore: avoid_print
    print('BENCH mounted_cards_initial=$cards0');

    // 滚动 30 帧，每帧 120px，记录总耗时与每帧耗时。
    final list = find.byType(ListView);
    final sw = Stopwatch()..start();
    final frames = <int>[];
    for (var i = 0; i < 30; i++) {
      final f = Stopwatch()..start();
      await tester.drag(list.first, const Offset(0, -120));
      await tester.pump();
      frames.add(f.elapsedMicroseconds);
    }
    sw.stop();
    final total = sw.elapsedMicroseconds;
    frames.sort();
    final median = frames[frames.length ~/ 2];
    final p90 = frames[(frames.length * 0.9).floor().clamp(0, 29)];
    // ignore: avoid_print
    print('BENCH scroll30_total_us=$total median_frame_us=$median '
        'p90_frame_us=$p90 max_frame_us=${frames.last}');
    // ignore: avoid_print
    print('BENCH mounted_cards_after_scroll=${countCards(tester)}');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('BENCH 单卡构建成本', (tester) async {
    final song = real.songs.first;
    late StateSetter setter;
    // MaterialApp / 主题只构建一次，循环里只重建卡片本身 —— 量的是
    // 「卡片 rebuild + layout」，不是「整棵树重建」。
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme('official'),
      home: Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          setter = s;
          return ListView(children: [
            SongCardView(
              key: const ValueKey('bench-card'),
              song: song,
              reason: null,
              onTap: () {},
            ),
          ]);
        }),
      ),
    ));
    await tester.pump();

    // 预热 3 次（image cache、字体等一次性成本）。
    for (var i = 0; i < 3; i++) {
      setter(() {});
      await tester.pump();
    }

    final samples = <int>[];
    for (var i = 0; i < 20; i++) {
      final sw = Stopwatch()..start();
      setter(() {});
      await tester.pump();
      samples.add(sw.elapsedMicroseconds);
    }
    samples.sort();
    // ignore: avoid_print
    print('BENCH single_card_rebuild median_us=${samples[samples.length ~/ 2]} '
        'p90_us=${samples[18]} max_us=${samples.last}');
  });
}
