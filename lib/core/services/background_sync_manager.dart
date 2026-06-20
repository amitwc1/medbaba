import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/foundation.dart';
import 'sync_service.dart';
import '../network/connectivity_service.dart';

class BackgroundSyncManager {
  static final BackgroundSyncManager instance = BackgroundSyncManager._();

  final SyncService _syncService = SyncService.instance;
  final ConnectivityService _connectivity = ConnectivityService.instance;
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;

  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<auth.User?>? _authSubscription;
  Timer? _periodicSyncTimer;
  bool _initialized = false;

  BackgroundSyncManager._();

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    debugPrint('[BackgroundSyncManager] Initializing BackgroundSyncManager...');

    // 1. Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((online) {
      if (online && _auth.currentUser != null) {
        debugPrint('[BackgroundSyncManager] Connectivity shifted to online. Triggering auto sync.');
        _syncService.triggerSync();
      }
    });

    // 2. Listen to auth state changes to start/stop periodic sync
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user != null) {
        debugPrint('[BackgroundSyncManager] User logged in: ${user.uid}. Starting sync manager.');
        _startPeriodicSync();
        // Trigger initial sync on login
        _syncService.triggerSync();
      } else {
        debugPrint('[BackgroundSyncManager] User logged out. Stopping sync manager.');
        _stopPeriodicSync();
      }
    });

    // Start periodic sync if already logged in at initialization
    if (_auth.currentUser != null) {
      _startPeriodicSync();
    }
  }

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    // Run sync every 5 minutes
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      debugPrint('[BackgroundSyncManager] Periodic sync interval reached.');
      if (_auth.currentUser != null) {
        _syncService.triggerSync();
      }
    });
    debugPrint('[BackgroundSyncManager] Periodic sync scheduled (every 5 mins).');
  }

  void _stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    debugPrint('[BackgroundSyncManager] Periodic sync stopped.');
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _authSubscription?.cancel();
    _periodicSyncTimer?.cancel();
    _initialized = false;
    debugPrint('[BackgroundSyncManager] Disposed.');
  }
}
