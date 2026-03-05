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
      travelLevel: json['travel_level'] as int? ?? 1,
      totalXp: json['total_xp'] as int? ?? 0,
      totalDistanceKm: (json['total_distance_km'] as num?)?.toDouble() ?? 0,
      countriesVisited: json['countries_visited'] as int? ?? 0,
      citiesVisited: json['cities_visited'] as int? ?? 0,
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
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt,
    );
  }
}
