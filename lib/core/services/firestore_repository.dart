import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../../features/auth/domain/models/app_user.dart';

class FirestoreRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  FirestoreRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  Future<T> _retryOnPermissionDenied<T>(Future<T> Function() operation) async {
    int attempts = 0;
    while (true) {
      try {
        return await operation();
      } catch (e) {
        final errorStr = e.toString();
        if (errorStr.contains('permission-denied') || errorStr.contains('Permission denied')) {
          attempts++;
          if (attempts >= 4) {
            rethrow;
          }
          debugPrint('[FirestoreRepository] Firestore operation permission-denied (attempt $attempts). Retrying in ${300 * attempts}ms...');
          await Future.delayed(Duration(milliseconds: 300 * attempts));
        } else {
          rethrow;
        }
      }
    }
  }

  void _verifyAuth() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User not authenticated");
    }
    debugPrint('[FirestoreRepository] Authenticated user active: UID=${user.uid}, Email=${user.email}, DisplayName=${user.displayName}');
  }

  // ─────────────────────────── USER PROFILE ───────────────────────────

  Future<void> saveUser(AppUser user) async {
    debugPrint('[FirestoreRepository] saveUser: UID ${user.uid}');
    _verifyAuth();
    await _retryOnPermissionDenied(() => _firestore.collection('users').doc(user.uid).set(
          user.toJson(),
          SetOptions(merge: true),
        ));
  }

  Future<AppUser?> getUser(String uid) async {
    debugPrint('[FirestoreRepository] getUser: UID $uid');
    _verifyAuth();
    final doc = await _retryOnPermissionDenied(() => _firestore.collection('users').doc(uid).get());
    if (doc.exists) {
      return AppUser.fromFirestore(doc);
    }
    return null;
  }

  // ─────────────────────────── GENERAL SUBCOLLECTIONS ───────────────────────────

  Future<void> saveDocument({
    required String uid,
    required String collectionName,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    debugPrint('[FirestoreRepository] saveDocument: $collectionName/$docId for user $uid');
    _verifyAuth();
    
    // We sanitize keys or datetime values if necessary.
    // Convert DateTime or Timestamp representations for Firestore.
    final sanitizedData = _sanitizeData(data);

    await _retryOnPermissionDenied(() => _firestore
        .collection('users')
        .doc(uid)
        .collection(collectionName)
        .doc(docId)
        .set(sanitizedData, SetOptions(merge: true)));
  }

  Future<void> deleteDocument({
    required String uid,
    required String collectionName,
    required String docId,
  }) async {
    debugPrint('[FirestoreRepository] deleteDocument: $collectionName/$docId for user $uid');
    _verifyAuth();
    await _retryOnPermissionDenied(() => _firestore
        .collection('users')
        .doc(uid)
        .collection(collectionName)
        .doc(docId)
        .delete());
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getDocuments({
    required String uid,
    required String collectionName,
    DateTime? since,
  }) async {
    debugPrint('[FirestoreRepository] getDocuments: $collectionName for user $uid (since: $since)');
    _verifyAuth();
    
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(uid)
        .collection(collectionName);

    if (since != null) {
      // Query documents updated or synced after 'since'
      // We will look at both 'updatedAt' field in the doc
      query = query.where('updatedAt', isGreaterThan: Timestamp.fromDate(since));
    }

    final snapshot = await _retryOnPermissionDenied(() => query.get());
    return snapshot.docs;
  }

  // ─────────────────────────── PROFILE SETTINGS ───────────────────────────

  Future<void> saveProfileSettings(String uid, Map<String, dynamic> settings) async {
    debugPrint('[FirestoreRepository] saveProfileSettings: user $uid');
    _verifyAuth();
    await _retryOnPermissionDenied(() => _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('profile')
        .set(settings, SetOptions(merge: true)));
  }

  Future<Map<String, dynamic>?> getProfileSettings(String uid) async {
    debugPrint('[FirestoreRepository] getProfileSettings: user $uid');
    _verifyAuth();
    final doc = await _retryOnPermissionDenied(() => _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('profile')
        .get());
    return doc.data();
  }

  // ─────────────────────────── PROFILE STATISTICS ───────────────────────────

  Future<void> saveProfileStatistics(String uid, Map<String, dynamic> stats) async {
    debugPrint('[FirestoreRepository] saveProfileStatistics: user $uid');
    _verifyAuth();
    await _retryOnPermissionDenied(() => _firestore
        .collection('users')
        .doc(uid)
        .collection('statistics')
        .doc('profile')
        .set(stats, SetOptions(merge: true)));
  }

  Future<Map<String, dynamic>?> getProfileStatistics(String uid) async {
    debugPrint('[FirestoreRepository] getProfileStatistics: user $uid');
    _verifyAuth();
    final doc = await _retryOnPermissionDenied(() => _firestore
        .collection('users')
        .doc(uid)
        .collection('statistics')
        .doc('profile')
        .get());
    return doc.data();
  }

  // ─────────────────────────── FIREBASE STORAGE ATTACHMENTS ───────────────────────────

  /// Upload file to storage and return attachment metadata to be stored in Firestore
  Future<Map<String, dynamic>> uploadAttachmentFile({
    required String uid,
    required String fileId,
    required String localPath,
    required String fileName,
    required String mimeType,
  }) async {
    debugPrint('[FirestoreRepository] uploadAttachmentFile: uploading $fileName for user $uid');
    
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileNotFoundException(localPath);
    }

    final storagePath = 'users/$uid/attachments/$fileId/$fileName';
    final ref = _storage.ref().child(storagePath);
    
    final uploadTask = ref.putFile(
      file,
      SettableMetadata(contentType: mimeType),
    );

    // Track progress if needed, otherwise await completion
    final snapshot = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();
    final size = await file.length();

    return {
      'id': fileId,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'type': mimeType,
      'size': size,
      'createdAt': Timestamp.now(),
    };
  }

  Future<void> deleteAttachmentFile(String storagePath) async {
    debugPrint('[FirestoreRepository] deleteAttachmentFile: deleting storage path $storagePath');
    try {
      await _storage.ref().child(storagePath).delete();
    } catch (e) {
      debugPrint('[FirestoreRepository] deleteAttachmentFile WARNING: $e');
    }
  }

  // Helper to sanitize data for Firestore (convert ISO strings or timestamps correctly)
  Map<String, dynamic> _sanitizeData(Map<String, dynamic> data) {
    final sanitized = <String, dynamic>{};
    data.forEach((key, value) {
      if (value is DateTime) {
        sanitized[key] = Timestamp.fromDate(value);
      } else if (value is Map<String, dynamic>) {
        sanitized[key] = _sanitizeData(value);
      } else if (value is List) {
        sanitized[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _sanitizeData(item);
          }
          if (item is DateTime) {
            return Timestamp.fromDate(item);
          }
          return item;
        }).toList();
      } else {
        sanitized[key] = value;
      }
    });
    return sanitized;
  }
}

class FileNotFoundException implements Exception {
  final String path;
  FileNotFoundException(this.path);
  @override
  String toString() => 'File not found at: $path';
}
