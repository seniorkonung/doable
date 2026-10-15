import 'package:flutter/material.dart';

/// Тени плавающих плоскостей Doable с плавным переходом между темами.
/// https://api.flutter.dev/flutter/material/ThemeExtension-class.html
final class DoableShadows extends ThemeExtension<DoableShadows> {
  DoableShadows({required List<BoxShadow> shadowFloat})
    : shadowFloat = List.unmodifiable(shadowFloat);

  static final light = DoableShadows(
    shadowFloat: const [
      BoxShadow(
        color: Color(0x1a111114),
        offset: Offset(0, 10),
        blurRadius: 30,
      ),
      BoxShadow(color: Color(0x0f111114), offset: Offset(0, 1), blurRadius: 3),
    ],
  );

  static final dark = DoableShadows(
    shadowFloat: const [
      BoxShadow(
        color: Color(0x8c000000),
        offset: Offset(0, 10),
        blurRadius: 30,
      ),
      BoxShadow(color: Color(0x80000000), offset: Offset(0, 1), blurRadius: 3),
    ],
  );

  final List<BoxShadow> shadowFloat;

  @override
  DoableShadows copyWith({List<BoxShadow>? shadowFloat}) =>
      DoableShadows(shadowFloat: shadowFloat ?? this.shadowFloat);

  @override
  DoableShadows lerp(covariant DoableShadows? other, double t) {
    if (other == null) return this;
    return DoableShadows(
      shadowFloat: BoxShadow.lerpList(shadowFloat, other.shadowFloat, t)!,
    );
  }
}
