import 'dart:async';

/// 限并发 + 会重试的曲绘预取队列。
///
/// **并发上限是这里唯一重要的性质**。曲绘 TTFB 在一秒以上，看起来「多开几个
/// 并发更快」，但真实事故是：几十个并发打同一个 CDN，触发限流后连眼前这几张
/// 都取不到 —— 预取这个纯优化反而把可见内容挤没了。所以上限钉死在 2，
/// 并且用测试守住（`test/prefetch_test.dart`）。
///
/// 这一层不认识 Flutter，也不碰缓存实现：`load` 由调用方注入，测试里换成
/// 记录并发的假 loader 就能验。
class PrefetchQueue {
  PrefetchQueue({
    required this.load,
    this.maxConcurrent = 2,
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 1500),
  });

  /// 真正去取一件曲绘。抛错即视为一次失败，按 [maxAttempts] 重试。
  final Future<void> Function(String artwork) load;

  /// 同时在飞的请求数上限。
  final int maxConcurrent;

  /// 总尝试次数（含第一次）。1 = 不重试。
  final int maxAttempts;

  /// 两次尝试之间的间隔。`Duration.zero` = 不等待（测试用）。
  final Duration retryDelay;

  final List<String> _queue = [];
  final Set<String> _seen = {};
  int _active = 0;
  bool _disposed = false;

  /// 当前在飞的请求数。
  int get active => _active;

  /// 还没开始的数量。
  int get pending => _queue.length;

  /// 排过队的条目（含成功与失败的），用于去重。
  ///
  /// **只读快照，O(n) 拷贝** —— 别在 build/滚动回调里调它。日常判重请用
  /// [contains]，否则滚过一千首之后每次 build 都要复制一千条字符串引用。
  Set<String> get seen => Set.unmodifiable(_seen);

  /// 是否已经排过队。O(1)，供高频路径（滚动回调、build）使用。
  bool contains(String? artwork) =>
      artwork != null && artwork.isNotEmpty && _seen.contains(artwork);

  /// 排队预取一批。空串与已经排过的跳过。
  void prefetch(Iterable<String?> artworks) {
    if (_disposed) return;
    var added = false;
    for (final artwork in artworks) {
      if (artwork == null || artwork.isEmpty) continue;
      if (!_seen.add(artwork)) continue;
      _queue.add(artwork);
      added = true;
    }
    if (added) _pump();
  }

  void _pump() {
    while (!_disposed && _active < maxConcurrent && _queue.isNotEmpty) {
      final artwork = _queue.removeAt(0);
      _active++;
      unawaited(
        _run(artwork).whenComplete(() {
          _active--;
          _pump();
        }),
      );
    }
  }

  Future<void> _run(String artwork) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_disposed) return;
      try {
        await load(artwork);
        return;
      } catch (_) {
        // 预取是纯优化：失败就放弃，绝不往外抛 —— 一次网络抖动不该变成红屏。
        if (attempt < maxAttempts && retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }
  }

  /// 停止接收新任务并清空队列。在飞的请求会自然结束。
  void dispose() {
    _disposed = true;
    _queue.clear();
  }
}
