import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/services/cloud_upload_service.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';

/// Status of an upload item
enum UploadStatus {
  pending,
  uploading,
  completed,
  failed,
}

/// An item in the upload queue
class UploadQueueItem {
  final String id;
  final String localPath;
  final String remotePath;
  final String trackName;
  final String artistName;
  final UploadStatus status;
  final double progress;
  final String? error;
  final DateTime queuedAt;
  final DateTime? completedAt;

  const UploadQueueItem({
    required this.id,
    required this.localPath,
    required this.remotePath,
    required this.trackName,
    required this.artistName,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
    this.error,
    required this.queuedAt,
    this.completedAt,
  });

  UploadQueueItem copyWith({
    UploadStatus? status,
    double? progress,
    String? error,
    DateTime? completedAt,
  }) {
    return UploadQueueItem(
      id: id,
      localPath: localPath,
      remotePath: remotePath,
      trackName: trackName,
      artistName: artistName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      queuedAt: queuedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// State of the upload queue
class UploadQueueState {
  final List<UploadQueueItem> items;
  final bool isProcessing;
  final int completedCount;
  final int failedCount;

  const UploadQueueState({
    this.items = const [],
    this.isProcessing = false,
    this.completedCount = 0,
    this.failedCount = 0,
  });

  UploadQueueState copyWith({
    List<UploadQueueItem>? items,
    bool? isProcessing,
    int? completedCount,
    int? failedCount,
  }) {
    return UploadQueueState(
      items: items ?? this.items,
      isProcessing: isProcessing ?? this.isProcessing,
      completedCount: completedCount ?? this.completedCount,
      failedCount: failedCount ?? this.failedCount,
    );
  }

  int get pendingCount => items.where((i) => i.status == UploadStatus.pending).length;
  int get uploadingCount => items.where((i) => i.status == UploadStatus.uploading).length;
}

/// Provider for managing the cloud upload queue
class UploadQueueNotifier extends Notifier<UploadQueueState> {
  final CloudUploadService _uploadService = CloudUploadService.instance;
  bool _isProcessing = false;

  @override
  UploadQueueState build() {
    return const UploadQueueState();
  }

  /// Add a file to the upload queue
  void addToQueue({
    required String localPath,
    required String trackName,
    required String artistName,
  }) {
    final settings = ref.read(settingsProvider);
    
    // Don't add if cloud upload is disabled
    if (!settings.cloudUploadEnabled || settings.cloudProvider == 'none') {
      return;
    }

    final remotePath = _uploadService.getRemotePath(
      localFilePath: localPath,
      baseRemotePath: settings.cloudRemotePath,
      downloadDirectory: settings.downloadDirectory,
    );

    final item = UploadQueueItem(
      id: '${DateTime.now().millisecondsSinceEpoch}_${localPath.hashCode}',
      localPath: localPath,
      remotePath: remotePath,
      trackName: trackName,
      artistName: artistName,
      queuedAt: DateTime.now(),
    );

    state = state.copyWith(
      items: [...state.items, item],
    );

    // Start processing if not already
    _processQueue();
  }

  /// Process the upload queue
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    state = state.copyWith(isProcessing: true);

    while (true) {
      final settings = ref.read(settingsProvider);

      // Stop processing if cloud upload is disabled or provider is unset
      if (!settings.cloudUploadEnabled || settings.cloudProvider == 'none') {
        break;
      }

      // Find next pending item
      final pendingIndex = state.items.indexWhere(
        (i) => i.status == UploadStatus.pending,
      );

      if (pendingIndex == -1) break;

      // Update status to uploading
      final item = state.items[pendingIndex];
      _updateItem(pendingIndex, item.copyWith(status: UploadStatus.uploading));

      // Perform upload based on provider
      CloudUploadResult result;
      if (settings.cloudProvider == 'webdav') {
        result = await _uploadService.uploadFileWebDAV(
          localPath: item.localPath,
          remotePath: item.remotePath,
          serverUrl: settings.cloudServerUrl,
          username: settings.cloudUsername,
          password: settings.cloudPassword,
          allowInsecureHttp: settings.cloudAllowInsecureHttp,
          onProgress: (sent, total) {
            if (total > 0) {
              final progress = sent / total;
              _updateItem(pendingIndex, item.copyWith(
                status: UploadStatus.uploading,
                progress: progress,
              ));
            }
          },
        );
      } else if (settings.cloudProvider == 'sftp') {
        result = await _uploadService.uploadFileSFTP(
          localPath: item.localPath,
          remotePath: item.remotePath,
          serverUrl: settings.cloudServerUrl,
          username: settings.cloudUsername,
          password: settings.cloudPassword,
          onProgress: (sent, total) {
            if (total > 0) {
              final progress = sent / total;
              _updateItem(pendingIndex, item.copyWith(
                status: UploadStatus.uploading,
                progress: progress,
              ));
            }
          },
        );
      } else {
        result = CloudUploadResult.failure('Unknown cloud provider: ${settings.cloudProvider}');
      }

      // Update status based on result
      if (result.success) {
        _updateItem(pendingIndex, item.copyWith(
          status: UploadStatus.completed,
          progress: 1.0,
          completedAt: DateTime.now(),
        ));
        state = state.copyWith(completedCount: state.completedCount + 1);
      } else {
        _updateItem(pendingIndex, item.copyWith(
          status: UploadStatus.failed,
          error: result.error,
        ));
        state = state.copyWith(failedCount: state.failedCount + 1);
      }

      // Small delay between uploads to prevent overwhelming the server
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isProcessing = false;
    state = state.copyWith(isProcessing: false);
  }

  void _updateItem(int index, UploadQueueItem item) {
    if (index < 0 || index >= state.items.length) return;
    
    final items = [...state.items];
    items[index] = item;
    state = state.copyWith(items: items);
  }

  /// Retry a failed upload
  void retryFailed(String id) {
    final index = state.items.indexWhere((i) => i.id == id);
    if (index == -1) return;

    final item = state.items[index];
    if (item.status != UploadStatus.failed) return;

    _updateItem(index, item.copyWith(
      status: UploadStatus.pending,
      progress: 0.0,
      error: null,
    ));

    state = state.copyWith(failedCount: state.failedCount - 1);
    _processQueue();
  }

  /// Retry all failed uploads
  void retryAllFailed() {
    final items = state.items.map((item) {
      if (item.status == UploadStatus.failed) {
        return item.copyWith(
          status: UploadStatus.pending,
          progress: 0.0,
          error: null,
        );
      }
      return item;
    }).toList();

    state = state.copyWith(
      items: items,
      failedCount: 0,
    );

    _processQueue();
  }

  /// Remove completed items from queue
  void clearCompleted() {
    final items = state.items.where(
      (i) => i.status != UploadStatus.completed,
    ).toList();

    state = state.copyWith(
      items: items,
      completedCount: 0,
    );
  }

  /// Remove a specific item from queue
  void removeItem(String id) {
    final items = state.items.where((i) => i.id != id).toList();
    state = state.copyWith(items: items);
  }

  /// Clear all items from queue
  void clearAll() {
    state = const UploadQueueState();
  }
}

final uploadQueueProvider = NotifierProvider<UploadQueueNotifier, UploadQueueState>(
  UploadQueueNotifier.new,
);
