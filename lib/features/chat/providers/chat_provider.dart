import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../../shared/models/msg.dart';
import '../../../shared/models/chat_session.dart';
import '../../../shared/services/ai_service.dart';
import '../../auth/providers/auth_provider.dart';

import 'persona_provider.dart';
import '../../../core/config.dart';

final activeChatIdProvider = StateProvider<String?>((ref) => null);

final chatSearchProvider = StateProvider<String>((ref) => '');

final chatMessagesProvider = StreamProvider.autoDispose<List<Msg>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  final chatId = ref.watch(activeChatIdProvider);
  if (uid == null || chatId == null) return Stream.value([]);
  return ref.watch(firebaseServiceProvider).getMessages(uid, chatId);
});

final selectedModelProvider =
    StateProvider<String>((ref) => Config.groqModels.first);

class ChatNotifier extends StateNotifier<bool> {
  final Ref ref;

  StreamSubscription? _subscription;
  http.Client? _streamClient; // owned HTTP client – closed on stop()
  bool _isStopped = false;

  // Keep the latest bot message so stopResponse() always saves accurate text
  Msg? _currentBotMsg;
  String? _currentChatId;

  ChatNotifier(this.ref) : super(false);

  // ──────────────────────────────────────────────
  //  STOP – immediately aborts HTTP + saves current partial response
  // ──────────────────────────────────────────────
  void stopResponse() async {
    _isStopped = true;

    // Close the HTTP connection right away so no more chunks arrive
    _streamClient?.close();
    _streamClient = null;

    await _subscription?.cancel();
    _subscription = null;

    final uid = ref.read(currentUserProvider)?.uid;

    // Save whatever text we have so far (accurate, not from delayed stream)
    if (uid != null && _currentBotMsg != null && _currentChatId != null) {
      final partial = _currentBotMsg!.copyWith(status: MsgStatus.sent);
      await ref
          .read(firebaseServiceProvider)
          .saveMessage(uid, _currentChatId!, partial);
    }

    _currentBotMsg = null;
    _currentChatId = null;
    state = false;
  }

  // ──────────────────────────────────────────────
  //  SEND
  // ──────────────────────────────────────────────
  Future<void> sendMessage(
    String text, {
    String? fileName,
    String? fileType,
    String? fileUrl,
    String? mimeType,
    String? localFileData,
    String? docContent,
  }) async {
    final uid = ref.read(currentUserProvider)?.uid;
    var chatId = ref.read(activeChatIdProvider);
    if (uid == null) return;

    _isStopped = false;

    final bool isNewChat = (chatId == null);

    if (chatId == null) {
      chatId = await ref.read(firebaseServiceProvider).createChat(uid);
      ref.read(activeChatIdProvider.notifier).state = chatId;
    }

    final String finalChatId = chatId;
    _currentChatId = finalChatId;

    // Build visible user message text
    String displayText = text;
    if (fileType == 'doc' && fileName != null) {
      displayText = 'Attached Document: $fileName\n\n$text';
    }

    final userMsg = Msg(
      id: const Uuid().v4(),
      text: displayText,
      isUser: true,
      time: DateTime.now(),
      fileName: fileName,
      fileType: fileType,
      fileUrl: fileUrl,
      mimeType: mimeType,
      status: MsgStatus.sent,
    );

    await ref
        .read(firebaseServiceProvider)
        .saveMessage(uid, finalChatId, userMsg);

    if (isNewChat) {
      _setTitle(uid, finalChatId, text);
    }

    state = true;

    try {
      final messages = ref.read(chatMessagesProvider).value ?? [];
      final botMsgId = const Uuid().v4();
      String fullResponse = '';
      final persona = ref.read(selectedPersonaProvider);

      // ── IMAGE ──────────────────────────────────
      if (fileType == 'image' && localFileData != null) {
        fullResponse = await AIService.sendGroqVision(
          prompt: 'System Instruction: ${persona.prompt}\n\nUser Question: $text',
          base64Image: localFileData,
          mimeType: mimeType ?? 'image/jpeg',
          // Uses llama-4-scout (Groq's supported vision model)
          model: 'meta-llama/llama-4-scout-17b-16e-instruct',
        );
        if (!_isStopped) {
          final botMsg = Msg(
              id: botMsgId,
              text: fullResponse,
              isUser: false,
              time: DateTime.now());
          await ref
              .read(firebaseServiceProvider)
              .saveMessage(uid, finalChatId, botMsg);
        }
        state = false;
        _currentBotMsg = null;
        _currentChatId = null;
      } else {
        // ── TEXT / DOCUMENT ────────────────────────
        List<Msg> history = [...messages];

        if (fileType == 'doc' && docContent != null) {
          final docPromptMsg = Msg(
            id: 'doc-context',
            isUser: true,
            time: DateTime.now(),
            text: 'CONTEXT – DOCUMENT CONTENT:\n$docContent\n\n'
                'INSTRUCTION: The user uploaded a document. Use the above '
                'content to answer their question: $text',
          );
          history.add(docPromptMsg);
        } else {
          history.add(userMsg);
        }

        final model = ref.read(selectedModelProvider);

        var botMsg = Msg(
          id: botMsgId,
          text: '',
          isUser: false,
          time: DateTime.now(),
          status: MsgStatus.sending,
        );
        _currentBotMsg = botMsg;

        await ref
            .read(firebaseServiceProvider)
            .saveMessage(uid, finalChatId, botMsg);

        // Create a new HTTP client for this stream so stop() can kill it
        _streamClient = http.Client();

        final stream = AIService.streamGroq(
          history,
          model: model,
          systemPrompt: persona.prompt,
          client: _streamClient,
        );

        _subscription = stream.listen(
          (delta) async {
            // Guard 1: before any work
            if (_isStopped) return;

            fullResponse += delta;
            botMsg = botMsg.copyWith(text: fullResponse);
            _currentBotMsg = botMsg;

            // Guard 2: before network write
            if (_isStopped) return;

            await ref
                .read(firebaseServiceProvider)
                .saveMessage(uid, finalChatId, botMsg);
          },
          onDone: () async {
            if (!_isStopped) {
              final finished = botMsg.copyWith(status: MsgStatus.sent);
              _currentBotMsg = finished;
              await ref
                  .read(firebaseServiceProvider)
                  .saveMessage(uid, finalChatId, finished);
              state = false;
            }
            _streamClient = null;
            _currentBotMsg = null;
            _currentChatId = null;
            _subscription = null;
          },
          onError: (e) async {
            if (!_isStopped) {
              String errorText = 'Error: $e';
              if (e.toString().contains('429')) {
                errorText =
                    '⚠️ AI quota exceeded. Please wait a few seconds and try again.';
              }
              final errorMsg = Msg(
                id: const Uuid().v4(),
                text: errorText,
                isUser: false,
                time: DateTime.now(),
                status: MsgStatus.error,
              );
              await ref
                  .read(firebaseServiceProvider)
                  .saveMessage(uid, finalChatId, errorMsg);
              state = false;
            }
            _streamClient = null;
            _currentBotMsg = null;
            _currentChatId = null;
            _subscription = null;
          },
        );
      }
    } catch (e) {
      if (!_isStopped) {
        String errorText = 'Error: $e';
        if (e.toString().contains('429')) {
          errorText =
              '⚠️ AI quota exceeded. Please wait a few seconds and try again.';
        }
        final errorMsg = Msg(
          id: const Uuid().v4(),
          text: errorText,
          isUser: false,
          time: DateTime.now(),
          status: MsgStatus.error,
        );
        await ref
            .read(firebaseServiceProvider)
            .saveMessage(uid, finalChatId, errorMsg);
        state = false;
      }
      _streamClient = null;
      _currentBotMsg = null;
      _currentChatId = null;
    }
  }

  // ──────────────────────────────────────────────
  //  AUTO-TITLE – sets fallback immediately, then tries AI
  // ──────────────────────────────────────────────
  void _setTitle(String uid, String chatId, String text) async {
    // Step 1: immediate fallback from first words (always succeeds)
    final words = text.trim().split(RegExp(r'\s+')).take(5).join(' ');
    final fallback = words.length > 40 ? '${words.substring(0, 40)}…' : words;
    if (fallback.isNotEmpty) {
      await ref
          .read(firebaseServiceProvider)
          .updateChatTitle(uid, chatId, fallback);
    }

    // Step 2: ask AI for a better title (may fail silently)
    try {
      final history = [
        Msg(id: 'temp', text: text, isUser: true, time: DateTime.now())
      ];
      final aiTitle = await AIService.sendGroq(
        history,
        systemPrompt: 'Create a short, descriptive chat title in 3-5 words. '
            'Reply ONLY with the title. No quotes, no punctuation.',
        model: 'openai/gpt-oss-20b',
      );
      final clean = aiTitle.replaceAll('"', '').replaceAll("'", '').trim();
      if (clean.isNotEmpty) {
        await ref
            .read(firebaseServiceProvider)
            .updateChatTitle(uid, chatId, clean);
      }
    } catch (_) {
      // AI title failed – fallback from step 1 remains, which is fine
    }
  }

  // ──────────────────────────────────────────────
  //  REGENERATE
  // ──────────────────────────────────────────────
  Future<void> regenerateLast() async {
    final messages = ref.read(chatMessagesProvider).value ?? [];
    if (messages.isEmpty) return;
    final lastUserIdx = messages.lastIndexWhere((m) => m.isUser);
    if (lastUserIdx == -1) return;
    final lastUserMsg = messages[lastUserIdx];
    sendMessage(
      lastUserMsg.text,
      fileName: lastUserMsg.fileName,
      fileType: lastUserMsg.fileType,
      fileUrl: lastUserMsg.fileUrl,
      mimeType: lastUserMsg.mimeType,
    );
  }
}

final chatNotifierProvider =
    StateNotifierProvider<ChatNotifier, bool>((ref) => ChatNotifier(ref));

final chatSessionsProvider = StreamProvider<List<ChatSession>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  final search = ref.watch(chatSearchProvider).toLowerCase();
  if (uid == null) return Stream.value([]);
  return ref.watch(firebaseServiceProvider).getChatSessions(uid).map((list) {
    if (search.isEmpty) return list;
    return list.where((s) => s.title.toLowerCase().contains(search)).toList();
  });
});
