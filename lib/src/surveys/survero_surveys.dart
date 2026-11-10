import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/survero_client.dart';
import '../events/survero_event.dart';
import '../events/tracker.dart';
import 'eligible_survey.dart';
import 'local_caps.dart';
import 'survero_theme.dart';
import 'survey_sheet.dart';

/// Custom renderer (headless mode, SDK-015): receives the already localized survey and returns answered or dismissed.
/// The SDK still records impressions, caps and events.
typedef SurveyRenderer = Future<SurveyOutcome> Function(BuildContext context, EligibleSurvey survey);

/// `Survero.surveys` (SDK-014). Manual (`show`) and automatic (when a trigger event arrives) go through the same
/// gate: local caps → server gate (rules, caps, already answered). Every evaluation emits
/// `$survey_gate_evaluated {survey, trigger, reason}`, also when nothing is shown (principle 5).
class SurveroSurveys {
  SurveroSurveys.internal();

  bool _enabled = true;
  SurveroTheme? _theme;
  SurveyRenderer? _renderer;
  GlobalKey<NavigatorState>? _navigatorKey;

  Tracker? _tracker;
  SurveroClient? _client;
  EventContext? _context;
  LocalCaps _caps = LocalCaps();
  Set<String> _triggers = {};
  bool _busy = false;
  SurveroEventListener? _sink;

  /// Local kill switch. Defaults to `true` (lesson from the local `false` default that won on cold start).
  void enabled(bool value) => _enabled = value;
  bool get isEnabled => _enabled;

  /// Local override of the server style.
  void theme(SurveroTheme? value) => _theme = value;

  /// Headless mode: the app renders the survey.
  void renderer(SurveyRenderer? value) => _renderer = value;

  /// The app's Navigator: required for automatic triggering (there is no BuildContext in a `track()`).
  void attach(GlobalKey<NavigatorState> navigatorKey) => _navigatorKey = navigatorKey;

  /// Called by `Survero.init`.
  void bind({required Tracker tracker, required SurveroClient client, required EventContext context, LocalCaps? caps}) {
    if (_sink != null) _tracker?.removeSink(_sink!);
    _tracker = tracker;
    _client = client;
    _context = context;
    _caps = caps ?? LocalCaps();
    _sink = (event) {
      if (event.name.startsWith(r'$') || !_triggers.contains(event.name)) return;
      unawaited(onTrigger(event.name, props: event.props));
    };
    tracker.addSink(_sink!);
    unawaited(refreshTriggers());
  }

  void unbind() {
    if (_sink != null) _tracker?.removeSink(_sink!);
    _sink = null;
    _tracker = null;
    _client = null;
  }

  /// Reloads the list of events that can trigger surveys (1 h cache with ETag).
  Future<void> refreshTriggers() async {
    try {
      _triggers = await _client?.getTriggers() ?? {};
    } catch (_) {}
  }

  /// Shows a survey by slug, if the identity is eligible. It does not skip caps or rules.
  Future<SurveyOutcome?> show(String slug, {BuildContext? context, Map<String, Object?>? props}) =>
      _run(slug: slug, trigger: null, context: context, props: props);

  /// Evaluates the surveys for a trigger event (the SDK does this on its own on `track`; it can also be called).
  Future<SurveyOutcome?> onTrigger(String event, {BuildContext? context, Map<String, Object?>? props}) =>
      _run(slug: null, trigger: event, context: context, props: props);

  Future<SurveyOutcome?> _run({
    required String? slug,
    required String? trigger,
    BuildContext? context,
    Map<String, Object?>? props,
  }) async {
    final tracker = _tracker;
    final client = _client;
    if (tracker == null || client == null) {
      debugPrint('Survero: call Survero.init() before showing surveys');
      return null;
    }
    String? surveySlug = slug;
    // Solo quien tomó la puerta la libera: un segundo intento que recibe `busy` no debe soltar la del primero.
    var ownsBusy = false;
    Future<void> gate(String reason) =>
        tracker.trackSystem(r'$survey_gate_evaluated', {'survey': ?surveySlug, 'trigger': ?trigger, 'reason': reason});

    try {
      if (!_enabled) return await _skip(gate, 'disabled');
      // Sin dónde pintar no tiene sentido preguntar al servidor (p. ej. disparo automático sin attach()).
      final buildContext = context ?? _navigatorKey?.currentContext;
      if (buildContext == null) return await _skip(gate, 'no_context');
      if (_busy) return await _skip(gate, 'busy');
      final local = await _caps.blockBeforeServer();
      if (local != null) return await _skip(gate, local);

      _busy = true;
      ownsBusy = true;
      // Las reglas cuentan eventos en el servidor: el evento disparador (y lo encolado) tiene que haber llegado.
      await tracker.flush();
      final ctx = _context!;
      final result = await client.eligible({
        'device_id': tracker.identity.deviceId,
        'user_id': ?tracker.identity.userId,
        'trigger': ?trigger,
        'slug': ?slug,
        'locale': ?ctx.locale,
        'platform': ctx.platform,
        'app_version': ?ctx.appVersion,
        'types': EligibleSurvey.supportedTypes.join(','),
        if (props != null && props.isNotEmpty) 'props': jsonEncode(props),
      });
      if (result == null) return await _skip(gate, 'offline');

      final evaluated = (result['evaluated'] as List?) ?? const [];
      if (result['survey'] == null) {
        if (evaluated.isNotEmpty) surveySlug = (evaluated.last as Map)['slug'] as String?;
        return await _skip(gate, result['reason'] as String? ?? 'no_survey');
      }

      final survey = EligibleSurvey.fromJson(Map<String, dynamic>.from(result['survey'] as Map));
      surveySlug = survey.slug;
      final blocked = await _caps.blockSurvey(survey.slug);
      if (blocked != null) return await _skip(gate, blocked);

      if (!buildContext.mounted) return await _skip(gate, 'no_context');

      await gate('shown');
      if (!buildContext.mounted) return null;
      return await _present(buildContext, survey, trigger);
    } catch (e) {
      debugPrint('Survero: survey failed: $e');
      return null;
    } finally {
      if (ownsBusy) _busy = false;
    }
  }

  Future<SurveyOutcome?> _skip(Future<void> Function(String) gate, String reason) async {
    await gate(reason);
    return null;
  }

  Future<SurveyOutcome> _present(BuildContext context, EligibleSurvey survey, String? trigger) async {
    final tracker = _tracker!;
    final identity = {'device_id': tracker.identity.deviceId, 'user_id': ?tracker.identity.userId};
    await _caps.recordShown();
    await tracker.trackSystem(r'$survey_shown', {'survey': survey.slug, 'trigger': ?trigger});
    unawaited(tracker.sendOrKeep({
      'op': 'exposure',
      'survey_id': survey.id,
      'body': {...identity, 'outcome': 'shown', 'trigger_event': ?trigger},
    }));

    if (!context.mounted) return const SurveyOutcome.dismissed();
    SurveyOutcome? outcome;
    if (_renderer != null) {
      outcome = await _renderer!(context, survey);
    } else {
      outcome = await showModalBottomSheet<SurveyOutcome>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => SurveySheet(
          survey: survey,
          theme: _theme,
          onOutcome: (o) => Navigator.of(sheetContext).pop(o),
        ),
      );
    }
    outcome ??= const SurveyOutcome.dismissed(); // cerrada deslizando o tocando fuera

    switch (outcome) {
      case SurveyAnswered(:final answer):
        await _caps.recordAnswered(survey.slug);
        await tracker.trackSystem(r'$survey_answered', {
          'survey': survey.slug,
          'answer_key': answer.key,
          'has_text': answer.freeText?.isNotEmpty == true,
          'trigger': ?trigger,
        });
        final ctx = _context!;
        unawaited(tracker.sendOrKeep({
          'op': 'survey_response',
          'survey_id': survey.id,
          'body': {
            ...identity,
            'answer_key': ?answer.answerKey,
            'value': ?answer.value,
            'free_text': ?answer.freeText,
            'locale': survey.locale,
            'app_version': ?ctx.appVersion,
            'platform': ctx.platform,
            'trigger_event': ?trigger,
          },
        }));
      case SurveyDismissed():
        await _caps.recordDismissed(survey.slug);
        await tracker.trackSystem(r'$survey_dismissed', {'survey': survey.slug, 'trigger': ?trigger});
        unawaited(tracker.sendOrKeep({
          'op': 'exposure',
          'survey_id': survey.id,
          'body': {...identity, 'outcome': 'dismissed', 'trigger_event': ?trigger},
        }));
    }
    return outcome;
  }
}
