import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AIPersona {
  helpful(
    name: 'Helpful',
    prompt: 'You are a helpful assistant. Maintain a medium length for responses (around 2-3 paragraphs or 100-200 words) unless the user explicitly requests otherwise. Use markdown.',
    icon: '😊',
  ),
  creative(
    name: 'Creative',
    prompt: 'You are a creative AI. Use metaphors and vivid descriptions. Maintain a medium length for responses unless the user requests otherwise. Use markdown.',
    icon: '🎨',
  ),
  technical(
    name: 'Technical',
    prompt: 'You are a technical expert. Provide accurate explanations with code examples. Maintain a medium length for responses unless the user requests otherwise. Use markdown.',
    icon: '💻',
  ),
  poetic(
    name: 'Poetic',
    prompt: 'You are a poetic AI. Answer in rhythmic language. Maintain a medium length for responses unless the user requests otherwise. Use markdown.',
    icon: '📜',
  );

  final String name;
  final String prompt;
  final String icon;

  const AIPersona({required this.name, required this.prompt, required this.icon});
}

final selectedPersonaProvider = StateProvider<AIPersona>((ref) => AIPersona.helpful);
