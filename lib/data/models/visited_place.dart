class VisitedPlace {
  final int? id;
  final String userId;
  final String name;
  final String? countryCode;
  final double? lat;
  final double? lng;
  final DateTime? firstVisitedAt;
  final int visitCount;
  final bool xpAwarded;

  VisitedPlace({
    this.id,
    required this.userId,
    required this.name,
    this.countryCode,
    this.lat,
    this.lng,
    this.firstVisitedAt,
    this.visitCount = 1,
    this.xpAwarded = false,
  });

  factory VisitedPlace.fromJson(Map<String, dynamic> json) {
    return VisitedPlace(
      id: json['id'] as int?,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      countryCode: json['country_code'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      firstVisitedAt: json['first_visited_at'] != null
          ? DateTime.parse(json['first_visited_at'] as String)
          : null,
      visitCount: json['visit_count'] as int? ?? 1,
      xpAwarded: json['xp_awarded'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'country_code': countryCode,
      'lat': lat,
      'lng': lng,
      'visit_count': visitCount,
      'xp_awarded': xpAwarded,
    };
  }
}

class Achievement {
  final int? id;
  final String userId;
  final String badgeKey;
  final DateTime? earnedAt;

  Achievement({
    this.id,
    required this.userId,
    required this.badgeKey,
    this.earnedAt,
  });

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'] as int?,
      userId: json['user_id'] as String,
      badgeKey: json['badge_key'] as String,
      earnedAt: json['earned_at'] != null
          ? DateTime.parse(json['earned_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'badge_key': badgeKey,
    };
  }
}
