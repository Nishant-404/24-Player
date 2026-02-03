import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/upload_queue_provider.dart';
import 'package:spotiflac_android/services/cloud_upload_service.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

class CloudSettingsPage extends ConsumerStatefulWidget {
  const CloudSettingsPage({super.key});

  @override
  ConsumerState<CloudSettingsPage> createState() => _CloudSettingsPageState();
}

class _CloudSettingsPageState extends ConsumerState<CloudSettingsPage> {
  late TextEditingController _serverUrlController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _remotePathController;
  bool _isTestingConnection = false;
  bool _isResettingHostKey = false;
  bool _isResettingAllHostKeys = false;
  String? _connectionTestResult;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _serverUrlController = TextEditingController(text: settings.cloudServerUrl);
    _usernameController = TextEditingController(text: settings.cloudUsername);
    _passwordController = TextEditingController(text: settings.cloudPassword);
    _remotePathController = TextEditingController(text: settings.cloudRemotePath);
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remotePathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 120 + topPadding,
              collapsedHeight: kToolbarHeight,
              floating: false,
              pinned: true,
              backgroundColor: colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  final maxHeight = 120 + topPadding;
                  final minHeight = kToolbarHeight + topPadding;
                  final expandRatio =
                      ((constraints.maxHeight - minHeight) /
                              (maxHeight - minHeight))
                          .clamp(0.0, 1.0);
                  final leftPadding = 56 - (32 * expandRatio);
                  return FlexibleSpaceBar(
                    expandedTitleScale: 1.0,
                    titlePadding: EdgeInsets.only(
                      left: leftPadding,
                      bottom: 16,
                    ),
                    title: Text(
                      context.l10n.cloudSettingsTitle,
                      style: TextStyle(
                        fontSize: 20 + (8 * expandRatio),
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Enable Cloud Upload
            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.cloudSettingsSectionGeneral),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsSwitchItem(
                    icon: Icons.cloud_upload_outlined,
                    title: context.l10n.cloudSettingsEnable,
                    subtitle: context.l10n.cloudSettingsEnableSubtitle,
                    value: settings.cloudUploadEnabled,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setCloudUploadEnabled(value);
                    },
                    showDivider: false,
                  ),
                ],
              ),
            ),

            // Provider Selection
            if (settings.cloudUploadEnabled) ...[
              SliverToBoxAdapter(
                child: SettingsSectionHeader(title: context.l10n.cloudSettingsSectionProvider),
              ),
              SliverToBoxAdapter(
                child: SettingsGroup(
                  children: [
                    SettingsItem(
                      icon: Icons.dns_outlined,
                      title: context.l10n.cloudSettingsProvider,
                      subtitle: _getProviderName(settings.cloudProvider),
                      onTap: () => _showProviderPicker(context, settings.cloudProvider),
                      showDivider: false,
                    ),
                  ],
                ),
              ),

              // Server Configuration (for WebDAV/SFTP)
              if (settings.cloudProvider != 'none' && settings.cloudProvider != 'gdrive') ...[
                SliverToBoxAdapter(
                  child: SettingsSectionHeader(title: context.l10n.cloudSettingsSectionServer),
                ),
                SliverToBoxAdapter(
                  child: SettingsGroup(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: TextField(
                          controller: _serverUrlController,
                          decoration: InputDecoration(
                            labelText: context.l10n.cloudSettingsServerUrl,
                            hintText: settings.cloudProvider == 'webdav'
                                ? 'https://your-server.com/webdav'
                                : 'sftp://your-server.com:22',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.link),
                          ),
                          onChanged: (value) {
                            ref.read(settingsProvider.notifier).setCloudServerUrl(value);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: context.l10n.cloudSettingsUsername,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          onChanged: (value) {
                            ref.read(settingsProvider.notifier).setCloudUsername(value);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: context.l10n.cloudSettingsPassword,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock_outline),
                          ),
                          onChanged: (value) {
                            ref.read(settingsProvider.notifier).setCloudPassword(value);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: TextField(
                          controller: _remotePathController,
                          decoration: InputDecoration(
                            labelText: context.l10n.cloudSettingsRemotePath,
                            hintText: '/Music/SpotiFLAC',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.folder_outlined),
                          ),
                          onChanged: (value) {
                            ref.read(settingsProvider.notifier).setCloudRemotePath(value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (settings.cloudProvider == 'webdav')
                  SliverToBoxAdapter(
                    child: SettingsGroup(
                      children: [
                        SettingsSwitchItem(
                          icon: Icons.warning_amber_outlined,
                          title: context.l10n.cloudSettingsAllowHttpTitle,
                          subtitle: context.l10n.cloudSettingsAllowHttpSubtitle,
                          value: settings.cloudAllowInsecureHttp,
                          onChanged: _handleAllowHttpChanged,
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),

                // Test Connection Button
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: FilledButton.icon(
                      onPressed: _isTestingConnection ? null : _testConnection,
                      icon: _isTestingConnection
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(context.l10n.cloudSettingsTestConnection),
                    ),
                  ),
                ),
                if (settings.cloudProvider == 'sftp')
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: OutlinedButton.icon(
                        onPressed: (_isResettingHostKey || settings.cloudServerUrl.isEmpty)
                            ? null
                            : _resetSftpHostKey,
                        icon: _isResettingHostKey
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.security),
                        label: Text(context.l10n.cloudSettingsResetSftpHostKey),
                      ),
                    ),
                  ),
                if (settings.cloudProvider == 'sftp')
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: OutlinedButton.icon(
                        onPressed: _isResettingAllHostKeys ? null : _resetAllSftpHostKeys,
                        icon: _isResettingAllHostKeys
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_sweep),
                        label: Text(context.l10n.cloudSettingsResetAllSftpHostKeys),
                      ),
                    ),
                  ),

                // Connection Test Result
                if (_connectionTestResult != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Card(
                        color: _connectionTestResult!.startsWith('Success')
                            ? colorScheme.primaryContainer
                            : colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(
                                _connectionTestResult!.startsWith('Success')
                                    ? Icons.check_circle
                                    : Icons.error,
                                color: _connectionTestResult!.startsWith('Success')
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _connectionTestResult!,
                                  style: TextStyle(
                                    color: _connectionTestResult!.startsWith('Success')
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],

              // Info about the feature
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Card(
                    color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: colorScheme.tertiary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.l10n.cloudSettingsInfo,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Upload Queue Section
              SliverToBoxAdapter(
                child: _buildUploadQueueSection(context),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  String _getProviderName(String provider) {
    switch (provider) {
      case 'webdav':
        return context.l10n.cloudProviderWebdav;
      case 'sftp':
        return context.l10n.cloudProviderSftp;
      default:
        return context.l10n.cloudProviderNotConfigured;
    }
  }

  void _showProviderPicker(BuildContext context, String current) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                context.l10n.cloudSettingsProvider,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                context.l10n.cloudSettingsProviderDescription,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.web),
              title: Text(context.l10n.cloudProviderWebdavTitle),
              subtitle: Text(context.l10n.cloudProviderWebdavSubtitle),
              trailing: current == 'webdav' ? Icon(Icons.check, color: colorScheme.primary) : null,
              onTap: () {
                ref.read(settingsProvider.notifier).setCloudProvider('webdav');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.terminal),
              title: Text(context.l10n.cloudProviderSftpTitle),
              subtitle: Text(context.l10n.cloudProviderSftpSubtitle),
              trailing: current == 'sftp' ? Icon(Icons.check, color: colorScheme.primary) : null,
              onTap: () {
                ref.read(settingsProvider.notifier).setCloudProvider('sftp');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _connectionTestResult = null;
    });

    final settings = ref.read(settingsProvider);
    
    if (settings.cloudServerUrl.isEmpty) {
      setState(() {
        _isTestingConnection = false;
        _connectionTestResult = context.l10n.errorGeneric(context.l10n.cloudTestErrorServerUrlRequired);
      });
      return;
    }

    if (settings.cloudUsername.isEmpty || settings.cloudPassword.isEmpty) {
      setState(() {
        _isTestingConnection = false;
        _connectionTestResult = context.l10n.errorGeneric(context.l10n.cloudTestErrorCredentialsRequired);
      });
      return;
    }

    if (settings.cloudProvider == 'webdav') {
      final result = await CloudUploadService.instance.testWebDAVConnection(
        serverUrl: settings.cloudServerUrl,
        username: settings.cloudUsername,
        password: settings.cloudPassword,
        allowInsecureHttp: settings.cloudAllowInsecureHttp,
      );

      setState(() {
        _isTestingConnection = false;
        _connectionTestResult = result.success
            ? context.l10n.connectionTestSuccess(context.l10n.cloudTestSuccessWebdav)
            : context.l10n.errorGeneric(_localizeWebDavError(context, result));
      });
    } else if (settings.cloudProvider == 'sftp') {
      final result = await CloudUploadService.instance.testSFTPConnection(
        serverUrl: settings.cloudServerUrl,
        username: settings.cloudUsername,
        password: settings.cloudPassword,
      );

      setState(() {
        _isTestingConnection = false;
        _connectionTestResult = result.success
            ? context.l10n.connectionTestSuccess(context.l10n.cloudTestSuccessSftp)
            : context.l10n.errorGeneric(result.error ?? '');
      });
    } else {
      setState(() {
        _isTestingConnection = false;
        _connectionTestResult = context.l10n.errorGeneric(context.l10n.cloudTestErrorNoProvider);
      });
    }
  }

  Future<void> _handleAllowHttpChanged(bool value) async {
    if (!value) {
      ref.read(settingsProvider.notifier).setCloudAllowInsecureHttp(false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.cloudSettingsAllowHttpTitle),
          content: Text(context.l10n.cloudSettingsAllowHttpMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.dialogCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.cloudSettingsAllowHttpConfirm),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      ref.read(settingsProvider.notifier).setCloudAllowInsecureHttp(true);
    }
  }

  String _localizeWebDavError(
    BuildContext context,
    CloudUploadResult result,
  ) {
    switch (result.errorCode) {
      case 'webdav_invalid_scheme':
        return context.l10n.webdavErrorInvalidScheme;
      case 'webdav_https_required':
        return context.l10n.webdavErrorHttpsRequired;
      case 'webdav_invalid_host':
        return context.l10n.webdavErrorInvalidHost;
      case 'webdav_auth_failed':
        return context.l10n.webdavErrorAuthFailed;
      case 'webdav_forbidden':
        return context.l10n.webdavErrorForbidden;
      case 'webdav_not_found':
        return context.l10n.webdavErrorNotFound;
      case 'webdav_connection_failed':
        return context.l10n.webdavErrorConnectionFailed;
      case 'webdav_tls_error':
        return context.l10n.webdavErrorTlsError;
      case 'webdav_timeout':
        return context.l10n.webdavErrorTimeout;
      case 'webdav_insufficient_storage':
        return context.l10n.webdavErrorInsufficientStorage;
      case 'webdav_unknown':
        return result.error ?? context.l10n.webdavErrorUnknown;
      default:
        return result.error ?? context.l10n.webdavErrorUnknown;
    }
  }

  Future<void> _resetSftpHostKey() async {
    final settings = ref.read(settingsProvider);
    if (settings.cloudServerUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.cloudSettingsServerUrlRequired)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.cloudSettingsResetSftpHostKey),
          content: Text(context.l10n.cloudSettingsResetSftpHostKeyMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.dialogCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.cloudSettingsResetConfirm),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isResettingHostKey = true;
    });

    final cleared = await CloudUploadService.instance.clearSftpHostKey(
      serverUrl: settings.cloudServerUrl,
    );

    if (!mounted) return;
    setState(() {
      _isResettingHostKey = false;
    });

    final message = cleared
        ? context.l10n.cloudSettingsResetSftpHostKeySuccess
        : context.l10n.cloudSettingsResetSftpHostKeyNotFound;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _resetAllSftpHostKeys() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.cloudSettingsResetAllSftpHostKeys),
          content: Text(context.l10n.cloudSettingsResetAllSftpHostKeysMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.dialogCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.cloudSettingsResetAllConfirm),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isResettingAllHostKeys = true;
    });

    final clearedCount = await CloudUploadService.instance.clearAllSftpHostKeys();

    if (!mounted) return;
    setState(() {
      _isResettingAllHostKeys = false;
    });

    final message = clearedCount > 0
        ? context.l10n.cloudSettingsResetAllSftpHostKeysCleared(clearedCount)
        : context.l10n.cloudSettingsResetAllSftpHostKeysNone;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildUploadQueueSection(BuildContext context) {
    final uploadState = ref.watch(uploadQueueProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(title: context.l10n.cloudSettingsUploadQueue),
        SettingsGroup(
          children: [
            // Stats row
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    context,
                    Icons.hourglass_empty,
                    uploadState.pendingCount.toString(),
                    context.l10n.uploadStatusPending,
                    colorScheme.tertiary,
                  ),
                  _buildStatItem(
                    context,
                    Icons.cloud_upload,
                    uploadState.uploadingCount.toString(),
                    context.l10n.uploadStatusUploading,
                    colorScheme.primary,
                  ),
                  _buildStatItem(
                    context,
                    Icons.check_circle,
                    uploadState.completedCount.toString(),
                    context.l10n.uploadStatusDone,
                    Colors.green,
                  ),
                  _buildStatItem(
                    context,
                    Icons.error,
                    uploadState.failedCount.toString(),
                    context.l10n.uploadStatusFailed,
                    colorScheme.error,
                  ),
                ],
              ),
            ),
            
            // Action buttons
            if (uploadState.failedCount > 0 || uploadState.completedCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    if (uploadState.failedCount > 0)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref.read(uploadQueueProvider.notifier).retryAllFailed();
                          },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(context.l10n.cloudSettingsRetryFailed),
                        ),
                      ),
                    if (uploadState.failedCount > 0 && uploadState.completedCount > 0)
                      const SizedBox(width: 12),
                    if (uploadState.completedCount > 0)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref.read(uploadQueueProvider.notifier).clearCompleted();
                          },
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: Text(context.l10n.cloudSettingsClearDone),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),

        // Recent uploads list (show last 5)
        if (uploadState.items.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              context.l10n.cloudSettingsRecentUploads,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ...uploadState.items.reversed.take(5).map((item) => _buildUploadItem(context, item)),
        ],
      ],
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildUploadItem(BuildContext context, UploadQueueItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    
    IconData icon;
    Color iconColor;
    Widget? trailing;

    switch (item.status) {
      case UploadStatus.pending:
        icon = Icons.hourglass_empty;
        iconColor = colorScheme.tertiary;
        break;
      case UploadStatus.uploading:
        icon = Icons.cloud_upload;
        iconColor = colorScheme.primary;
        trailing = SizedBox(
          width: 40,
          child: Text(
            '${(item.progress * 100).toInt()}%',
            style: TextStyle(color: colorScheme.primary),
          ),
        );
        break;
      case UploadStatus.completed:
        icon = Icons.check_circle;
        iconColor = Colors.green;
        break;
      case UploadStatus.failed:
        icon = Icons.error;
        iconColor = colorScheme.error;
        trailing = IconButton(
          icon: Icon(Icons.refresh, color: colorScheme.primary),
          onPressed: () {
            ref.read(uploadQueueProvider.notifier).retryFailed(item.id);
          },
          tooltip: context.l10n.dialogRetry,
        );
        break;
    }

    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        item.trackName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        item.artistName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      trailing: trailing,
      dense: true,
    );
  }
}
