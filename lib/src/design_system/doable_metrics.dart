/// Шкалы отступов, радиусов и размеры компонентов Doable.
abstract final class DoableMetrics {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;

  static const double radiusXs = 6;
  static const double radiusSm = 12;
  static const double radiusMd = 14;
  static const double radiusLg = 16;
  static const double radiusXl = 28;
  static const double radiusFull = 9999;

  static const double controlHeight = 40;
  static const double controlHeightSm = 36;
  static const double tapMin = 44;
  static const double navHeight = 61;
  static const double iconSize = 24;

  /// Сплошная линия связи «нужно».
  static const double strokeNeed = 2;

  /// Пунктирная линия связи «можно».
  static const double strokeCan = 1.5;

  /// Штрих и промежуток пунктира линии «можно».
  static const double strokeDash = 5;
  static const double strokeGap = 5;
}
