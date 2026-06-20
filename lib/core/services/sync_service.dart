import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'firestore_repository.dart';
import '../network/connectivity_service.dart';

enum SyncState { idle, syncing, success, failure }

class SyncService {
  static final SyncService instance = SyncService._();

  final AppDatabase _db;
  final FirestoreRepository _firestoreRepo;
  final ConnectivityService _connectivity;

  final _syncStateController = StreamController<SyncState>.broadcast();
  SyncState _state = SyncState.idle;
  DateTime? _lastSyncTime;
  String? _errorMessage;

  SyncService._()
      : _db = AppDatabase.instance,
        _firestoreRepo = FirestoreRepository(),
        _connectivity = ConnectivityService.instance {
    // Hook database modification callback to trigger upload
    AppDatabase.onDatabaseModified = () {
      triggerUpload();
    };
  }

  static String compressString(String jsonStr) {
    if (jsonStr.isEmpty) return jsonStr;
    final compressedBase64 = base64Encode(gzip.encode(utf8.encode(jsonStr)));
    return 'gz:$compressedBase64';
  }

  static String decompressString(String? val) {
    if (val == null || val.isEmpty) return '';
    if (val.startsWith('gz:')) {
      final base64Data = val.substring(3);
      return utf8.decode(gzip.decode(base64Decode(base64Data)));
    }
    return val;
  }

  Stream<SyncState> get syncStateStream => _syncStateController.stream;
  SyncState get state => _state;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get errorMessage => _errorMessage;

  void _updateState(SyncState newState, {String? error}) {
    _state = newState;
    _errorMessage = error;
    if (newState == SyncState.success) {
      _lastSyncTime = DateTime.now();
    }
    _syncStateController.add(newState);
    debugPrint('[SyncService] SyncState shifted to: $newState ${error != null ? "- $error" : ""}');
  }

  // ─────────────────────────── MANUAL TRIGGER ───────────────────────────

  Future<void> triggerSync() async {
    if (_state == SyncState.syncing) return;
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[SyncService] Cannot sync: User is not authenticated');
      return;
    }

    final isOnline = await _connectivity.isOnline;
    if (!isOnline) {
      debugPrint('[SyncService] Cannot sync: Device is offline');
      _updateState(SyncState.failure, error: 'Device is offline');
      return;
    }

    _updateState(SyncState.syncing);
    debugPrint('[SyncService] Sync Started');

    try {
      // 1. Process local mutations upload queue
      await uploadPendingQueue(user.uid);
      
      // 2. Fetch updates from cloud and merge
      await downloadUpdates(user.uid);

      // 3. Update stats and last sync time on user profile
      await _updateCloudUserProfile(user.uid);

      _updateState(SyncState.success);
      debugPrint('[SyncService] Sync Completed Successfully');
    } catch (e, stackTrace) {
      debugPrint('[SyncService] Sync Failure: $e');
      debugPrint('[SyncService] StackTrace: $stackTrace');
      _updateState(SyncState.failure, error: _mapSyncError(e));
    }
  }

  Future<void> triggerUpload() async {
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final isOnline = await _connectivity.isOnline;
    if (!isOnline) {
      debugPrint('[SyncService] DB Modified but device offline. Skipping instant upload.');
      return;
    }

    // Run upload in background asynchronously without blocking
    unawaited(
      uploadPendingQueue(user.uid).catchError((e) {
        debugPrint('[SyncService] Auto background upload failed: $e');
      }),
    );
  }

  // ─────────────────────────── UPLOAD PENDING QUEUE ───────────────────────────

  Future<void> uploadPendingQueue(String uid) async {
    final pendingItems = await _db.getPendingSyncItems();
    if (pendingItems.isEmpty) return;

    debugPrint('[SyncService] Processing ${pendingItems.length} pending upload queue items...');

    for (final item in pendingItems) {
      try {
        final table = item.targetTable;
        final docId = item.recordId;
        final operation = item.operation;

        if (operation == 'delete') {
          // Soft delete in Cloud Firestore
          await _firestoreRepo.saveDocument(
            uid: uid,
            collectionName: _getFirestoreCollection(table),
            docId: docId,
            data: {'id': docId, 'isDeleted': true, 'updatedAt': DateTime.now()},
          );
        } else {
          // Read fresh record from local database (latest values)
          final localRecord = await _getLocalRecord(table, docId);
          if (localRecord == null) {
            debugPrint('[SyncService] Upload Warning: Local record not found for table $table, ID $docId');
            await _db.markSynced(item.id);
            continue;
          }

          final localData = localRecord.toJson();
          
          // Conflict Resolution check: Fetch current cloud document updatedAt
          final cloudDocRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection(_getFirestoreCollection(table))
              .doc(docId);
          
          final cloudSnapshot = await cloudDocRef.get();
          if (cloudSnapshot.exists) {
            final cloudData = cloudSnapshot.data()!;
            final cloudUpdatedAt = (cloudData['updatedAt'] as Timestamp?)?.toDate();
            final localUpdatedAtStr = localData['updatedAt'] as String?;
            final localUpdatedAt = localUpdatedAtStr != null ? DateTime.parse(localUpdatedAtStr) : DateTime.now();

            if (cloudUpdatedAt != null && cloudUpdatedAt.isAfter(localUpdatedAt)) {
              debugPrint('[SyncService] Conflict Detected: Firestore version is newer for $table/$docId. Overwriting local with cloud.');
              // Overwrite local record with cloud record
              await _writeLocalRecord(table, cloudData);
              await _db.markSynced(item.id);
              continue;
            }
          }

          // Fetch associated junction values for Notes (tagIds and linkedNoteIds)
          if (table == 'notes') {
            final tagIds = (await _db.getTagsForNote(docId)).map((t) => t.id).toList();
            final linkedNoteIds = (await _db.getForwardLinks(docId)).map((n) => n.id).toList();
            localData['tagIds'] = tagIds;
            localData['linkedNoteIds'] = linkedNoteIds;
          }

          // Compress drawing stroke coordinate arrays for Firebase Storage savings
          if (table == 'drawingStrokes') {
            if (localData['pointsJson'] != null) {
              localData['pointsJson'] = compressString(localData['pointsJson'] as String);
            }
            if (localData['pressureJson'] != null) {
              localData['pressureJson'] = compressString(localData['pressureJson'] as String);
            }
            if (localData['tiltJson'] != null) {
              localData['tiltJson'] = compressString(localData['tiltJson'] as String);
            }
          }

          // Upload to Firestore
          await _firestoreRepo.saveDocument(
            uid: uid,
            collectionName: _getFirestoreCollection(table),
            docId: docId,
            data: localData,
          );
        }

        // Update local database status to 'synced'
        await _updateLocalSyncStatus(table, docId, 'synced');
        // Mark sync queue item as synced
        await _db.markSynced(item.id);
        debugPrint('[SyncService] Upload Success: $table/$docId');
      } catch (e) {
        debugPrint('[SyncService] Upload Error on item ${item.id} ($e). Marking status as failed.');
        await _updateLocalSyncStatus(item.targetTable, item.recordId, 'failed');
        rethrow;
      }
    }

    // Clean up successfully synced queue logs
    await _db.clearSyncedItems();
  }

  // ─────────────────────────── DOWNLOAD UPDATES (DELTA SYNC) ───────────────────────────

  Future<void> downloadUpdates(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncTimeStr = prefs.getString('${uid}_lastSyncTime');
    final lastSync = lastSyncTimeStr != null ? DateTime.parse(lastSyncTimeStr) : null;

    debugPrint('[SyncService] Downloading updates since: $lastSync');

    final collections = [
      'folders',
      'notes',
      'tags',
      'decks',
      'flashCards',
      'reviewHistory',
      'attachments',
      'dailyNotes',
      'studySessions',
      'searchHistory',
      'drawingNotes',
      'drawingPages',
      'drawingStrokes',
    ];

    for (final col in collections) {
      final firestoreCol = _getFirestoreCollection(col);
      final docs = await _firestoreRepo.getDocuments(uid: uid, collectionName: firestoreCol, since: lastSync);

      debugPrint('[SyncService] Downloaded ${docs.length} updates for $firestoreCol');

      for (final doc in docs) {
        final cloudData = doc.data();
        final recordId = doc.id;
        final preparedData = _prepareFirestoreDataForDrift(cloudData);

        // Check if local version exists
        final localRecord = await _getLocalRecord(col, recordId);
        if (localRecord == null) {
          // Insert locally if not present and not deleted
          if (preparedData['isDeleted'] == true) continue;
          await _writeLocalRecord(col, preparedData);
        } else {
          // Merge based on latest updatedAt
          final localData = localRecord.toJson();
          final localUpdatedAtStr = localData['updatedAt'] as String?;
          final localUpdatedAt = localUpdatedAtStr != null ? DateTime.parse(localUpdatedAtStr) : DateTime.now();

          final cloudUpdatedAt = (cloudData['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now();

          if (cloudUpdatedAt.isAfter(localUpdatedAt)) {
            await _writeLocalRecord(col, preparedData);
          } else if (localUpdatedAt.isAfter(cloudUpdatedAt)) {
            // Local is newer: Queue it for upload
            await _db.addToSyncQueue(
              SyncQueueCompanion.insert(
                targetTable: col,
                recordId: recordId,
                operation: 'update',
                payload: Value(jsonEncode(localData)),
                createdAt: Value(DateTime.now()),
              ),
            );
          }
        }
      }
    }

    // Save sync time locally
    await prefs.setString('${uid}_lastSyncTime', DateTime.now().toIso8601String());
  }

  // ─────────────────────────── REINSTALL RESTORE ───────────────────────────

  Future<void> restoreAllData(String uid) async {
    _updateState(SyncState.syncing);
    debugPrint('[SyncService] Full restore starting for UID $uid');

    try {
      // 1. Wipe local database tables (excluding user credentials)
      await _db.transaction(() async {
        await _db.delete(_db.notes).go();
        await _db.delete(_db.folders).go();
        await _db.delete(_db.tags).go();
        await _db.delete(_db.noteTags).go();
        await _db.delete(_db.noteLinks).go();
        await _db.delete(_db.decks).go();
        await _db.delete(_db.flashCards).go();
        await _db.delete(_db.reviewHistory).go();
        await _db.delete(_db.attachments).go();
        await _db.delete(_db.dailyNotes).go();
        await _db.delete(_db.studySessions).go();
        await _db.delete(_db.searchHistory).go();
        await _db.delete(_db.drawingNotes).go();
        await _db.delete(_db.drawingPages).go();
        await _db.delete(_db.drawingStrokes).go();
        await _db.delete(_db.syncQueue).go();
      });

      // 2. Fetch and restore all subcollections from Firestore
      final collections = [
        'folders',
        'notes',
        'tags',
        'decks',
        'flashCards',
        'reviewHistory',
        'attachments',
        'dailyNotes',
        'studySessions',
        'searchHistory',
        'drawingNotes',
        'drawingPages',
        'drawingStrokes',
      ];

      for (final col in collections) {
        final firestoreCol = _getFirestoreCollection(col);
        final docs = await _firestoreRepo.getDocuments(uid: uid, collectionName: firestoreCol);
        debugPrint('[SyncService] Restore: Fetched ${docs.length} items from cloud collection: $firestoreCol');

        for (final doc in docs) {
          final cloudData = doc.data();
          if (cloudData['isDeleted'] == true) continue;
          
          final preparedData = _prepareFirestoreDataForDrift(cloudData);
          await _writeLocalRecord(col, preparedData);
        }
      }

      // 3. Restore profile settings
      await restoreProfileSettings(uid);

      // Save sync timestamp
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${uid}_lastSyncTime', DateTime.now().toIso8601String());

      _updateState(SyncState.success);
      debugPrint('[SyncService] Full restore completed successfully');
    } catch (e, stackTrace) {
      debugPrint('[SyncService] Restore Failure: $e');
      debugPrint('[SyncService] StackTrace: $stackTrace');
      _updateState(SyncState.failure, error: _mapSyncError(e));
      rethrow;
    }
  }

  Future<void> wipeLocalData() async {
    debugPrint('[SyncService] Wiping all local data on logout...');
    final prefs = await SharedPreferences.getInstance();
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user != null) {
      await prefs.remove('${user.uid}_lastSyncTime');
    }
    
    await _db.transaction(() async {
      await _db.deleteAllUsers();
      await _db.delete(_db.notes).go();
      await _db.delete(_db.folders).go();
      await _db.delete(_db.tags).go();
      await _db.delete(_db.noteTags).go();
      await _db.delete(_db.noteLinks).go();
      await _db.delete(_db.decks).go();
      await _db.delete(_db.flashCards).go();
      await _db.delete(_db.reviewHistory).go();
      await _db.delete(_db.attachments).go();
      await _db.delete(_db.dailyNotes).go();
      await _db.delete(_db.studySessions).go();
      await _db.delete(_db.searchHistory).go();
      await _db.delete(_db.drawingNotes).go();
      await _db.delete(_db.drawingPages).go();
      await _db.delete(_db.drawingStrokes).go();
      await _db.delete(_db.syncQueue).go();
    });
    debugPrint('[SyncService] Local data wipe complete.');
  }

  // ─────────────────────────── SETTINGS SYNC ───────────────────────────

  Future<void> backupProfileSettings(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final geminiApiKey = prefs.getString('gemini_api_key');
    
    if (geminiApiKey != null) {
      await _firestoreRepo.saveProfileSettings(uid, {
        'geminiApiKey': geminiApiKey,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[SyncService] Settings backup complete');
    }
  }

  Future<void> restoreProfileSettings(String uid) async {
    final settings = await _firestoreRepo.getProfileSettings(uid);
    if (settings != null && settings['geminiApiKey'] != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gemini_api_key', settings['geminiApiKey'] as String);
      debugPrint('[SyncService] Settings restored: Gemini Key');
    }
  }

  // ─────────────────────────── CLOUD USER PROFILE ───────────────────────────

  Future<void> _updateCloudUserProfile(String uid) async {
    final totalNotes = await _db.countNotes();
    final totalCards = await _db.countAllCards();
    final totalDecks = await (_db.select(_db.decks)..where((d) => d.isDeleted.equals(false))).get().then((v) => v.length);
    final totalFolders = await (_db.select(_db.folders)..where((f) => f.isDeleted.equals(false))).get().then((v) => v.length);
    final totalTags = await (_db.select(_db.tags)..where((t) => t.isDeleted.equals(false))).get().then((v) => v.length);

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await userRef.set({
      'lastSyncAt': FieldValue.serverTimestamp(),
      'totalNotes': totalNotes,
      'totalFlashcards': totalCards,
      'totalDecks': totalDecks,
      'totalFolders': totalFolders,
      'totalTags': totalTags,
    }, SetOptions(merge: true));

    // Also sync dynamic statistics to stats sub-profile
    final stats = await _calculateStatistics();
    await _firestoreRepo.saveProfileStatistics(uid, stats);
  }

  Future<Map<String, dynamic>> _calculateStatistics() async {
    final totalNotes = await _db.countNotes();
    final totalCards = await _db.countAllCards();
    final reviewsToday = await _db.countReviewsToday();
    
    final allSessions = await (_db.select(_db.studySessions)..where((s) => s.isDeleted.equals(false))).get();
    final totalSeconds = allSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final totalStudyTimeMinutes = (totalSeconds / 60).ceil();

    final allReviews = await (_db.select(_db.reviewHistory)..where((r) => r.isDeleted.equals(false))).get();
    final correctReviews = allReviews.where((r) => r.rating >= 3).length;
    final accuracy = allReviews.isNotEmpty ? (correctReviews / allReviews.length * 100) : 0.0;

    return {
      'totalNotes': totalNotes,
      'totalCards': totalCards,
      'reviewsToday': reviewsToday,
      'totalReviews': allReviews.length,
      'totalStudyTimeMinutes': totalStudyTimeMinutes,
      'accuracy': accuracy,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // ─────────────────────────── UTILITY METHODS ───────────────────────────

  String _getFirestoreCollection(String dbTable) {
    switch (dbTable) {
      case 'notes':
        return 'notes';
      case 'folders':
        return 'folders';
      case 'tags':
        return 'tags';
      case 'decks':
        return 'decks';
      case 'flashCards':
        return 'flashcards';
      case 'reviewHistory':
        return 'reviewHistory';
      case 'attachments':
        return 'attachments';
      case 'dailyNotes':
        return 'dailyNotes';
      case 'studySessions':
        return 'studySessions';
      case 'searchHistory':
        return 'searchHistory';
      case 'drawingNotes':
        return 'drawingNotes';
      case 'drawingPages':
        return 'drawingPages';
      case 'drawingStrokes':
        return 'drawingStrokes';
      default:
        throw Exception('Unknown dbTable: $dbTable');
    }
  }

  Future<dynamic> _getLocalRecord(String table, String id) async {
    switch (table) {
      case 'notes':
        return _db.getNoteById(id);
      case 'folders':
        return _db.getFolderById(id);
      case 'tags':
        return _db.getTagById(id);
      case 'decks':
        return _db.getDeckById(id);
      case 'flashCards':
        return _db.getCardById(id);
      case 'reviewHistory':
        return (_db.select(_db.reviewHistory)..where((r) => r.id.equals(id))).getSingleOrNull();
      case 'attachments':
        return _db.getAttachmentById(id);
      case 'dailyNotes':
        return (_db.select(_db.dailyNotes)..where((dn) => dn.id.equals(id))).getSingleOrNull();
      case 'studySessions':
        return (_db.select(_db.studySessions)..where((s) => s.id.equals(id))).getSingleOrNull();
      case 'searchHistory':
        return (_db.select(_db.searchHistory)..where((s) => s.id.equals(id))).getSingleOrNull();
      case 'drawingNotes':
        return _db.getDrawingNoteById(id);
      case 'drawingPages':
        return _db.getDrawingPageById(id);
      case 'drawingStrokes':
        return _db.getDrawingStrokeById(id);
      default:
        return null;
    }
  }

  Future<void> _writeLocalRecord(String table, Map<String, dynamic> data) async {
    await _db.transaction(() async {
      switch (table) {
        case 'notes':
          final record = Note.fromJson(data);
          await _db.into(_db.notes).insertOnConflictUpdate(record);
          
          // Restore note tags if tagIds are present in the JSON payload
          if (data['tagIds'] != null) {
            final tagIds = List<String>.from(data['tagIds']);
            await _db.setTagsForNote(record.id, tagIds);
          }
          // Restore note links if linkedNoteIds are present
          if (data['linkedNoteIds'] != null) {
            final targetIds = List<String>.from(data['linkedNoteIds']);
            await _db.setNoteLinks(record.id, targetIds);
          }
          break;
        case 'folders':
          await _db.into(_db.folders).insertOnConflictUpdate(Folder.fromJson(data));
          break;
        case 'tags':
          await _db.into(_db.tags).insertOnConflictUpdate(Tag.fromJson(data));
          break;
        case 'decks':
          await _db.into(_db.decks).insertOnConflictUpdate(Deck.fromJson(data));
          break;
        case 'flashCards':
          await _db.into(_db.flashCards).insertOnConflictUpdate(FlashCard.fromJson(data));
          break;
        case 'reviewHistory':
          await _db.into(_db.reviewHistory).insertOnConflictUpdate(ReviewHistoryData.fromJson(data));
          break;
        case 'attachments':
          await _db.into(_db.attachments).insertOnConflictUpdate(Attachment.fromJson(data));
          break;
        case 'dailyNotes':
          await _db.into(_db.dailyNotes).insertOnConflictUpdate(DailyNote.fromJson(data));
          break;
        case 'studySessions':
          await _db.into(_db.studySessions).insertOnConflictUpdate(StudySession.fromJson(data));
          break;
        case 'searchHistory':
          await _db.into(_db.searchHistory).insertOnConflictUpdate(SearchHistoryData.fromJson(data));
          break;
        case 'drawingNotes':
          await _db.into(_db.drawingNotes).insertOnConflictUpdate(DrawingNote.fromJson(data));
          break;
        case 'drawingPages':
          await _db.into(_db.drawingPages).insertOnConflictUpdate(DrawingPage.fromJson(data));
          break;
        case 'drawingStrokes':
          if (data['pointsJson'] != null) {
            data['pointsJson'] = decompressString(data['pointsJson'] as String?);
          }
          if (data['pressureJson'] != null) {
            data['pressureJson'] = decompressString(data['pressureJson'] as String?);
          }
          if (data['tiltJson'] != null) {
            data['tiltJson'] = decompressString(data['tiltJson'] as String?);
          }
          await _db.into(_db.drawingStrokes).insertOnConflictUpdate(DrawingStroke.fromJson(data));
          break;
      }
    });
  }

  Future<void> _updateLocalSyncStatus(String table, String id, String status) async {
    final now = DateTime.now();
    switch (table) {
      case 'notes':
        await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
          NotesCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'folders':
        await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
          FoldersCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'tags':
        await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
          TagsCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'decks':
        await (_db.update(_db.decks)..where((d) => d.id.equals(id))).write(
          DecksCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'flashCards':
        await (_db.update(_db.flashCards)..where((c) => c.id.equals(id))).write(
          FlashCardsCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'reviewHistory':
        await (_db.update(_db.reviewHistory)..where((r) => r.id.equals(id))).write(
          ReviewHistoryCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'attachments':
        await (_db.update(_db.attachments)..where((a) => a.id.equals(id))).write(
          AttachmentsCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'dailyNotes':
        await (_db.update(_db.dailyNotes)..where((dn) => dn.id.equals(id))).write(
          DailyNotesCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'studySessions':
        await (_db.update(_db.studySessions)..where((s) => s.id.equals(id))).write(
          StudySessionsCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'searchHistory':
        await (_db.update(_db.searchHistory)..where((s) => s.id.equals(id))).write(
          SearchHistoryCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'drawingNotes':
        await (_db.update(_db.drawingNotes)..where((dn) => dn.id.equals(id))).write(
          DrawingNotesCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'drawingPages':
        await (_db.update(_db.drawingPages)..where((dp) => dp.id.equals(id))).write(
          DrawingPagesCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
      case 'drawingStrokes':
        await (_db.update(_db.drawingStrokes)..where((ds) => ds.id.equals(id))).write(
          DrawingStrokesCompanion(syncStatus: Value(status), lastSyncedAt: Value(now)),
        );
        break;
    }
  }

  Map<String, dynamic> _prepareFirestoreDataForDrift(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    data.forEach((key, value) {
      if (value is Timestamp) {
        result[key] = value.toDate().toIso8601String();
      } else if (value is Map<String, dynamic>) {
        result[key] = _prepareFirestoreDataForDrift(value);
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Timestamp) {
            return item.toDate().toIso8601String();
          }
          if (item is Map<String, dynamic>) {
            return _prepareFirestoreDataForDrift(item);
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  String _mapSyncError(dynamic e) {
    final errorStr = e.toString();
    if (errorStr.contains('permission-denied') || errorStr.contains('Permission denied')) {
      return "We couldn't restore your data because access was denied. Please try again.";
    }
    if (errorStr.contains('network_error') || errorStr.contains('SocketException')) {
      return "We couldn't restore your data due to a network connection issue. Please check your internet and try again.";
    }
    if (errorStr.contains('timeout') || errorStr.contains('TimeoutException')) {
      return "We couldn't restore your data because the request timed out. Please try again.";
    }
    return "We couldn't restore your data. Please try again.";
  }
}
