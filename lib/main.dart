import 'dart:async';

import 'package:fluid_glass/fluid_glass.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 玻璃的 fragment program 与首屏数据并行加载，且**不 await**：
  // 它只影响底栏观感，不该让启动多等一次 IO。加载完的元素自己会重画；
  // 后端不支持 shader 时一直走「模糊 + 表面色」的回退外观。
  unawaited(FluidGlass.ensureInitialized());
  final preferences = await SharedPreferences.getInstance();
  runApp(SongQueryApp(preferences: preferences));
}
