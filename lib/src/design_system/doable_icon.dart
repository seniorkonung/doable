import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Исходные значки дизайна; мини-значки сохраняют собственную толщину линий.
enum DoableIconData {
  home('home'),
  homeFilled('home_filled'),
  calendarDays('calendar_days'),
  calendarDaysFilled('calendar_days_filled'),
  graph('graph'),
  graphFilled('graph_filled'),
  plus('plus'),
  plusSmall('plus_small'),
  intention('intention'),
  relation('relation'),
  calendar('calendar'),
  intentionMini('intention_mini'),
  relationMini('relation_mini'),
  calendarMini('calendar_mini'),
  fromIntention('from_intention'),
  fromAction('from_action'),
  check('check'),
  exclude('exclude'),
  chevronRight('chevron_right'),
  chevronDown('chevron_down'),
  search('search'),
  clear('clear'),
  grip('grip'),
  edit('edit'),
  copy('copy'),
  delete('delete'),
  settings('settings'),
  export('export'),
  lockOpen('lock_open'),
  backups('backups'),
  import('import'),
  warning('warning'),
  close('close'),
  filter('filter'),
  bolt('bolt'),
  arrowUpRight('arrow_up_right'),
  archive('archive');

  const DoableIconData(this._assetName);

  final String _assetName;
}

/// Декоративная иконка в квадрате [size] с сохранением пропорций исходника.
/// Название и роль для доступности задаёт содержащий её элемент управления.
final class DoableIcon extends StatelessWidget {
  const DoableIcon(
    this.icon, {
    required this.size,
    required this.color,
    super.key,
  });

  final DoableIconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    // Без жёсткого квадрата `vector_graphics` пересчитывает ширину
    // неквадратной графики по высоте и выходит за `size`.
    child: FittedBox(
      child: SvgPicture.asset(
        'lib/src/design_system/icons/assets/${icon._assetName}.svg',
        // Фильтр окрашивает и заливки, и линии, сохраняя прозрачные вырезы:
        // https://pub.dev/packages/flutter_svg#-readme-tab-
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        excludeFromSemantics: true,
      ),
    ),
  );
}
