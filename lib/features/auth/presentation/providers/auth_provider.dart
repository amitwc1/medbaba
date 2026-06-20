import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/app_user.dart';
import '../../../../core/services/sync_service.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService.instance;
});

/// Provides the implementation of AuthRepository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl();
});

/// Streams the Firebase Auth state changes
final authStateProvider = StreamProvider<User?>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return authRepository.authStateChanges;
});

/// Streams the currently logged in user's profile from Firestore
final currentUserProvider = StreamProvider<AppUser?>((ref) async* {
  final authState = ref.watch(authStateProvider);
  final authRepository = ref.watch(authRepositoryProvider);

  // If we are still loading the auth state, yield null or keep previous state.
  if (authState.isLoading) {
    yield null;
    return;
  }

  final user = authState.value;

  if (user == null) {
    // If we are in "guest" mode or logged out.
    // The AuthNotifier state will determine if it's guest or just unauthenticated.
    final currentStatus = ref.read(authNotifierProvider).status;
    if (currentStatus == AuthStatus.authenticated &&
        ref.read(authNotifierProvider).isGuest) {
      yield AppUser(
        uid: 'guest',
        name: 'Guest User',
        email: '',
        provider: 'local',
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
        isGuest: true,
      );
    } else {
      yield null;
    }
  } else {
    // User is logged into Firebase, fetch from Firestore
    try {
      final appUser = await authRepository.getUser(user.uid);
      yield appUser;
    } catch (e) {
      yield null;
    }
  }
});

/// Authentication state status
enum AuthStatus { initial, authenticated, unauthenticated, loading, error }

/// Auth state class
class AuthState {
  final AuthStatus status;
  final bool isGuest;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.isGuest = false,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    bool? isGuest,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      isGuest: isGuest ?? this.isGuest,
      errorMessage: errorMessage,
    );
  }
}

/// Auth state provider
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

/// Auth notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;

  AuthNotifier(this._ref) : super(const AuthState()) {
    _ref.listen<AsyncValue<User?>>(authStateProvider, (previous, next) {
      if (!next.isLoading) {
        if (next.value != null) {
          state = state.copyWith(status: AuthStatus.authenticated, isGuest: false);
        } else {
          // If we were previously authenticated as a guest, we might want to keep it
          // But to be safe, if Firebase says null, and we aren't explicitly setting guest mode, we are unauthenticated.
          if (!state.isGuest) {
             state = state.copyWith(status: AuthStatus.unauthenticated);
          }
        }
      }
    });
  }

  Future<void> signInWithGoogle() async {
    if (state.status == AuthStatus.loading) return;
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final repository = _ref.read(authRepositoryProvider);
      final user = await repository.signInWithGoogle();
      
      if (user != null) {
        state = state.copyWith(status: AuthStatus.authenticated, isGuest: false);
      } else {
        // User cancelled login
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      final friendlyError = _mapError(e);
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: friendlyError,
      );
    }
  }

  Future<void> continueAsGuest() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    await Future.delayed(const Duration(milliseconds: 500));
    state = state.copyWith(
      status: AuthStatus.authenticated,
      isGuest: true,
    );
  }

  Future<void> signOut() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      await _ref.read(syncServiceProvider).wipeLocalData();
      final repository = _ref.read(authRepositoryProvider);
      await repository.signOut();
      state = state.copyWith(status: AuthStatus.unauthenticated, isGuest: false);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: _mapError(e),
      );
    }
  }

  String _mapError(dynamic e) {
    final errorStr = e.toString();
    if (errorStr.contains('TimeoutException')) {
      return 'Connection timed out. Please check your internet connection and try again.';
    }
    if (errorStr.contains('PlatformException(sign_in_failed,') || 
        errorStr.contains('ApiException: 10') || 
        errorStr.contains('DEVELOPER_ERROR')) {
      return 'Google Sign-In failed (Developer Error 10). Please ensure correct SHA-1 and SHA-256 fingerprints are added in Firebase Console.';
    }
    if (errorStr.contains('network_error') || errorStr.contains('SocketException')) {
      return 'Network unavailable. Please verify your internet connection.';
    }
    if (errorStr.contains('sign_in_canceled') || errorStr.contains('cancelled')) {
      return 'Google Sign-In was cancelled by the user.';
    }
    if (errorStr.contains('play-services-not-available')) {
      return 'Google Play Services are unavailable on this device.';
    }
    if (errorStr.contains('permission-denied') || errorStr.contains('Permission denied')) {
      return 'Permission denied by Firestore security rules. Please check Firestore permissions.';
    }
    return errorStr.replaceFirst('Exception:', '').replaceFirst('SystemException:', '').trim();
  }
  
  // Backward compatibility with previous implementation mock
  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    await Future.delayed(const Duration(seconds: 1));
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      errorMessage: 'Email login is currently disabled. Use Google Sign-in.',
    );
  }

  Future<void> registerWithEmail(String name, String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    await Future.delayed(const Duration(seconds: 1));
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      errorMessage: 'Email registration is currently disabled. Use Google Sign-in.',
    );
  }
}
