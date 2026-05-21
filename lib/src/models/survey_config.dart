class SurveySettings {
  final int maxStars;
  final bool showComment;

  const SurveySettings({
    this.maxStars = 5,
    this.showComment = true,
  });

  factory SurveySettings.fromJson(Map<String, dynamic> json) {
    return SurveySettings(
      maxStars: json['maxStars'] as int? ?? 5,
      showComment: json['showComment'] as bool? ?? true,
    );
  }
}

class SurveyStyle {
  final String primaryColor;
  final String fontFamily;
  final double borderRadius;

  const SurveyStyle({
    this.primaryColor = '#E30B5C',
    this.fontFamily = 'Inter',
    this.borderRadius = 8,
  });

  factory SurveyStyle.fromJson(Map<String, dynamic> json) {
    return SurveyStyle(
      primaryColor: json['primaryColor'] as String? ?? '#E30B5C',
      fontFamily: json['fontFamily'] as String? ?? 'Inter',
      borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 8,
    );
  }
}

class SurveyConfig {
  final String id;
  final String title;
  final String type;
  final bool isActive;
  final SurveySettings settings;
  final SurveyStyle style;

  const SurveyConfig({
    required this.id,
    required this.title,
    required this.type,
    required this.isActive,
    required this.settings,
    required this.style,
  });

  factory SurveyConfig.fromJson(Map<String, dynamic> json) {
    return SurveyConfig(
      id: json['id'] as String,
      title: json['title'] as String,
      type: json['type'] as String,
      isActive: json['is_active'] as bool? ?? true,
      settings: SurveySettings.fromJson(
        json['settings'] as Map<String, dynamic>? ?? {},
      ),
      style: SurveyStyle.fromJson(
        json['style'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}
