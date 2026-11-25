import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/version.dart';

/// 版本标识的唯一真值在 `pubspec.yaml`，`lib/src/version.dart` 是给界面读的副本。
/// 这份测试就是那条「别忘同步」的护栏：出包前改了 pubspec 却忘了改常量，
/// 关于页会显示旧版本，等于又回到「分不清装的是哪一版」。
void main() {
  test('version.dart 与 pubspec.yaml 的版本必须一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 里找不到 version 行');

    final declared = match!.group(1)!;
    expect(
      appVersionLabel,
      declared,
      reason: 'lib/src/version.dart 拼出的标签（$appVersionLabel）'
          '与 pubspec.yaml（$declared）不一致，改了版本号要两处一起改',
    );
  });

  test('版本号不是初始占位值', () {
    // 0.0.1+1 是项目初始值。回到它说明有人回滚了 pubspec，
    // 或者新包忘了 bump —— 两种都会让 Android 端无法区分新旧。
    expect(appVersionLabel, isNot('0.0.1+1'));
  });

  test('不再有 build 号（用户要求彻底去掉）', () {
    // 2026-11-24 用户指示：「build 不要了，以后也不要出现」。
    // pubspec 里带 `+N` 就又回来了，这里直接拦住。
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
    final declared = match!.group(1)!;
    expect(declared, isNot(contains('+')),
        reason: 'pubspec 的 version 不该再有 +N（build 号），只留版本名');
  });

  test('默认是 beta 版：标签形如 x.y.z-betaN', () {
    // 只有用户明确说「出正式版」时才去掉 -beta。默认出包必须带 beta 序号，
    // 否则一个测试包会被当成正式版发出去。
    if (appBeta > 0) {
      expect(appVersionLabel, matches(RegExp(r'^\d+\.\d+\.\d+-beta\d+$')));
    } else {
      // 正式版：不能带任何后缀。
      expect(appVersionLabel, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    }
  });

  test('beta 序号非负', () {
    expect(appBeta, greaterThanOrEqualTo(0));
  });
}
