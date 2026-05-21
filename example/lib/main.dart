import 'package:flutter/material.dart';
import 'package:survero/survero.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Survero SDK with your API key
  await Survero.init(
    apiKey: 'sk_live_your_api_key_here',
    // For local development, point to your NestJS backend:
    baseUrl: 'http://localhost:4000/api/v1',
    appVersion: '1.0.0',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Survero Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E3A87)),
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
      appBar: AppBar(
        title: const Text('Survero SDK Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.rate_review_outlined,
              size: 64,
              color: Color(0xFF2E3A87),
            ),
            const SizedBox(height: 16),
            const Text(
              'Survero Flutter SDK',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the button below to show a survey',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showSurvey(context),
              icon: const Icon(Icons.star_rounded),
              label: const Text('Show Survey'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE30B5C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSurvey(BuildContext context) {
    // Replace with your actual survey ID from the Survero Dashboard
    Survero.show(
      context: context,
      surveyId: 'your-survey-id-here',
      onComplete: (response) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Thanks! You rated ${response.rating} stars'
              '${response.comment != null ? ' — "${response.comment}"' : ''}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      },
      onDismiss: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Survey dismissed'),
            backgroundColor: Colors.grey,
          ),
        );
      },
    );
  }
}
