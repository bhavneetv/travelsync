import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/group_service.dart';
import '../../../data/models/travel_group.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _todoController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _membersFuture;
  late Future<Map<String, dynamic>?> _groupFuture;
  late Stream<List<GroupTodo>> _todoStream;
  bool _isPublicGroup = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _membersFuture = ref.read(groupServiceProvider).getGroupMembers(widget.groupId);
    _groupFuture = AppConstants.supabase
        .from('travel_groups')
        .select()
        .eq('id', widget.groupId)
        .maybeSingle();
    _todoStream = ref.read(groupServiceProvider).todosStream(widget.groupId);

    _groupFuture.then((group) {
      if (!mounted) return;
      setState(() {
        _isPublicGroup = (group?['is_public'] as bool?) ?? false;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _todoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: AppColors.lightSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Group Details'),
            if (_isPublicGroup) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'PUBLIC',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: _showShareDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Checklist'),
            Tab(text: 'Members'),
            Tab(text: 'Info'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Checklist tab
          _ChecklistTab(
            groupId: widget.groupId,
            todoController: _todoController,
            todoStream: _todoStream,
          ),
          // Members tab
          _MembersTab(groupId: widget.groupId, membersFuture: _membersFuture),
          // Info tab
          _InfoTab(groupId: widget.groupId, groupFuture: _groupFuture),
        ],
      ),
    );
  }

  void _showShareDialog() async {
    // Get group info
    final group = await AppConstants.supabase
        .from('travel_groups')
        .select()
        .eq('id', widget.groupId)
        .maybeSingle();

    if (group == null || !mounted) return;

    final inviteCode = group['invite_code'] as String?;
    if (inviteCode == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final media = MediaQuery.of(context);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              16 + media.viewInsets.bottom + media.padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Invite Members',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                // QR Code
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: inviteCode,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  inviteCode,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Share.share('Join my TravelSync group! Code: $inviteCode');
                  },
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share Code'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChecklistTab extends ConsumerWidget {
  final String groupId;
  final TextEditingController todoController;
  final Stream<List<GroupTodo>> todoStream;

  const _ChecklistTab({
    required this.groupId,
    required this.todoController,
    required this.todoStream,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupService = ref.watch(groupServiceProvider);

    return Column(
      children: [
        // Add todo input
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: todoController,
                  decoration: const InputDecoration(
                    hintText: 'Add a task...',
                    prefixIcon: Icon(Icons.add_task_rounded),
                  ),
                  onSubmitted: (text) async {
                    if (text.trim().isNotEmpty) {
                      await groupService.addTodo(groupId, text.trim());
                      todoController.clear();
                      FocusScope.of(context).unfocus();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IconButton(
                  onPressed: () async {
                    if (todoController.text.trim().isNotEmpty) {
                      await groupService.addTodo(
                        groupId,
                        todoController.text.trim(),
                      );
                      todoController.clear();
                      FocusScope.of(context).unfocus();
                    }
                  },
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ),

        // Todo list (realtime)
        Expanded(
          child: _ChecklistList(
            todoStream: todoStream,
            groupService: groupService,
          ),
        ),
      ],
    );
  }
}

class _ChecklistList extends StatefulWidget {
  final Stream<List<GroupTodo>> todoStream;
  final GroupService groupService;

  const _ChecklistList({required this.todoStream, required this.groupService});

  @override
  State<_ChecklistList> createState() => _ChecklistListState();
}

class _ChecklistListState extends State<_ChecklistList> {
  final Map<int, bool> _pendingState = {};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupTodo>>(
      stream: widget.todoStream,
      initialData: const <GroupTodo>[],
      builder: (context, snapshot) {
        final todos = snapshot.data ?? const <GroupTodo>[];

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not load checklist',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        if (todos.isEmpty && snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Text(
              'Loading checklist...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        if (todos.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.checklist_rounded,
                  size: 64,
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No tasks yet',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: todos.length,
          itemBuilder: (context, index) {
            final todo = todos[index];
            final todoId = todo.id;
            final displayedState =
                todoId != null && _pendingState.containsKey(todoId)
                    ? _pendingState[todoId]!
                    : todo.isDone;

            return Dismissible(
              key: Key('todo-${todo.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.delete_rounded,
                  color: AppColors.accent,
                ),
              ),
              onDismissed: (_) {
                if (todo.id != null) {
                  widget.groupService.deleteTodo(todo.id!);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppColors.cardShadow,
                ),
                child: CheckboxListTile(
                  value: displayedState,
                  onChanged: todoId == null
                      ? null
                      : (next) async {
                          if (next == null) return;
                          setState(() => _pendingState[todoId] = next);
                          try {
                            await widget.groupService.toggleTodo(todoId, next);
                          } finally {
                            if (mounted) {
                              setState(() => _pendingState.remove(todoId));
                            }
                          }
                        },
                  title: Text(
                    todo.text,
                    style: TextStyle(
                      decoration:
                          displayedState ? TextDecoration.lineThrough : null,
                      color: displayedState
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  activeColor: AppColors.success,
                  checkColor: Colors.white,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MembersTab extends ConsumerWidget {
  final String groupId;
  final Future<List<Map<String, dynamic>>> membersFuture;

  const _MembersTab({required this.groupId, required this.membersFuture});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: membersFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final members = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];
            final user = member['users'] as Map<String, dynamic>?;
            final isOwner = member['role'] == 'owner';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightSurface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.cardShadow,
                border: isOwner
                    ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
                    : null,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    child: Text(
                      (user?['username'] as String? ?? '?')[0].toUpperCase(),
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?['full_name'] as String? ??
                              user?['username'] as String? ??
                              'Unknown',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '@${user?['username'] ?? 'unknown'}',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isOwner)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Owner',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _InfoTab extends ConsumerWidget {
  final String groupId;
  final Future<Map<String, dynamic>?> groupFuture;

  const _InfoTab({required this.groupId, required this.groupFuture});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: groupFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final group = TravelGroup.fromJson(snapshot.data!);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group name
              _InfoRow(
                icon: Icons.group_rounded,
                label: 'Name',
                value: group.name,
              ),
              if (group.destination != null)
                _InfoRow(
                  icon: Icons.place_rounded,
                  label: 'Destination',
                  value: group.destination!,
                ),
              if (group.tripStart != null)
                _InfoRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Trip Start',
                  value:
                      '${group.tripStart!.day}/${group.tripStart!.month}/${group.tripStart!.year}',
                ),
              if (group.tripEnd != null)
                _InfoRow(
                  icon: Icons.event_rounded,
                  label: 'Trip End',
                  value:
                      '${group.tripEnd!.day}/${group.tripEnd!.month}/${group.tripEnd!.year}',
                ),
              if (group.budget != null)
                _InfoRow(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Budget',
                  value: '₹${group.budget!.toStringAsFixed(0)}',
                ),
              _InfoRow(
                icon: Icons.vpn_key_rounded,
                label: 'Invite Code',
                value: group.inviteCode ?? '---',
              ),

              const SizedBox(height: 32),

              // Leave group button
              if (group.ownerId != AppConstants.supabase.auth.currentUser?.id)
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Leave Group?'),
                        content: const Text(
                          'You will no longer have access to this group.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Leave',
                              style: TextStyle(color: AppColors.accent),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await ref.read(groupServiceProvider).leaveGroup(groupId);
                      if (context.mounted) context.pop();
                    }
                  },
                  icon: const Icon(
                    Icons.exit_to_app_rounded,
                    color: AppColors.accent,
                  ),
                  label: const Text(
                    'Leave Group',
                    style: TextStyle(color: AppColors.accent),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.accent),
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
