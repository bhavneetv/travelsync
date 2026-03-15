import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme.dart';
import '../../../services/memory_service.dart';
import '../../../data/models/travel_memory.dart';

class MemoryViewerScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  final String placeType;
  final String placeName;

  const MemoryViewerScreen({
    super.key,
    required this.initialIndex,
    required this.placeType,
    required this.placeName,
  });

  @override
  ConsumerState<MemoryViewerScreen> createState() =>
      _MemoryViewerScreenState();
}

class _MemoryViewerScreenState extends ConsumerState<MemoryViewerScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _deleteMemory(TravelMemory memory) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Memory?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete this photo and cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final service = ref.read(memoryServiceProvider);
    await service.deleteMemory(memory.id!, memory.imageUrl);

    if (mounted) {
      ref.invalidate(memoriesProvider);
      ref.invalidate(latestMemoryProvider);
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Memory deleted'),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final memoriesAsync = ref.watch(memoriesProvider(
      MemoryQuery(placeType: widget.placeType, placeName: widget.placeName),
    ));

    return Scaffold(
      backgroundColor: Colors.black,
      body: memoriesAsync.when(
        data: (memories) {
          if (memories.isEmpty) {
            return const Center(
              child: Text('No memories', style: TextStyle(color: Colors.white)),
            );
          }

          return GestureDetector(
            onTap: () => setState(() => _showUI = !_showUI),
            child: Stack(
              children: [
                // Photo pager
                PageView.builder(
                  controller: _pageController,
                  itemCount: memories.length,
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  itemBuilder: (context, index) {
                    final memory = memories[index];
                    return Hero(
                      tag: 'memory_${memory.id}',
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: CachedNetworkImage(
                          imageUrl: memory.imageUrl,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2,
                            ),
                          ),
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_rounded,
                                color: Colors.white54, size: 60),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Top bar
                if (_showUI)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () => context.pop(),
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white, size: 28),
                              ),
                              const Spacer(),
                              Text(
                                '${_currentPage + 1} / ${memories.length}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () =>
                                    _deleteMemory(memories[_currentPage]),
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: AppColors.accent, size: 26),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Bottom caption
                if (_showUI && memories[_currentPage].caption != null &&
                    memories[_currentPage].caption!.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                memories[_currentPage].caption!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (memories[_currentPage].createdAt != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _formatDate(
                                        memories[_currentPage].createdAt!),
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Page indicator dots
                if (_showUI && memories.length > 1)
                  Positioned(
                    bottom: 100,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        memories.length > 10 ? 0 : memories.length,
                        (index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: index == _currentPage ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: index == _currentPage
                                ? AppColors.primary
                                : Colors.white30,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppColors.accent)),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
