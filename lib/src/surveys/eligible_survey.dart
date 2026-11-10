/// A survey the server gate decided to show, with the copy already in one language (the widget does not know
/// about languages).
class EligibleSurvey {
  final String id;
  final String slug;

  /// `single_choice`, `star`, `nps`, `emoji` or `free_text`: picks the renderer.
  final String type;
  final String? triggerEvent;
  final String locale;
  final String question;
  final List<SurveyOption> options;
  final SurveyFollowup? followup;
  final String? submitLabel;

  /// Scale for `star` (1..maxStars) and `nps` (0..10).
  final int? scaleMin;
  final int? scaleMax;
  final SurveyServerStyle style;

  const EligibleSurvey({
    required this.id,
    required this.slug,
    required this.type,
    required this.locale,
    required this.question,
    this.triggerEvent,
    this.options = const [],
    this.followup,
    this.submitLabel,
    this.scaleMin,
    this.scaleMax,
    this.style = const SurveyServerStyle(),
  });

  /// Types this SDK version can render (sent to the server; a new one → `sdk_too_old`).
  static const supportedTypes = ['single_choice', 'star', 'nps', 'emoji', 'free_text'];

  factory EligibleSurvey.fromJson(Map<String, dynamic> json) {
    final copy = Map<String, dynamic>.from(json['copy'] as Map? ?? const {});
    final scale = json['scale'] as Map?;
    final followup = copy['followup'] as Map?;
    return EligibleSurvey(
      id: json['id'] as String,
      slug: json['slug'] as String,
      type: json['type'] as String,
      triggerEvent: json['trigger_event'] as String?,
      locale: json['locale'] as String? ?? 'en',
      question: copy['question'] as String? ?? '',
      options: [
        for (final o in (copy['options'] as List? ?? const []))
          SurveyOption(
            key: (o as Map)['key'] as String,
            label: o['label'] as String? ?? o['key'] as String,
            emoji: o['emoji'] as String?,
          ),
      ],
      followup: followup == null
          ? null
          : SurveyFollowup(
              prompt: followup['prompt'] as String? ?? '',
              placeholder: followup['placeholder'] as String?,
              forKeys: (followup['for_keys'] as List?)?.cast<String>() ?? const [],
            ),
      submitLabel: copy['submit'] as String?,
      scaleMin: (scale?['min'] as num?)?.toInt(),
      scaleMax: (scale?['max'] as num?)?.toInt(),
      style: SurveyServerStyle.fromJson(Map<String, dynamic>.from(json['style'] as Map? ?? const {})),
    );
  }

  /// Whether the follow-up applies after this answer (no `for_keys` = always).
  bool followupFor(String answerKey) =>
      followup != null && (followup!.forKeys.isEmpty || followup!.forKeys.contains(answerKey));

  /// Languages written right to left.
  bool get isRtl => const {'ar', 'he', 'fa', 'ur', 'ps', 'yi'}.contains(locale.split(RegExp('[-_]')).first);
}

class SurveyOption {
  final String key;
  final String label;
  final String? emoji;
  const SurveyOption({required this.key, required this.label, this.emoji});
}

class SurveyFollowup {
  final String prompt;
  final String? placeholder;
  final List<String> forKeys;
  const SurveyFollowup({required this.prompt, this.placeholder, this.forKeys = const []});
}

/// Style sent by the server (editable in the dashboard).
class SurveyServerStyle {
  final String? primaryColor;
  final String? fontFamily;
  final double? borderRadius;
  const SurveyServerStyle({this.primaryColor, this.fontFamily, this.borderRadius});

  factory SurveyServerStyle.fromJson(Map<String, dynamic> json) => SurveyServerStyle(
        primaryColor: json['primaryColor'] as String?,
        fontFamily: json['fontFamily'] as String?,
        borderRadius: (json['borderRadius'] as num?)?.toDouble(),
      );
}

/// A survey answer: the option's stable key, the scale value and/or free text.
class SurveyAnswer {
  final String? answerKey;
  final int? value;
  final String? freeText;
  const SurveyAnswer({this.answerKey, this.value, this.freeText});

  /// Key emitted in `$survey_answered` and stored on the server.
  String get key => answerKey ?? (value?.toString() ?? 'text');
}

/// What a renderer returns: answered or dismissed.
sealed class SurveyOutcome {
  const SurveyOutcome();
  const factory SurveyOutcome.answered(SurveyAnswer answer) = SurveyAnswered;
  const factory SurveyOutcome.dismissed() = SurveyDismissed;
}

class SurveyAnswered extends SurveyOutcome {
  final SurveyAnswer answer;
  const SurveyAnswered(this.answer);
}

class SurveyDismissed extends SurveyOutcome {
  const SurveyDismissed();
}
