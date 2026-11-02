import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survero/src/surveys/eligible_survey.dart';
import 'package:survero/src/surveys/survey_sheet.dart';

EligibleSurvey survey(String type, {SurveyFollowup? followup, String locale = 'en', List<SurveyOption>? options}) =>
    EligibleSurvey(
      id: 's1',
      slug: 'demo',
      type: type,
      locale: locale,
      question: 'How would you feel?',
      options: options ??
          const [
            SurveyOption(key: 'very', label: 'Very disappointed', emoji: '😞'),
            SurveyOption(key: 'not', label: 'Not disappointed', emoji: '🙂'),
          ],
      followup: followup,
      scaleMin: type == 'nps' ? 0 : 1,
      scaleMax: type == 'nps' ? 10 : 5,
      style: const SurveyServerStyle(primaryColor: '#E30B5C', borderRadius: 16),
    );

Future<List<SurveyOutcome>> pump(WidgetTester tester, EligibleSurvey s, {ThemeData? theme}) async {
  final outcomes = <SurveyOutcome>[];
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: SurveySheet(survey: s, onOutcome: outcomes.add))),
  ));
  return outcomes;
}

SurveyAnswer answerOf(List<SurveyOutcome> outcomes) => (outcomes.single as SurveyAnswered).answer;

void main() {
  testWidgets('single_choice: un tap responde si no hay follow-up', (tester) async {
    final out = await pump(tester, survey('single_choice'));
    await tester.tap(find.text('Not disappointed'));
    expect(answerOf(out).answerKey, 'not');
  });

  testWidgets('follow-up en la misma hoja solo para las claves indicadas', (tester) async {
    final out = await pump(
      tester,
      survey('single_choice', followup: const SurveyFollowup(prompt: 'Why?', forKeys: ['very'])),
    );
    await tester.tap(find.text('Very disappointed'));
    await tester.pumpAndSettle();
    expect(out, isEmpty);
    expect(find.text('Why?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  It helps me  ');
    await tester.tap(find.byType(FilledButton));
    final answer = answerOf(out);
    expect(answer.answerKey, 'very');
    expect(answer.freeText, 'It helps me');
  });

  testWidgets('star: el valor elegido', (tester) async {
    final out = await pump(tester, survey('star'));
    await tester.tap(find.bySemanticsLabel('4 / 5'));
    expect(answerOf(out).value, 4);
    expect(answerOf(out).key, '4');
  });

  testWidgets('nps: 11 botones de 0 a 10', (tester) async {
    final out = await pump(tester, survey('nps'));
    for (var n = 0; n <= 10; n++) {
      expect(find.text('$n'), findsOneWidget);
    }
    await tester.tap(find.text('9'));
    expect(answerOf(out).value, 9);
  });

  testWidgets('emoji: responde con la clave de la opción', (tester) async {
    final out = await pump(tester, survey('emoji'));
    await tester.tap(find.text('🙂'));
    expect(answerOf(out).answerKey, 'not');
  });

  testWidgets('free_text: no envía vacío; con texto sí', (tester) async {
    final out = await pump(tester, survey('free_text', options: const []));
    await tester.tap(find.byType(FilledButton));
    expect(out, isEmpty);
    await tester.enterText(find.byType(TextField), 'Más historias');
    await tester.tap(find.byType(FilledButton));
    expect(answerOf(out).freeText, 'Más historias');
  });

  testWidgets('cerrar → descartada', (tester) async {
    final out = await pump(tester, survey('single_choice'));
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(out.single, isA<SurveyDismissed>());
  });

  testWidgets('árabe se pinta de derecha a izquierda', (tester) async {
    await pump(tester, survey('single_choice', locale: 'ar'));
    final dir = tester.widget<Directionality>(
      find.ancestor(of: find.text('How would you feel?'), matching: find.byType(Directionality)).first,
    );
    expect(dir.textDirection, TextDirection.rtl);
  });

  testWidgets('accesibilidad: toques ≥ 44 pt y contraste, en claro y oscuro', (tester) async {
    final handle = tester.ensureSemantics();
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      for (final type in ['single_choice', 'star', 'nps', 'emoji']) {
        await pump(tester, survey(type), theme: theme);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
    }
    handle.dispose();
  });
}
