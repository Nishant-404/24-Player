import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/services/ffmpeg_service.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/history_database.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/services/downloaded_embedded_cover_resolver.dart';

/// Screen to display downloaded tracks from a specific album
class DownloadedAlbumScreen extends ConsumerStatefulWidget {
  final String albumName;
  final String artistName;
  final String? coverUrl;

  const DownloadedAlbumScreen({
    super.key,
    required this.albumName,
    required this.artistName,
    this.coverUrl,
  });

  @override
  ConsumerState<DownloadedAlbumScreen> createState() =>
      _DownloadedAlbumScreenState();
}

class _DownloadedAlbumScreenState extends ConsumerState<DownloadedAlbumScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _showTitleInAppBar = false;
  final ScrollController _scrollController = ScrollController();
  bool _embeddedCoverRefreshScheduled = false;
  List<DownloadHistoryItem>? _albumTracksSourceCache;
  List<DownloadHistoryItem>? _albumTracksCache;
  List<DownloadHistoryItem>? _discGroupingSourceCache;
  Map<int, List<DownloadHistoryItem>>? _discGroupingCache;
  List<int>? _sortedDiscNumbersCache;
  List<DownloadHistoryItem>? _commonQualitySourceCache;
  String? _commonQualityCache;
  List<DownloadHistoryItem>? _embeddedCoverSourceCache;
  String? _embeddedCoverPathCache;
  bool _embeddedCoverPathResolved = false;

  String get _albumLookupKey =>
      '${widget.albumName.toLowerCase()}|${widget.artistName.toLowerCase()}';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DownloadedAlbumScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumName != widget.albumName ||
        oldWidget.artistName != widget.artistName) {
      _albumTracksSourceCache = null;
      _albumTracksCache = null;
      _invalidateDerivedTrackCaches();
    }
  }

  void _onScroll() {
    final shouldShow = _scrollController.offset > 280;
    if (shouldShow != _showTitleInAppBar) {
      setState(() => _showTitleInAppBar = shouldShow);
    }
  }

  /// Get tracks for this album from history provider (reactive)
  List<DownloadHistoryItem> _getAlbumTracks(
    List<DownloadHistoryItem> allItems,
  ) {
    final cached = _albumTracksCache;
    if (cached != null && identical(allItems, _albumTracksSourceCache)) {
      return cached;
    }

    final tracks =
        allItems.where((item) {
          // Use albumArtist if available and not empty, otherwise artistName
          final itemArtist =
              (item.albumArtist != null && item.albumArtist!.isNotEmpty)
              ? item.albumArtist!
              : item.artistName;
          // Use lowercase for case-insensitive matching
          final itemKey =
              '${item.albumName.toLowerCase()}|${itemArtist.toLowerCase()}';
          return itemKey == _albumLookupKey;
        }).toList()..sort((a, b) {
          // Sort by disc number first, then by track number
          final aDisc = a.discNumber ?? 1;
          final bDisc = b.discNumber ?? 1;
          if (aDisc != bDisc) return aDisc.compareTo(bDisc);
          final aNum = a.trackNumber ?? 999;
          final bNum = b.trackNumber ?? 999;
          if (aNum != bNum) return aNum.compareTo(bNum);
          return a.trackName.compareTo(b.trackName);
        });

    _albumTracksSourceCache = allItems;
    _albumTracksCache = tracks;
    _invalidateDerivedTrackCaches();
    return tracks;
  }

  void _invalidateDerivedTrackCaches() {
    _discGroupingSourceCache = null;
    _discGroupingCache = null;
    _sortedDiscNumbersCache = null;
    _commonQualitySourceCache = null;
    _commonQualityCache = null;
    _embeddedCoverSourceCache = null;
    _embeddedCoverPathCache = null;
    _embeddedCoverPathResolved = false;
  }

  Map<int, List<DownloadHistoryItem>> _getDiscGroups(
    List<DownloadHistoryItem> tracks,
  ) {
    final cached = _discGroupingCache;
    if (cached != null && identical(tracks, _discGroupingSourceCache)) {
      return cached;
    }

    final discMap = <int, List<DownloadHistoryItem>>{};
    for (final track in tracks) {
      final discNumber = track.discNumber ?? 1;
      discMap.putIfAbsent(discNumber, () => []).add(track);
    }
    _discGroupingSourceCache = tracks;
    _discGroupingCache = discMap;
    _sortedDiscNumbersCache = discMap.keys.toList()..sort();
    return discMap;
  }

  List<int> _getSortedDiscNumbers(List<DownloadHistoryItem> tracks) {
    _getDiscGroups(tracks);
    return _sortedDiscNumbersCache ?? const [];
  }

  void _enterSelectionMode(String itemId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(itemId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String itemId) {
    setState(() {
      if (_selectedIds.contains(itemId)) {
        _selectedIds.remove(itemId);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(itemId);
      }
    });
  }

  void _selectAll(List<DownloadHistoryItem> tracks) {
    setState(() {
      _selectedIds.addAll(tracks.map((e) => e.id));
    });
  }

  Future<void> _deleteSelected(List<DownloadHistoryItem> currentTracks) async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.downloadedAlbumDeleteSelected),
        content: Text(context.l10n.downloadedAlbumDeleteMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.dialogDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final historyNotifier = ref.read(downloadHistoryProvider.notifier);
      final idsToDelete = _selectedIds.toList();
      final tracksById = {for (final track in currentTracks) track.id: track};

      int deletedCount = 0;
      for (final id in idsToDelete) {
        final item = tracksById[id];
        if (item != null) {
          try {
            await deleteFile(item.filePath);
          } catch (_) {}
          historyNotifier.removeFromHistory(id);
          deletedCount++;
        }
      }

      _exitSelectionMode();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarDeletedTracks(deletedCount)),
          ),
        );
      }
    }
  }

  Future<void> _openFile(String filePath) async {
    try {
      await openFile(filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarCannotOpenFile(e.toString())),
          ),
        );
      }
    }
  }

  void _onEmbeddedCoverChanged() {
    if (!mounted || _embeddedCoverRefreshScheduled) return;
    _embeddedCoverRefreshScheduled = true;
    _embeddedCoverPathResolved = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _embeddedCoverRefreshScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _navigateToMetadataScreen(DownloadHistoryItem item) async {
    final navigator = Navigator.of(context);
    _precacheCover(item.coverUrl);
    final beforeModTime =
        await DownloadedEmbeddedCoverResolver.readFileModTimeMillis(
          item.filePath,
        );
    if (!mounted) return;

    final result = await navigator.push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            TrackMetadataScreen(item: item),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    await DownloadedEmbeddedCoverResolver.scheduleRefreshForPath(
      item.filePath,
      beforeModTime: beforeModTime,
      force: result == true,
      onChanged: _onEmbeddedCoverChanged,
    );
  }

  void _precacheCover(String? url) {
    if (url == null || url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return;
    }
    final dpr = MediaQuery.devicePixelRatioOf(
      context,
    ).clamp(1.0, 3.0).toDouble();
    final targetSize = (360 * dpr).round().clamp(512, 1024).toInt();
    precacheImage(
      ResizeImage(
        CachedNetworkImageProvider(
          url,
          cacheManager: CoverCacheManager.instance,
        ),
        width: targetSize,
        height: targetSize,
      ),
      context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final allHistoryItems = ref.watch(
      downloadHistoryProvider.select((s) => s.items),
    );
    final tracks = _getAlbumTracks(allHistoryItems);

    // Show empty state if no tracks found
    if (tracks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.albumName)),
        body: Center(child: Text('No tracks found for this album')),
      );
    }

    final validIds = tracks.map((t) => t.id).toSet();
    _selectedIds.removeWhere((id) => !validIds.contains(id));
    if (_selectedIds.isEmpty && _isSelectionMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isSelectionMode = false);
      });
    }

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                _buildAppBar(context, colorScheme, tracks),
                _buildInfoCard(context, colorScheme, tracks),
                _buildTrackListHeader(context, colorScheme, tracks),
                _buildTrackList(context, colorScheme, tracks),
                SliverToBoxAdapter(
                  child: SizedBox(height: _isSelectionMode ? 120 : 32),
                ),
              ],
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: _isSelectionMode ? 0 : -(200 + bottomPadding),
              child: _buildSelectionBottomBar(
                context,
                colorScheme,
                tracks,
                bottomPadding,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _resolveAlbumEmbeddedCoverPath(List<DownloadHistoryItem> tracks) {
    if (_embeddedCoverPathResolved &&
        identical(tracks, _embeddedCoverSourceCache)) {
      return _embeddedCoverPathCache;
    }

    _embeddedCoverSourceCache = tracks;
    _embeddedCoverPathResolved = true;

    if (tracks.isEmpty) {
      _embeddedCoverPathCache = null;
      return null;
    }

    _embeddedCoverPathCache = DownloadedEmbeddedCoverResolver.resolve(
      tracks.first.filePath,
      onChanged: _onEmbeddedCoverChanged,
    );
    return _embeddedCoverPathCache;
  }

  Widget _buildAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<DownloadHistoryItem> tracks,
  ) {
    final mediaSize = MediaQuery.of(context).size;
    final screenWidth = mediaSize.width;
    final shortestSide = mediaSize.shortestSide;
    final coverSize = (screenWidth * 0.5).clamp(140.0, 220.0);
    final expandedHeight = (shortestSide * 0.82).clamp(280.0, 340.0);
    final bottomGradientHeight = (shortestSide * 0.2).clamp(56.0, 80.0);
    final coverTopPadding = (shortestSide * 0.14).clamp(40.0, 60.0);
    final fallbackIconSize = (coverSize * 0.32).clamp(44.0, 64.0);
    final embeddedCoverPath = _resolveAlbumEmbeddedCoverPath(tracks);

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      stretch: true,
      backgroundColor:
          colorScheme.surface, // Use theme color for collapsed state
      surfaceTintColor: Colors.transparent,
      title: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _showTitleInAppBar ? 1.0 : 0.0,
        child: Text(
          widget.albumName,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final collapseRatio =
              (constraints.maxHeight - kToolbarHeight) /
              (expandedHeight - kToolbarHeight);
          final showContent = collapseRatio > 0.3;
          final dpr = MediaQuery.devicePixelRatioOf(
            context,
          ).clamp(1.0, 3.0).toDouble();
          final backgroundMemCacheWidth = (constraints.maxWidth * dpr)
              .round()
              .clamp(720, 1440)
              .toInt();

          return FlexibleSpaceBar(
            collapseMode: CollapseMode.none,
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Blurred cover background
                if (embeddedCoverPath != null)
                  Image.file(
                    File(embeddedCoverPath),
                    fit: BoxFit.cover,
                    cacheWidth: backgroundMemCacheWidth,
                    errorBuilder: (_, _, _) =>
                        Container(color: colorScheme.surface),
                  )
                else if (widget.coverUrl != null)
                  CachedNetworkImage(
                    imageUrl: widget.coverUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: backgroundMemCacheWidth,
                    cacheManager: CoverCacheManager.instance,
                    placeholder: (_, _) =>
                        Container(color: colorScheme.surface),
                    errorWidget: (_, _, _) =>
                        Container(color: colorScheme.surface),
                  )
                else
                  Container(color: colorScheme.surface),
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      color: colorScheme.surface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: bottomGradientHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colorScheme.surface.withValues(alpha: 0.0),
                          colorScheme.surface,
                        ],
                      ),
                    ),
                  ),
                ),
                // Cover image centered - fade out when collapsing
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: showContent ? 1.0 : 0.0,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: coverTopPadding),
                      child: Container(
                        width: coverSize,
                        height: coverSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: embeddedCoverPath != null
                              ? Image.file(
                                  File(embeddedCoverPath),
                                  fit: BoxFit.cover,
                                  cacheWidth: (coverSize * 2).toInt(),
                                  cacheHeight: (coverSize * 2).toInt(),
                                  errorBuilder: (_, _, _) => Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.album,
                                      size: fallbackIconSize,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : widget.coverUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: widget.coverUrl!,
                                  fit: BoxFit.cover,
                                  memCacheWidth: (coverSize * 2).toInt(),
                                  cacheManager: CoverCacheManager.instance,
                                )
                              : Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.album,
                                    size: fallbackIconSize,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            stretchModes: const [
              StretchMode.zoomBackground,
              StretchMode.blurBackground,
            ],
          );
        },
      ),
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.8),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.arrow_back, color: colorScheme.onSurface),
        ),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    ColorScheme colorScheme,
    List<DownloadHistoryItem> tracks,
  ) {
    final commonQuality = _getCommonQuality(tracks);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.albumName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.artistName,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.download_done,
                            size: 14,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            context.l10n.downloadedAlbumDownloadedCount(
                              tracks.length,
                            ),
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (commonQuality != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: commonQuality.startsWith('24')
                              ? colorScheme.tertiaryContainer
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          commonQuality,
                          style: TextStyle(
                            color: commonQuality.startsWith('24')
                                ? colorScheme.onTertiaryContainer
                                : colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _getCommonQuality(List<DownloadHistoryItem> tracks) {
    if (identical(tracks, _commonQualitySourceCache)) {
      return _commonQualityCache;
    }

    if (tracks.isEmpty) {
      _commonQualitySourceCache = tracks;
      _commonQualityCache = null;
      return null;
    }
    final firstQuality = tracks.first.quality;
    if (firstQuality == null) {
      _commonQualitySourceCache = tracks;
      _commonQualityCache = null;
      return null;
    }
    for (final track in tracks) {
      if (track.quality != firstQuality) {
        _commonQualitySourceCache = tracks;
        _commonQualityCache = null;
        return null;
      }
    }
    _commonQualitySourceCache = tracks;
    _commonQualityCache = firstQuality;
    return firstQuality;
  }

  Widget _buildTrackListHeader(
    BuildContext context,
    ColorScheme colorScheme,
    List<DownloadHistoryItem> tracks,
  ) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(
          children: [
            Icon(Icons.queue_music, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              context.l10n.downloadedAlbumTracksHeader,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (!_isSelectionMode)
              TextButton.icon(
                onPressed: tracks.isNotEmpty
                    ? () => _enterSelectionMode(tracks.first.id)
                    : null,
                icon: const Icon(Icons.checklist, size: 18),
                label: Text(context.l10n.actionSelect),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackList(
    BuildContext context,
    ColorScheme colorScheme,
    List<DownloadHistoryItem> tracks,
  ) {
    final discMap = _getDiscGroups(tracks);

    if (discMap.length <= 1) {
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final track = tracks[index];
          return KeyedSubtree(
            key: ValueKey(track.id),
            child: _buildTrackItem(context, colorScheme, track),
          );
        }, childCount: tracks.length),
      );
    }

    final discNumbers = _getSortedDiscNumbers(tracks);
    final List<Widget> children = [];

    for (final discNumber in discNumbers) {
      final discTracks = discMap[discNumber];
      if (discTracks == null || discTracks.isEmpty) continue;

      // Add disc separator
      children.add(_buildDiscSeparator(context, colorScheme, discNumber));

      // Add tracks for this disc
      for (final track in discTracks) {
        children.add(
          KeyedSubtree(
            key: ValueKey(track.id),
            child: _buildTrackItem(context, colorScheme, track),
          ),
        );
      }
    }

    return SliverList(delegate: SliverChildListDelegate(children));
  }

  Widget _buildDiscSeparator(
    BuildContext context,
    ColorScheme colorScheme,
    int discNumber,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.album,
                  size: 16,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  context.l10n.downloadedAlbumDiscHeader(discNumber),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackItem(
    BuildContext context,
    ColorScheme colorScheme,
    DownloadHistoryItem track,
  ) {
    final isSelected = _selectedIds.contains(track.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Card(
        elevation: 0,
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onTap: _isSelectionMode
              ? () => _toggleSelection(track.id)
              : () => _navigateToMetadataScreen(track),
          onLongPress: _isSelectionMode
              ? null
              : () => _enterSelectionMode(track.id),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isSelectionMode) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.outline,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: colorScheme.onPrimary,
                          size: 16,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
              ],
              SizedBox(
                width: 24,
                child: Text(
                  track.trackNumber?.toString() ?? '-',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          title: Text(
            track.trackName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            track.artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          trailing: _isSelectionMode
              ? null
              : IconButton(
                  onPressed: () => _openFile(track.filePath),
                  icon: Icon(Icons.play_arrow, color: colorScheme.primary),
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// Share selected tracks via system share sheet
  Future<void> _shareSelected(List<DownloadHistoryItem> allTracks) async {
    final tracksById = {for (final t in allTracks) t.id: t};
    final safUris = <String>[];
    final filesToShare = <XFile>[];

    for (final id in _selectedIds) {
      final item = tracksById[id];
      if (item == null) continue;
      final path = item.filePath;
      if (isContentUri(path)) {
        if (await fileExists(path)) safUris.add(path);
      } else if (await fileExists(path)) {
        filesToShare.add(XFile(path));
      }
    }

    if (safUris.isEmpty && filesToShare.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.selectionShareNoFiles)),
        );
      }
      return;
    }

    // Share SAF content URIs via native intent
    if (safUris.isNotEmpty) {
      try {
        if (safUris.length == 1) {
          await PlatformBridge.shareContentUri(safUris.first);
        } else {
          await PlatformBridge.shareMultipleContentUris(safUris);
        }
      } catch (_) {}
    }

    // Share regular files via SharePlus
    if (filesToShare.isNotEmpty) {
      await SharePlus.instance.share(ShareParams(files: filesToShare));
    }
  }

  /// Show batch convert bottom sheet
  void _showBatchConvertSheet(
    BuildContext context,
    List<DownloadHistoryItem> allTracks,
  ) {
    String selectedFormat = 'MP3';
    String selectedBitrate = '320k';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colorScheme = Theme.of(context).colorScheme;
            final formats = ['MP3', 'Opus'];
            final bitrates = ['128k', '192k', '256k', '320k'];

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.selectionBatchConvertConfirmTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context.l10n.trackConvertTargetFormat,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: formats.map((format) {
                        final isSelected = format == selectedFormat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(format),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setSheetState(() {
                                  selectedFormat = format;
                                  selectedBitrate =
                                      format == 'Opus' ? '128k' : '320k';
                                });
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.trackConvertBitrate,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: bitrates.map((br) {
                        final isSelected = br == selectedBitrate;
                        return ChoiceChip(
                          label: Text(br),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setSheetState(() => selectedBitrate = br);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _performBatchConversion(
                            allTracks: allTracks,
                            targetFormat: selectedFormat,
                            bitrate: selectedBitrate,
                          );
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          context.l10n.selectionConvertCount(_selectedIds.length),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _performBatchConversion({
    required List<DownloadHistoryItem> allTracks,
    required String targetFormat,
    required String bitrate,
  }) async {
    final tracksById = {for (final t in allTracks) t.id: t};
    final selected = <DownloadHistoryItem>[];
    for (final id in _selectedIds) {
      final item = tracksById[id];
      if (item == null) continue;
      // For SAF items, use safFileName to detect format (filePath is content:// URI)
      final nameToCheck = (item.safFileName != null && item.safFileName!.isNotEmpty)
          ? item.safFileName!.toLowerCase()
          : item.filePath.toLowerCase();
      final ext = nameToCheck.endsWith('.flac') ? 'FLAC'
          : nameToCheck.endsWith('.mp3') ? 'MP3'
          : (nameToCheck.endsWith('.opus') || nameToCheck.endsWith('.ogg')) ? 'Opus'
          : null;
      if (ext != null && ext != targetFormat) selected.add(item);
    }

    if (selected.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.selectionConvertNoConvertible)),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.selectionBatchConvertConfirmTitle),
        content: Text(
          context.l10n.selectionBatchConvertConfirmMessage(
            selected.length, targetFormat, bitrate,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.trackConvertFormat),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    int successCount = 0;
    final total = selected.length;
    final historyDb = HistoryDatabase.instance;

    for (int i = 0; i < total; i++) {
      if (!mounted) break;
      final item = selected[i];

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.selectionBatchConvertProgress(i + 1, total)),
          duration: const Duration(seconds: 30),
        ),
      );

      try {
        final metadata = <String, String>{
          'TITLE': item.trackName,
          'ARTIST': item.artistName,
          'ALBUM': item.albumName,
        };
        try {
          final result = await PlatformBridge.readFileMetadata(item.filePath);
          if (result['error'] == null) {
            result.forEach((key, value) {
              if (key == 'error' || value == null) return;
              final v = value.toString().trim();
              if (v.isEmpty) return;
              metadata[key.toUpperCase()] = v;
            });
          }
        } catch (_) {}

        String? coverPath;
        try {
          final tempDir = await getTemporaryDirectory();
          final coverOutput =
              '${tempDir.path}${Platform.pathSeparator}batch_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final coverResult = await PlatformBridge.extractCoverToFile(
            item.filePath, coverOutput,
          );
          if (coverResult['error'] == null) coverPath = coverOutput;
        } catch (_) {}

        String workingPath = item.filePath;
        final isSaf = isContentUri(item.filePath);
        String? safTempPath;

        if (isSaf) {
          safTempPath = await PlatformBridge.copyContentUriToTemp(item.filePath);
          if (safTempPath == null) continue;
          workingPath = safTempPath;
        }

        final newPath = await FFmpegService.convertAudioFormat(
          inputPath: workingPath,
          targetFormat: targetFormat.toLowerCase(),
          bitrate: bitrate,
          metadata: metadata,
          coverPath: coverPath,
          deleteOriginal: !isSaf,
        );

        if (coverPath != null) {
          try { await File(coverPath).delete(); } catch (_) {}
        }

        if (newPath == null) {
          if (safTempPath != null) {
            try { await File(safTempPath).delete(); } catch (_) {}
          }
          continue;
        }

        if (isSaf) {
          final treeUri = item.downloadTreeUri;
          final relativeDir = item.safRelativeDir ?? '';
          if (treeUri != null && treeUri.isNotEmpty) {
            final oldFileName = item.safFileName ?? '';
            final dotIdx = oldFileName.lastIndexOf('.');
            final baseName = dotIdx > 0 ? oldFileName.substring(0, dotIdx) : oldFileName;
            final newExt = targetFormat.toLowerCase() == 'opus' ? '.opus' : '.mp3';
            final newFileName = '$baseName$newExt';
            final mimeType = targetFormat.toLowerCase() == 'opus' ? 'audio/opus' : 'audio/mpeg';

            final safUri = await PlatformBridge.createSafFileFromPath(
              treeUri: treeUri,
              relativeDir: relativeDir,
              fileName: newFileName,
              mimeType: mimeType,
              srcPath: newPath,
            );

            if (safUri == null || safUri.isEmpty) {
              try { await File(newPath).delete(); } catch (_) {}
              if (safTempPath != null) {
                try { await File(safTempPath).delete(); } catch (_) {}
              }
              continue;
            }

            try { await PlatformBridge.safDelete(item.filePath); } catch (_) {}
            await historyDb.updateFilePath(item.id, safUri, newSafFileName: newFileName);
          }
          try { await File(newPath).delete(); } catch (_) {}
          if (safTempPath != null) {
            try { await File(safTempPath).delete(); } catch (_) {}
          }
        } else {
          await historyDb.updateFilePath(item.id, newPath);
        }

        successCount++;
      } catch (_) {}
    }

    ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
    _exitSelectionMode();

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.selectionBatchConvertSuccess(successCount, total, targetFormat),
          ),
        ),
      );
    }
  }

  Widget _buildSelectionBottomBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<DownloadHistoryItem> tracks,
    double bottomPadding,
  ) {
    final selectedCount = _selectedIds.length;
    final allSelected = selectedCount == tracks.length && tracks.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding > 0 ? 8 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _exitSelectionMode,
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.downloadedAlbumSelectedCount(selectedCount),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          allSelected
                              ? context.l10n.downloadedAlbumAllSelected
                              : context.l10n.downloadedAlbumTapToSelect,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      if (allSelected) {
                        _exitSelectionMode();
                      } else {
                        _selectAll(tracks);
                      }
                    },
                    icon: Icon(
                      allSelected ? Icons.deselect : Icons.select_all,
                      size: 20,
                    ),
                    label: Text(
                      allSelected
                          ? context.l10n.actionDeselect
                          : context.l10n.actionSelectAll,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Action buttons row: Share, Convert
              Row(
                children: [
                  Expanded(
                    child: _DownloadedAlbumSelectionActionButton(
                      icon: Icons.share_outlined,
                      label: context.l10n.selectionShareCount(selectedCount),
                      onPressed: selectedCount > 0
                          ? () => _shareSelected(tracks)
                          : null,
                      colorScheme: colorScheme,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DownloadedAlbumSelectionActionButton(
                      icon: Icons.swap_horiz,
                      label: context.l10n.selectionConvertCount(selectedCount),
                      onPressed: selectedCount > 0
                          ? () => _showBatchConvertSheet(context, tracks)
                          : null,
                      colorScheme: colorScheme,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: selectedCount > 0
                      ? () => _deleteSelected(tracks)
                      : null,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    selectedCount > 0
                        ? context.l10n.downloadedAlbumDeleteCount(selectedCount)
                        : context.l10n.downloadedAlbumSelectToDelete,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: selectedCount > 0
                        ? colorScheme.error
                        : colorScheme.surfaceContainerHighest,
                    foregroundColor: selectedCount > 0
                        ? colorScheme.onError
                        : colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadedAlbumSelectionActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final ColorScheme colorScheme;

  const _DownloadedAlbumSelectionActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;
    return Material(
      color: isDisabled
          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isDisabled
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDisabled
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                        : colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
