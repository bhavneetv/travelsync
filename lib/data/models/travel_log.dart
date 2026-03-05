class TravelLog {
  final int? id;
  final String userId;
  final double latitude;
  final double longitude;
  final double? altitudeM;
  final double? speedKmh;
  final double? heading;
  final double? accuracyM;
  final String? city;
  final String? state;
  final String? country;
  final String? countryCode;
  final String? transportMode;
  final DateTime recordedAt;
  final DateTime? syncedAt;

  TravelLog({
    this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.altitudeM,
    this.speedKmh,
    this.heading,
    this.accuracyM,
    this.city,
    this.state,
    this.country,
    this.countryCode,
    this.transportMode,
    required this.recordedAt,
    this.syncedAt,
  });

  factory TravelLog.fromJson(Map<String, dynamic> json) {
    return TravelLog(
      id: json['id'] as int?,
      userId: json['user_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitudeM: (json['altitude_m'] as num?)?.toDouble(),
      speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      countryCode: json['country_code'] as String?,
      transportMode: json['transport_mode'] as String?,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      syncedAt: json['synced_at'] != null
          ? DateTime.parse(json['synced_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'altitude_m': altitudeM,
      'speed_kmh': speedKmh,
      'heading': heading,
      'accuracy_m': accuracyM,
      'city': city,
      'state': state,
      'country': country,
      'country_code': countryCode,
      'transport_mode': transportMode,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }
}
