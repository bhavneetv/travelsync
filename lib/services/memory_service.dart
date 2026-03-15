import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../data/models/travel_memory.dart';

final memoryServiceProvider = Provider<MemoryService>((ref) {
  return MemoryService();
});

/// Provider that fetches memories filtered by place
final memoriesProvider =
    FutureProvider.family<List<TravelMemory>, MemoryQuery>((ref, query) async {
  final service = ref.read(memoryServiceProvider);
  return service.getMemories(
    placeType: query.placeType,
    placeName: query.placeName,
  );
});

/// Provider for fetching all memories count per place (for thumbnails on list screens)
final memoryCountProvider =
    FutureProvider.family<int, MemoryQuery>((ref, query) async {
  final service = ref.read(memoryServiceProvider);
  final list = await service.getMemories(
    placeType: query.placeType,
    placeName: query.placeName,
  );
  return list.length;
});

/// Provider for the latest memory image per place (used as card thumbnail)
final latestMemoryProvider =
    FutureProvider.family<TravelMemory?, MemoryQuery>((ref, query) async {
  final service = ref.read(memoryServiceProvider);
  return service.getLatestMemory(
    placeType: query.placeType,
    placeName: query.placeName,
  );
});

class MemoryQuery {
  final String placeType;
  final String placeName;

  const MemoryQuery({required this.placeType, required this.placeName});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryQuery &&
          placeType == other.placeType &&
          placeName == other.placeName;

  @override
  int get hashCode => placeType.hashCode ^ placeName.hashCode;
}

class MemoryService {
  final _supabase = AppConstants.supabase;
  final _picker = ImagePicker();
  final _uuid = const Uuid();

  /// Fetch all memories for a given place
  Future<List<TravelMemory>> getMemories({
    required String placeType,
    required String placeName,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final data = await _supabase
        .from('travel_memories')
        .select()
        .eq('user_id', userId)
        .eq('place_type', placeType)
        .eq('place_name', placeName)
        .order('created_at', ascending: false);

    return (data as List).map((e) => TravelMemory.fromJson(e)).toList();
  }

  /// Get the latest memory for thumbnail display
  Future<TravelMemory?> getLatestMemory({
    required String placeType,
    required String placeName,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final data = await _supabase
        .from('travel_memories')
        .select()
        .eq('user_id', userId)
        .eq('place_type', placeType)
        .eq('place_name', placeName)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;
    return TravelMemory.fromJson(data);
  }

  /// Pick an image from camera or gallery
  Future<File?> pickImage({bool fromCamera = false}) async {
    final picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// Upload a memory image and create a record
  Future<TravelMemory?> uploadMemory({
    required File imageFile,
    String? caption,
    required String placeType,
    required String placeName,
    String? countryCode,
    double? lat,
    double? lng,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    String? storagePath;
    try {
      // Upload image to storage
      final extParts = imageFile.path.split('.');
      final fileExt = extParts.length > 1 ? extParts.last : 'jpg';
      final fileName = '${_uuid.v4()}.$fileExt';
      storagePath = '$userId/$fileName';

      await _supabase.storage.from('memories').upload(storagePath, imageFile);

      final imageUrl = _supabase.storage.from('memories').getPublicUrl(storagePath);

      // Insert record
      final memory = TravelMemory(
        userId: userId,
        imageUrl: imageUrl,
        caption: caption,
        placeType: placeType,
        placeName: placeName,
        countryCode: countryCode,
        lat: lat,
        lng: lng,
      );

      final result = await _supabase
          .from('travel_memories')
          .insert(memory.toJson())
          .select()
          .single();

      return TravelMemory.fromJson(result);
    } catch (_) {
      // Roll back uploaded file if metadata insert failed.
      if (storagePath != null) {
        try {
          await _supabase.storage.from('memories').remove([storagePath]);
        } catch (_) {}
      }
      return null;
    }
  }

  /// Delete a memory
  Future<void> deleteMemory(int id, String imageUrl) async {
    // Extract storage path from URL
    final uri = Uri.parse(imageUrl);
    final segments = uri.pathSegments;
    // URL format: .../storage/v1/object/public/memories/{userId}/{fileName}
    final bucketIndex = segments.indexOf('memories');
    if (bucketIndex >= 0 && bucketIndex + 2 < segments.length) {
      final path = segments.sublist(bucketIndex + 1).join('/');
      await _supabase.storage.from('memories').remove([path]);
    }

    await _supabase.from('travel_memories').delete().eq('id', id);
  }
}
