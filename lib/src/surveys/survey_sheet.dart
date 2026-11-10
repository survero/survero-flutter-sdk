import 'package:flutter/material.dart';

import 'eligible_survey.dart';
import 'survero_theme.dart';

/// The survey sheet the SDK renders (SDK-013). One renderer per `type`; one sheet, one tap; the follow-up is
/// revealed in the same sheet. Returns the result through [onOutcome] (answered or dismissed).
class SurveySheet extends StatefulWidget {
  final EligibleSurvey survey;
  final SurveroTheme? theme;
  final ValueChanged<SurveyOutcome> onOutcome;

  const SurveySheet({super.key, required this.survey, required this.onOutcome, this.theme});

  @override
  State<SurveySheet> createState() => _SurveySheetState();
}

class _SurveySheetState extends State<SurveySheet> {
  final _text = TextEditingController();

  /// Chosen answer waiting for the follow-up (or the free text).
  SurveyAnswer? _pending;
  bool _done = false;

  EligibleSurvey get survey => widget.survey;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _finish(SurveyOutcome outcome) {
    if (_done) return;
    _done = true;
    widget.onOutcome(outcome);
  }

  /// One tap: if there is no follow-up for that answer, it is sent right away.
  void _choose(SurveyAnswer answer) {
    if (survey.followupFor(answer.key)) {
      setState(() => _pending = answer);
    } else {
      _finish(SurveyOutcome.answered(answer));
    }
  }

  void _submitPending() {
    final answer = _pending;
    final text = _text.text.trim();
    if (survey.type == 'free_text') {
      if (text.isEmpty) return;
      _finish(SurveyOutcome.answered(SurveyAnswer(answerKey: 'text', freeText: text)));
      return;
    }
    if (answer == null) return;
    _finish(SurveyOutcome.answered(
      SurveyAnswer(answerKey: answer.answerKey, value: answer.value, freeText: text.isEmpty ? null : text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final style = ResolvedSurveyStyle.resolve(context, survey.style, widget.theme);
    final textTheme = Theme.of(context).textTheme.apply(
          bodyColor: style.text,
          displayColor: style.text,
          fontFamily: style.fontFamily,
        );
    final rtl = survey.isRtl;

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : Directionality.of(context),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: style.background,
            borderRadius: BorderRadius.circular(style.radius),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, -4))],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        icon: Icon(Icons.close_rounded, color: style.muted),
                        onPressed: () => _finish(const SurveyOutcome.dismissed()),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: Semantics(
                      header: true,
                      child: Text(survey.question, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _body(style, textTheme),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(ResolvedSurveyStyle style, TextTheme textTheme) {
    if (survey.type == 'free_text') return _followup(style, textTheme, prompt: null);
    final pending = _pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (survey.type) {
          'single_choice' => _choices(style, textTheme),
          'emoji' => _emojis(style, textTheme),
          'star' => _stars(style),
          'nps' => _nps(style, textTheme),
          _ => const SizedBox.shrink(),
        },
        if (pending != null) ...[
          const SizedBox(height: 16),
          _followup(style, textTheme, prompt: survey.followup?.prompt),
        ],
      ],
    );
  }

  Widget _choices(ResolvedSurveyStyle style, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in survey.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionButton(
              label: option.label,
              selected: _pending?.answerKey == option.key,
              style: style,
              textStyle: textTheme.bodyLarge,
              onTap: () => _choose(SurveyAnswer(answerKey: option.key)),
            ),
          ),
      ],
    );
  }

  Widget _emojis(ResolvedSurveyStyle style, TextTheme textTheme) {
    return Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in survey.options)
          Semantics(
            button: true,
            selected: _pending?.answerKey == option.key,
            label: option.label,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(style.radius),
              onTap: () => _choose(SurveyAnswer(answerKey: option.key)),
              child: Container(
                constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(style.radius),
                  border: Border.all(color: _pending?.answerKey == option.key ? style.primary : Colors.transparent, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(option.emoji ?? '', style: const TextStyle(fontSize: 32)),
                    const SizedBox(height: 4),
                    Text(option.label, style: textTheme.bodySmall?.copyWith(color: style.muted), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _stars(ResolvedSurveyStyle style) {
    final min = survey.scaleMin ?? 1;
    final max = survey.scaleMax ?? 5;
    final selected = _pending?.value ?? 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var star = min; star <= max; star++)
          Semantics(
            button: true,
            selected: star <= selected,
            label: '$star / $max',
            excludeSemantics: true,
            child: InkResponse(
              radius: 26,
              onTap: () => _choose(SurveyAnswer(value: star)),
              child: SizedBox(
                width: 44,
                height: 48,
                child: Icon(
                  star <= selected ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: max <= 5 ? 40 : 30,
                  color: star <= selected ? style.primary : style.outline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _nps(ResolvedSurveyStyle style, TextTheme textTheme) {
    final min = survey.scaleMin ?? 0;
    final max = survey.scaleMax ?? 10;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = max - min + 1;
        // Una fila si cabe con toques de 44 pt; si no, dos.
        final perRow = constraints.maxWidth / count >= 44 ? count : (count / 2).ceil();
        final size = (constraints.maxWidth / perRow).clamp(44.0, 56.0) - 4;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var n = min; n <= max; n++)
              Semantics(
                button: true,
                selected: _pending?.value == n,
                label: '$n',
                excludeSemantics: true,
                child: Material(
                  color: _pending?.value == n ? style.primary : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: _pending?.value == n ? style.primary : style.outline),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _choose(SurveyAnswer(value: n)),
                    child: SizedBox(
                      width: size,
                      height: 44,
                      child: Center(
                        child: Text(
                          '$n',
                          style: textTheme.bodyLarge?.copyWith(
                            color: _pending?.value == n ? style.onPrimary : style.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _followup(ResolvedSurveyStyle style, TextTheme textTheme, {required String? prompt}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prompt != null && prompt.isNotEmpty) ...[
          Text(prompt, style: textTheme.bodyMedium?.copyWith(color: style.muted)),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _text,
          autofocus: survey.type == 'free_text',
          minLines: 2,
          maxLines: 4,
          maxLength: 2000,
          style: textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: survey.followup?.placeholder,
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(style.radius / 2)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(style.radius / 2),
              borderSide: BorderSide(color: style.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: style.primary,
              foregroundColor: style.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(style.radius / 2)),
            ),
            onPressed: _submitPending,
            child: Text(survey.submitLabel ?? MaterialLocalizations.of(context).okButtonLabel),
          ),
        ),
      ],
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final bool selected;
  final ResolvedSurveyStyle style;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  const _OptionButton({
    required this.label,
    required this.selected,
    required this.style,
    required this.textStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? style.primary.withValues(alpha: 0.12) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.radius / 2),
          side: BorderSide(color: selected ? style.primary : style.outline, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(style.radius / 2),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Align(alignment: AlignmentDirectional.centerStart, child: Text(label, style: textStyle)),
            ),
          ),
        ),
      ),
    );
  }
}
