import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../database/app_database.dart';
import '../services/sync_service.dart';

class SyncProviderState {
  final auth.User? currentUser;
  final SyncState syncState;
  final DateTime? lastSyncTime;
  final int pendingOperations;
  final bool isSyncing;
  final String? errorMessage;

  SyncProviderState({
    this.currentUser,
    this.syncState = SyncState.idle,
    this.lastSyncTime,
    this.pendingOperations = 0,
    this.isSyncing = false,
    this.errorMessage,
  });

  SyncProviderState copyWith({
    auth.User? currentUser,
    SyncState? syncState,
    DateTime? lastSyncTime,
    int? pendingOperations,
    bool? isSyncing,
    String? errorMessage,
  }) {
    return SyncProviderState(
      currentUser: currentUser ?? this.currentUser,
      syncState: syncState ?? this.syncState,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      isSyncing: isSyncing ?? this.isSyncing,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class SyncNotifier extends StateNotifier<SyncProviderState> {
  final SyncService _syncService = SyncService.instance;
  final AppDatabase _db = AppDatabase.instance;
  StreamSubscription? _syncServiceSubscription;
  Timer? _pendingOperationsTimer;

  SyncNotifier() : super(SyncProviderState()) {
    // 1. Listen to SyncService state stream
    _syncServiceSubscription = _syncService.syncStateStream.listen((state) {
      _updateFromService();
    });

    // 2. Set up a periodic timer to update pending operation count
    _pendingOperationsTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _updatePendingCount();
    });

    // 3. Listen to firebase auth changes
    auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) {
        state = state.copyWith(currentUser: user);
        _updateFromService();
      }
    });

    _updateFromService();
  }

  void _updateFromService() async {
    if (!mounted) return;
    final pendingCount = await _db.getPendingSyncItems().then((v) => v.length);
    state = state.copyWith(
      currentUser: auth.FirebaseAuth.instance.currentUser,
      syncState: _syncService.state,
      lastSyncTime: _syncService.lastSyncTime,
      isSyncing: _syncService.state == SyncState.syncing,
      pendingOperations: pendingCount,
      errorMessage: _syncService.errorMessage,
    );
  }

  void _updatePendingCount() async {
    if (!mounted) return;
    final pendingCount = await _db.getPendingSyncItems().then((v) => v.length);
    if (state.pendingOperations != pendingCount) {
      state = state.copyWith(pendingOperations: pendingCount);
    }
  }

  Future<void> sync() async {
    await _syncService.triggerSync();
  }

  Future<void> restore(String uid) async {
    await _syncService.restoreAllData(uid);
  }

  @override
  void dispose() {
    _syncServiceSubscription?.cancel();
    _pendingOperationsTimer?.cancel();
    super.dispose();
  }
}

// ─────────────────────────── PROVIDERS ───────────────────────────

final syncProvider = StateNotifierProvider<SyncNotifier, SyncProviderState>((ref) {
  return SyncNotifier();
});

final notesProvider = StreamProvider<List<Note>>((ref) {
  return AppDatabase.instance.watchAllNotes();
});

final flashcardsProvider = StreamProvider.family<List<FlashCard>, String>((ref, deckId) {
  return AppDatabase.instance.watchCardsInDeck(deckId);
});

final deckProvider = StreamProvider<List<Deck>>((ref) {
  return AppDatabase.instance.watchAllDecks();
});

final folderProvider = StreamProvider<List<Folder>>((ref) {
  return AppDatabase.instance.watchAllFolders();
});

final tagProvider = StreamProvider<List<Tag>>((ref) {
  return AppDatabase.instance.watchAllTags();
});
