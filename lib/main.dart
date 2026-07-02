import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme.dart';
import 'features/auth/views/auth_screen.dart';
import 'features/chat/views/chat_screen.dart';
import 'features/auth/providers/auth_provider.dart';
import 'firebase_options.dart';
import 'core/theme_provider.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Load .env file (GROQ_KEY, GEMINI_KEY, GOOGLE_CLIENT_ID)
    await dotenv.load(fileName: ".env");

    // ULTRA-DEFENSIVE: guard against duplicate-app crash
    debugPrint('Initializing Firebase...');
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('Firebase initialized successfully');
      } else {
        debugPrint('Firebase already exists, skipping initialization');
      }
    } catch (e) {
      if (e.toString().contains('duplicate-app')) {
        debugPrint('Suppressed duplicate-app error');
      } else {
        debugPrint('Firebase Initialization Warning: $e');
        // If it's not a duplicate app error, we might still want to try to continue
        // as long as Firebase.apps is not empty.
        if (Firebase.apps.isEmpty) rethrow;
      }
    }

    runApp(const ProviderScope(child: ChatBotApp()));
  } catch (e) {
    debugPrint('CRITICAL STARTUP ERROR: $e');
    // Shows error on screen instead of blank crash
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'Failed to start app: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.red),
            ),
          ),
        ),
      ),
    ));
  }
}

class ChatBotApp extends ConsumerWidget {
  const ChatBotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zahra AI Chat',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: authState.when(
        data: (user) =>
        user == null ? const AuthScreen() : const ChatScreen(),
        loading: () =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, s) =>
            Scaffold(body: Center(child: Text('Auth Error: $e'))),
      ),
    );
  }
}
