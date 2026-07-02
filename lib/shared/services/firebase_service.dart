import 'dart:typed_data';
import 'package:flutter/material.dart' hide Column;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/config.dart'; // Add this import
import '../models/msg.dart';
import '../models/chat_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

class FirebaseService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  // Initialize with serverClientId for robust Android/iOS auth
  late final _google = GoogleSignIn(
    serverClientId: Config.googleClientId,
  );

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ──────────────────────────────────────────────────────────────
  //  FIXED: Google Sign-In
  //  Error was: appClientId != null  (google_sign_in_web requires
  //  a Web OAuth clientId, but Config.googleClientId was empty)
  //  Solution: On web → use Firebase popup (no clientId needed).
  //            On mobile → keep using google_sign_in package.
  // ──────────────────────────────────────────────────────────────
  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      // Web: Firebase Auth popup handles Google OAuth automatically
      final provider = GoogleAuthProvider();
      return await _auth.signInWithPopup(provider);
    } else {
      // Android / iOS: use google_sign_in package
      final gUser = await _google.signIn();
      if (gUser == null) return null;
      final gAuth = await gUser.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );
      return await _auth.signInWithCredential(cred);
    }
  }

  Future<void> signOut() async {
    if (!kIsWeb) await _google.signOut(); // google_sign_in signOut not needed on web
    await _auth.signOut();
  }

  // Email/Password Auth
  Future<UserCredential> signUpWithEmail(String email, String password, {String? displayName}) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    if (displayName != null) {
      await cred.user?.updateDisplayName(displayName);
      await _db.collection('users').doc(cred.user!.uid).set({
        'name': displayName,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return cred;
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
        email: email, password: password);
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // Chats
  Stream<List<ChatSession>> getChatSessions(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) =>
        s.docs.map((d) => ChatSession.fromFirestore(d.data(), d.id)).toList());
  }

  Future<String> createChat(String uid, {String title = 'New Chat'}) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .add({
      'title': title,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> updateChatTitle(
      String uid, String chatId, String title) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .doc(chatId)
        .update({'title': title});
  }

  Future<void> deleteChat(String uid, String chatId) async {
    final msgs = await _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .get();
    final batch = _db.batch();
    for (var doc in msgs.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(
        _db.collection('users').doc(uid).collection('chats').doc(chatId));
    await batch.commit();
  }

  // Messages
  Stream<List<Msg>> getMessages(String uid, String chatId) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('time', descending: false)
        .snapshots()
        .map((s) => s.docs.map((d) => Msg.fromFirestore(d.data(), d.id)).toList());
  }

  Future<void> saveMessage(String uid, String chatId, Msg msg) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(msg.id)
        .set(msg.toFirestore());
  }

  Future<void> updateMessageReactions(String uid, String chatId, String msgId,
      Map<String, String> reactions) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(msgId)
        .update({'reactions': reactions});
  }

  Future<void> updateProfilePicture(String uid, String photoUrl) async {
    await _auth.currentUser?.updatePhotoURL(photoUrl);
    await _db.collection('users').doc(uid).update({'photoUrl': photoUrl});
  }

  Future<void> addReaction(String uid, String chatId, String msgId, String emoji) async {
    final docRef = _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(msgId);
    
    await docRef.update({
      'reactions.$uid': emoji,
    });
  }

  // Storage
  Future<String> uploadFile(
      String uid, String fileName, List<int> bytes, String mimeType) async {
    try {
      // Ensure we are using the bucket from options explicitly if default fails
      final storageRef = _storage.ref();
      final bucket = storageRef.bucket;
      
      // Sanitize fileName: remove special characters and spaces
      final sanitizedName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '_');
      final path = 'users/$uid/uploads/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';
      
      final ref = storageRef.child(path);
      
      // Log the attempt for debugging
      print('DEBUG: Starting upload to bucket: $bucket, path: $path');
      
      final task = await ref.putData(
        Uint8List.fromList(bytes), 
        SettableMetadata(contentType: mimeType)
      );

      // Verify task completion
      if (task.state == TaskState.success) {
        final url = await task.ref.getDownloadURL();
        print('DEBUG: Upload success. URL: $url');
        return url;
      } else {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'upload-not-successful',
          message: 'Upload task finished with state: ${task.state}',
        );
      }
    } on FirebaseException catch (e) {
      print('DEBUG: Firebase Storage Error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('DEBUG: Unexpected Upload Error: $e');
      rethrow;
    }
  }
}
