// 把 Dart 侧 SongEngine 的 title 排序结果导出成 build/_dart_order.json，
// 供 tool/compare_collation.mjs 与 Node/ICU 真值逐对核对。
//
// 这不是断言型测试，是一条导出通道（Dart 的排序逻辑依赖 Flutter，跑不了纯 dart）。
// 校验日文排序是否退化：
//   flutter test test/collation_export_test.dart && node tool/compare_collation.mjs
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/domain.dart';

void main() {
  test('export dart title order', () async {
    final json = jsonDecode(
      await File('assets/songs-2026.10.15.json').readAsString(),
    );
    final data = Dataset.fromJson(json);
    final engine = SongEngine(data.songs);
    final titles =
        engine.list(sort: SortKey.title).map((s) => s.title).toList();
    await Directory('build').create(recursive: true);
    await File('build/_dart_order.json').writeAsString(jsonEncode(titles));
    expect(titles, isNotEmpty);
  });
}
