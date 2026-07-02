import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../shared/models/msg.dart';
import '../../../core/theme.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../../auth/providers/auth_provider.dart';

class MessageBubble extends ConsumerStatefulWidget {
  final Msg msg;
  final VoidCallback onRegenerate;

  const MessageBubble({super.key, required this.msg, required this.onRegenerate});

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutQuad),
    ));

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard!'), duration: Duration(seconds: 1)),
    );
  }

  void _react(String emoji) {
    final uid = ref.read(currentUserProvider)?.uid;
    final chatId = ref.read(activeChatIdProvider);
    if (uid != null && chatId != null) {
      ref.read(firebaseServiceProvider).addReaction(uid, chatId, widget.msg.id, emoji);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.msg.isUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isUser) _buildAvatar(false),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isUser 
                            ? (isDark ? AppTheme.pastelLavender.withValues(alpha: 0.2) : AppTheme.pastelLavender) 
                            : (isDark ? AppTheme.pastelPink.withValues(alpha: 0.2) : AppTheme.pastelPink),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isUser ? 20 : 0),
                            bottomRight: Radius.circular(isUser ? 0 : 20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.msg.fileUrl != null && widget.msg.fileType == 'image')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(widget.msg.fileUrl!),
                                ),
                              ),
                            if (widget.msg.fileType == 'doc')
                               Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black12,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.description_rounded, size: 20, color: Color(0xFFAD1457)),
                                      const SizedBox(width: 8),
                                      Text(widget.msg.fileName ?? 'Document', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            MarkdownBody(
                              data: widget.msg.text,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(color: isDark ? Colors.white : AppTheme.textDark, fontSize: 15),
                                code: const TextStyle(
                                    backgroundColor: Colors.black12, color: Colors.indigoAccent),
                              ),
                            ),
                            if (!isUser && widget.msg.status == MsgStatus.sent)
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.grey),
                                      onPressed: () => _copyToClipboard(widget.msg.text),
                                      tooltip: 'Copy Response',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.grey),
                                      onPressed: widget.onRegenerate,
                                      tooltip: 'Regenerate',
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isUser) _buildAvatar(true),
                  ],
                ),
                if (!isUser && widget.msg.status != MsgStatus.sending)
                  Padding(
                    padding: const EdgeInsets.only(left: 44, top: 4),
                    child: Row(
                      children: [
                        _buildMiniAction(Icons.thumb_up_off_alt_rounded, () => _react('👍'), 'Like'),
                        const SizedBox(width: 4),
                        _buildMiniAction(Icons.thumb_down_off_alt_rounded, () => _react('👎'), 'Dislike'),
                        if (widget.msg.reactions != null && widget.msg.reactions!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            widget.msg.reactions!.values.join(' '),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniAction(IconData icon, VoidCallback onTap, String tooltip) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Icon(icon, size: 18, color: AppTheme.textLight.withValues(alpha: 0.6)),
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    final photoUrl = ref.watch(currentUserProvider)?.photoURL;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: isUser ? AppTheme.pastelLavender : AppTheme.pastelPink, width: 2),
      ),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: isUser ? AppTheme.pastelMint : AppTheme.pastelAqua,
        backgroundImage: (isUser && photoUrl != null) ? NetworkImage(photoUrl) : null,
        child: (isUser && photoUrl == null) 
            ? Icon(Icons.person_rounded, size: 18, color: const Color(0xFFAD1457))
            : (!isUser ? Icon(Icons.auto_awesome_rounded, size: 18, color: const Color(0xFFAD1457)) : null),
      ),
    );
  }
}
