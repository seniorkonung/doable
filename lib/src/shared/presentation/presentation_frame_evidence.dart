import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Сообщает о фактическом предъявлении [subject] после первого завершённого
/// кадра, в котором [child] виден в приложении с фокусом ввода.
///
/// Построение виджета, запись состояния или вызов API показа предъявлением не
/// считаются: проверка выполняется после кадра по фактической раскладке и
/// отрисовке. Пока проверка не пройдена, она повторяется после следующих
/// кадров, не заставляя приложение рисовать дополнительные кадры.
final class PresentationFrameEvidence<T extends Object> extends StatefulWidget {
  const PresentationFrameEvidence({
    required this.subject,
    required this.onPresented,
    required this.child,
    this.requiresCurrentRoute = true,
    super.key,
  });

  /// Предъявляемый результат; `null` означает отсутствие права подтверждать.
  final T? subject;
  final ValueChanged<T> onPresented;

  /// Требует, чтобы маршрут сообщения был верхним и не перекрывался диалогом.
  final bool requiresCurrentRoute;
  final Widget child;

  @override
  State<PresentationFrameEvidence<T>> createState() =>
      _PresentationFrameEvidenceState<T>();
}

final class _PresentationFrameEvidenceState<T extends Object>
    extends State<PresentationFrameEvidence<T>>
    with WidgetsBindingObserver {
  T? _presentedSubject;
  T? _scheduledSubject;
  ModalRoute<Object?>? _route;
  var _isTickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Переход inactive → resumed сам по себе не планирует кадр.
    if (state == AppLifecycleState.resumed && _scheduledSubject != null) {
      SchedulerBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    _route = ModalRoute.of(context);
    _isTickerEnabled = TickerMode.valuesOf(context).enabled;
    _scheduleCheck();
    return widget.child;
  }

  void _scheduleCheck() {
    final subject = widget.subject;
    if (subject == null ||
        identical(subject, _presentedSubject) ||
        identical(subject, _scheduledSubject)) {
      return;
    }
    _scheduledSubject = subject;
    SchedulerBinding.instance.addPostFrameCallback((_) => _check(subject));
  }

  void _check(T subject) {
    if (!mounted || !identical(widget.subject, subject)) {
      if (identical(_scheduledSubject, subject)) {
        _scheduledSubject = null;
      }
      return;
    }
    if (!_isPresentedInCompletedFrame()) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _check(subject));
      return;
    }
    _scheduledSubject = null;
    _presentedSubject = subject;
    widget.onPresented(subject);
  }

  bool _isPresentedInCompletedFrame() {
    if (SchedulerBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        !_isTickerEnabled) {
      return false;
    }
    final route = _route;
    if (widget.requiresCurrentRoute && route != null && !route.isCurrent) {
      return false;
    }
    final renderObject = context.findRenderObject();
    return renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize &&
        hasVisiblePaintArea(renderObject);
  }
}

/// Проверяет, что после последнего кадра часть [box] попадает в видимую
/// область экрана с учётом отсечений, скрытия и прозрачности предков.
@visibleForTesting
bool hasVisiblePaintArea(RenderBox box) {
  var rect = Offset.zero & box.size;
  if (rect.isEmpty) {
    return false;
  }
  RenderObject child = box;
  var parent = child.parent;
  while (parent != null && parent is! RenderView) {
    if (!parent.paintsChild(child)) {
      return false;
    }
    final transform = Matrix4.identity();
    parent.applyPaintTransform(child, transform);
    rect = MatrixUtils.transformRect(transform, rect);
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null) {
      rect = rect.intersect(clip);
    }
    if (rect.isEmpty) {
      return false;
    }
    child = parent;
    parent = child.parent;
  }
  if (parent is RenderView) {
    rect = rect.intersect(Offset.zero & parent.size);
  }
  return !rect.isEmpty;
}
