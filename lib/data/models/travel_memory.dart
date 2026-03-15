class TravelMemory {
  final int? id;
  final String userId;
  final String imageUrl;
  final String? caption;
  final String placeType; // 'country', 'state', 'city', 'village'
  final String placeName;
  final String? countryCode;
  final double? lat;
  final double? lng;
  final DateTime? createdAt;

  TravelMemory({
    this.id,
    required this.userId,
    required this.imageUrl,
    this.caption,
    required this.placeType,
    required this.placeName,
    this.countryCode,
    this.lat,
    this.lng,
    this.createdAt,
  });

  factory TravelMemory.fromJson(Map<String, dynamic> json) {
    return TravelMemory(
      id: json['id'] as int?,
      userId: json['user_id'] as String,
      imageUrl: json['image_url'] as String,
      caption: json['caption'] as String?,
      placeType: json['place_type'] as String,
      placeName: json['place_name'] as String,
      countryCode: json['country_code'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'image_url': imageUrl,
      'caption': caption,
      'place_type': placeType,
      'place_name': placeName,
      'country_code': countryCode,
      'lat': lat,
      'lng': lng,
    };
  }
}
