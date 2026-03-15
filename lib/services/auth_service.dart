import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../core/constants.dart';
import '../data/models/user_profile.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final currentUserProvider = StreamProvider<UserProfile?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.userProfileStream();
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return AppConstants.supabase.auth.onAuthStateChange;
});

class AuthService {
  final _supabase = AppConstants.supabase;

  User? get currentUser => _supabase.auth.currentUser;
  String? get userId => currentUser?.id;

  Stream<UserProfile?> userProfileStream() {
    return Stream<UserProfile?>.multi((controller) {
      Timer? poller;
      StreamSubscription<AuthState>? authSub;

      Future<void> emitProfile() async {
        final user = currentUser;
        if (user == null) {
          controller.add(null);
          return;
        }

        try {
          final data = await _supabase
              .from('users')
              .select()
              .eq('id', user.id)
              .maybeSingle();

          if (!controller.isClosed) {
            controller.add(data == null ? null : UserProfile.fromJson(data));
          }
        } catch (_) {
          // Avoid surfacing realtime/polling exceptions to profile UI.
          if (!controller.isClosed) {
            controller.add(null);
          }
        }
      }

      emitProfile();
      authSub = _supabase.auth.onAuthStateChange.listen((_) => emitProfile());
      poller = Timer.periodic(const Duration(seconds: 20), (_) => emitProfile());

      controller.onCancel = () async {
        poller?.cancel();
        await authSub?.cancel();
      };
    });
  }

  Future<UserProfile?> getProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final data = await _supabase
        .from('users')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (data == null) return null;
    return UserProfile.fromJson(data);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String username,
    String? fullName,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (response.user != null) {
      await _supabase.from('users').insert({
        'id': response.user!.id,
        'username': username,
        'full_name': fullName,
      });
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> updateProfile(UserProfile profile) async {
    await _supabase
        .from('users')
        .update(profile.toJson())
        .eq('id', profile.id);
  }

  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;

    // Delete user data (cascade will handle related tables)
    await _supabase.from('users').delete().eq('id', user.id);
    await signOut();
  }

  Future<String?> uploadAvatar(String filePath, String fileName) async {
    final user = currentUser;
    if (user == null) return null;

    final path = '${user.id}/$fileName';
    await _supabase.storage.from('avatars').upload(
      path,
      Uri.parse(filePath).toFilePath() as dynamic,
      fileOptions: const FileOptions(upsert: true),
    );

    return _supabase.storage.from('avatars').getPublicUrl(path);
  }
}
