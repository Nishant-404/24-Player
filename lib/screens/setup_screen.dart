import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  int _currentStep = 0;
  bool _storagePermissionGranted = false;
  bool _notificationPermissionGranted = false;
  String? _selectedDirectory;
  bool _isLoading = false;
  int _androidSdkVersion = 0;

  // Total steps: Storage -> Notification (Android 13+) -> Folder
  int get _totalSteps => _androidSdkVersion >= 33 ? 3 : 2;

  @override
  void initState() {
    super.initState();
    _initDeviceInfo();
  }

  Future<void> _initDeviceInfo() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      _androidSdkVersion = androidInfo.version.sdkInt;
      debugPrint('Android SDK Version: $_androidSdkVersion');
    }
    await _checkInitialPermissions();
  }

  Future<void> _checkInitialPermissions() async {
    if (Platform.isIOS) {
      if (mounted) {
        setState(() {
          _storagePermissionGranted = true;
          _notificationPermissionGranted = true;
        });
      }
    } else if (Platform.isAndroid) {
      // Check storage permission
      PermissionStatus storageStatus;
      if (_androidSdkVersion >= 33) {
        storageStatus = await Permission.audio.status;
      } else if (_androidSdkVersion >= 30) {
        storageStatus = await Permission.manageExternalStorage.status;
      } else {
        storageStatus = await Permission.storage.status;
      }
      
      // Check notification permission (Android 13+)
      PermissionStatus notificationStatus = PermissionStatus.granted;
      if (_androidSdkVersion >= 33) {
        notificationStatus = await Permission.notification.status;
      }
      
      if (mounted) {
        setState(() {
          _storagePermissionGranted = storageStatus.isGranted;
          _notificationPermissionGranted = notificationStatus.isGranted;
        });
      }
    }
  }

  Future<void> _requestStoragePermission() async {
    setState(() => _isLoading = true);

    try {
      if (Platform.isIOS) {
        setState(() => _storagePermissionGranted = true);
      } else if (Platform.isAndroid) {
        PermissionStatus status;
        
        if (_androidSdkVersion >= 33) {
          // Android 13+: Use audio permission
          status = await Permission.audio.request();
        } else if (_androidSdkVersion >= 30) {
          // Android 11-12: Need MANAGE_EXTERNAL_STORAGE
          // This opens system settings, not a dialog
          status = await Permission.manageExternalStorage.status;
          if (!status.isGranted) {
            // Show explanation dialog first
            if (mounted) {
              final shouldOpen = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Storage Access Required'),
                  content: const Text(
                    'Android 11+ requires "All files access" permission to save music files.\n\n'
                    'Please enable "Allow access to manage all files" in the next screen.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Open Settings'),
                    ),
                  ],
                ),
              );
              
              if (shouldOpen == true) {
                status = await Permission.manageExternalStorage.request();
              }
            }
          }
        } else {
          // Android 10 and below: Use legacy storage permission
          status = await Permission.storage.request();
        }
        
        if (status.isGranted) {
          setState(() => _storagePermissionGranted = true);
        } else if (status.isPermanentlyDenied) {
          _showPermissionDeniedDialog('Storage');
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permission denied. Please grant permission to continue.')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Permission error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _requestNotificationPermission() async {
    setState(() => _isLoading = true);

    try {
      if (_androidSdkVersion >= 33) {
        final status = await Permission.notification.request();
        if (status.isGranted) {
          setState(() => _notificationPermissionGranted = true);
        } else if (status.isPermanentlyDenied) {
          _showPermissionDeniedDialog('Notification');
        }
      } else {
        // Notification permission not needed for older Android
        setState(() => _notificationPermissionGranted = true);
      }
    } catch (e) {
      debugPrint('Notification permission error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _skipNotificationPermission() {
    setState(() => _notificationPermissionGranted = true);
  }

  void _showPermissionDeniedDialog(String permissionType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$permissionType Permission Required'),
        content: Text(
          '$permissionType permission is required for the best experience. '
          'Please grant permission in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDirectory() async {
    setState(() => _isLoading = true);

    try {
      if (Platform.isIOS) {
        // iOS: Show options dialog
        await _showIOSDirectoryOptions();
      } else {
        // Android: Use file picker
        String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Select Download Folder',
        );

        if (selectedDirectory != null) {
          setState(() => _selectedDirectory = selectedDirectory);
        } else {
          final defaultDir = await _getDefaultDirectory();
          if (mounted) {
            final useDefault = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Use Default Folder?'),
                content: Text('No folder selected. Would you like to use the default Music folder?\n\n$defaultDir'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Use Default')),
                ],
              ),
            );

            if (useDefault == true) {
              setState(() => _selectedDirectory = defaultDir);
            }
          }
        }
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showIOSDirectoryOptions() async {
    final colorScheme = Theme.of(context).colorScheme;
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text('Download Location', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                'On iOS, downloads are saved to the app\'s Documents folder which is accessible via the Files app.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            ListTile(
              leading: Icon(Icons.folder_special, color: colorScheme.primary),
              title: const Text('App Documents Folder'),
              subtitle: const Text('Recommended - accessible via Files app'),
              trailing: Icon(Icons.check_circle, color: colorScheme.primary),
              onTap: () async {
                final dir = await _getDefaultDirectory();
                setState(() => _selectedDirectory = dir);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.cloud, color: colorScheme.onSurfaceVariant),
              title: const Text('Choose from Files'),
              subtitle: const Text('Select iCloud or other location'),
              onTap: () async {
                Navigator.pop(ctx);
                // Note: iOS requires folder to have at least one file to be selectable
                final result = await FilePicker.platform.getDirectoryPath();
                if (result != null) {
                  setState(() => _selectedDirectory = result);
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: colorScheme.tertiary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'iOS limitation: Empty folders cannot be selected. Create a file inside first or use App Documents.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String> _getDefaultDirectory() async {
    if (Platform.isIOS) {
      final appDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${appDir.path}/SpotiFLAC');
      try {
        if (!await musicDir.exists()) {
          await musicDir.create(recursive: true);
        }
        return musicDir.path;
      } catch (e) {
        debugPrint('Cannot create SpotiFLAC folder: $e');
      }
      return '${appDir.path}/SpotiFLAC';
    } else if (Platform.isAndroid) {
      final musicDir = Directory('/storage/emulated/0/Music/SpotiFLAC');
      try {
        if (!await musicDir.exists()) {
          await musicDir.create(recursive: true);
        }
        return musicDir.path;
      } catch (e) {
        debugPrint('Cannot create Music folder: $e');
      }
    }
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/SpotiFLAC';
  }

  Future<void> _completeSetup() async {
    if (_selectedDirectory == null) return;

    setState(() => _isLoading = true);

    try {
      final dir = Directory(_selectedDirectory!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      ref.read(settingsProvider.notifier).setDownloadDirectory(_selectedDirectory!);
      ref.read(settingsProvider.notifier).setFirstLaunchComplete();

      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom - 48),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top section - Logo/Title
                Column(
                  children: [
                    const SizedBox(height: 24),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset('assets/images/logo.png', width: 96, height: 96),
                    ),
                    const SizedBox(height: 12),
                    Text('SpotiFLAC',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: colorScheme.primary)),
                    const SizedBox(height: 4),
                    Text('Download Spotify tracks in FLAC',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant)),
                  ],
                ),

                // Middle section - Steps and Content
                Column(
                  children: [
                    const SizedBox(height: 24),
                    _buildStepIndicator(colorScheme),
                    const SizedBox(height: 24),
                    _buildCurrentStepContent(colorScheme),
                  ],
                ),

                // Bottom section - Navigation Buttons
                Column(
                  children: [
                    const SizedBox(height: 24),
                    _buildNavigationButtons(colorScheme),
                    const SizedBox(height: 16),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(ColorScheme colorScheme) {
    final steps = _androidSdkVersion >= 33
        ? ['Storage', 'Notification', 'Folder']
        : ['Permission', 'Folder'];
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                width: 32,
                height: 2,
                color: _currentStep >= i ? colorScheme.primary : colorScheme.surfaceContainerHighest,
              ),
            ),
          _buildStepDot(i, steps[i], colorScheme),
        ],
      ],
    );
  }

  Widget _buildStepDot(int step, String label, ColorScheme colorScheme) {
    final isActive = _currentStep >= step;
    final isCompleted = _isStepCompleted(step);

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? colorScheme.primary
                : isActive ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check, size: 18, color: colorScheme.onPrimary)
                : Text('${step + 1}',
                    style: TextStyle(
                      color: isActive ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant)),
      ],
    );
  }

  bool _isStepCompleted(int step) {
    if (_androidSdkVersion >= 33) {
      // 3 steps: Storage, Notification, Folder
      switch (step) {
        case 0: return _storagePermissionGranted;
        case 1: return _notificationPermissionGranted;
        case 2: return _selectedDirectory != null;
      }
    } else {
      // 2 steps: Permission, Folder
      switch (step) {
        case 0: return _storagePermissionGranted;
        case 1: return _selectedDirectory != null;
      }
    }
    return false;
  }

  Widget _buildCurrentStepContent(ColorScheme colorScheme) {
    if (_androidSdkVersion >= 33) {
      switch (_currentStep) {
        case 0: return _buildStoragePermissionStep(colorScheme);
        case 1: return _buildNotificationPermissionStep(colorScheme);
        case 2: return _buildDirectoryStep(colorScheme);
      }
    } else {
      switch (_currentStep) {
        case 0: return _buildStoragePermissionStep(colorScheme);
        case 1: return _buildDirectoryStep(colorScheme);
      }
    }
    return const SizedBox();
  }

  Widget _buildStoragePermissionStep(ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _storagePermissionGranted ? Icons.check_circle : Icons.folder_open,
          size: 56,
          color: _storagePermissionGranted ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          _storagePermissionGranted ? 'Storage Permission Granted!' : 'Storage Permission Required',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _storagePermissionGranted
              ? 'You can now proceed to the next step.'
              : 'SpotiFLAC needs storage access to save downloaded music files to your device.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (!_storagePermissionGranted)
          FilledButton.icon(
            onPressed: _isLoading ? null : _requestStoragePermission,
            icon: _isLoading
                ? SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary))
                : const Icon(Icons.security),
            label: const Text('Grant Permission'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          ),
      ],
    );
  }

  Widget _buildNotificationPermissionStep(ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _notificationPermissionGranted ? Icons.check_circle : Icons.notifications_outlined,
          size: 56,
          color: _notificationPermissionGranted ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          _notificationPermissionGranted ? 'Notification Permission Granted!' : 'Enable Notifications',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _notificationPermissionGranted
              ? 'You will receive download progress notifications.'
              : 'Get notified about download progress and completion. This helps you track downloads when the app is in background.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (!_notificationPermissionGranted) ...[
          FilledButton.icon(
            onPressed: _isLoading ? null : _requestNotificationPermission,
            icon: _isLoading
                ? SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary))
                : const Icon(Icons.notifications_active),
            label: const Text('Enable Notifications'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _skipNotificationPermission,
            child: const Text('Skip for now'),
          ),
        ],
      ],
    );
  }

  Widget _buildDirectoryStep(ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _selectedDirectory != null ? Icons.folder : Icons.create_new_folder,
          size: 56,
          color: _selectedDirectory != null ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          _selectedDirectory != null ? 'Download Folder Selected!' : 'Choose Download Folder',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (_selectedDirectory != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(_selectedDirectory!,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          )
        else
          Text('Select a folder where your downloaded music will be saved.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _isLoading ? null : _selectDirectory,
          icon: _isLoading
              ? SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary))
              : Icon(_selectedDirectory != null ? Icons.edit : Icons.folder_open),
          label: Text(_selectedDirectory != null ? 'Change Folder' : 'Select Folder'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons(ColorScheme colorScheme) {
    final isLastStep = _currentStep == _totalSteps - 1;
    final canProceed = _isStepCompleted(_currentStep);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Back button
        if (_currentStep > 0)
          TextButton.icon(
            onPressed: () => setState(() => _currentStep--),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          )
        else
          const SizedBox(width: 100),

        // Next/Finish button
        if (!isLastStep)
          FilledButton(
            onPressed: canProceed ? () => setState(() => _currentStep++) : null,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('Next'), SizedBox(width: 8), Icon(Icons.arrow_forward, size: 18)],
            ),
          )
        else
          FilledButton(
            onPressed: _selectedDirectory != null && !_isLoading ? _completeSetup : null,
            child: _isLoading
                ? SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary))
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('Get Started'), SizedBox(width: 8), Icon(Icons.check, size: 18)],
                  ),
          ),
      ],
    );
  }
}
