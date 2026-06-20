import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_user.freezed.dart';
part 'app_user.g.dart';

@freezed
class AppUser with _$AppUser {
  const factory AppUser({
    required String uid,
    required String name,
    required String email,
    String? photoUrl,
    @Default('google') String provider,
    @DateTimeConverter() required DateTime createdAt,
    @DateTimeConverter() required DateTime lastLoginAt,
    @Default(false) bool isGuest,
    @Default(false) bool isPremium,
    @Default(0) int streak,
    @Default(0) int totalNotes,
    @Default(0) int totalCards,
  }) = _AppUser;

  factory AppUser.fromJson(Map<String, dynamic> json) => _$AppUserFromJson(json);

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Document data is null');
    }
    // ensure uid is present
    data['uid'] = doc.id;
    return AppUser.fromJson(data);
  }
}

class DateTimeConverter implements JsonConverter<DateTime, Object> {
  const DateTimeConverter();

  @override
  DateTime fromJson(Object json) {
    if (json is Timestamp) {
      return json.toDate();
    }
    if (json is String) {
      return DateTime.parse(json);
    }
    if (json is int) {
      return DateTime.fromMillisecondsSinceEpoch(json);
    }
    return DateTime.now();
  }

  @override
  Object toJson(DateTime object) {
    return Timestamp.fromDate(object);
  }
}
