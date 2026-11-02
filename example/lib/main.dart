import 'package:flutter/material.dart';
import 'package:survero/survero.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Valores de ejemplo: cámbialos por los de tu proyecto (Dashboard → Settings → API Keys, y Surveys).
const publicKey = String.fromEnvironment('SURVERO_KEY', defaultValue: 'pk_live_REPLACE_WITH_YOUR_PUBLIC_KEY');
const apiUrl = String.fromEnvironment('SURVERO_API', defaultValue: 'http://localhost:4000/api/v1');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clave PÚBLICA del proyecto (pk_). Nunca una secreta (sk_) en una app.
  await Survero.init(apiKey: publicKey, baseUrl: apiUrl, appVersion: '2.4.1', enableInDebug: true);
  // Necesario para que una encuesta se abra sola al llegar su evento disparador.
  Survero.surveys.attach(navigatorKey);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Survero Example',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E3A87)), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E3A87), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Survero SDK Example')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('La app no tiene ningún widget de encuesta: la hoja la pinta el SDK.'),
          const SizedBox(height: 24),
          FilledButton(
            // Si hay una encuesta con trigger_event = story_completed y la identidad es elegible, se abre sola.
            onPressed: () => Survero.track('story_completed', {'story_id': 'demo'}),
            child: const Text('track("story_completed")'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            // Manual por slug: pasa por la misma puerta (reglas, caps, ya respondida).
            onPressed: () async {
              final outcome = await Survero.surveys.show('sean-ellis', context: context);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(switch (outcome) {
                  SurveyAnswered(:final answer) => 'Answered: ${answer.key}',
                  SurveyDismissed() => 'Dismissed',
                  null => 'Not shown (see \$survey_gate_evaluated for the reason)',
                }),
              ));
            },
            child: const Text('Survero.surveys.show("sean-ellis")'),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: () => Survero.identify('demo-user'), child: const Text('identify("demo-user")')),
        ],
      ),
    );
  }
}
