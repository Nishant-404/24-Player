import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:dartssh2/dartssh2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/utils/logger.dart';

/// Result of a cloud upload operation
class CloudUploadResult {
  final bool success;
  final String? error;
  final String? errorCode;
  final String? remotePath;

  const CloudUploadResult({
    required this.success,
    this.error,
    this.errorCode,
    this.remotePath,
  });

  factory CloudUploadResult.success(String remotePath) => CloudUploadResult(
    success: true,
    remotePath: remotePath,
  );

  factory CloudUploadResult.failure(String error, {String? errorCode}) =>
      CloudUploadResult(
    success: false,
    error: error,
    errorCode: errorCode,
  );
}

/// Parsed SFTP server URL
class SftpServerInfo {
  final String host;
  final int port;
  
  const SftpServerInfo({required this.host, required this.port});
}

class _WebDavError {
  final String code;
  final String message;

  const _WebDavError({required this.code, required this.message});
}

/// Service for uploading files to cloud storage (WebDAV, SFTP)
class CloudUploadService {
  static CloudUploadService? _instance;
  static CloudUploadService get instance => _instance ??= CloudUploadService._();

  CloudUploadService._();

  final LogBuffer _log = LogBuffer();
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  webdav.Client? _webdavClient;
  String? _currentServerUrl;
  String? _currentUsername;
  String? _currentPassword;
  bool? _currentAllowInsecureHttp;

  static const _sftpHostKeysKey = 'sftp_known_host_keys';
  Map<String, Map<String, String>>? _knownHostKeys;

  void _logInfo(String tag, String message) {
    _log.add(LogEntry(
      timestamp: DateTime.now(),
      level: 'INFO',
      tag: tag,
      message: message,
    ));
  }

  void _logError(String tag, String message, [String? error]) {
    _log.add(LogEntry(
      timestamp: DateTime.now(),
      level: 'ERROR',
      tag: tag,
      message: message,
      error: error,
    ));
  }

  // ============================================================
  // WebDAV Methods
  // ============================================================

  _WebDavError? _validateWebDavUrl(
    String url, {
    required bool allowInsecureHttp,
  }) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme.isEmpty) {
      return const _WebDavError(
        code: 'webdav_invalid_scheme',
        message: 'Invalid URL: scheme is required',
      );
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https') {
      if (scheme == 'http' && allowInsecureHttp) {
        // Explicitly allowed by user
      } else {
        return const _WebDavError(
          code: 'webdav_https_required',
          message: 'WebDAV URL must use https',
        );
      }
    }
    if (uri.host.isEmpty) {
      return const _WebDavError(
        code: 'webdav_invalid_host',
        message: 'Invalid URL: hostname is required',
      );
    }
    return null;
  }

  /// Initialize WebDAV client with server credentials
  Future<void> initializeWebDAV({
    required String serverUrl,
    required String username,
    required String password,
    bool allowInsecureHttp = false,
  }) async {
    final urlError = _validateWebDavUrl(
      serverUrl,
      allowInsecureHttp: allowInsecureHttp,
    );
    if (urlError != null) {
      throw ArgumentError(urlError.message);
    }

    // Reuse existing client if credentials haven't changed
    if (_webdavClient != null && 
        _currentServerUrl == serverUrl && 
        _currentUsername == username &&
        _currentPassword == password &&
        _currentAllowInsecureHttp == allowInsecureHttp) {
      return;
    }

    _webdavClient = webdav.newClient(
      serverUrl,
      user: username,
      password: password,
      debug: false,
    );

    _currentServerUrl = serverUrl;
    _currentUsername = username;
    _currentPassword = password;
    _currentAllowInsecureHttp = allowInsecureHttp;

    _logInfo('CloudUpload', 'WebDAV client initialized for $serverUrl');
  }

  /// Test connection to WebDAV server
  Future<CloudUploadResult> testWebDAVConnection({
    required String serverUrl,
    required String username,
    required String password,
    bool allowInsecureHttp = false,
  }) async {
    final urlError = _validateWebDavUrl(
      serverUrl,
      allowInsecureHttp: allowInsecureHttp,
    );
    if (urlError != null) {
      return CloudUploadResult.failure(
        urlError.message,
        errorCode: urlError.code,
      );
    }
    try {
      final client = webdav.newClient(
        serverUrl,
        user: username,
        password: password,
        debug: false,
      );

      // Try to ping/read root directory
      await client.ping();
      
      _logInfo('CloudUpload', 'WebDAV connection test successful: $serverUrl');
      return CloudUploadResult.success('/');
    } catch (e) {
      _logError('CloudUpload', 'WebDAV connection test failed', e.toString());
      final parsed = _parseWebDAVError(e);
      return CloudUploadResult.failure(
        parsed.message,
        errorCode: parsed.code,
      );
    }
  }

  /// Upload a file to WebDAV server
  Future<CloudUploadResult> uploadFileWebDAV({
    required String localPath,
    required String remotePath,
    required String serverUrl,
    required String username,
    required String password,
    void Function(int sent, int total)? onProgress,
    bool allowInsecureHttp = false,
  }) async {
    final urlError = _validateWebDavUrl(
      serverUrl,
      allowInsecureHttp: allowInsecureHttp,
    );
    if (urlError != null) {
      return CloudUploadResult.failure(
        urlError.message,
        errorCode: urlError.code,
      );
    }
    try {
      // Initialize client if needed
      await initializeWebDAV(
        serverUrl: serverUrl,
        username: username,
        password: password,
        allowInsecureHttp: allowInsecureHttp,
      );

      final client = _webdavClient!;
      final file = File(localPath);

      if (!await file.exists()) {
        return CloudUploadResult.failure('File not found: $localPath');
      }

      // Extract directory path and ensure it exists
      final remoteDir = remotePath.substring(0, remotePath.lastIndexOf('/'));
      if (remoteDir.isNotEmpty) {
        await _ensureWebDAVDirectoryExists(client, remoteDir);
      }

      // Upload the file
      _logInfo('CloudUpload', 'WebDAV uploading: $localPath -> $remotePath');
      
      await client.writeFromFile(
        localPath,
        remotePath,
        onProgress: onProgress,
      );

      _logInfo('CloudUpload', 'WebDAV upload complete: $remotePath');
      return CloudUploadResult.success(remotePath);
    } catch (e) {
      _logError('CloudUpload', 'WebDAV upload failed', e.toString());
      final parsed = _parseWebDAVError(e);
      return CloudUploadResult.failure(
        parsed.message,
        errorCode: parsed.code,
      );
    }
  }

  /// Ensure a directory exists on the WebDAV server, creating it if necessary
  Future<void> _ensureWebDAVDirectoryExists(webdav.Client client, String path) async {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    var currentPath = '';

    for (final part in parts) {
      currentPath += '/$part';
      try {
        await client.mkdir(currentPath);
      } catch (e) {
        // Directory might already exist, ignore error
      }
    }
  }

  /// Parse WebDAV error to user-friendly message
  _WebDavError _parseWebDAVError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
      return const _WebDavError(
        code: 'webdav_auth_failed',
        message: 'Authentication failed. Check username and password.',
      );
    }
    if (errorStr.contains('403') || errorStr.contains('forbidden')) {
      return const _WebDavError(
        code: 'webdav_forbidden',
        message: 'Access denied. Check permissions on the server.',
      );
    }
    if (errorStr.contains('404') || errorStr.contains('not found')) {
      return const _WebDavError(
        code: 'webdav_not_found',
        message: 'Server path not found. Check the URL.',
      );
    }
    if (errorStr.contains('connection refused') || errorStr.contains('socket')) {
      return const _WebDavError(
        code: 'webdav_connection_failed',
        message: 'Cannot connect to server. Check URL and network.',
      );
    }
    if (errorStr.contains('certificate') || errorStr.contains('ssl') || errorStr.contains('tls')) {
      return const _WebDavError(
        code: 'webdav_tls_error',
        message: 'SSL/TLS error. Server certificate may be invalid.',
      );
    }
    if (errorStr.contains('timeout')) {
      return const _WebDavError(
        code: 'webdav_timeout',
        message: 'Connection timed out. Server may be unreachable.',
      );
    }
    if (errorStr.contains('507') || errorStr.contains('insufficient storage')) {
      return const _WebDavError(
        code: 'webdav_insufficient_storage',
        message: 'Insufficient storage on server.',
      );
    }

    return _WebDavError(
      code: 'webdav_unknown',
      message: 'Upload failed: ${error.toString()}',
    );
  }

  // ============================================================
  // SFTP Methods
  // ============================================================

  /// Parse SFTP server URL to extract host and port
  /// Supports formats: 
  ///   - sftp://hostname:port
  ///   - sftp://hostname
  ///   - hostname:port
  ///   - hostname
  SftpServerInfo _parseSftpUrl(String serverUrl) {
    var url = serverUrl.trim();
    
    // Remove sftp:// prefix if present
    if (url.toLowerCase().startsWith('sftp://')) {
      url = url.substring(7);
    }
    
    // Check for port
    final colonIndex = url.lastIndexOf(':');
    if (colonIndex > 0) {
      final host = url.substring(0, colonIndex);
      final portStr = url.substring(colonIndex + 1);
      final port = int.tryParse(portStr) ?? 22;
      return SftpServerInfo(host: host, port: port);
    }
    
    return SftpServerInfo(host: url, port: 22);
  }

  /// Test connection to SFTP server
  Future<CloudUploadResult> testSFTPConnection({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    SSHClient? client;
    try {
      final serverInfo = _parseSftpUrl(serverUrl);
      
      _logInfo('CloudUpload', 'SFTP connecting to ${serverInfo.host}:${serverInfo.port}');
      
      // Connect to SSH server
      final socket = await SSHSocket.connect(
        serverInfo.host,
        serverInfo.port,
        timeout: const Duration(seconds: 10),
      );
      
      client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
        onVerifyHostKey: (type, fingerprint) => _verifySftpHostKey(
          host: serverInfo.host,
          port: serverInfo.port,
          type: type,
          fingerprint: fingerprint,
        ),
      );
      
      // Wait for authentication
      await client.authenticated;
      
      // Test SFTP subsystem
      final sftp = await client.sftp();
      await sftp.listdir('.');
      sftp.close();
      
      _logInfo('CloudUpload', 'SFTP connection test successful: ${serverInfo.host}');
      return CloudUploadResult.success('/');
    } catch (e) {
      _logError('CloudUpload', 'SFTP connection test failed', e.toString());
      return CloudUploadResult.failure(_parseSFTPError(e));
    } finally {
      client?.close();
    }
  }

  /// Upload a file to SFTP server
  Future<CloudUploadResult> uploadFileSFTP({
    required String localPath,
    required String remotePath,
    required String serverUrl,
    required String username,
    required String password,
    void Function(int sent, int total)? onProgress,
  }) async {
    SSHClient? client;
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        return CloudUploadResult.failure('File not found: $localPath');
      }

      final fileSize = await file.length();
      final serverInfo = _parseSftpUrl(serverUrl);
      
      _logInfo('CloudUpload', 'SFTP connecting to ${serverInfo.host}:${serverInfo.port}');
      
      // Connect to SSH server
      final socket = await SSHSocket.connect(
        serverInfo.host,
        serverInfo.port,
        timeout: const Duration(seconds: 30),
      );
      
      client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
        onVerifyHostKey: (type, fingerprint) => _verifySftpHostKey(
          host: serverInfo.host,
          port: serverInfo.port,
          type: type,
          fingerprint: fingerprint,
        ),
      );
      
      // Wait for authentication
      await client.authenticated;
      
      // Open SFTP session
      final sftp = await client.sftp();
      
      // Ensure remote directory exists
      final remoteDir = remotePath.substring(0, remotePath.lastIndexOf('/'));
      if (remoteDir.isNotEmpty) {
        await _ensureSFTPDirectoryExists(sftp, remoteDir);
      }
      
      _logInfo('CloudUpload', 'SFTP uploading: $localPath -> $remotePath');
      
      // Open remote file for writing
      final remoteFile = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.create | 
              SftpFileOpenMode.write | 
              SftpFileOpenMode.truncate,
      );
      
      // Read local file and write to remote with progress
      final localFileStream = file.openRead();
      int bytesUploaded = 0;
      
      await for (final chunk in localFileStream) {
        await remoteFile.write(Stream.value(Uint8List.fromList(chunk)));
        bytesUploaded += chunk.length;
        onProgress?.call(bytesUploaded, fileSize);
      }
      
      await remoteFile.close();
      sftp.close();
      
      _logInfo('CloudUpload', 'SFTP upload complete: $remotePath');
      return CloudUploadResult.success(remotePath);
    } catch (e) {
      _logError('CloudUpload', 'SFTP upload failed', e.toString());
      return CloudUploadResult.failure(_parseSFTPError(e));
    } finally {
      client?.close();
    }
  }

  /// Ensure a directory exists on the SFTP server, creating it if necessary
  Future<void> _ensureSFTPDirectoryExists(SftpClient sftp, String path) async {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;
    final isAbsolute = path.startsWith('/');
    var currentPath = '';

    for (final part in parts) {
      if (currentPath.isEmpty) {
        currentPath = isAbsolute ? '/$part' : part;
      } else {
        currentPath += '/$part';
      }
      try {
        await sftp.mkdir(currentPath);
      } catch (e) {
        // Directory might already exist, ignore error
        // SFTP throws exception if directory exists
      }
    }
  }

  /// Parse SFTP error to user-friendly message
  String _parseSFTPError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('authentication') || 
        errorStr.contains('permission denied') ||
        errorStr.contains('auth fail')) {
      return 'Authentication failed. Check username and password.';
    }
    if (errorStr.contains('connection refused')) {
      return 'Connection refused. Check server address and port.';
    }
    if (errorStr.contains('no route to host') || 
        errorStr.contains('network is unreachable')) {
      return 'Cannot reach server. Check network connection.';
    }
    if (errorStr.contains('connection timed out') || 
        errorStr.contains('timeout')) {
      return 'Connection timed out. Server may be unreachable.';
    }
    if (errorStr.contains('host key') || 
        errorStr.contains('fingerprint')) {
      return 'Host key verification failed.';
    }
    if (errorStr.contains('no such file') || 
        errorStr.contains('not found')) {
      return 'Remote path not found.';
    }
    if (errorStr.contains('permission') || 
        errorStr.contains('access denied')) {
      return 'Permission denied. Check folder permissions.';
    }
    if (errorStr.contains('disk full') || 
        errorStr.contains('no space')) {
      return 'Insufficient storage on server.';
    }
    if (errorStr.contains('socket') || 
        errorStr.contains('broken pipe')) {
      return 'Connection lost. Try again.';
    }

    return 'SFTP error: ${error.toString()}';
  }

  // ============================================================
  // Common Methods
  // ============================================================

  /// Get the remote path for a downloaded file
  String getRemotePath({
    required String localFilePath,
    required String baseRemotePath,
    required String downloadDirectory,
  }) {
    // Extract relative path from download directory
    String relativePath;
    if (localFilePath.startsWith(downloadDirectory)) {
      relativePath = localFilePath.substring(downloadDirectory.length);
      if (relativePath.startsWith('/') || relativePath.startsWith('\\')) {
        relativePath = relativePath.substring(1);
      }
    } else {
      // Just use the filename
      relativePath = localFilePath.split(Platform.pathSeparator).last;
    }

    // Normalize path separators
    relativePath = relativePath.replaceAll('\\', '/');

    // Combine with base remote path
    var remotePath = baseRemotePath;
    if (!remotePath.endsWith('/')) {
      remotePath += '/';
    }
    remotePath += relativePath;

    return remotePath;
  }

  /// Dispose resources
  void dispose() {
    _webdavClient = null;
    _currentServerUrl = null;
    _currentUsername = null;
    _currentPassword = null;
    _currentAllowInsecureHttp = null;
  }

  Future<bool> clearSftpHostKey({required String serverUrl}) async {
    final serverInfo = _parseSftpUrl(serverUrl);
    final knownHostKeys = await _loadKnownHostKeys();
    final keyId = '${serverInfo.host}:${serverInfo.port}';

    final removed = knownHostKeys.remove(keyId) != null;
    if (removed) {
      await _saveKnownHostKeys();
      _logInfo('CloudUpload', 'Cleared SFTP host key for $keyId');
    }
    return removed;
  }

  Future<int> clearAllSftpHostKeys() async {
    final knownHostKeys = await _loadKnownHostKeys();
    final count = knownHostKeys.length;
    if (count == 0) {
      return 0;
    }

    knownHostKeys.clear();
    await _saveKnownHostKeys();
    _logInfo('CloudUpload', 'Cleared all SFTP host keys');
    return count;
  }

  Future<Map<String, Map<String, String>>> _loadKnownHostKeys() async {
    if (_knownHostKeys != null) {
      return _knownHostKeys!;
    }

    final prefs = await _prefs;
    final raw = prefs.getString(_sftpHostKeysKey);
    if (raw == null || raw.isEmpty) {
      _knownHostKeys = <String, Map<String, String>>{};
      return _knownHostKeys!;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final map = <String, Map<String, String>>{};
        decoded.forEach((key, value) {
          if (value is Map) {
            final type = value['type'];
            final fingerprint = value['fingerprint'];
            if (type is String && fingerprint is String) {
              map[key] = {'type': type, 'fingerprint': fingerprint};
            }
          }
        });
        _knownHostKeys = map;
        return map;
      }
    } catch (e) {
      _logError('CloudUpload', 'Failed to parse known host keys', e.toString());
    }

    _knownHostKeys = <String, Map<String, String>>{};
    return _knownHostKeys!;
  }

  Future<void> _saveKnownHostKeys() async {
    if (_knownHostKeys == null) return;
    final prefs = await _prefs;
    await prefs.setString(_sftpHostKeysKey, jsonEncode(_knownHostKeys));
  }

  String _formatFingerprint(Uint8List fingerprint) {
    final buffer = StringBuffer();
    for (var i = 0; i < fingerprint.length; i++) {
      if (i > 0) buffer.write(':');
      buffer.write(fingerprint[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Future<bool> _verifySftpHostKey({
    required String host,
    required int port,
    required String type,
    required Uint8List fingerprint,
  }) async {
    final knownHostKeys = await _loadKnownHostKeys();
    final keyId = '$host:$port';
    final fingerprintHex = _formatFingerprint(fingerprint);
    final existing = knownHostKeys[keyId];

    if (existing == null) {
      knownHostKeys[keyId] = {
        'type': type,
        'fingerprint': fingerprintHex,
      };
      await _saveKnownHostKeys();
      _logInfo('CloudUpload', 'Saved new SFTP host key for $keyId');
      return true;
    }

    final existingFingerprint = existing['fingerprint'];
    if (existingFingerprint == fingerprintHex) {
      return true;
    }

    _logError(
      'CloudUpload',
      'SFTP host key mismatch for $keyId',
      'expected=$existingFingerprint got=$fingerprintHex',
    );
    return false;
  }
}
