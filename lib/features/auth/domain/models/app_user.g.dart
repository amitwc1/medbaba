// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AppUserImpl _$$AppUserImplFromJson(Map<String, dynamic> json) =>
    _$AppUserImpl(
      uid: json['uid'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      photoUrl: json['photoUrl'] as String?,
      provider: json['provider'] as String? ?? 'google',
      createdAt: const DateTimeConverter().fromJson(
        json['createdAt'] as Object,
      ),
      lastLoginAt: const DateTimeConverter().fromJson(
        json['lastLoginAt'] as Object,
      ),
      isGuest: json['isGuest'] as bool? ?? false,
      isPremium: json['isPremium'] as bool? ?? false,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      totalNotes: (json['totalNotes'] as num?)?.toInt() ?? 0,
      totalCards: (json['totalCards'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$AppUserImplToJson(_$AppUserImpl instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'name': instance.name,
      'email': instance.email,
      'photoUrl': instance.photoUrl,
      'provider': instance.provider,
      'createdAt': const DateTimeConverter().toJson(instance.createdAt),
      'lastLoginAt': const DateTimeConverter().toJson(instance.lastLoginAt),
      'isGuest': instance.isGuest,
      'isPremium': instance.isPremium,
      'streak': instance.streak,
      'totalNotes': instance.totalNotes,
      'totalCards': instance.totalCards,
    };
