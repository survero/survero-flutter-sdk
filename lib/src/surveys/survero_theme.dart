import 'package:flutter/material.dart';

import '../utils/color_utils.dart';
import 'eligible_survey.dart';

/// Override local del estilo de la hoja. Capas (consultoría §4.7 regla 3):
/// estilo del servidor → [SurveroTheme] → tema de la app (`Theme.of`): brillo, colores de superficie, tipografía.
class SurveroTheme {
  final Color? primaryColor;
  final Color? backgroundColor;
  final Color? textColor;
  final double? borderRadius;
  final String? fontFamily;

  const SurveroTheme({this.primaryColor, this.backgroundColor, this.textColor, this.borderRadius, this.fontFamily});
}

/// Estilo final que usa el widget.
class ResolvedSurveyStyle {
  final Color primary;
  final Color onPrimary;
  final Color background;
  final Color text;
  final Color muted;
  final Color outline;
  final double radius;
  final String? fontFamily;

  const ResolvedSurveyStyle({
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.text,
    required this.muted,
    required this.outline,
    required this.radius,
    this.fontFamily,
  });

  static ResolvedSurveyStyle resolve(BuildContext context, SurveyServerStyle server, SurveroTheme? local) {
    final scheme = Theme.of(context).colorScheme;
    Color? serverPrimary;
    try {
      if (server.primaryColor != null) serverPrimary = hexToColor(server.primaryColor!);
    } catch (_) {}
    final primary = local?.primaryColor ?? serverPrimary ?? scheme.primary;
    return ResolvedSurveyStyle(
      primary: primary,
      onPrimary: ThemeData.estimateBrightnessForColor(primary) == Brightness.dark ? Colors.white : Colors.black,
      background: local?.backgroundColor ?? scheme.surface,
      text: local?.textColor ?? scheme.onSurface,
      // 0.75: el texto secundario a 12 pt mantiene contraste WCAG AA (≥ 4,5) en claro y oscuro.
      muted: (local?.textColor ?? scheme.onSurface).withValues(alpha: 0.75),
      outline: scheme.outlineVariant,
      radius: local?.borderRadius ?? server.borderRadius ?? 16,
      // La fuente del servidor solo si la app la tiene registrada; por defecto, la tipografía de la app.
      fontFamily: local?.fontFamily,
    );
  }
}
