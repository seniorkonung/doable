import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_type.dart';
import 'notice.dart';

/// Состояние всего списка на месте его строк — загрузка или отказ загрузки —
/// либо подгрузка следующей порции в конце списка.
///
/// Экранный диктор Android не различает роли статуса и оповещения, а Flutter
/// запрещает совмещать их с живой областью, поэтому оба вида объявляются
/// живой областью:
/// https://api.flutter.dev/flutter/semantics/SemanticsProperties/liveRegion.html
sealed class ListState extends StatelessWidget {
  const ListState._({super.key});

  /// Кольцо и текст о том, что загружается; объявляется как статус.
  const factory ListState.loading({required String text, Key? key}) =
      _LoadingListState;

  /// Кольцо по центру строки высотой 40 в конце списка, пока в нём есть
  /// незагруженные строки. Видимого текста нет: [text] называет, что
  /// подгружается, и объявляется как статус.
  const factory ListState.more({required String text, Key? key}) =
      _MoreListState;

  /// Карточка отказа со значком, сообщением о том, что не загружено, и
  /// действием повтора, если повтор может помочь; объявляется как оповещение.
  const factory ListState.error({
    required String message,
    ({String label, VoidCallback onPressed})? retry,
    Key? key,
  }) = _ErrorListState;
}

final class _LoadingListState extends ListState {
  const _LoadingListState({required this.text, super.key}) : super._();

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Semantics(
      container: true,
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 24),
        child: Row(
          children: [
            _Spinner(color: colors.muted, trackColor: colors.hairline),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: DoableType.body.copyWith(color: colors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MoreListState extends ListState {
  const _MoreListState({required this.text, super.key}) : super._();

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: SizedBox(
        height: 40,
        child: Center(
          child: _Spinner(color: colors.muted, trackColor: colors.hairline),
        ),
      ),
    );
  }
}

final class _ErrorListState extends ListState {
  const _ErrorListState({required this.message, this.retry, super.key})
    : super._();

  final String message;
  final ({String label, VoidCallback onPressed})? retry;

  /// Карточка отказа списка выглядит как карточка отказа [Notice].
  @override
  Widget build(BuildContext context) => Notice.content(
    message: Semantics(container: true, liveRegion: true, child: Text(message)),
    action: retry,
  );
}

/// Кольцо загрузки: оборот за 0,8 с, а при уменьшенной анимации — втрое
/// медленнее, без остановки.
final class _Spinner extends StatefulWidget {
  const _Spinner({required this.color, required this.trackColor});

  final Color color;
  final Color trackColor;

  @override
  State<_Spinner> createState() => _SpinnerState();
}

final class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final _turns = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 2400)
        : const Duration(milliseconds: 800);
    if (_turns.duration != duration) {
      _turns
        ..duration = duration
        ..repeat();
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turns,
    child: SizedBox.square(
      dimension: 18,
      child: CustomPaint(
        painter: _SpinnerPainter(
          color: widget.color,
          trackColor: widget.trackColor,
        ),
      ),
    ),
  );
}

final class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.color, required this.trackColor});

  static const double _strokeWidth = 2;

  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    canvas.drawCircle(center, radius, stroke..color = trackColor);
    // Дуга — верхняя четверть кольца, как цветная верхняя граница в макете.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3 * math.pi / 4,
      math.pi / 2,
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      color != oldDelegate.color || trackColor != oldDelegate.trackColor;
}
