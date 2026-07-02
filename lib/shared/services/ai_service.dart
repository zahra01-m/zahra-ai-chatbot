import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config.dart';
import '../models/msg.dart';

class AIService {
  static Future<String> sendGroq(
      List<Msg> history, {
        String? model,
        String? systemPrompt,
      }) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': systemPrompt ??
            'You are a helpful, friendly AI assistant. Use markdown for formatting.',
      }
    ];

    for (var m in history) {
      messages.add({
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      });
    }

    final response = await http.post(
      Uri.parse(Config.groqUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${Config.groqKey}',
      },
      body: jsonEncode({
        'model': model ?? Config.defaultGroqModel,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 1024,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['choices'][0]['message']['content'];
    } else {
      throw Exception('Groq Error ${response.statusCode}: ${response.body}');
    }
  }

  /// Stream tokens from Groq.
  /// Pass [client] from ChatNotifier so stop() can close it immediately.
  /// If [client] is null a temporary one is created and disposed internally.
  static Stream<String> streamGroq(
      List<Msg> history, {
        String? model,
        String? systemPrompt,
        http.Client? client,
      }) async* {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': systemPrompt ?? 'You are a helpful AI.',
      }
    ];

    for (var m in history) {
      messages.add({
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      });
    }

    final ownClient = client == null;
    final httpClient = client ?? http.Client();

    try {
      final request = http.Request('POST', Uri.parse(Config.groqUrl))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${Config.groqKey}'
        ..body = jsonEncode({
          'model': model ?? Config.defaultGroqModel,
          'messages': messages,
          'temperature': 0.7,
          'stream': true,
        });

      final response = await httpClient.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception('Streaming error ${response.statusCode}: $body');
      }

      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.startsWith('data: ')) {
          final data = chunk.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data);
            final delta = json['choices'][0]['delta']['content'] as String?;
            if (delta != null) yield delta;
          } catch (_) {}
        }
      }
    } finally {
      // Only close if we created the client ourselves
      if (ownClient) httpClient.close();
    }
  }

  /// Vision understanding via Groq (image + text).
  /// Uses llama-4-scout as the supported vision model.
  static Future<String> sendGroqVision({
    required String prompt,
    required String base64Image,
    required String mimeType,
    String? model,
  }) async {
    final response = await http.post(
      Uri.parse(Config.groqUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${Config.groqKey}',
      },
      body: jsonEncode({
        // llama-4-scout is the current supported vision model on Groq
        'model': model ?? 'meta-llama/llama-4-scout-17b-16e-instruct',
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': prompt.isEmpty ? 'Describe this image in detail.' : prompt
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$mimeType;base64,$base64Image',
                },
              },
            ],
          }
        ],
        'temperature': 0.7,
        'max_tokens': 1024,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['choices'][0]['message']['content'];
    } else {
      throw Exception(
          'Groq Vision Error ${response.statusCode}: ${response.body}');
    }
  }

  static Future<String> sendGeminiVision({
    required String prompt,
    required String base64Image,
    required String mimeType,
  }) async {
    final response = await http.post(
      Uri.parse('${Config.geminiUrl}?key=${Config.geminiKey}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'inline_data': {
                  'mime_type': mimeType,
                  'data': base64Image,
                }
              },
              {'text': prompt.isEmpty ? 'Describe this image' : prompt},
            ]
          }
        ],
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['candidates'][0]['content']['parts'][0]
      ['text'];
    } else {
      throw Exception(
          'Gemini Error ${response.statusCode}: ${response.body}');
    }
  }
}