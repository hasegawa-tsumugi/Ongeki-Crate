import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/domain.dart';

/// 双端对拍的第一步：把 App 侧「分组 + 段内排序」的**全量**结果导出成 JSON。
///
/// 为什么要有这一步：网页端 `index.template.html` 里另写了一份 `filtered()`，
/// 它和 `SongEngine.listGrouped` 是同一套规则的两个实现。以前只靠人工翻两页
/// 比对，样本太小 —— 曲名兜底那次就是靠这个抓到的（App 用标题原文、网页用读音，
/// 只在特定几个曲名上分道扬镳）。现在改成全量对拍：
///
///   1. `flutter test test/parity_export_test.dart`  → build/_parity_app.json
///   2. `node tool/check_parity.mjs`                 → 逐首比对，打印差异
///
/// 只导出 `available` 的分组 / 排序：灰项在两端都退回默认，导出来只是重复。
void main() {
  test('导出分组排序全量结果供网页端对拍', () {
    final data = Dataset.fromJson(
        jsonDecode(File('assets/songs-2026.10.15.json').readAsStringSync()));
    final engine = SongEngine(data.songs);

    final groups = TabGroup.values.where((g) => g.available).toList();
    final sorts = TabSort.values.where((s) => s.available).toList();

    final cases = <String, Object?>{};
    for (final g in groups) {
      for (final s in sorts) {
        final grouped = engine.listGrouped(group: g, sort: s);
        cases['${g.name}/${s.name}'] = {
          'groups': [
            for (final grp in grouped) [grp.label, grp.songs.length],
          ],
          'ids': [
            for (final grp in grouped)
              for (final song in grp.songs) song.id,
          ],
        };
      }
    }

    final file = File('build/_parity_app.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode({
      'source': 'assets/songs-2026.10.15.json',
      'total': data.songs.length,
      'cases': cases,
    }));

    // 自检：导出本身不能是空的，否则第 2 步会「0 差异」地骗人。
    expect(cases, hasLength(groups.length * sorts.length));
    expect(data.songs.length, greaterThan(1000));
    for (final entry in cases.entries) {
      final ids = (entry.value as Map)['ids'] as List;
      expect(ids, hasLength(data.songs.length), reason: '${entry.key} 曲目数不对');
    }
  });
}
