import 'package:cloud_firestore/cloud_firestore.dart';

class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final String? model;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    this.model,
  });

  factory ChatSession.fromFirestore(Map<String, dynamic> data, String id) {
    return ChatSession(
      id: id,
      title: data['title'] as String? ?? 'New Chat',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      model: data['model'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'title': title,
    'createdAt': Timestamp.fromDate(createdAt),
    'model': model,
  };
}
