import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../data/models/travel_group.dart';
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

  bool _isInfiniteRecursionError(PostgrestException error) {
    return error.message.toLowerCase().contains('infinite recursion detected');
  }

  List<TravelGroup> _parseGroups(List<dynamic> rows) {
    return rows
        .map((row) => TravelGroup.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Stream<List<TravelGroup>> _memberGroupsStream(String userId) {
    return _supabase
        .from('group_members')
        .stream(primaryKey: ['group_id', 'user_id'])
        .eq('user_id', userId)
        .asyncMap((members) async {
      if (members.isEmpty) return <TravelGroup>[];

      final groupIds = members.map((m) => m['group_id']).toList();
      final groups = await _supabase
          .from('travel_groups')
          .select()
          .inFilter('id', groupIds);

      return _parseGroups(groups as List);
    });
  }

  Stream<List<TravelGroup>> _ownedGroupsStream(String userId) {
    return _supabase
        .from('travel_groups')
        .stream(primaryKey: ['id'])
        .eq('owner_id', userId)
        .map((rows) => _parseGroups(rows));
  }

  Stream<List<TravelGroup>> userGroupsStream(String userId) async* {
    try {
      yield* _memberGroupsStream(userId);
    } on PostgrestException catch (error) {
      if (!_isInfiniteRecursionError(error)) rethrow;
      yield* _ownedGroupsStream(userId);
    }
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
    } on PostgrestException catch (error) {
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
    final existing = await _supabase
        .from('group_members')
        .select()
        .eq('group_id', group['id'])
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) return TravelGroup.fromJson(group);

    await _supabase.from('group_members').insert({
      'group_id': group['id'],
      'user_id': userId,
      'role': 'member',
    });

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
    try {
      final members = await _supabase
          .from('group_members')
          .select('*, users:user_id(username, full_name, avatar_url, travel_level)')
          .eq('group_id', groupId);

      return List<Map<String, dynamic>>.from(members);
    } on PostgrestException catch (error) {
      if (!_isInfiniteRecursionError(error)) rethrow;

      final group = await _supabase
          .from('travel_groups')
          .select('owner_id, users:owner_id(username, full_name, avatar_url, travel_level)')
          .eq('id', groupId)
          .maybeSingle();

      if (group == null) return [];
      return [
        {
          'group_id': groupId,
          'user_id': group['owner_id'],
          'role': 'owner',
          'users': group['users'],
        },
      ];
    }
  }

  Future<void> leaveGroup(String groupId) async {
    final userId = _supabase.auth.currentUser!.id;
    await _supabase
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }
}
