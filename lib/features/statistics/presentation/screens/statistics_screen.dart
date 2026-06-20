import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../providers/statistics_providers.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(statisticsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Statistics')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(statisticsProvider.notifier).load(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(statisticsProvider.notifier).load(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary cards
              Row(
                children: [
                  _StatCard(
                    title: 'Notes',
                    value: '${state.totalNotes}',
                    icon: Icons.note,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    title: 'Cards',
                    value: '${state.totalCards}',
                    icon: Icons.style,
                    color: AppColors.accent,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatCard(
                    title: 'Reviewed Today',
                    value: '${state.reviewsToday}',
                    icon: Icons.replay,
                    color: AppColors.reviewGood,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    title: 'Total Reviews',
                    value: '${state.totalReviews}',
                    icon: Icons.checklist_rounded,
                    color: AppColors.info,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatCard(
                    title: 'Study Streak',
                    value: '${state.studyStreak} days',
                    icon: Icons.local_fire_department,
                    color: AppColors.streakFire,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    title: 'Retention Rate',
                    value: '${state.averageRetention}%',
                    icon: Icons.psychology,
                    color: colorScheme.tertiary,
                  ),
                ],
              ),

              const SizedBox(height: 28),
              Text(
                'Today\'s Rating Distribution',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              // Ratings chart
              SizedBox(
                height: 200,
                child: state.todayReviews.isEmpty
                    ? Center(
                        child: Text(
                          'No reviews today',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: _getMaxReviewsCount(state.todayReviews),
                          barGroups: [
                            _makeBarGroup(0, state.todayReviews.where((r) => r.rating == 1).length.toDouble(), AppColors.reviewAgain),
                            _makeBarGroup(1, state.todayReviews.where((r) => r.rating == 2).length.toDouble(), AppColors.reviewHard),
                            _makeBarGroup(2, state.todayReviews.where((r) => r.rating == 3).length.toDouble(), AppColors.reviewGood),
                            _makeBarGroup(3, state.todayReviews.where((r) => r.rating == 4).length.toDouble(), AppColors.reviewEasy),
                          ],
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, _) => Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    ['Again', 'Hard', 'Good', 'Easy'][value.toInt()],
                                    style: textTheme.labelSmall,
                                  ),
                                ),
                              ),
                            ),
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          gridData: const FlGridData(show: false),
                        ),
                      ),
              ),
              const SizedBox(height: 28),
              
              // Heatmap
              Text(
                'Study Heatmap (Last 35 Days)',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildHeatmap(context, state.heatmapData),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  double _getMaxReviewsCount(List<ReviewHistoryData> reviews) {
    if (reviews.isEmpty) return 5.0;
    int maxCount = 1;
    for (int i = 1; i <= 4; i++) {
      final count = reviews.where((r) => r.rating == i).length;
      if (count > maxCount) maxCount = count;
    }
    return maxCount.toDouble() + 1.0;
  }

  BarChartGroupData _makeBarGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 32,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(6),
          ),
        ),
      ],
    );
  }

  Widget _buildHeatmap(BuildContext context, Map<DateTime, int> heatmapData) {
    final colorScheme = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: 35,
      itemBuilder: (context, index) {
        final date = DateTime.now().subtract(Duration(days: 34 - index));
        final dateKey = DateTime(date.year, date.month, date.day);
        final sessionsCount = heatmapData[dateKey] ?? 0;

        // Map session count to intensity levels (0 to 4)
        final intensity = sessionsCount > 4 ? 4 : sessionsCount;

        Color blockColor = colorScheme.surfaceContainerHighest;
        if (intensity > 0) {
          blockColor = colorScheme.primary.withValues(alpha: 0.15 + (intensity * 0.2));
        }

        return Tooltip(
          message: '${dateKey.day}/${dateKey.month}: $sessionsCount sessions studied',
          child: Container(
            decoration: BoxDecoration(
              color: blockColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      title,
                      style: textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
