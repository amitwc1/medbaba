import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';

class StatisticsState {
  final int totalNotes;
  final int totalCards;
  final int reviewsToday;
  final int studyStreak;
  final int totalReviews;
  final int totalStudyTimeMinutes;
  final int averageRetention;
  final double accuracy;
  final List<ReviewHistoryData> todayReviews;
  final Map<DateTime, int> heatmapData;
  final Map<String, double> weeklyProgress;
  final bool isLoading;

  StatisticsState({
    required this.totalNotes,
    required this.totalCards,
    required this.reviewsToday,
    required this.studyStreak,
    required this.totalReviews,
    required this.totalStudyTimeMinutes,
    required this.averageRetention,
    required this.accuracy,
    required this.todayReviews,
    required this.heatmapData,
    required this.weeklyProgress,
    this.isLoading = false,
  });
}

class StatisticsNotifier extends StateNotifier<StatisticsState> {
  StatisticsNotifier()
      : super(StatisticsState(
          totalNotes: 0,
          totalCards: 0,
          reviewsToday: 0,
          studyStreak: 0,
          totalReviews: 0,
          totalStudyTimeMinutes: 0,
          averageRetention: 0,
          accuracy: 0.0,
          todayReviews: [],
          heatmapData: {},
          weeklyProgress: {},
          isLoading: true,
        )) {
    load();
  }

  Future<void> load() async {
    final db = AppDatabase.instance;
    final notes = await db.countNotes();
    final cards = await db.countAllCards();
    final reviewsToday = await db.countReviewsToday();
    final todayReviews = await db.getReviewsToday();

    // Get all non-deleted review logs
    final allReviews = await (db.select(db.reviewHistory)
          ..where((r) => r.isDeleted.equals(false)))
        .get();

    // Get all non-deleted study sessions
    final allSessions = await (db.select(db.studySessions)
          ..where((s) => s.isDeleted.equals(false)))
        .get();

    // Calculate streak
    final sessionDates = allSessions.map((s) => s.startedAt).toList();
    final streak = _calculateStreak(sessionDates);

    // Total study time in minutes
    final totalSeconds = allSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final totalTimeMinutes = (totalSeconds / 60).ceil();

    // Average Retention Rate
    final correctReviews = allReviews.where((r) => r.rating >= 3).length;
    final accuracy = allReviews.isNotEmpty
        ? (correctReviews / allReviews.length * 100)
        : 0.0;

    // Heatmap Data (Date -> Session Count)
    final Map<DateTime, int> heatmap = {};
    for (final s in allSessions) {
      final dateKey = DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day);
      heatmap[dateKey] = (heatmap[dateKey] ?? 0) + 1;
    }

    // Weekly progress (last 7 days)
    final Map<String, double> weekly = {};
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayName = _getDayName(date.weekday);
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final count = allReviews
          .where((r) => r.reviewedAt.isAfter(startOfDay) && r.reviewedAt.isBefore(endOfDay))
          .length;
      weekly[dayName] = count.toDouble();
    }

    state = StatisticsState(
      totalNotes: notes,
      totalCards: cards,
      reviewsToday: reviewsToday,
      studyStreak: streak,
      totalReviews: allReviews.length,
      totalStudyTimeMinutes: totalTimeMinutes,
      averageRetention: accuracy.round(),
      accuracy: accuracy,
      todayReviews: todayReviews,
      heatmapData: heatmap,
      weeklyProgress: weekly,
      isLoading: false,
    );
  }

  int _calculateStreak(List<DateTime> dates) {
    if (dates.isEmpty) return 0;
    final normalizedDates = dates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a)); // Descending order (latest first)

    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (!normalizedDates.contains(today) && !normalizedDates.contains(yesterday)) {
      return 0;
    }

    int streak = 0;
    DateTime currentDay = normalizedDates.contains(today) ? today : yesterday;

    while (normalizedDates.contains(currentDay)) {
      streak++;
      currentDay = currentDay.subtract(const Duration(days: 1));
    }
    return streak;
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
      default:
        return 'Sun';
    }
  }
}

final statisticsProvider = StateNotifierProvider<StatisticsNotifier, StatisticsState>((ref) {
  return StatisticsNotifier();
});
