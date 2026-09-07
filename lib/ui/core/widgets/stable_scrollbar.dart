import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 变高懒加载列表的滚动条：一次握把手势使用固定倍率的增量映射。
/// 保留 RawScrollbar 的绘制、命中、轨道点击与淡出行为，不依赖业务状态。
class StableScrollbar extends RawScrollbar {
  const StableScrollbar({
    super.key,
    required ScrollController super.controller,
    required super.child,
    super.thumbColor,
    super.thickness,
    super.radius,
  });

  @override
  RawScrollbarState<StableScrollbar> createState() => _StableScrollbarState();
}

class _StableScrollbarState extends RawScrollbarState<StableScrollbar> {
  Drag? _incrementalDrag;
  Offset? _lastPointer;
  double _scrollPerTrackPixel = 1;

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    _lastPointer = localPosition;
    final ratio = scrollbarPainter.getTrackToScroll(1);
    _scrollPerTrackPixel = ratio.isFinite && ratio > 0 ? ratio : 1;
    // 接管框架建立的 Drag；position.drag 会取消旧活动，框架的 dispose
    // 回调随即清空旧引用。后续仅由此 Drag 驱动，不使用 jumpTo 打断手势。
    _incrementalDrag = widget.controller!.position.drag(
      DragStartDetails(localPosition: localPosition),
      () => _incrementalDrag = null,
    );
  }

  @override
  // 故意替换框架的绝对映射；调用 super 会再次按变化的估算高度跳位。
  // ignore: must_call_super
  void handleThumbPressUpdate(Offset localPosition) {
    final last = _lastPointer;
    _lastPointer = localPosition;
    final drag = _incrementalDrag;
    if (last == null || drag == null) return;
    final position = widget.controller!.position;
    final horizontal = position.axis == Axis.horizontal;
    final movement = horizontal
        ? localPosition.dx - last.dx
        : localPosition.dy - last.dy;
    final reversed = axisDirectionIsReversed(position.axisDirection);
    final requested = movement * _scrollPerTrackPixel * (reversed ? -1 : 1);
    final target = (position.pixels + requested).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final delta = (target - position.pixels) * (reversed ? 1 : -1);
    drag.update(
      DragUpdateDetails(
        localPosition: localPosition,
        globalPosition: (context.findRenderObject()! as RenderBox)
            .localToGlobal(localPosition),
        delta: horizontal ? Offset(delta, 0) : Offset(0, delta),
        primaryDelta: delta,
      ),
    );
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    final drag = _incrementalDrag;
    _incrementalDrag = null;
    _lastPointer = null;
    drag?.end(DragEndDetails(localPosition: localPosition, primaryVelocity: 0));
  }

  @override
  Widget build(BuildContext context) => Listener(
    // RawScrollbar 的取消回调只知道它原先的 Drag；接管后的活动也必须取消。
    onPointerCancel: (_) {
      _incrementalDrag?.cancel();
      _incrementalDrag = null;
      _lastPointer = null;
    },
    child: super.build(context),
  );

  @override
  void dispose() {
    _incrementalDrag?.cancel();
    _incrementalDrag = null;
    super.dispose();
  }
}
