import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';

class DailyNotesScreen extends ConsumerStatefulWidget {
  const DailyNotesScreen({super.key});

  @override
  ConsumerState<DailyNotesScreen> createState() => _DailyNotesScreenState();
}

class _DailyNotesScreenState extends ConsumerState<DailyNotesScreen> {
  DateTime _selectedDate = DateTime.now();
  DailyNote? _dailyNote;
  bool _isLoading = true;

  final _tasksController = TextEditingController();
  final _meetingsController = TextEditingController();
  final _learningsController = TextEditingController();
  final _reflectionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDailyNote();
  }

  Future<void> _loadDailyNote() async {
    setState(() => _isLoading = true);
    final note = await AppDatabase.instance.getDailyNote(_selectedDate);
    if (mounted) {
      setState(() {
        _dailyNote = note;
        _tasksController.text = note?.tasks ?? '';
        _meetingsController.text = note?.meetings ?? '';
        _learningsController.text = note?.learnings ?? '';
        _reflectionsController.text = note?.reflections ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveDailyNote() async {
    final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    if (_dailyNote != null) {
      await AppDatabase.instance.updateDailyNote(DailyNotesCompanion(
        id: drift.Value(_dailyNote!.id),
        tasks: drift.Value(_tasksController.text),
        meetings: drift.Value(_meetingsController.text),
        learnings: drift.Value(_learningsController.text),
        reflections: drift.Value(_reflectionsController.text),
        updatedAt: drift.Value(DateTime.now()),
      ));
    } else {
      await AppDatabase.instance.createDailyNote(DailyNotesCompanion.insert(
        id: const Uuid().v4(),
        date: startOfDay,
        tasks: drift.Value(_tasksController.text),
        meetings: drift.Value(_meetingsController.text),
        learnings: drift.Value(_learningsController.text),
        reflections: drift.Value(_reflectionsController.text),
      ));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
    }
  }

  @override
  void dispose() {
    _tasksController.dispose();
    _meetingsController.dispose();
    _learningsController.dispose();
    _reflectionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isToday = _selectedDate.day == DateTime.now().day &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.year == DateTime.now().year;

    return Scaffold(
      appBar: AppBar(
        title: Text(isToday ? 'Today' : '${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                _selectedDate = date;
                _loadDailyNote();
              }
            },
          ),
          IconButton(icon: const Icon(Icons.check), onPressed: _saveDailyNote),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DailySection(
                    title: 'Tasks',
                    icon: Icons.checklist,
                    color: colorScheme.primary,
                    controller: _tasksController,
                    hint: '- [ ] Task 1\n- [ ] Task 2',
                  ),
                  const SizedBox(height: 20),
                  _DailySection(
                    title: 'Meetings',
                    icon: Icons.groups_outlined,
                    color: Colors.blue,
                    controller: _meetingsController,
                    hint: 'Meeting notes...',
                  ),
                  const SizedBox(height: 20),
                  _DailySection(
                    title: 'Learnings',
                    icon: Icons.school_outlined,
                    color: Colors.green,
                    controller: _learningsController,
                    hint: 'What did you learn today?',
                  ),
                  const SizedBox(height: 20),
                  _DailySection(
                    title: 'Reflections',
                    icon: Icons.self_improvement,
                    color: Colors.orange,
                    controller: _reflectionsController,
                    hint: 'Thoughts and reflections...',
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}

class _DailySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final TextEditingController controller;
  final String hint;

  const _DailySection({
    required this.title,
    required this.icon,
    required this.color,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(title, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(14),
            ),
            maxLines: null,
            minLines: 3,
          ),
        ),
      ],
    );
  }
}
