import 'package:cloud_firestore/cloud_firestore.dart';

enum MsgStatus { sending, sent, error }

class Msg {
  final String id;
  final String text;
  final bool isUser;
  final DateTime time;
  final String? fileName;
  final String? fileType;   // 'image' | 'text' | 'pdf' | 'docx'
  final String? fileUrl;
  final String? mimeType;
  final MsgStatus status;
  final Map<String, String>? reactions; // emoji -> count or user list

  Msg({
    required this.id,
    required this.text,
    required this.isUser,
    required this.time,
    this.fileName,
    this.fileType,
    this.fileUrl,
    this.mimeType,
    this.status = MsgStatus.sent,
    this.reactions,
  });

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'text': text,
    'isUser': isUser,
    'time': Timestamp.fromDate(time),
    'fileName': fileName,
    'fileType': fileType,
    'fileUrl': fileUrl,
    'mimeType': mimeType,
    'status': status.name,
    'reactions': reactions,
  };

  factory Msg.fromFirestore(Map<String, dynamic> j, String docId) => Msg(
    id: docId,
    text: j['text'] as String? ?? '',
    isUser: j['isUser'] as bool? ?? false,
    time: (j['time'] as Timestamp?)?.toDate() ?? DateTime.now(),
    fileName: j['fileName'] as String?,
    fileType: j['fileType'] as String?,
    fileUrl: j['fileUrl'] as String?,
    mimeType: j['mimeType'] as String?,
    status: MsgStatus.values.firstWhere((e) => e.name == j['status'], orElse: () => MsgStatus.sent),
    reactions: (j['reactions'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())),
  );

  Msg copyWith({
    String? text,
    MsgStatus? status,
    Map<String, String>? reactions,
  }) => Msg(
    id: id,
    text: text ?? this.text,
    isUser: isUser,
    time: time,
    fileName: fileName,
    fileType: fileType,
    fileUrl: fileUrl,
    mimeType: mimeType,
    status: status ?? this.status,
    reactions: reactions ?? this.reactions,
  );
}
