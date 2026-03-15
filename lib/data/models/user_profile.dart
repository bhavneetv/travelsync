class UserProfile {
  final String id;
  final String username;
  final String? fullName;
  final String? bio;
  final String? avatarUrl;
  final int travelLevel;
  final int totalXp;
  final double totalDistanceKm;
  final int countriesVisited;
  final int citiesVisited;
  final int villagesVisited;
  final bool isPublic;
  final DateTime? createdAt;

  UserProfile({
    required this.id,
    required this.username,
    this.fullName,
    this.bio,
    this.avatarUrl,
    this.travelLevel = 1,
    this.totalXp = 0,
    this.totalDistanceKm = 0,
    this.countriesVisited = 0,
    this.citiesVisited = 0,
    this.villagesVisited = 0,
    this.isPublic = true,
    this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      fullName: json['full_name'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      travelLevel: _asInt(json['travel_level'], fallback: 1),
      totalXp: _asInt(json['total_xp']),
      totalDistanceKm: _asDouble(json['total_distance_km']),
      countriesVisited: _asInt(json['countries_visited']),
      citiesVisited: _asInt(json['cities_visited']),
      villagesVisited: _asInt(json['villages_visited']),
      isPublic: json['is_public'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'bio': bio,
      'avatar_url': avatarUrl,
      'travel_level': travelLevel,
      'total_xp': totalXp,
      'total_distance_km': totalDistanceKm,
      'countries_visited': countriesVisited,
      'cities_visited': citiesVisited,
      'villages_visited': villagesVisited,
      'is_public': isPublic,
    };
  }

  UserProfile copyWith({
    String? username,
    String? fullName,
    String? bio,
    String? avatarUrl,
    int? travelLevel,
    int? totalXp,
    double? totalDistanceKm,
    int? countriesVisited,
    int? citiesVisited,
    int? villagesVisited,
    bool? isPublic,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      travelLevel: travelLevel ?? this.travelLevel,
      totalXp: totalXp ?? this.totalXp,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      countriesVisited: countriesVisited ?? this.countriesVisited,
      citiesVisited: citiesVisited ?? this.citiesVisited,
      villagesVisited: villagesVisited ?? this.villagesVisited,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt,
    );
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static double _asDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }
}
