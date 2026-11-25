import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'domain.dart';

const jacketBases = <String>[
  'https://gcore.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/jacket/',
  'https://testingcf.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/jacket/',
  'https://otoge-db.net/ongeki/jacket/',
];
const dataBases = <String>[
  'https://fastly.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/data/music-ex.json',
  'https://cdn.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/data/music-ex.json',
  'https://gcore.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/data/music-ex.json',
  'https://raw.githubusercontent.com/hasegawa-tsumugi/otoge-db/main/ongeki/data/music-ex.json',
];

class SongRepository {
  SongRepository({
    http.Client? client,
    Future<Directory> Function()? documentsDir,
  })  : _client = client ?? http.Client(),
        _documentsDir = documentsDir ?? getApplicationDocumentsDirectory;

  final http.Client _client;

  /// 注入点：默认走 path_provider，测试里指向临时目录。
  final Future<Directory> Function() _documentsDir;

  Future<Directory> get _dir async {
    final d = Directory('${(await _documentsDir()).path}/dataset');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> get _file async => File('${(await _dir).path}/songs.json');

  /// 上一次成功安装时上游给的 ETag，用来判断「还用不用下」。
  Future<File> get _etagFile async =>
      File('${(await _dir).path}/songs.json.etag');

  /// 存的是两行：`产出这个 ETag 的线路` + `ETag`。
  ///
  /// **必须连线路一起存**。各家的 ETag 口径不一样，实测同一份文件
  /// jsDelivr 给弱 ETag `W/"194620-47007985bd6c1c6f"`（大小+时间戳），
  /// raw.githubusercontent 给强哈希 `"7359e9a1…"`。只存 ETag、固定拿第一条
  /// 线路去比的话，一旦某次是回退线路装成功的，存下来的值永远对不上，
  /// 之后每次冷启都白下一次 —— 正好把这个优化抵消掉。
  Future<(String url, String etag)> _storedProbe() async {
    try {
      final raw = await (await _etagFile).readAsString();
      final lines = raw.trim().split('\n');
      if (lines.length >= 2) {
        return (lines[0].trim(), lines.sublist(1).join().trim());
      }
      // 旧格式（只有 ETag）：不知道产自哪条线路，按「通常是第一条」上下注。
      // 猜错只会多下一次，代价可控。
      return (dataBases.first, lines.first.trim());
    } catch (_) {
      return ('', '');
    }
  }

  /// 清单协商的轻量替代。
  ///
  /// 启动时每次都会走一次更新，原先等于每次冷启都重下 1.6MB（还要解码、重编码、
  /// 落盘、再解码）。jsDelivr / raw.githubusercontent 都发 ETag，所以存下上次的
  /// ETag，用一次 HEAD 比一下：没变就省掉整包下载。HEAD 失败或上游不发 ETag
  /// 都当作「可能变了」，回落到正常下载 —— 宁可多下一次，不能漏更新。
  Future<bool> _upstreamUnchanged() async {
    final (url, stored) = await _storedProbe();
    if (url.isEmpty || stored.isEmpty) return false;
    try {
      final res = await _client
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return false;
      final remote = res.headers['etag'];
      return remote != null && remote == stored;
    } catch (_) {
      return false;
    }
  }

  /// 读本地曲库。两道关：**格式版本**与**条目数**。
  ///
  /// 版本关不是为了好看：旧版本装下的文件可能结构合法、条数也够，只是某些值算错了
  /// （2026-11-02 的定数 1.1 —— 条数、编码、结构全对，无从从文件本身分辨）。
  /// 而 ETag 协商在「上游没变」时会直接返回本地数据，**不拒绝这份坏文件就永远修不好**。
  Dataset _decodeStored(String contents) {
    final dataset = Dataset.fromJson(jsonDecode(contents));
    final schema = dataset.meta['schema'];
    if (schema != datasetSchemaVersion) {
      throw FormatException(
        '本地曲库格式版本不符（$schema → $datasetSchemaVersion），需要重新安装',
      );
    }
    if (dataset.songs.length < 500) {
      throw const FormatException('本地曲库条目不足，文件可能不完整');
    }
    return dataset;
  }

  Future<void> _recoverInterruptedInstall() async {
    // 这一步只是**清理半成品**，不是安装本身。清理失败不能让更新流程炸掉 ——
    // 真实故障（target 是非空目录时 `delete()` 删不掉、`rename()` 也抛）会让
    // 异常从这里逃逸出 fetchAndInstall 的开头，用户点「检查更新」直接崩。
    try {
      final target = await _file;
      final backup = File('${target.path}.bak');
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
        return;
      }
      // A valid target always wins; a leftover backup only means cleanup was
      // interrupted after a successful promotion.
      if (await target.exists() && await backup.exists()) {
        try {
          _decodeStored(await target.readAsString());
          await backup.delete();
        } catch (_) {
          await target.delete();
          await backup.rename(target.path);
        }
      }
    } catch (_) {
      // 清理半成品失败不外抛：留着现场让安装流程自己去覆盖或报错，
      // 都比把「检查更新」变成一个未捕获异常强。
    }
  }

  Future<Dataset?> loadLocal() async {
    try {
      await _recoverInterruptedInstall();
      final f = await _file;
      if (!await f.exists()) return null;
      return _decodeStored(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<int> localBytes() async {
    try {
      return await (await _file).length();
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    final f = await _file;
    for (final file in [
      f,
      File('${f.path}.bak'),
      File('${f.path}.tmp'),
      await _etagFile,
    ]) {
      if (await file.exists()) await file.delete();
    }
  }

  /// 把响应字节解码成 JSON。
  ///
  /// 截断 / 乱码属于**传输**问题（换条线路可能就好了），所以转成 [HttpException]
  /// 走重试分支。否则 `jsonDecode` 的 FormatException 会和「上游字段改名」混在一起，
  /// 让下面「格式错误不重试」的判断把可恢复的失败也一起判死。
  Object? _decodePayload(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw HttpException('响应不是完整 JSON：${e.message}');
    }
  }

  Future<Dataset> fetchAndInstall({
    void Function(int, int, String)? onProgress,
  }) async {
    await _recoverInterruptedInstall();
    // 上游没变就直接返回本地数据，一次 HEAD 换掉整包下载。
    if (await _upstreamUnchanged()) {
      final local = await loadLocal();
      if (local != null) return local;
    }
    Object? last;
    for (final url in dataBases) {
      try {
        final req = http.Request('GET', Uri.parse(url));
        final response =
            await _client.send(req).timeout(const Duration(seconds: 60));
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}');
        }
        final remoteEtag = response.headers['etag'] ?? '';
        final bytes = <int>[];
        final total = response.contentLength ?? 0;
        await for (final chunk in response.stream) {
          bytes.addAll(chunk);
          onProgress?.call(bytes.length, total, url);
        }
        final raw = _decodePayload(bytes);
        final ds = Dataset.fromUpstream(raw);
        if (ds.songs.length < 500) {
          throw const FormatException('数据条目不足，拒绝覆盖本地曲库');
        }
        final dir = await _dir;
        final tmp = File('${dir.path}/songs.json.tmp');
        await tmp.writeAsBytes(
          utf8.encode(jsonEncode(ds.toJson())),
          flush: true,
        );
        final check = Dataset.fromJson(jsonDecode(await tmp.readAsString()));
        if (check.songs.length != ds.songs.length) {
          throw const FormatException('本地暂存校验失败');
        }
        final target = await _file;
        final backup = File('${target.path}.bak');
        var movedOldFile = false;
        try {
          if (await backup.exists()) await backup.delete();
          if (await target.exists()) {
            await target.rename(backup.path);
            movedOldFile = true;
          }
          await tmp.rename(target.path);
          // Verify the promoted file once more before discarding the backup.
          _decodeStored(await target.readAsString());
          if (movedOldFile && await backup.exists()) await backup.delete();
          // 第一行记线路：下次 HEAD 必须打同一条，否则两家的 ETag 口径对不上。
          await (await _etagFile)
              .writeAsString('$url\n$remoteEtag', flush: true);
          return ds;
        } catch (_) {
          if (await target.exists()) await target.delete();
          if (movedOldFile && await backup.exists()) {
            await backup.rename(target.path);
          }
          rethrow;
        }
      } on FormatException catch (e) {
        // 格式问题（字段改名 / 条目不足 / 暂存校验失败）是**数据本身**坏了，
        // 换一条线路下的还是同一份文件。继续试剩下三条只会白下 4.8MB，
        // 而且末尾那句「所有曲库线路均失败」会把真实原因彻底埋掉。
        throw FormatException('上游数据不可用，已保留本地曲库：${e.message}');
      } catch (e) {
        last = e;
      } finally {
        final dir = await _dir;
        final tmp = File('${dir.path}/songs.json.tmp');
        if (await tmp.exists()) await tmp.delete();
      }
    }
    throw Exception('所有曲库线路均失败：$last');
  }

  Future<String> etag() async {
    try {
      final bytes = await (await _file).readAsBytes();
      return sha256.convert(bytes).toString();
    } catch (_) {
      return '';
    }
  }

  // 注意：不要在这里用普通 HTTP 预取曲绘来「预热缓存」。
  // cached_network_image 走自己的内存/磁盘缓存，HTTP 请求取到的字节进不去，
  // 只会白耗流量和连接；真正的预取应改用同一插件的 prefetch。

  static Future<Dataset?> loadBundled() async {
    try {
      return Dataset.fromJson(
        jsonDecode(await rootBundle.loadString('assets/songs-2026.10.15.json')),
      );
    } catch (_) {
      return null;
    }
  }
}
