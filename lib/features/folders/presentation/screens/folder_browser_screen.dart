import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../shared/widgets/empty_state_widget.dart';

final foldersStreamProvider = StreamProvider<List<Folder>>((ref) {
  return AppDatabase.instance.watchRootFolders();
});

class FolderBrowserScreen extends ConsumerWidget {
  const FolderBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final foldersAsync = ref.watch(foldersStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      body: foldersAsync.when(
        data: (folders) {
          if (folders.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.folder_outlined,
              title: 'No folders yet',
              subtitle: 'Organize your notes into folders',
              actionLabel: 'Create Folder',
              onAction: () => _showCreateFolderDialog(context),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folder = folders[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      folder.isPinned ? Icons.folder_special : Icons.folder,
                      color: colorScheme.primary,
                    ),
                  ),
                  title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: PopupMenuButton(
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'pin', child: Text('Pin/Unpin')),
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                    onSelected: (v) async {
                      if (v == 'pin') {
                        await AppDatabase.instance.updateFolder(FoldersCompanion(
                          id: drift.Value(folder.id),
                          isPinned: drift.Value(!folder.isPinned),
                        ));
                      } else if (v == 'delete') {
                        await AppDatabase.instance.deleteFolder(folder.id);
                      }
                    },
                  ),
                  onTap: () {
                    // Show notes in this folder
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateFolderDialog(context),
        child: const Icon(Icons.create_new_folder),
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Folder Name', hintText: 'e.g., Work Notes'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await AppDatabase.instance.createFolder(
                  FoldersCompanion.insert(
                    id: const Uuid().v4(),
                    name: controller.text.trim(),
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
