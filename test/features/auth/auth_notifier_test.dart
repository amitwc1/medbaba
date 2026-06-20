import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mind_vault/features/auth/presentation/providers/auth_provider.dart';
import 'package:mind_vault/features/auth/data/repositories/auth_repository.dart';
import 'package:mind_vault/features/auth/domain/models/app_user.dart';
import 'package:mind_vault/core/services/sync_service.dart';

// ────────────────────────── FAKE AUTH REPOSITORY ──────────────────────────

class FakeAuthRepository extends Fake implements AuthRepository {
  AppUser? mockUser;
  bool shouldThrow = false;
  String throwMessage = 'Google Sign-In failed';

  @override
  Stream<User?> get authStateChanges => Stream.value(null);

  @override
  Future<AppUser?> signInWithGoogle() async {
    if (shouldThrow) {
      throw Exception(throwMessage);
    }
    return mockUser;
  }

  @override
  Future<void> signOut() async {
    if (shouldThrow) {
      throw Exception('Sign out failed');
    }
  }

  @override
  Future<AppUser?> getUser(String uid) async {
    return mockUser;
  }
}

class FakeSyncService extends Fake implements SyncService {
  @override
  Future<void> wipeLocalData() async {
    // No-op for tests
  }
}

// ────────────────────────── TEST SUITE ──────────────────────────

void main() {
  group('AuthNotifier Tests', () {
    late FakeAuthRepository fakeAuthRepository;
    late ProviderContainer container;

    setUp(() {
      fakeAuthRepository = FakeAuthRepository();
      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuthRepository),
          syncServiceProvider.overrideWithValue(FakeSyncService()),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state should be AuthStatus.initial', () {
      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.initial);
      expect(state.errorMessage, null);
      expect(state.isGuest, false);
    });

    test('signInWithGoogle success should set AuthStatus.authenticated', () async {
      fakeAuthRepository.mockUser = AppUser(
        uid: 'test-uid',
        name: 'Test User',
        email: 'test@email.com',
        provider: 'google',
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.signInWithGoogle();

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.isGuest, false);
      expect(state.errorMessage, null);
    });

    test('signInWithGoogle user cancel should set AuthStatus.unauthenticated', () async {
      fakeAuthRepository.mockUser = null; // user cancelled

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.signInWithGoogle();

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.errorMessage, null);
    });

    test('signInWithGoogle throw should set AuthStatus.error and map errors', () async {
      fakeAuthRepository.shouldThrow = true;
      fakeAuthRepository.throwMessage = 'ApiException: 10'; // simulate missing SHA

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.signInWithGoogle();

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.error);
      expect(state.errorMessage, contains('Developer Error 10'));
    });

    test('continueAsGuest should set AuthStatus.authenticated and isGuest=true', () async {
      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.continueAsGuest();

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.isGuest, true);
    });

    test('signOut should reset state to AuthStatus.unauthenticated', () async {
      final notifier = container.read(authNotifierProvider.notifier);
      
      // sign in first
      fakeAuthRepository.mockUser = AppUser(
        uid: 'test-uid',
        name: 'Test User',
        email: 'test@email.com',
        provider: 'google',
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      await notifier.signInWithGoogle();
      expect(container.read(authNotifierProvider).status, AuthStatus.authenticated);

      // sign out
      await notifier.signOut();
      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.isGuest, false);
    });
  });
}
