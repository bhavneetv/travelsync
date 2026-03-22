import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../data/models/travel_group.dart';
import 'dart:async';
import 'dart:math';

final groupServiceProvider = Provider<GroupService>((ref) => GroupService());

final userGroupsProvider = StreamProvider<List<TravelGroup>>((ref) {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return Stream.value([]);

  return ref.read(groupServiceProvider).userGroupsStream(userId);
});

class GroupService {
  final _supabase = AppConstants.supabase;

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  bool _isInfiniteRecursionError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('infinite recursion detected') ||
        text.contains('42p17') ||
        text.contains('relation "group_members"');
  }

  List<TravelGroup> _parseGroups(List<dynamic> rows) {
    return rows
        .map((row) => TravelGroup.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<TravelGroup>> getUserGroups(String userId) async {
    try {
      final members = await _supabase
          .from('group_members')
          .select('group_id')
          .eq('user_id', userId);

      final memberRows = List<Map<String, dynamic>>.from(members);
      if (memberRows.isEmpty) return <TravelGroup>[];

      final groupIds = memberRows
          .map((m) => m['group_id'])
          .where((id) => id != null)
          .toList();

      if (groupIds.isEmpty) return <TravelGroup>[];

      final groups = await _supabase
          .from('travel_groups')
          .select()
          .inFilter('id', groupIds);

      return _parseGroups(groups as List);
    } catch (error) {
      if (!_isInfiniteRecursionError(error)) rethrow;

      // Fallback for recursive RLS policies: show groups the user owns.
      try {
        final groups = await _supabase
            .from('travel_groups')
            .select()
            .eq('owner_id', userId);
        return _parseGroups(groups as List);
      } catch (fallbackError) {
        if (_isInfiniteRecursionError(fallbackError)) {
          // Final safety net: avoid surfacing backend policy recursion to UI.
          return <TravelGroup>[];
        }
        rethrow;
      }
    }
  }

  Stream<List<TravelGroup>> userGroupsStream(String userId) async* {
    try {
      yield await getUserGroups(userId);
    } catch (_) {
      yield <TravelGroup>[];
    }

    yield* Stream.periodic(const Duration(seconds: 6)).asyncMap((_) async {
      try {
        return await getUserGroups(userId);
      } catch (_) {
        return <TravelGroup>[];
      }
    });
  }

  Future<TravelGroup> createGroup({
    required String name,
    String? destination,
    DateTime? tripStart,
    DateTime? tripEnd,
    double? budget,
  }) async {
    final userId = _supabase.auth.currentUser!.id;
    final inviteCode = _generateInviteCode();

    final data = await _supabase.from('travel_groups').insert({
      'owner_id': userId,
      'name': name,
      'invite_code': inviteCode,
      'destination': destination,
      'trip_start': tripStart?.toIso8601String().split('T').first,
      'trip_end': tripEnd?.toIso8601String().split('T').first,
      'budget': budget,
    }).select().single();

    // Add owner as member
    try {
      await _supabase.from('group_members').insert({
        'group_id': data['id'],
        'user_id': userId,
        'role': 'owner',
      });
    } catch (error) {
      if (!_isInfiniteRecursionError(error)) rethrow;
    }

    return TravelGroup.fromJson(data);
  }

  Future<TravelGroup?> joinGroup(String inviteCode) async {
    final userId = _supabase.auth.currentUser!.id;

    final group = await _supabase
        .from('travel_groups')
        .select()
        .eq('invite_code', inviteCode.toUpperCase())
        .maybeSingle();

    if (group == null) return null;

    // Check if already a member
    Map<String, dynamic>? existing;
    try {
      existing = await _supabase
          .from('group_members')
          .select()
          .eq('group_id', group['id'])
          .eq('user_id', userId)
          .maybeSingle();
    } catch (error) {
      if (!_isInfiniteRecursionError(error)) rethrow;
      existing = null;
    }

    if (existing != null) return TravelGroup.fromJson(group);

    try {
      await _supabase.from('group_members').insert({
        'group_id': group['id'],
        'user_id': userId,
        'role': 'member',
      });
    } catch (error) {
      if (!_isInfiniteRecursionError(error)) rethrow;
    }

    return TravelGroup.fromJson(group);
  }

  Future<List<GroupTodo>> getTodos(String groupId) async {
    final data = await _supabase
        .from('group_todos')
        .select()
        .eq('group_id', groupId)
        .order('created_at');

    return (data as List).map((t) => GroupTodo.fromJson(t)).toList();
  }

  Stream<List<GroupTodo>> todosStream(String groupId) {
    return _supabase
        .from('group_todos')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .order('created_at')
        .map((data) => data.map((t) => GroupTodo.fromJson(t)).toList());
  }

  Future<void> addTodo(String groupId, String text) async {
    final userId = _supabase.auth.currentUser!.id;
    await _supabase.from('group_todos').insert({
      'group_id': groupId,
      'created_by': userId,
      'text': text,
    });
  }

  Future<void> toggleTodo(int todoId, bool isDone) async {
    await _supabase.from('group_todos').update({
      'is_done': isDone,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', todoId);
  }

  Future<void> deleteTodo(int todoId) async {
    await _supabase.from('group_todos').delete().eq('id', todoId);
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    Future<Map<String, Map<String, dynamic>>> loadUsersById(
      List<String> userIds,
    ) async {
      if (userIds.isEmpty) return {};
      final rows = await _supabase
          .from('users')
          .select('id, username, full_name, avatar_url, travel_level')
          .inFilter('id', userIds);

      return {
        for (final row in (rows as List))
          (row['id'] as String): Map<String, dynamic>.from(row as Map),
      };
    }

    try {
      final members = await _supabase
          .from('group_members')
          .select('group_id, user_id, role')
          .eq('group_id', groupId);

      final memberRows = List<Map<String, dynamic>>.from(members);
      if (memberRows.isEmpty) return [];

      final userIds = memberRows
          .map((m) => m['user_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final usersById = await loadUsersById(userIds);

      return memberRows
          .map((m) => {
                ...m,
                'users': usersById[m['user_id']?.toString()] ??
                    {
                      'username': 'unknown',
                      'full_name': null,
                      'avatar_url': null,
                      'travel_level': 1,
                    },
              })
          .toList();
    } catch (error) {
      if (!_isInfiniteRecursionError(error)) rethrow;

      final group = await _supabase
          .from('travel_groups')
          .select('owner_id')
          .eq('id', groupId)
          .maybeSingle();

      if (group == null || group['owner_id'] == null) return [];

      final ownerId = group['owner_id'].toString();
      Map<String, dynamic>? ownerProfile;
      try {
        final usersById = await loadUsersById([ownerId]);
        ownerProfile = usersById[ownerId];
      } catch (_) {
        ownerProfile = null;
      }

      return [
        {
          'group_id': groupId,
          'user_id': ownerId,
          'role': 'owner',
          'users': ownerProfile ??
              {
                'username': 'owner',
                'full_name': null,
                'avatar_url': null,
                'travel_level': 1,
              },
        },
      ];
    }
  }

  Future<void> leaveGroup(String groupId) async {
    final userId = _supabase.auth.currentUser!.id;
    try {
      await _supabase
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId);
    } catch (error) {
      if (!_isInfiniteRecursionError(error)) rethrow;
    }
  }
}
