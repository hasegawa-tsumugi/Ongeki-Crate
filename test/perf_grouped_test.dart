import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/domain.dart';

/// 分组排序的耗时诊断脚本（默认跳过，不进常规测试）。
///
///     SONGQUERY_BENCH=1 flutter test test/perf_grouped_test.dart
///
/// 这不是断言测试 —— 绝对耗时跟机器负载有关，写成断言就是给未来埋一个随机红。
/// 真正防回归的是 `grouped_sort_test.dart` 里那条源码级护栏（比较器里不许现算
/// 组标签）。这里只负责「改完想量一下」时有个可复现的口子。
///
/// 参考值（这台机器，1112 首，2026-11-24）：优化前「谱面等级 / 对手等级」
/// 18.78ms、「曲名 / 章节」18.06ms，而「分类 / 推荐」只要 5.64ms —— 三倍差距
/// 全来自比较器里重算 `kanaRow` / `topLevel`。预计算 `labels` 后四个组合齐平在
/// 5.4–6.4ms。
void main() {
  test('分组排序耗时', () {
    final ds = Dataset.fromJson(
        jsonDecode(File('assets/songs-2026.10.15.json').readAsStringSync()));
    final engine = SongEngine(ds.songs);
    const combos = <(TabGroup, TabSort)>[
      (TabGroup.genre, TabSort.recommended),
      (TabGroup.character, TabSort.title),
      (TabGroup.title, TabSort.chapter),
      (TabGroup.level, TabSort.enemyLevel),
    ];
    for (final (g, s) in combos) {
      engine.listGrouped(group: g, sort: s); // 预热，别把首次 JIT 算进去
      final sw = Stopwatch()..start();
      const n = 10;
      for (var i = 0; i < n; i++) {
        engine.listGrouped(group: g, sort: s);
      }
      sw.stop();
      // ignore: avoid_print
      print('BENCH ${g.name}/${s.name} avg='
          '${(sw.elapsedMicroseconds / n / 1000).toStringAsFixed(2)}ms');
    }
  }, skip: Platform.environment['SONGQUERY_BENCH'] != '1');
}
