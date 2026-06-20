import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/models/drawing_tool.dart';

class DrawingEditorState {
  final DrawingNote? activeNote;
  final List<DrawingPage> pages;
  final int currentPageIndex;
  final List<DrawingStroke> currentStrokes;
  final bool isLoading;
  final String? error;

  DrawingEditorState({
    this.activeNote,
    this.pages = const [],
    this.currentPageIndex = 0,
    this.currentStrokes = const [],
    this.isLoading = false,
    this.error,
  });

  DrawingEditorState copyWith({
    DrawingNote? activeNote,
    List<DrawingPage>? pages,
    int? currentPageIndex,
    List<DrawingStroke>? currentStrokes,
    bool? isLoading,
    String? error,
  }) {
    return DrawingEditorState(
      activeNote: activeNote ?? this.activeNote,
      pages: pages ?? this.pages,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      currentStrokes: currentStrokes ?? this.currentStrokes,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class DrawingEditorNotifier extends StateNotifier<DrawingEditorState> {
  final _db = AppDatabase.instance;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  DrawingEditorNotifier() : super(DrawingEditorState());

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Future<void> loadNote(String? noteId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      DrawingNote? note;
      List<DrawingPage> pagesList = [];

      if (noteId == null || noteId.isEmpty) {
        // Create new drawing note and linked standard note
        final id = const Uuid().v4();
        final stdNoteId = const Uuid().v4();

        await _db.createNote(NotesCompanion.insert(
          id: stdNoteId,
          title: const Value('Handwritten Note'),
          content: const Value('[Drawing Note]'),
          plainText: const Value('[Drawing Note]'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));

        await _db.createDrawingNote(DrawingNotesCompanion.insert(
          id: id,
          noteId: Value(stdNoteId),
          title: const Value('Handwritten Note'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));

        // Create first blank page
        final pageId = const Uuid().v4();
        await _db.createDrawingPage(DrawingPagesCompanion.insert(
          id: pageId,
          drawingNoteId: id,
          pageNumber: const Value(1),
          backgroundType: const Value('blank'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));

        note = await _db.getDrawingNoteById(id);
        pagesList = await _db.getPagesForDrawingNote(id);
      } else {
        // Note: noteId passed can either be the drawing note ID or standard note ID!
        // To be extremely flexible, check both!
        note = await _db.getDrawingNoteById(noteId);
        if (note == null) {
          // Check if the noteId is the linked standard note ID
          note = await (_db.select(_db.drawingNotes)..where((dn) => dn.noteId.equals(noteId))).getSingleOrNull();
        }

        if (note == null) {
          state = state.copyWith(isLoading: false, error: 'Note not found');
          return;
        }

        pagesList = await _db.getPagesForDrawingNote(note.id);

        if (pagesList.isEmpty) {
          // Create page if note has no pages
          final pageId = const Uuid().v4();
          await _db.createDrawingPage(DrawingPagesCompanion.insert(
            id: pageId,
            drawingNoteId: note.id,
            pageNumber: const Value(1),
            backgroundType: const Value('blank'),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ));
          pagesList = await _db.getPagesForDrawingNote(note.id);
        }
      }

      final firstPageId = pagesList.first.id;
      final strokes = await _db.getStrokesForPage(firstPageId);

      _undoStack.clear();
      _redoStack.clear();
      // Populate undo stack with existing stroke IDs
      for (final s in strokes) {
        if (!s.isDeleted) {
          _undoStack.add(s.id);
        }
      }

      state = DrawingEditorState(
        activeNote: note,
        pages: pagesList,
        currentPageIndex: 0,
        currentStrokes: strokes,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> changePage(int index) async {
    if (index < 0 || index >= state.pages.length) return;

    final targetPageId = state.pages[index].id;
    final strokes = await _db.getStrokesForPage(targetPageId);

    _undoStack.clear();
    _redoStack.clear();
    for (final s in strokes) {
      if (!s.isDeleted) {
        _undoStack.add(s.id);
      }
    }

    state = state.copyWith(
      currentPageIndex: index,
      currentStrokes: strokes,
    );
  }

  Future<void> addPage({String backgroundType = 'blank', String? pdfPath, int? pdfPageNumber}) async {
    final note = state.activeNote;
    if (note == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final pageId = const Uuid().v4();
      final nextPageNumber = state.pages.length + 1;

      await _db.createDrawingPage(DrawingPagesCompanion.insert(
        id: pageId,
        drawingNoteId: note.id,
        pageNumber: Value(nextPageNumber),
        backgroundType: Value(backgroundType),
        pdfPath: Value(pdfPath),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));

      final pagesList = await _db.getPagesForDrawingNote(note.id);
      state = state.copyWith(
        pages: pagesList,
        currentPageIndex: pagesList.length - 1,
        currentStrokes: const [],
        isLoading: false,
      );

      _undoStack.clear();
      _redoStack.clear();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> deletePage(int index) async {
    if (state.pages.length <= 1) return; // Cannot delete the only page
    final note = state.activeNote;
    if (note == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final pageToDelete = state.pages[index];
      await _db.deleteDrawingPage(pageToDelete.id);

      // Reorder remaining pages
      final remainingPages = await _db.getPagesForDrawingNote(note.id);
      for (int i = 0; i < remainingPages.length; i++) {
        final p = remainingPages[i];
        if (p.pageNumber != (i + 1)) {
          await _db.updateDrawingPage(DrawingPagesCompanion(
            id: Value(p.id),
            pageNumber: Value(i + 1),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }

      final updatedPages = await _db.getPagesForDrawingNote(note.id);
      int newIndex = state.currentPageIndex;
      if (newIndex >= updatedPages.length) {
        newIndex = updatedPages.length - 1;
      }

      state = state.copyWith(
        pages: updatedPages,
        isLoading: false,
      );

      await changePage(newIndex);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> duplicatePage(int index) async {
    final note = state.activeNote;
    if (note == null || index < 0 || index >= state.pages.length) return;

    state = state.copyWith(isLoading: true);
    try {
      final sourcePage = state.pages[index];
      final newPageId = const Uuid().v4();
      final nextPageNumber = state.pages.length + 1;

      // Create duplicated page
      await _db.createDrawingPage(DrawingPagesCompanion.insert(
        id: newPageId,
        drawingNoteId: note.id,
        pageNumber: Value(nextPageNumber),
        backgroundType: Value(sourcePage.backgroundType),
        pdfPath: Value(sourcePage.pdfPath),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));

      // Duplicate strokes
      final sourceStrokes = await _db.getStrokesForPage(sourcePage.id);
      for (final s in sourceStrokes) {
        if (s.isDeleted) continue;
        await _db.createDrawingStroke(DrawingStrokesCompanion.insert(
          id: const Uuid().v4(),
          pageId: newPageId,
          pointsJson: s.pointsJson,
          pressureJson: Value(s.pressureJson),
          tiltJson: Value(s.tiltJson),
          color: Value(s.color),
          thickness: Value(s.thickness),
          opacity: Value(s.opacity),
          toolType: Value(s.toolType),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
      }

      final pagesList = await _db.getPagesForDrawingNote(note.id);
      state = state.copyWith(
        pages: pagesList,
        currentPageIndex: pagesList.length - 1,
        isLoading: false,
      );

      await changePage(pagesList.length - 1);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> saveStroke(DrawingStroke stroke) async {
    try {
      // Create companion
      final companion = DrawingStrokesCompanion.insert(
        id: stroke.id,
        pageId: stroke.pageId,
        pointsJson: stroke.pointsJson,
        pressureJson: Value(stroke.pressureJson),
        tiltJson: Value(stroke.tiltJson),
        color: Value(stroke.color),
        thickness: Value(stroke.thickness),
        opacity: Value(stroke.opacity),
        toolType: Value(stroke.toolType),
        isDeleted: const Value(false),
        syncStatus: const Value('pending'),
        createdAt: Value(stroke.createdAt),
        updatedAt: Value(stroke.updatedAt),
      );

      await _db.createDrawingStroke(companion);
      _undoStack.add(stroke.id);
      _redoStack.clear();

      final updatedStrokes = await _db.getStrokesForPage(stroke.pageId);
      state = state.copyWith(currentStrokes: updatedStrokes);
    } catch (e) {
      if (kDebugMode) {
        print('Error saving stroke: $e');
      }
    }
  }

  Future<void> eraseStroke(String strokeId) async {
    try {
      await _db.deleteDrawingStroke(strokeId);
      _undoStack.remove(strokeId);

      final activePageId = state.pages[state.currentPageIndex].id;
      final updatedStrokes = await _db.getStrokesForPage(activePageId);
      state = state.copyWith(currentStrokes: updatedStrokes);
    } catch (e) {
      if (kDebugMode) {
        print('Error erasing stroke: $e');
      }
    }
  }

  Future<void> eraseMultipleStrokes(List<String> strokeIds) async {
    if (strokeIds.isEmpty) return;
    try {
      for (final id in strokeIds) {
        await _db.deleteDrawingStroke(id);
        _undoStack.remove(id);
      }

      final activePageId = state.pages[state.currentPageIndex].id;
      final updatedStrokes = await _db.getStrokesForPage(activePageId);
      state = state.copyWith(currentStrokes: updatedStrokes);
    } catch (e) {
      if (kDebugMode) {
        print('Error erasing multiple strokes: $e');
      }
    }
  }

  Future<void> undo() async {
    if (_undoStack.isEmpty) return;

    final strokeId = _undoStack.removeLast();
    await _db.deleteDrawingStroke(strokeId);
    _redoStack.add(strokeId);

    final activePageId = state.pages[state.currentPageIndex].id;
    final updatedStrokes = await _db.getStrokesForPage(activePageId);
    state = state.copyWith(currentStrokes: updatedStrokes);
  }

  Future<void> redo() async {
    if (_redoStack.isEmpty) return;

    final strokeId = _redoStack.removeLast();
    // Update stroke in database to restore it
    await _db.updateDrawingStroke(DrawingStrokesCompanion(
      id: Value(strokeId),
      isDeleted: const Value(false),
      updatedAt: Value(DateTime.now()),
    ));
    _undoStack.add(strokeId);

    final activePageId = state.pages[state.currentPageIndex].id;
    final updatedStrokes = await _db.getStrokesForPage(activePageId);
    state = state.copyWith(currentStrokes: updatedStrokes);
  }

  Future<void> updateBackgroundType(String type) async {
    final page = state.pages[state.currentPageIndex];
    try {
      await _db.updateDrawingPage(DrawingPagesCompanion(
        id: Value(page.id),
        backgroundType: Value(type),
        updatedAt: Value(DateTime.now()),
      ));

      final note = state.activeNote;
      if (note != null) {
        final pagesList = await _db.getPagesForDrawingNote(note.id);
        state = state.copyWith(pages: pagesList);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating background: $e');
      }
    }
  }

  Future<void> updateTitle(String title) async {
    final note = state.activeNote;
    if (note == null) return;

    try {
      await _db.updateDrawingNote(DrawingNotesCompanion(
        id: Value(note.id),
        title: Value(title),
        updatedAt: Value(DateTime.now()),
      ));

      if (note.noteId != null) {
        await _db.updateNote(NotesCompanion(
          id: Value(note.noteId!),
          title: Value(title),
          updatedAt: Value(DateTime.now()),
        ));
      }

      final updatedNote = await _db.getDrawingNoteById(note.id);
      state = state.copyWith(activeNote: updatedNote);
    } catch (e) {
      if (kDebugMode) {
        print('Error updating title: $e');
      }
    }
  }
}

final drawingEditorProvider = StateNotifierProvider.family<DrawingEditorNotifier, DrawingEditorState, String?>((ref, noteId) {
  final notifier = DrawingEditorNotifier();
  notifier.loadNote(noteId);
  return notifier;
});
