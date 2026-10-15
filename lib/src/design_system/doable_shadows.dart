import 'package:flutter/material.dart';

/// Тени, используемые компонентами Doable.
enum DoableShadowToken {
  sm,
  float;

  // Пара обязательна для каждого токена: светлое и тёмное значения.
  (List<BoxShadow>, List<BoxShadow>) get _palette => switch (this) {
    sm => (
      const [
        BoxShadow(
          color: Color(0x0f111114),
          offset: Offset(0, 1),
          blurRadius: 2,
        ),
        BoxShadow(
          color: Color(0x0d111114),
          offset: Offset(0, 2),
          blurRadius: 8,
        ),
      ],
      const [
        BoxShadow(
          color: Color(0x80000000),
          offset: Offset(0, 1),
          blurRadius: 2,
        ),
      ],
    ),
    float => (
      const [
        BoxShadow(
          color: Color(0x1a111114),
          offset: Offset(0, 10),
          blurRadius: 30,
        ),
        BoxShadow(
          color: Color(0x0f111114),
          offset: Offset(0, 1),
          blurRadius: 3,
        ),
      ],
      const [
        BoxShadow(
          color: Color(0x8c000000),
          offset: Offset(0, 10),
          blurRadius: 30,
        ),
        BoxShadow(
          color: Color(0x80000000),
          offset: Offset(0, 1),
          blurRadius: 3,
        ),
      ],
    ),
  };
}

/// Тени Doable, плавно меняющиеся вместе с темой.
///
/// https://api.flutter.dev/flutter/material/ThemeExtension-class.html
final class DoableShadows extends ThemeExtension<DoableShadows> {
  DoableShadows._(List<BoxShadow> Function(DoableShadowToken token) shadowsFor)
    : _shadows = List.unmodifiable(
        DoableShadowToken.values.map(
          (token) => List<BoxShadow>.unmodifiable(shadowsFor(token)),
        ),
      );

  static final light = DoableShadows._((token) => token._palette.$1);
  static final dark = DoableShadows._((token) => token._palette.$2);

  final List<List<BoxShadow>> _shadows;

  List<BoxShadow> operator [](DoableShadowToken token) => _shadows[token.index];

  /// `shadow-sm`: тень выбранного дня недели.
  List<BoxShadow> get sm => this[DoableShadowToken.sm];

  /// `shadow-float`: тень плавающих листов.
  List<BoxShadow> get shadowFloat => this[DoableShadowToken.float];

  /// Заменяет тени, для которых [shadowsFor] возвращает ненулевое значение.
  @override
  DoableShadows copyWith({
    List<BoxShadow>? Function(DoableShadowToken token)? shadowsFor,
  }) {
    if (shadowsFor == null) return this;
    return DoableShadows._((token) => shadowsFor(token) ?? this[token]);
  }

  @override
  DoableShadows lerp(covariant DoableShadows? other, double t) {
    if (other == null) return this;
    // Разное число слоёв поддерживает сам Flutter:
    // https://api.flutter.dev/flutter/painting/BoxShadow/lerpList.html
    return DoableShadows._(
      (token) => BoxShadow.lerpList(this[token], other[token], t)!,
    );
  }
}
