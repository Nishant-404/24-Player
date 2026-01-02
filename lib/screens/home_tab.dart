import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/track_provider.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});
  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  Timer? _debounce;
  bool _isTyping = false;
  final FocusNode _searchFocusNode = FocusNode();
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onSearchChanged);
  }
  
  @override
  void dispose() {
    _debounce?.cancel();
    _urlController.removeListener(_onSearchChanged);
    _urlController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Called when trackState changes - used to sync search bar with state
  void _onTrackStateChanged(TrackState? previous, TrackState next) {
    // If state was cleared (no content, no search text, not loading), clear the search bar
    if (previous != null && 
        !next.hasContent && 
        !next.hasSearchText && 
        !next.isLoading &&
        _urlController.text.isNotEmpty) {
      _urlController.clear();
      setState(() => _isTyping = false);
    }
  }  void _onSearchChanged() {
    final text = _urlController.text.trim();
    final wasFocused = _searchFocusNode.hasFocus;
    
    // Update search text state for MainShell back button handling
    ref.read(trackProvider.notifier).setSearchText(text.isNotEmpty);
    
    // Update typing state immediately for UI transition
    if (text.isNotEmpty && !_isTyping) {
      setState(() => _isTyping = true);
    } else if (text.isEmpty && _isTyping) {
      setState(() => _isTyping = false);
      ref.read(trackProvider.notifier).clear();
      return;
    }
    
    // Re-request focus after rebuild if it was focused
    if (wasFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    }
    
    // Debounce all requests (URLs and searches)
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (text.isEmpty) return;
      
      if (text.startsWith('http') || text.startsWith('spotify:')) {
        _fetchMetadata();
      } else if (text.length >= 2) {
        _performSearch(text);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    await ref.read(trackProvider.notifier).search(query);
    ref.read(settingsProvider.notifier).setHasSearchedBefore();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlController.text = data!.text!;
      // For URLs, trigger fetch immediately after paste
      final text = data.text!.trim();
      if (text.startsWith('http') || text.startsWith('spotify:')) {
        _fetchMetadata();
      }
    }
  }

  Future<void> _clearAndRefresh() async {
    _debounce?.cancel();
    _urlController.clear();
    _searchFocusNode.unfocus();
    setState(() => _isTyping = false);
    ref.read(trackProvider.notifier).clear();
  }

  Future<void> _fetchMetadata() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (url.startsWith('http') || url.startsWith('spotify:')) {
      await ref.read(trackProvider.notifier).fetchFromUrl(url);
    } else {
      await ref.read(trackProvider.notifier).search(url);
    }
    ref.read(settingsProvider.notifier).setHasSearchedBefore();
  }

  void _downloadTrack(int index) {
    final trackState = ref.read(trackProvider);
    if (index >= 0 && index < trackState.tracks.length) {
      final track = trackState.tracks[index];
      final settings = ref.read(settingsProvider);
      
      if (settings.askQualityBeforeDownload) {
        _showQualityPicker(context, (quality) {
          ref.read(downloadQueueProvider.notifier).addToQueue(track, settings.defaultService, qualityOverride: quality);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${track.name}" to queue')));
        });
      } else {
        ref.read(downloadQueueProvider.notifier).addToQueue(track, settings.defaultService);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${track.name}" to queue')));
      }
    }
  }

  void _downloadAll() {
    final trackState = ref.read(trackProvider);
    if (trackState.tracks.isEmpty) return;
    final settings = ref.read(settingsProvider);
    
    if (settings.askQualityBeforeDownload) {
      _showQualityPicker(context, (quality) {
        ref.read(downloadQueueProvider.notifier).addMultipleToQueue(trackState.tracks, settings.defaultService, qualityOverride: quality);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${trackState.tracks.length} tracks to queue')));
      });
    } else {
      ref.read(downloadQueueProvider.notifier).addMultipleToQueue(trackState.tracks, settings.defaultService);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${trackState.tracks.length} tracks to queue')));
    }
  }

  void _showQualityPicker(BuildContext context, void Function(String quality) onSelect) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text('Select Quality', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            _QualityPickerOption(
              title: 'FLAC Lossless',
              subtitle: '16-bit / 44.1kHz',
              onTap: () { Navigator.pop(context); onSelect('LOSSLESS'); },
            ),
            _QualityPickerOption(
              title: 'Hi-Res FLAC',
              subtitle: '24-bit / up to 96kHz',
              onTap: () { Navigator.pop(context); onSelect('HI_RES'); },
            ),
            _QualityPickerOption(
              title: 'Hi-Res FLAC Max',
              subtitle: '24-bit / up to 192kHz',
              onTap: () { Navigator.pop(context); onSelect('HI_RES_LOSSLESS'); },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // Listen for state changes to sync search bar
    ref.listen<TrackState>(trackProvider, _onTrackStateChanged);
    
    // Use select() to only rebuild when specific fields change
    final tracks = ref.watch(trackProvider.select((s) => s.tracks));
    final isLoading = ref.watch(trackProvider.select((s) => s.isLoading));
    final error = ref.watch(trackProvider.select((s) => s.error));
    final albumName = ref.watch(trackProvider.select((s) => s.albumName));
    final playlistName = ref.watch(trackProvider.select((s) => s.playlistName));
    final artistName = ref.watch(trackProvider.select((s) => s.artistName));
    final coverUrl = ref.watch(trackProvider.select((s) => s.coverUrl));
    final artistAlbums = ref.watch(trackProvider.select((s) => s.artistAlbums));
    final hasSearchedBefore = ref.watch(settingsProvider.select((s) => s.hasSearchedBefore));
    
    final colorScheme = Theme.of(context).colorScheme;
    final hasResults = _isTyping || tracks.isNotEmpty || artistAlbums != null || isLoading;
    final screenHeight = MediaQuery.of(context).size.height;
    final historyItems = ref.watch(downloadHistoryProvider.select((s) => s.items));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar - always present
          SliverAppBar(
            expandedHeight: 130,
            collapsedHeight: kToolbarHeight,
            floating: false,
            pinned: true,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              expandedTitleScale: 1.3,
              titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
              title: Text(
                'Home',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
          
          // Idle content (logo, title) - always in tree, animated size
          SliverToBoxAdapter(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: hasResults
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        SizedBox(height: screenHeight * 0.06),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.music_note, size: 48, color: colorScheme.primary),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'SpotiFLAC',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Paste a Spotify link or search by name',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          
          // Search bar - always present at same position in tree
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, hasResults ? 8 : 32, 16, hasResults ? 8 : 16),
              child: _buildSearchBar(colorScheme),
            ),
          ),
          
          // Idle content below search bar - always in tree
          SliverToBoxAdapter(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: hasResults
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        if (!hasSearchedBefore)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Supports: Track, Album, Playlist, Artist URLs',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (historyItems.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                            child: _buildRecentDownloads(historyItems, colorScheme),
                          ),
                      ],
                    ),
            ),
          ),
          
          // Results content - always in tree
          ..._buildResultsContentOptimized(
            tracks: tracks,
            isLoading: isLoading,
            error: error,
            albumName: albumName,
            playlistName: playlistName,
            artistName: artistName,
            coverUrl: coverUrl,
            artistAlbums: artistAlbums,
            colorScheme: colorScheme,
            hasResults: hasResults,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentDownloads(List<DownloadHistoryItem> items, ColorScheme colorScheme) {
    final displayItems = items.take(10).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Recent',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              final item = displayItems[index];
              return KeyedSubtree(
                key: ValueKey(item.id),
                child: GestureDetector(
                  onTap: () => _navigateToMetadataScreen(item),
                  child: Container(
                    width: 60,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: item.coverUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: item.coverUrl!,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 112,
                                  memCacheHeight: 112,
                                )
                              : Container(
                                  width: 56,
                                  height: 56,
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant, size: 24),
                                ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.trackName,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _navigateToMetadataScreen(DownloadHistoryItem item) {
    Navigator.push(context, PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) => TrackMetadataScreen(item: item),
      transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
    ));
  }

  // Results content slivers (without app bar and search bar) - optimized version
  List<Widget> _buildResultsContentOptimized({
    required List<Track> tracks,
    required bool isLoading,
    required String? error,
    required String? albumName,
    required String? playlistName,
    required String? artistName,
    required String? coverUrl,
    required List<ArtistAlbum>? artistAlbums,
    required ColorScheme colorScheme,
    required bool hasResults,
  }) {
    // Return empty slivers when no results to keep tree structure stable
    if (!hasResults) {
      return [const SliverToBoxAdapter(child: SizedBox.shrink())];
    }
    
    return [
      // Error message
      if (error != null)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(error, style: TextStyle(color: colorScheme.error)),
        )),

      // Loading indicator
      if (isLoading)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: LinearProgressIndicator())),

      // Album/Playlist header
      if (albumName != null || playlistName != null)
        SliverToBoxAdapter(child: _buildHeaderOptimized(
          albumName: albumName,
          playlistName: playlistName,
          coverUrl: coverUrl,
          trackCount: tracks.length,
          colorScheme: colorScheme,
        )),

      // Artist header and discography
      if (artistName != null && artistAlbums != null)
        SliverToBoxAdapter(child: _buildArtistHeaderOptimized(
          artistName: artistName,
          coverUrl: coverUrl,
          albumCount: artistAlbums.length,
          colorScheme: colorScheme,
        )),

      if (artistAlbums != null && artistAlbums.isNotEmpty)
        SliverToBoxAdapter(child: _buildArtistDiscographyOptimized(artistAlbums, colorScheme)),

      // Download All button
      if (tracks.length > 1 && albumName == null && playlistName == null && artistAlbums == null)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.icon(onPressed: _downloadAll, icon: const Icon(Icons.download),
            label: Text('Download All (${tracks.length})'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48))),
        )),

      // Track list with keys for efficient updates
      SliverList(delegate: SliverChildBuilderDelegate(
        (context, index) {
          final track = tracks[index];
          return KeyedSubtree(
            key: ValueKey(track.id),
            child: _buildTrackTileOptimized(track, index, colorScheme),
          );
        },
        childCount: tracks.length,
      )),

      // Bottom padding
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];
  }

  Widget _buildHeaderOptimized({
    required String? albumName,
    required String? playlistName,
    required String? coverUrl,
    required int trackCount,
    required ColorScheme colorScheme,
  }) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (coverUrl != null)
              ClipRRect(borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(imageUrl: coverUrl, width: 80, height: 80, fit: BoxFit.cover,
                  placeholder: (_, _) => Container(width: 80, height: 80, color: colorScheme.surfaceContainerHighest))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(albumName ?? playlistName ?? '',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('$trackCount tracks',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
            ])),
            FilledButton.tonal(onPressed: _downloadAll,
              style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(16)),
              child: const Icon(Icons.download)),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistHeaderOptimized({
    required String? artistName,
    required String? coverUrl,
    required int albumCount,
    required ColorScheme colorScheme,
  }) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (coverUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: CachedNetworkImage(
                  imageUrl: coverUrl,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    width: 80,
                    height: 80,
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.person, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artistName ?? '',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$albumCount releases',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistDiscographyOptimized(List<ArtistAlbum> albums, ColorScheme colorScheme) {
    final albumsOnly = albums.where((a) => a.albumType == 'album').toList();
    final singles = albums.where((a) => a.albumType == 'single').toList();
    final compilations = albums.where((a) => a.albumType == 'compilation').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (albumsOnly.isNotEmpty) _buildAlbumSection('Albums', albumsOnly, colorScheme),
        if (singles.isNotEmpty) _buildAlbumSection('Singles & EPs', singles, colorScheme),
        if (compilations.isNotEmpty) _buildAlbumSection('Compilations', compilations, colorScheme),
      ],
    );
  }

  Widget _buildTrackTileOptimized(Track track, int index, ColorScheme colorScheme) {
    return ListTile(
      leading: track.coverUrl != null
          ? ClipRRect(borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: track.coverUrl!, 
                width: 48, 
                height: 48, 
                fit: BoxFit.cover,
                memCacheWidth: 96,
                memCacheHeight: 96,
              ))
          : Container(width: 48, height: 48,
              decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant)),
      title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(track.artistName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colorScheme.onSurfaceVariant)),
      trailing: IconButton(icon: Icon(Icons.download, color: colorScheme.primary), onPressed: () => _downloadTrack(index)),
      onTap: () => _downloadTrack(index),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    final hasText = _urlController.text.isNotEmpty;
    
    return TextField(
      controller: _urlController,
      focusNode: _searchFocusNode,
      autofocus: false,
      decoration: InputDecoration(
        hintText: 'Paste Spotify URL or search...',
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: _clearAndRefresh,
                tooltip: 'Clear',
              )
            else
              IconButton(
                icon: const Icon(Icons.paste),
                onPressed: _pasteFromClipboard,
                tooltip: 'Paste',
              ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      onSubmitted: (_) => _fetchMetadata(),
    );
  }

  Widget _buildAlbumSection(String title, List<ArtistAlbum> albums, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            '$title (${albums.length})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return KeyedSubtree(
                key: ValueKey(album.id),
                child: _buildAlbumCard(album, colorScheme),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumCard(ArtistAlbum album, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => _fetchAlbum(album.id),
      child: Container(
        width: 130,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: album.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: album.coverUrl!,
                      width: 130,
                      height: 130,
                      fit: BoxFit.cover,
                      memCacheWidth: 260,
                      memCacheHeight: 260,
                    )
                  : Container(
                      width: 130,
                      height: 130,
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.album, color: colorScheme.onSurfaceVariant),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${album.releaseDate.length >= 4 ? album.releaseDate.substring(0, 4) : album.releaseDate} • ${album.totalTracks} tracks',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _fetchAlbum(String albumId) {
    // Use fetchAlbumFromArtist to save artist state for back navigation
    ref.read(trackProvider.notifier).fetchAlbumFromArtist(albumId);
    ref.read(settingsProvider.notifier).setHasSearchedBefore();
  }
}

class _QualityPickerOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QualityPickerOption({required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(Icons.music_note, color: colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: colorScheme.onSurfaceVariant)),
      onTap: onTap,
    );
  }
}
