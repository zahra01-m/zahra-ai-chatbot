import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:archive/archive.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../../../core/theme.dart';
import '../../../core/config.dart';
import '../../auth/providers/auth_provider.dart';

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/persona_provider.dart';
import '../../profile/views/profile_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isUploading = false;  // tracks Firebase Storage upload progress

  XFile? _selectedImage;
  Uint8List? _imageBytes;
  String? _base64Image;
  String _imageMimeType = 'image/jpeg';

  PlatformFile? _selectedDoc;
  String? _docContent;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  void _toBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _detectMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _exportChat() async {
    final messages = ref.read(chatMessagesProvider).value;
    if (messages == null || messages.isEmpty) return;
    final String content = messages
        .map((m) => '${m.isUser ? "User" : "AI"}: ${m.text}')
        .join('\n\n');
    final directory = await getTemporaryDirectory();
    final file = File(
        '${directory.path}/chat_export_${DateTime.now().millisecondsSinceEpoch}.txt');
    await file.writeAsString(content);
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], text: 'Chat Export'));
  }

  Future<void> _showSignOutDialog() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.pastelPink,
        title: const Text('Sign Out'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign Out')),
        ],
      ),
    );
    if (result == true) ref.read(firebaseServiceProvider).signOut();
  }

  Future<void> _showDeleteChatDialog(String chatId) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.pastelYellow,
        title: const Text('Delete Chat'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (result == true) {
      final uid = ref.read(currentUserProvider)?.uid;
      if (uid != null) {
        await ref.read(firebaseServiceProvider).deleteChat(uid, chatId);
        if (ref.read(activeChatIdProvider) == chatId) {
          ref.read(activeChatIdProvider.notifier).state = null;
        }
      }
    }
  }

  // ──────────────────────────────────────────────
  //  FILE PICKER – supports PDF, DOCX, TXT and code files
  // ──────────────────────────────────────────────
  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'doc', 'txt', 'csv', 'dart', 'py'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    String content = '';
    String? extractionError;

    try {
      final ext = (file.extension ?? '').toLowerCase();

      if (ext == 'pdf') {
        // ── PDF ──────────────────────────────────
        final PdfDocument document = PdfDocument(inputBytes: file.bytes);
        content = PdfTextExtractor(document).extractText();
        document.dispose();

      } else if (ext == 'docx' || ext == 'doc') {
        // ── DOCX / DOC ───────────────────────────
        // DOCX is a ZIP archive; unpack word/document.xml for text
        try {
          final archive = ZipDecoder().decodeBytes(file.bytes!);
          final docEntry = archive.firstWhereOrNull(
                (f) => f.name == 'word/document.xml',
          );

          if (docEntry != null && docEntry.isFile) {
            final xmlStr =
            utf8.decode(docEntry.content as List<int>, allowMalformed: true);
            // Pull text from <w:t> elements; paragraphs separated by newlines
            content = xmlStr
                .replaceAllMapped(
              RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true),
                  (m) => m.group(1) ?? '',
            )
                .replaceAll(RegExp(r'</w:p>'), '\n')
                .replaceAll(RegExp(r'<[^>]+>'), '')
                .replaceAll(RegExp(r'[ \t]+'), ' ')
                .trim();

            if (content.isEmpty) {
              extractionError =
              'The document appears to be empty or uses an unsupported format.';
            }
          } else {
            extractionError = 'Could not find document content inside the file.';
          }
        } catch (zipErr) {
          extractionError = 'Could not read DOCX file: $zipErr';
        }

      } else {
        // ── Plain text / code files ───────────────
        content = utf8.decode(file.bytes!, allowMalformed: true);
      }
    } catch (e) {
      debugPrint('File extraction error: $e');
      extractionError = 'Could not extract text from this file.';
    }

    if (extractionError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(extractionError!),
            backgroundColor: Colors.red.shade400,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      // Still allow sending – AI gets an empty/error context
      content = '(File could not be read: $extractionError)';
    }

    // Truncate to avoid exceeding Groq's context window (~8 000 chars ≈ 2 000 tokens)
    const maxChars = 8000;
    if (content.length > maxChars) {
      content =
      '${content.substring(0, maxChars)}\n\n[Document truncated – showing first ~8 000 characters]';
    }

    setState(() {
      _selectedDoc = file;
      _docContent = content;
    });

    if (_ctrl.text.isEmpty) _ctrl.text = 'Please analyze this document';
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image =
    await picker.pickImage(source: source, imageQuality: 85);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    final mime = _detectMimeType(image.path);
    setState(() {
      _selectedImage = image;
      _imageBytes = bytes;
      _base64Image = base64Encode(bytes);
      _imageMimeType = mime;
    });
    if (_ctrl.text.isEmpty) _ctrl.text = 'Describe this image';
  }

  Future<void> _toggleVoice() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
            onResult: (val) =>
                setState(() => _ctrl.text = val.recognizedWords));
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _onSend() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _selectedImage == null && _selectedDoc == null) return;
    final notifier = ref.read(chatNotifierProvider.notifier);
    final uid = ref.read(currentUserProvider)?.uid;
    String? fileUrl;

    if (_selectedImage != null) {
      if (uid != null && _imageBytes != null) {
        // Fix Issue 3: show upload progress before calling notifier
        setState(() => _isUploading = true);
        try {
          fileUrl = await ref
              .read(firebaseServiceProvider)
              .uploadFile(uid, _selectedImage!.name, _imageBytes!, _imageMimeType);
        } catch (e) {
          debugPrint('Upload error: $e');
        } finally {
          setState(() => _isUploading = false);
        }
      }
      notifier.sendMessage(
        text.isEmpty ? 'Describe image' : text,
        fileType: 'image',
        fileUrl: fileUrl,
        fileName: _selectedImage!.name, // Fix Issue 1: pass fileName
        localFileData: _base64Image,
        mimeType: _imageMimeType,
      );
    } else if (_selectedDoc != null) {
      if (uid != null && _selectedDoc!.bytes != null) {
        try {
          final ext = _selectedDoc!.extension?.toLowerCase() ?? 'txt';
          final mime = ext == 'pdf' ? 'application/pdf' : 'text/plain';
          fileUrl = await ref
              .read(firebaseServiceProvider)
              .uploadFile(uid, _selectedDoc!.name, _selectedDoc!.bytes!, mime);
        } catch (e) {
          debugPrint('Upload error: $e');
        }
      }
      notifier.sendMessage(
        text,
        fileType: 'doc',
        fileName: _selectedDoc!.name,
        fileUrl: fileUrl,
        docContent: _docContent,
      );
    } else {
      notifier.sendMessage(text);
    }

    _ctrl.clear();
    setState(() {
      _selectedImage = null;
      _imageBytes = null;
      _base64Image = null;
      _selectedDoc = null;
      _docContent = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider);
    final sessionsAsync = ref.watch(chatSessionsProvider);
    final isLoading = ref.watch(chatNotifierProvider);
    final selectedModel = ref.watch(selectedModelProvider);
    final selectedPersona = ref.watch(selectedPersonaProvider);
    final user = ref.watch(currentUserProvider);
    final activeChatId = ref.watch(activeChatIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zahra AI'),
        actions: [
          IconButton(
              icon: const Icon(Icons.download_rounded), onPressed: _exportChat),
          PopupMenuButton<AIPersona>(
            icon: Text(selectedPersona.icon),
            onSelected: (p) =>
            ref.read(selectedPersonaProvider.notifier).state = p,
            itemBuilder: (context) => AIPersona.values
                .map((p) => PopupMenuItem(
                value: p,
                child: Row(children: [
                  Text(p.icon),
                  const SizedBox(width: 8),
                  Text(p.name)
                ])))
                .toList(),
          ),
          // Deduplicate model list and ensure current value exists in it
          Builder(builder: (context) {
            final modelList = Config.groqModels.toSet().toList();
            final safeModel = modelList.contains(selectedModel)
                ? selectedModel
                : modelList.first;
            return DropdownButton<String>(
              underline: const SizedBox(),
              value: safeModel,
              items: modelList
                  .map((m) => DropdownMenuItem(
                  value: m,
                  child: Text(m.split('/').last,
                      style: const TextStyle(fontSize: 10))))
                  .toList(),
              onChanged: (v) {
                if (v != null)
                  ref.read(selectedModelProvider.notifier).state = v;
              },
            );
          }),
        ],
      ),
      drawer: Drawer(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                margin: EdgeInsets.zero,
                decoration:
                const BoxDecoration(color: AppTheme.pastelLavender),
                currentAccountPicture: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()));
                  },
                  child: CircleAvatar(
                    backgroundColor: AppTheme.pastelPink,
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? Text(
                        user?.displayName
                            ?.substring(0, 1)
                            .toUpperCase() ??
                            'U',
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold))
                        : null,
                  ),
                ),
                accountName: Text(user?.displayName ?? 'User',
                    style: const TextStyle(color: AppTheme.textDark)),
                accountEmail: Text(user?.email ?? '',
                    style: const TextStyle(color: AppTheme.textLight)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Search...',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (v) =>
                  ref.read(chatSearchProvider.notifier).state = v,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('New Chat'),
                onTap: () {
                  ref.read(activeChatIdProvider.notifier).state = null;
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              Expanded(
                child: sessionsAsync.when(
                  data: (sessions) => ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: sessions.length,
                    itemBuilder: (context, i) => ListTile(
                      selected: activeChatId == sessions[i].id,
                      title: Text(sessions[i].title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () =>
                              _showDeleteChatDialog(sessions[i].id)),
                      onTap: () {
                        ref.read(activeChatIdProvider.notifier).state =
                            sessions[i].id;
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  loading: () =>
                  const Center(child: CircularProgressIndicator()),
                  error: (e, s) => Center(child: Text('Error: $e')),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout_rounded,
                    color: Colors.redAccent),
                title: const Text('Sign Out'),
                onTap: _showSignOutDialog,
              ),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppTheme.pastelYellow, AppTheme.pastelMint])),
        child: Column(
          children: [
            Expanded(
              child: messagesAsync.when(
                data: (msgs) {
                  _toBottom();
                  if (msgs.isEmpty) return _buildEmptyState();
                  return ListView.builder(
                    controller: _scroll,
                    itemCount: msgs.length,
                    itemBuilder: (context, i) => MessageBubble(
                      msg: msgs[i],
                      onRegenerate: () =>
                          ref.read(chatNotifierProvider.notifier).regenerateLast(),
                    ),
                  );
                },
                loading: () =>
                const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text('Error: $e')),
              ),
            ),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.only(left: 20, bottom: 8),
                child: Row(children: [
                  SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Thinking...',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textLight)),
                ]),
              ),
            _buildInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final suggestions = [
      'Write a funny poem',
      'Explain Quantum Physics',
      'Plan a 3-day trip'
    ];
    return Center(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 80, color: Color(0xFFAD1457)),
            const SizedBox(height: 16),
            const Text('How can I help?',
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: suggestions
                  .map((s) => ActionChip(
                  label: Text(s),
                  onPressed: () {
                    _ctrl.text = s;
                    _onSend();
                  }))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    final isLoading = ref.watch(chatNotifierProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, -5))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Image preview
          if (_imageBytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Stack(children: [
                  Image.memory(_imageBytes!,
                      height: 60, width: 60, fit: BoxFit.cover),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _selectedImage = null;
                        _imageBytes = null;
                        _base64Image = null;           // Fix: clear stale base64
                        _imageMimeType = 'image/jpeg'; // Fix: reset mime type
                      }),
                      child: Container(
                          color: Colors.black54,
                          child: const Icon(Icons.close,
                              size: 16, color: Colors.white)),
                    ),
                  )
                ])
              ]),
            ),
          // Document preview
          if (_selectedDoc != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.description),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(
                      _selectedDoc!.name,
                      overflow: TextOverflow.ellipsis,
                    )),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _selectedDoc = null;
                      _docContent = null;
                    })),
              ]),
            ),
          // Fix Issue 3: upload progress bar
          if (_isUploading)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 3),
                  Text('Uploading image…',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.image),
                        title: const Text('Image'),
                        onTap: () {
                          Navigator.pop(context);
                          _pickImage(ImageSource.gallery);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.camera_alt),
                        title: const Text('Camera'),
                        onTap: () {
                          Navigator.pop(context);
                          _pickImage(ImageSource.camera);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.description),
                        title: const Text('Document (PDF, DOCX, TXT…)'),
                        onTap: () {
                          Navigator.pop(context);
                          _pickFile();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.mic,
                    color: _isListening ? Colors.red : null),
                onPressed: _toggleVoice,
              ),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  maxLines: 4,
                  minLines: 1,
                  decoration: const InputDecoration(
                      hintText: 'Type...', border: InputBorder.none),
                ),
              ),
              if (isLoading)
                IconButton(
                  icon: const Icon(Icons.stop_circle,
                      color: Colors.red, size: 32),
                  onPressed: () =>
                      ref.read(chatNotifierProvider.notifier).stopResponse(),
                )
              else
                CircleAvatar(
                  backgroundColor: const Color(0xFFAD1457),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _onSend,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Extension helper used for DOCX archive lookup
// ──────────────────────────────────────────────
extension _ArchiveX on Archive {
  ArchiveFile? firstWhereOrNull(bool Function(ArchiveFile) test) {
    for (final f in this) {
      if (test(f)) return f;
    }
    return null;
  }
}