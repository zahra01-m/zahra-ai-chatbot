import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static String get groqKey => dotenv.get('GROQ_KEY', fallback: '');
  static String get geminiKey => dotenv.get('GEMINI_KEY', fallback: '');
  static String get googleClientId => dotenv.get('GOOGLE_CLIENT_ID', fallback: '');

  static const String groqUrl = 'https://api.groq.com/openai/v1/chat/completions';

  static const String geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  // Confirmed 2026 Flagship Models
  static const String defaultGroqModel = 'llama-3.3-70b-versatile'; 
  static const List<String> groqModels = [
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'mixtral-8x7b-32768',
    'qwen-2.5-32b', // Good for reasoning/context
  ];

  static const int maxHistory = 60;
}
