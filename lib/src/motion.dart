import 'package:flutter/widgets.dart';

/// 动效令牌。数值和 `tool/webapp/index.template.html` 那套 CSS 是同一份手感：
/// 网页端的按压 `.12s`、换色 `.12s`、展开，这里必须给同一组数字。两端各写一
/// 套，最后一定是「网页上轻快、装到手机上拖沓」，所以只留一处定义。
///
/// 曲线只用 ease-out（起步快、收尾稳，用户盯着看的正是开头那一下）。
/// **不要用 ease-in**——它把开头压慢，恰好卡在用户等结果的那一瞬间。
abstract final class Motion {
  /// 强 ease-out，等同 HTML 的 `cubic-bezier(.2,.8,.25,1)`。
  /// 内置的 `Curves.easeOut` 太弱，收尾拖泥带水，压不住重内容。
  static const easeOut = Cubic(.2, .8, .25, 1);

  /// 按压反馈。100–160ms 是手感区间，取中段 120ms。
  static const press = Duration(milliseconds: 120);

  /// 选中态换色：比按压稍慢一档，让「状态变了」被看见。
  static const state = Duration(milliseconds: 140);

  /// 展开/收起（字母与版本行条）。再快就看不出是展开，再慢就显得卡。
  static const expand = Duration(milliseconds: 180);

  /// 系统开了「移除动画」就把时长压到 0：状态照变，只是不再有运动。
  ///
  /// 注意这里是「变瞬变」而不是「不做动画」——`AnimatedScale` 拿到
  /// [Duration.zero] 会直接跳到终值，正是无障碍设置要的效果。
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// 按下去缩一点、松手弹回。
///
/// 只观察指针，不抢手势：卡片和按钮本来就有 `InkWell` / `InkResponse` 负责
/// 点击与水波纹，这里再挂一层 `GestureDetector` 会和水波纹抢手势竞技场。
/// `Listener` 收的是原始指针事件，不参与竞技场，两者可以并存。
///
/// 位移超过 8dp 就松开——手指一滑说明用户要滚列表，不能让整屏卡片跟着缩。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.scale = .94,
    this.enabled = true,
  });

  final Widget child;

  /// 按下时的比例。圆形按钮 .93–.94，整行卡片要更含蓄（.985 上下）。
  final double scale;

  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  static const _slop = 8.0;

  bool _down = false;
  Offset? _origin;

  void _start(PointerDownEvent event) {
    if (!widget.enabled) return;
    _origin = event.position;
    setState(() => _down = true);
  }

  void _move(PointerMoveEvent event) {
    final origin = _origin;
    if (!_down || origin == null) return;
    if ((event.position - origin).distance > _slop) _release();
  }

  void _release([PointerEvent? _]) {
    _origin = null;
    if (_down) setState(() => _down = false);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _start,
        onPointerMove: _move,
        onPointerUp: _release,
        onPointerCancel: _release,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Motion.of(context, Motion.press),
          curve: Motion.easeOut,
          child: widget.child,
        ),
      );
}
