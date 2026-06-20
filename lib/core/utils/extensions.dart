import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// DateTime extensions
extension DateTimeX on DateTime {
  /// Format as "Jun 20, 2025"
  String get formatted => DateFormat('MMM dd, yyyy').format(this);

  /// Format as "Jun 20"
  String get shortFormatted => DateFormat('MMM dd').format(this);

  /// Format as "3:45 PM"
  String get timeFormatted => DateFormat('h:mm a').format(this);

  /// Format as "Jun 20, 2025 at 3:45 PM"
  String get fullFormatted => DateFormat('MMM dd, yyyy \'at\' h:mm a').format(this);

  /// Relative time: "2 hours ago", "Yesterday", etc.
  String get relative {
    final now = DateTime.now();
    final diff = now.difference(this);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return formatted;
  }

  /// Is today?
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  /// Is yesterday?
  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year &&
        month == yesterday.month &&
        day == yesterday.day;
  }

  /// Start of day
  DateTime get startOfDay => DateTime(year, month, day);

  /// End of day
  DateTime get endOfDay => DateTime(year, month, day, 23, 59, 59);
}

/// String extensions
extension StringX on String {
  /// Capitalize first letter
  String get capitalized =>
      isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';

  /// Truncate with ellipsis
  String truncate(int maxLength, {String ellipsis = '...'}) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength - ellipsis.length)}$ellipsis';
  }

  /// Count words
  int get wordCount {
    final trimmed = trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  /// Estimated reading time in seconds
  int get readingTimeSeconds {
    const wordsPerMinute = 200;
    final words = wordCount;
    return ((words / wordsPerMinute) * 60).ceil();
  }

  /// Format reading time as human-readable string
  String get readingTimeFormatted {
    final seconds = readingTimeSeconds;
    if (seconds < 60) return '< 1 min read';
    final minutes = (seconds / 60).ceil();
    return '$minutes min read';
  }

  /// Extract [[wiki links]] from text
  List<String> get wikiLinks {
    final regex = RegExp(r'\[\[([^\]]+)\]\]');
    return regex.allMatches(this).map((m) => m.group(1)!).toList();
  }

  /// Strip markdown formatting for plain text
  String get stripMarkdown {
    var text = this;
    text = text.replaceAll(RegExp(r'#{1,6}\s'), ''); // Headers
    text = text.replaceAll(RegExp(r'\*{1,3}(.*?)\*{1,3}'), r'$1'); // Bold/Italic
    text = text.replaceAll(RegExp(r'~~(.*?)~~'), r'$1'); // Strikethrough
    text = text.replaceAll(RegExp(r'\[([^\]]*)\]\([^\)]*\)'), r'$1'); // Links
    text = text.replaceAll(RegExp(r'`{1,3}[^`]*`{1,3}'), ''); // Code
    text = text.replaceAll(RegExp(r'^\s*[-*+]\s', multiLine: true), ''); // Lists
    text = text.replaceAll(RegExp(r'^\s*\d+\.\s', multiLine: true), ''); // Numbered
    text = text.replaceAll(RegExp(r'\[\[([^\]]+)\]\]'), r'$1'); // Wiki links
    text = text.replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), ''); // Images
    return text.trim();
  }
}

/// Int extensions
extension IntX on int {
  /// Format duration from seconds
  String get durationFormatted {
    if (this < 60) return '${this}s';
    if (this < 3600) return '${(this / 60).floor()}m';
    final hours = (this / 3600).floor();
    final minutes = ((this % 3600) / 60).floor();
    return '${hours}h ${minutes}m';
  }

  /// Format large numbers with commas
  String get commaFormatted => NumberFormat('#,##0').format(this);
}

/// BuildContext extensions
extension BuildContextX on BuildContext {
  /// Get theme
  ThemeData get theme => Theme.of(this);

  /// Get color scheme
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// Get text theme
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// Get screen size
  Size get screenSize => MediaQuery.sizeOf(this);

  /// Get screen width
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Get screen height
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// Is dark mode
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Show snackbar
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? colorScheme.error
            : colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show success snackbar
  void showSuccess(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: colorScheme.onInverseSurface),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
