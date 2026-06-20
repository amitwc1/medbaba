import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../../core/database/app_database.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  List<Note> _noteResults = [];
  bool _isSearching = false;
  List<SearchHistoryData> _searchHistory = [];

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
  }

  Future<void> _loadSearchHistory() async {
    final history = await AppDatabase.instance.getSearchHistory();
    if (mounted) setState(() => _searchHistory = history);
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _noteResults = []; _isSearching = false; });
      return;
    }
    setState(() => _isSearching = true);

    // Parse advanced operators
    String searchQuery = query;
    // tag:, folder:, deck:, type: operators would be parsed here
    // For now, do basic search
    final db = AppDatabase.instance;
    final pattern = '%$searchQuery%';
    final notes = await (db.select(db.notes)
      ..where((n) => n.title.like(pattern) | n.plainText.like(pattern))
      ..limit(50))
        .get();

    await db.addSearchHistory(query);

    if (mounted) {
      setState(() {
        _noteResults = notes;
        _isSearching = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasQuery = _searchController.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search notes, decks, tags...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: hasQuery
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _noteResults = []);
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (_searchController.text == value) {
                    _performSearch(value);
                  }
                });
              },
            ),
          ),
          // Operators hint
          if (!hasQuery)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _OperatorChip(label: 'tag:', onTap: () {
                    _searchController.text = 'tag:';
                    _searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _searchController.text.length),
                    );
                  }),
                  _OperatorChip(label: 'folder:', onTap: () {
                    _searchController.text = 'folder:';
                    _searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _searchController.text.length),
                    );
                  }),
                  _OperatorChip(label: 'deck:', onTap: () {
                    _searchController.text = 'deck:';
                    _searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _searchController.text.length),
                    );
                  }),
                  _OperatorChip(label: 'type:note', onTap: () {
                    _searchController.text = 'type:note ';
                    _searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _searchController.text.length),
                    );
                  }),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // Results or history
          Expanded(
            child: hasQuery
                ? _isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : _noteResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 48, color: colorScheme.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text('No results found', style: textTheme.bodyLarge),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _noteResults.length,
                            itemBuilder: (context, index) {
                              final note = _noteResults[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.description, color: colorScheme.primary, size: 20),
                                  ),
                                  title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    note.plainText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                                  ),
                                  onTap: () => context.push('/notes/detail/${note.id}'),
                                ),
                              );
                            },
                          )
                : _searchHistory.isEmpty
                    ? Center(
                        child: Text('Start typing to search', style: textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        )),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Recent', style: textTheme.titleSmall),
                                TextButton(
                                  onPressed: () async {
                                    await AppDatabase.instance.clearSearchHistory();
                                    _loadSearchHistory();
                                  },
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _searchHistory.length,
                              itemBuilder: (context, index) {
                                final item = _searchHistory[index];
                                return ListTile(
                                  leading: const Icon(Icons.history),
                                  title: Text(item.query),
                                  dense: true,
                                  onTap: () {
                                    _searchController.text = item.query;
                                    _performSearch(item.query);
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _OperatorChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OperatorChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}
