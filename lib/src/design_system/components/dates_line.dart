import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_type.dart';

/// Приглушённая строка с датами создания и последнего изменения, которой
/// кончаются подробности одной сущности: «Создано 27 мар · Изменено 29 апр».
///
/// Даты приходят готовыми подписями: их форматирует потребитель и он же
/// решает, показывать ли дату изменения.
final class DatesLine extends StatelessWidget {
  const DatesLine({required this.created, this.changed, super.key});

  /// Метка и дата создания, например «Создано» и «6 окт».
  final ({String label, String date}) created;

  /// Метка и дата изменения. Без неё строка называет одну дату создания.
  final ({String label, String date})? changed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Text(
      [
        created,
        ?changed,
      ].map((part) => '${part.label} ${part.date}').join(' · '),
      style: DoableType.hint.copyWith(
        color: colors.muted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
