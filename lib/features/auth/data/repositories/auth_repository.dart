import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../domain/models/app_user.dart';

abstract class AuthRepository {
  Stream<User?> get authStateChanges;
  Future<AppUser?> getUser(String uid);
  Future<AppUser?> signInWithGoogle();
  Future<void> signOut();
}

class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  AuthRepositoryImpl({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  Future<T> _retryOnPermissionDenied<T>(Future<T> Function() operation) async {
    int attempts = 0;
    while (true) {
      try {
        return await operation();
      } catch (e) {
        final errorStr = e.toString();
        if (errorStr.contains('permission-denied') || errorStr.contains('Permission denied')) {
          attempts++;
          if (attempts >= 3) {
            rethrow;
          }
          debugPrint('[AuthRepository] Firestore operation permission-denied (attempt $attempts). Retrying in ${300 * attempts}ms...');
          await Future.delayed(Duration(milliseconds: 300 * attempts));
        } else {
          rethrow;
        }
      }
    }
  }

  @override
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  @override
  Future<AppUser?> getUser(String uid) async {
    debugPrint('[AuthRepository] getUser: Started for UID: $uid');
    try {
      final doc = await _retryOnPermissionDenied(() => 
        _firestore.collection('users').doc(uid).get()
            .timeout(const Duration(seconds: 15), onTimeout: () {
              debugPrint('[AuthRepository] getUser: Firestore doc retrieval timed out after 15 seconds');
              throw TimeoutException('Firestore user lookup timed out.');
            })
      );
      if (doc.exists) {
        debugPrint('[AuthRepository] getUser: User found');
        return AppUser.fromFirestore(doc);
      }
      debugPrint('[AuthRepository] getUser: User not found in Firestore');
      return null;
    } catch (e, stackTrace) {
      debugPrint('[AuthRepository] getUser ERROR: $e');
      debugPrint('[AuthRepository] StackTrace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<AppUser?> signInWithGoogle() async {
    debugPrint('[AuthRepository] signInWithGoogle: Button pressed / Google Sign-In started');
    try {
      // Trigger the authentication flow with 30s timeout
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn()
          .timeout(const Duration(seconds: 30), onTimeout: () {
            debugPrint('[AuthRepository] signInWithGoogle: Account picker timed out after 30 seconds');
            throw TimeoutException('Google Sign-In account picker timed out.');
          });

      // Cancelled by user
      if (googleUser == null) {
        debugPrint('[AuthRepository] signInWithGoogle: User cancelled sign-in');
        return null;
      }

      debugPrint('[AuthRepository] signInWithGoogle: Account selected - ${googleUser.email}');

      // Obtain the auth details from the request with 30s timeout
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication
          .timeout(const Duration(seconds: 30), onTimeout: () {
            debugPrint('[AuthRepository] signInWithGoogle: Token retrieval timed out after 30 seconds');
            throw TimeoutException('Google token retrieval timed out.');
          });

      debugPrint('[AuthRepository] signInWithGoogle: Tokens received');

      // Create a new credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      debugPrint('[AuthRepository] signInWithGoogle: Firebase credential created');

      // Sign in to Firebase with the Google [UserCredential] with 30s timeout
      final UserCredential userCredential = await _auth.signInWithCredential(credential)
          .timeout(const Duration(seconds: 30), onTimeout: () {
            debugPrint('[AuthRepository] signInWithGoogle: Firebase login timed out after 30 seconds');
            throw TimeoutException('Firebase login timed out.');
          });

      final User? firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        debugPrint('[AuthRepository] signInWithGoogle: UID received was null');
        throw Exception('Failed to sign in with Google: User is null');
      }

      debugPrint('[AuthRepository] signInWithGoogle: Firebase login success. UID: ${firebaseUser.uid}');

      // Check if user exists in Firestore with 15s timeout
      debugPrint('[AuthRepository] signInWithGoogle: Firestore lookup started');
      final userDocRef = _firestore.collection('users').doc(firebaseUser.uid);
      
      final docSnapshot = await _retryOnPermissionDenied(() => 
        userDocRef.get()
            .timeout(const Duration(seconds: 15), onTimeout: () {
              debugPrint('[AuthRepository] signInWithGoogle: Firestore lookup timed out after 15 seconds');
              throw TimeoutException('Firestore lookup timed out.');
            })
      );

      final now = DateTime.now();

      if (!docSnapshot.exists) {
        debugPrint('[AuthRepository] signInWithGoogle: Creating new user document');
        final newUser = AppUser(
          uid: firebaseUser.uid,
          name: firebaseUser.displayName ?? 'New User',
          email: firebaseUser.email ?? '',
          photoUrl: firebaseUser.photoURL,
          provider: 'google',
          createdAt: now,
          lastLoginAt: now,
          isGuest: false,
          isPremium: false,
          streak: 0,
          totalNotes: 0,
          totalCards: 0,
        );

        // Save with 15s timeout and merge option
        await _retryOnPermissionDenied(() =>
          userDocRef.set(newUser.toJson(), SetOptions(merge: true))
              .timeout(const Duration(seconds: 15), onTimeout: () {
                debugPrint('[AuthRepository] signInWithGoogle: Firestore creation timed out after 15 seconds');
                throw TimeoutException('Firestore user creation timed out.');
              })
        );
        
        debugPrint('[AuthRepository] signInWithGoogle: Firestore write completed (New User)');
        return newUser;
      } else {
        debugPrint('[AuthRepository] signInWithGoogle: Updating existing user document');
        
        // Update fields but use serverTimestamp and merge options
        final Map<String, dynamic> updateData = {
          'lastLoginAt': FieldValue.serverTimestamp(),
          'name': firebaseUser.displayName ?? 'User',
          'email': firebaseUser.email ?? '',
          'photoUrl': firebaseUser.photoURL,
          'provider': 'google',
          'isGuest': false,
        };

        await _retryOnPermissionDenied(() =>
          userDocRef.set(updateData, SetOptions(merge: true))
              .timeout(const Duration(seconds: 15), onTimeout: () {
                debugPrint('[AuthRepository] signInWithGoogle: Firestore update timed out after 15 seconds');
                throw TimeoutException('Firestore user update timed out.');
              })
        );

        debugPrint('[AuthRepository] signInWithGoogle: Firestore write completed (Existing User)');

        final freshSnapshot = await _retryOnPermissionDenied(() =>
          userDocRef.get()
              .timeout(const Duration(seconds: 15), onTimeout: () {
                debugPrint('[AuthRepository] signInWithGoogle: Firestore fresh lookup timed out after 15 seconds');
                throw TimeoutException('Firestore fresh user lookup timed out.');
              })
        );

        return AppUser.fromFirestore(freshSnapshot);
      }
    } catch (e, stackTrace) {
      debugPrint('[AuthRepository] signInWithGoogle ERROR: $e');
      debugPrint('[AuthRepository] StackTrace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    debugPrint('[AuthRepository] signOut: Started');
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]).timeout(const Duration(seconds: 15), onTimeout: () {
        debugPrint('[AuthRepository] signOut: Timed out after 15 seconds');
        throw TimeoutException('Sign out timed out.');
      });
      debugPrint('[AuthRepository] signOut: Completed successfully');
    } catch (e, stackTrace) {
      debugPrint('[AuthRepository] signOut ERROR: $e');
      debugPrint('[AuthRepository] StackTrace: $stackTrace');
      rethrow;
    }
  }
}
