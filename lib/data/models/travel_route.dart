class TravelRoute {
  final int? id;
  final String userId;
  final String? name;
  final String? polyline;
  final double? distanceKm;
  final int? durationMin;
  final double? avgSpeedKmh;
  final double? startLat;
  final double? startLng;
  final double? endLat;
  final double? endLng;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? transportMode;

  TravelRoute({
    this.id,
    required this.userId,
    this.name,
    this.polyline,
    this.distanceKm,
    this.durationMin,
    this.avgSpeedKmh,
    this.startLat,
    this.startLng,
    this.endLat,
    this.endLng,
    this.startedAt,
    this.endedAt,
    this.transportMode,
  });

  factory TravelRoute.fromJson(Map<String, dynamic> json) {
    return TravelRoute(
      id: json['id'] as int?,
      userId: json['user_id'] as String,
      name: json['name'] as String?,
      polyline: json['polyline'] as String?,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      durationMin: json['duration_min'] as int?,
      avgSpeedKmh: (json['avg_speed_kmh'] as num?)?.toDouble(),
      startLat: (json['start_lat'] as num?)?.toDouble(),
      startLng: (json['start_lng'] as num?)?.toDouble(),
      endLat: (json['end_lat'] as num?)?.toDouble(),
      endLng: (json['end_lng'] as num?)?.toDouble(),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      transportMode: json['transport_mode'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'polyline': polyline,
      'distance_km': distanceKm,
      'duration_min': durationMin,
      'avg_speed_kmh': avgSpeedKmh,
      'start_lat': startLat,
      'start_lng': startLng,
      'end_lat': endLat,
      'end_lng': endLng,
      'started_at': startedAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'transport_mode': transportMode,
    };
  }
}
