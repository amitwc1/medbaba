import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/services/sync_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/providers/sync_provider.dart';

class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  String _statusText = 'Preparing restoration...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startRestore();
    });
  }

  void _startRestore() async {
    final authState = ref.read(authNotifierProvider);
    
    // Check guest mode from AuthNotifier first
    if (authState.status == AuthStatus.authenticated && authState.isGuest) {
      setState(() {
        _statusText = 'Entering local guest mode...';
      });
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        context.go(RouteConstants.dashboard);
      }
      return;
    }

    // Direct check of FirebaseAuth state to avoid async StreamProvider race conditions
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      setState(() {
        _statusText = 'Connecting to Cloud Firestore...';
      });
      
      try {
        setState(() {
          _statusText = 'Restoring notes, flashcards, and decks...';
        });
        
        await ref.read(syncProvider.notifier).restore(firebaseUser.uid);
        
        if (mounted) {
          setState(() {
            _statusText = 'Restoration complete! Opening dashboard...';
          });
          
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            context.go(RouteConstants.dashboard);
          }
        }
      } catch (e) {
        debugPrint('[RestoreScreen] Restore Error: $e');
        String friendlyError = "We couldn't restore your data. Please try again.";
        final errorStr = e.toString();
        if (errorStr.contains('permission-denied') || errorStr.contains('Permission denied')) {
          friendlyError = "We couldn't restore your data because access was denied. Please try again.";
        } else if (errorStr.contains('network_error') || errorStr.contains('SocketException')) {
          friendlyError = "We couldn't restore your data due to a network connection issue. Please check your internet and try again.";
        } else if (errorStr.contains('timeout') || errorStr.contains('TimeoutException')) {
          friendlyError = "We couldn't restore your data because the request timed out. Please try again.";
        }
        
        if (mounted) {
          setState(() {
            _statusText = friendlyError;
          });
        }
      }
    } else {
      // Not authenticated, send back
      if (mounted) {
        context.go(RouteConstants.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final syncState = ref.watch(syncProvider);

    final isError = syncState.syncState == SyncState.failure;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.8),
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Sleek Psychology Icon with Glow
                  ZoomIn(
                    duration: const Duration(milliseconds: 600),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.cloud_download_rounded,
                        size: 48,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // App Branding Header
                  FadeInDown(
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      'Syncing MindVault',
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Tagline
                  FadeInDown(
                    duration: const Duration(milliseconds: 500),
                    delay: const Duration(milliseconds: 100),
                    child: Text(
                      'Restoring your library & learning logs from Firebase',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Status Card
                  FadeInUp(
                    duration: const Duration(milliseconds: 600),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        children: [
                          if (!isError) ...[
                            const SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                              ),
                            ),
                          ] else ...[
                            Icon(
                              Icons.error_outline_rounded,
                              size: 48,
                              color: colorScheme.error,
                            ),
                          ],
                          const SizedBox(height: 24),
                          Text(
                            isError ? 'Oops, something went wrong' : 'Restoration in Progress',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isError ? (syncState.errorMessage ?? 'Unknown error occurred') : _statusText,
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: isError ? colorScheme.error : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (isError) ...[
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton.icon(
                                onPressed: _startRestore,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Try Again'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => context.go(RouteConstants.login),
                              child: const Text('Back to Login'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
