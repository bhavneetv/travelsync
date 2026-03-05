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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Group Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _showShareDialog(context),
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
          ),
          // Members tab
          _MembersTab(groupId: widget.groupId),
          // Info tab
          _InfoTab(groupId: widget.groupId),
        ],
      ),
    );
  }

  void _showShareDialog(BuildContext context) async {
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
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ChecklistTab extends ConsumerWidget {
  final String groupId;
  final TextEditingController todoController;

  const _ChecklistTab({
    required this.groupId,
    required this.todoController,
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
          child: StreamBuilder(
            stream: groupService.todosStream(groupId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final todos = snapshot.data!;
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
                        groupService.deleteTodo(todo.id!);
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: GestureDetector(
                          onTap: () {
                            if (todo.id != null) {
                              groupService.toggleTodo(todo.id!, !todo.isDone);
                            }
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: todo.isDone
                                  ? AppColors.success
                                  : Colors.transparent,
                              border: Border.all(
                                color: todo.isDone
                                    ? AppColors.success
                                    : AppColors.textSecondary,
                                width: 2,
                              ),
                            ),
                            child: todo.isDone
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : null,
                          ),
                        ),
                        title: Text(
                          todo.text,
                          style: TextStyle(
                            decoration: todo.isDone
                                ? TextDecoration.lineThrough
                                : null,
                            color: todo.isDone
                                ? AppColors.textSecondary
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MembersTab extends ConsumerWidget {
  final String groupId;

  const _MembersTab({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.watch(groupServiceProvider).getGroupMembers(groupId),
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
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: isOwner
                    ? Border.all(
                        color: AppColors.gold.withValues(alpha: 0.3),
                      )
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
                            color: AppColors.textSecondary,
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

  const _InfoTab({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: AppConstants.supabase
          .from('travel_groups')
          .select()
          .eq('id', groupId)
          .maybeSingle(),
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
              _InfoRow(icon: Icons.group_rounded, label: 'Name', value: group.name),
              if (group.destination != null)
                _InfoRow(icon: Icons.place_rounded, label: 'Destination', value: group.destination!),
              if (group.tripStart != null)
                _InfoRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Trip Start',
                  value: '${group.tripStart!.day}/${group.tripStart!.month}/${group.tripStart!.year}',
                ),
              if (group.tripEnd != null)
                _InfoRow(
                  icon: Icons.event_rounded,
                  label: 'Trip End',
                  value: '${group.tripEnd!.day}/${group.tripEnd!.month}/${group.tripEnd!.year}',
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
                        content: const Text('You will no longer have access to this group.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Leave', style: TextStyle(color: AppColors.accent)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await ref.read(groupServiceProvider).leaveGroup(groupId);
                      if (context.mounted) context.pop();
                    }
                  },
                  icon: const Icon(Icons.exit_to_app_rounded, color: AppColors.accent),
                  label: const Text('Leave Group', style: TextStyle(color: AppColors.accent)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.accent),
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
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
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
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
