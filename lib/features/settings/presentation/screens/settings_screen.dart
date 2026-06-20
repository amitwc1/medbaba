import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../shared/providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Appearance
          _SectionHeader(title: 'Appearance'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: Text(switch (themeMode) {
              AppThemeMode.light => 'Light',
              AppThemeMode.dark => 'Dark',
              AppThemeMode.amoled => 'AMOLED Dark',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemeDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('Font Settings'),
            subtitle: const Text('Inter'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),

          // Data
          _SectionHeader(title: 'Data'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup & Restore'),
            subtitle: const Text('Export or import your data'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Sync Settings'),
            subtitle: const Text('Automatic sync enabled'),
            trailing: Switch(value: true, onChanged: (v) {}),
          ),

          // Import/Export
          _SectionHeader(title: 'Import / Export'),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import'),
            subtitle: const Text('Markdown, CSV, JSON, Anki'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showImportDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Export'),
            subtitle: const Text('Markdown, CSV, JSON, PDF'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showExportDialog(context),
          ),

          // Security
          _SectionHeader(title: 'Security'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('App Lock'),
            trailing: Switch(value: false, onChanged: (v) {}),
          ),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Biometrics'),
            trailing: Switch(value: false, onChanged: (v) {}),
          ),

          // Notifications
          _SectionHeader(title: 'Notifications'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Daily Study Reminder'),
            trailing: Switch(value: true, onChanged: (v) {}),
          ),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Review Reminders'),
            trailing: Switch(value: true, onChanged: (v) {}),
          ),
          ListTile(
            leading: const Icon(Icons.local_fire_department),
            title: const Text('Streak Reminders'),
            trailing: Switch(value: true, onChanged: (v) {}),
          ),

          // General
          _SectionHeader(title: 'General'),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language'),
            subtitle: const Text('English'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('AI Settings'),
            subtitle: const Text('Configure Gemini API'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(RouteConstants.aiSettings),
          ),

          // About
          _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: const Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            onTap: () {},
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Light'),
              leading: Radio<AppThemeMode>(
                value: AppThemeMode.light,
                groupValue: ref.read(themeModeProvider),
                onChanged: (v) {
                  ref.read(themeModeProvider.notifier).setThemeMode(v!);
                  Navigator.pop(ctx);
                },
              ),
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(AppThemeMode.light);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Dark'),
              leading: Radio<AppThemeMode>(
                value: AppThemeMode.dark,
                groupValue: ref.read(themeModeProvider),
                onChanged: (v) {
                  ref.read(themeModeProvider.notifier).setThemeMode(v!);
                  Navigator.pop(ctx);
                },
              ),
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(AppThemeMode.dark);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('AMOLED Dark'),
              leading: Radio<AppThemeMode>(
                value: AppThemeMode.amoled,
                groupValue: ref.read(themeModeProvider),
                onChanged: (v) {
                  ref.read(themeModeProvider.notifier).setThemeMode(v!);
                  Navigator.pop(ctx);
                },
              ),
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(AppThemeMode.amoled);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.description), title: const Text('Import Markdown'), onTap: () => Navigator.pop(ctx)),
            ListTile(leading: const Icon(Icons.table_chart), title: const Text('Import CSV'), onTap: () => Navigator.pop(ctx)),
            ListTile(leading: const Icon(Icons.data_object), title: const Text('Import JSON'), onTap: () => Navigator.pop(ctx)),
            ListTile(leading: const Icon(Icons.style), title: const Text('Import Anki Deck'), onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.description), title: const Text('Export Markdown'), onTap: () => Navigator.pop(ctx)),
            ListTile(leading: const Icon(Icons.table_chart), title: const Text('Export CSV'), onTap: () => Navigator.pop(ctx)),
            ListTile(leading: const Icon(Icons.data_object), title: const Text('Export JSON'), onTap: () => Navigator.pop(ctx)),
            ListTile(leading: const Icon(Icons.picture_as_pdf), title: const Text('Export PDF'), onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}
