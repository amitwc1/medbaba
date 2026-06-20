import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/route_constants.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/profile_screen.dart';
import '../../features/auth/presentation/screens/restore_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/notes/presentation/screens/notes_list_screen.dart';
import '../../features/notes/presentation/screens/note_editor_screen.dart';
import '../../features/notes/presentation/screens/note_detail_screen.dart';
import '../../features/decks/presentation/screens/deck_list_screen.dart';
import '../../features/decks/presentation/screens/deck_detail_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/graph/presentation/screens/graph_view_screen.dart';
import '../../features/flashcards/presentation/screens/card_editor_screen.dart';
import '../../features/review/presentation/screens/review_session_screen.dart';
import '../../features/daily_notes/presentation/screens/daily_notes_screen.dart';
import '../../features/statistics/presentation/screens/statistics_screen.dart';
import '../../features/ai/presentation/screens/ai_assistant_screen.dart';
import '../../features/ai/presentation/screens/ai_settings_screen.dart';
import '../../features/folders/presentation/screens/folder_browser_screen.dart';
import '../../features/tags/presentation/screens/tag_management_screen.dart';
import '../../features/drawing/presentation/screens/drawing_editor_screen.dart';

/// Global key for the router
final rootNavigatorKey = GlobalKey<NavigatorState>();


/// Router provider
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: RouteConstants.splash,
    debugLogDiagnostics: true,
    routes: [
      // ──────── Auth routes ────────
      GoRoute(
        path: RouteConstants.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RouteConstants.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: RouteConstants.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteConstants.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: RouteConstants.restore,
        builder: (context, state) => const RestoreScreen(),
      ),

      // ──────── Main Shell with Bottom Navigation ────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          // Dashboard Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteConstants.dashboard,
                name: RouteConstants.dashboardName,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          // Notes Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteConstants.notes,
                name: RouteConstants.notesName,
                builder: (context, state) => const NotesListScreen(),
              ),
            ],
          ),
          // Decks Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteConstants.decks,
                name: RouteConstants.decksName,
                builder: (context, state) => const DeckListScreen(),
              ),
            ],
          ),
          // Search Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteConstants.search,
                name: RouteConstants.searchName,
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          // Settings Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteConstants.settings,
                name: RouteConstants.settingsName,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),

      // ──────── Detail Routes (outside shell) ────────
      GoRoute(
        path: RouteConstants.noteEditor,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final noteId = state.uri.queryParameters['id'];
          return NoteEditorScreen(noteId: noteId);
        },
      ),
      GoRoute(
        path: RouteConstants.drawingEditor,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final noteId = state.uri.queryParameters['id'];
          return DrawingEditorScreen(noteId: noteId);
        },
      ),
      GoRoute(
        path: '/notes/detail/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return NoteDetailScreen(noteId: id);
        },
      ),
      GoRoute(
        path: RouteConstants.noteGraph,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const GraphViewScreen(),
      ),
      GoRoute(
        path: '/decks/detail/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return DeckDetailScreen(deckId: id);
        },
      ),
      GoRoute(
        path: RouteConstants.cardEditor,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final deckId = state.uri.queryParameters['deckId']!;
          final cardId = state.uri.queryParameters['cardId'];
          return CardEditorScreen(
            deckId: deckId,
            cardId: cardId,
          );
        },
      ),
      GoRoute(
        path: '/review/:deckId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final deckId = state.pathParameters['deckId']!;
          final mode = state.uri.queryParameters['mode'] ?? 'review';
          return ReviewSessionScreen(deckId: deckId, mode: mode);
        },
      ),
      GoRoute(
        path: RouteConstants.dailyNotes,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const DailyNotesScreen(),
      ),
      GoRoute(
        path: RouteConstants.statistics,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const StatisticsScreen(),
      ),
      GoRoute(
        path: RouteConstants.aiAssistant,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AiAssistantScreen(),
      ),
      GoRoute(
        path: RouteConstants.aiSettings,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AiSettingsScreen(),
      ),
      GoRoute(
        path: RouteConstants.profile,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: RouteConstants.folders,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const FolderBrowserScreen(),
      ),
      GoRoute(
        path: RouteConstants.tags,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const TagManagementScreen(),
      ),
    ],
  );
});

/// Main shell widget with bottom navigation
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.note_outlined),
            selectedIcon: Icon(Icons.note),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: 'Decks',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
