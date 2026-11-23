import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'cloud_sync_service.dart';

/// User- or build-configured Google OAuth 2.0 client credentials.
class GoogleOAuthClientConfig {
  const GoogleOAuthClientConfig({
    required this.clientId,
    this.clientSecret = '',
  });

  final String clientId;
  final String clientSecret;

  bool get isConfigured => clientId.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
    'clientId': clientId.trim(),
    'clientSecret': clientSecret.trim(),
  };

  factory GoogleOAuthClientConfig.fromJson(Map<String, dynamic> json) =>
      GoogleOAuthClientConfig(
        clientId: (json['clientId'] as String? ?? '').trim(),
        clientSecret: (json['clientSecret'] as String? ?? '').trim(),
      );
}

/// Remote vault file metadata stored in Google Drive's hidden `appDataFolder`.
class GoogleDriveVaultFile {
  const GoogleDriveVaultFile({
    required this.fileId,
    required this.blobId,
    required this.revision,
    this.updatedAt,
  });

  final String fileId;
  final String blobId;
  final int revision;
  final DateTime? updatedAt;
}

/// Google OAuth 2.0 (PKCE) sign-in and Google Drive `appDataFolder` transport
/// for client-encrypted vault archives.
class GoogleDriveSyncService {
  GoogleDriveSyncService({
    FlutterSecureStorage? secureStorage,
    Dio? dio,
    GoogleOAuthClientConfig? defaultConfig,
  }) : _storage = secureStorage ?? const FlutterSecureStorage(),
       _dio = dio ?? Dio(),
       _defaultConfig =
           defaultConfig ??
           const GoogleOAuthClientConfig(
             clientId: String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID'),
             clientSecret: String.fromEnvironment('GOOGLE_OAUTH_CLIENT_SECRET'),
           );

  static const workspaceId = 'google_drive_appdata';
  static const workspace = CloudWorkspace(
    id: workspaceId,
    slug: 'google-drive',
    name: 'Google Drive',
    provider: CloudSyncProvider.googleDrive,
  );

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _userInfoEndpoint =
      'https://www.googleapis.com/oauth2/v3/userinfo';
  static const _driveFilesApi = 'https://www.googleapis.com/drive/v3/files';
  static const _driveUploadApi =
      'https://www.googleapis.com/upload/drive/v3/files';

  static const _scopes =
      'openid email profile https://www.googleapis.com/auth/drive.appdata';
  static const _loopbackPort = 42872;
  static const _loopbackScheme = 'http://127.0.0.1:$_loopbackPort';
  static const _loopbackRedirectUri = '$_loopbackScheme/oauth/callback';

  static const _sessionKey = 'server_manager_google_oauth_session';
  static const _clientConfigKey = 'server_manager_google_oauth_config';
  static const _propBlobId = 'server_manager_blob_id';
  static const _propRevision = 'server_manager_revision';
  static const _propSchemeVersion = 'server_manager_scheme_version';
  static const _schemeVersion = '1';

  final FlutterSecureStorage _storage;
  final Dio _dio;
  final GoogleOAuthClientConfig _defaultConfig;

  static Future<_GoogleSession?>? _refreshFuture;

  Future<GoogleOAuthClientConfig> loadClientConfig() async {
    final raw = await _storage.read(key: _clientConfigKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final saved = GoogleOAuthClientConfig.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (saved.isConfigured) return saved;
      } catch (_) {
        await _storage.delete(key: _clientConfigKey);
      }
    }
    return _defaultConfig;
  }

  Future<void> saveClientConfig(GoogleOAuthClientConfig config) async {
    if (!config.isConfigured) {
      await _storage.delete(key: _clientConfigKey);
      return;
    }
    await _storage.write(
      key: _clientConfigKey,
      value: jsonEncode(config.toJson()),
    );
  }

  Future<bool> hasSession() async => (await _validSession()) != null;

  Future<CloudUser?> currentUser() async {
    final session = await _validSession();
    if (session == null) return null;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _userInfoEndpoint,
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      final data = response.data;
      if (data == null) return null;
      final email = (data['email'] as String? ?? '').trim();
      final name = (data['name'] as String? ?? '').trim();
      final picture = (data['picture'] as String? ?? '').trim();
      return CloudUser(
        name: name.isNotEmpty
            ? name
            : (email.isNotEmpty ? email : 'Google user'),
        handle: email,
        avatarUrl: picture.isEmpty ? null : picture,
        provider: CloudSyncProvider.googleDrive,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await signOut();
        return null;
      }
      rethrow;
    }
  }

  Future<CloudUser> signIn() async {
    final config = await loadClientConfig();
    if (!config.isConfigured) {
      throw const CloudSyncException(
        'Google OAuth Client ID is not configured yet.',
      );
    }
    try {
      await _authorize(config);
      final user = await currentUser();
      if (user == null) {
        throw const CloudSyncException(
          'Unable to load the signed-in Google account.',
        );
      }
      return user;
    } on DioException catch (error) {
      throw CloudSyncException(_googleApiError(error));
    }
  }

  Future<void> signOut() async {
    await _storage.delete(key: _sessionKey);
  }

  Future<List<CloudVaultBlob>> listVaultBlobs() async {
    final session = await _requireSession();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _driveFilesApi,
        queryParameters: {
          'spaces': 'appDataFolder',
          'q': "trashed = false and name contains 'vault-'",
          'fields': 'files(id,name,modifiedTime,appProperties)',
          'orderBy': 'modifiedTime desc',
          'pageSize': 100,
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      final files = response.data?['files'];
      if (files is! List) return const [];
      return files
          .whereType<Map>()
          .map((raw) => _parseDriveFile(Map<String, dynamic>.from(raw)))
          .whereType<GoogleDriveVaultFile>()
          .map(
            (file) => CloudVaultBlob(
              id: file.blobId,
              revision: file.revision,
              updatedAt: file.updatedAt,
            ),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw CloudSyncException(_googleApiError(error));
    }
  }

  Future<GoogleDriveVaultFile?> findVaultFile(String blobId) async {
    final session = await _requireSession();
    final safeName = _fileNameForBlob(blobId).replaceAll("'", r"\'");
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _driveFilesApi,
        queryParameters: {
          'spaces': 'appDataFolder',
          'q': "name = '$safeName' and trashed = false",
          'fields': 'files(id,name,modifiedTime,appProperties)',
          'pageSize': 5,
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      final files = response.data?['files'];
      if (files is! List || files.isEmpty) return null;
      final first = files.first;
      if (first is! Map) return null;
      return _parseDriveFile(Map<String, dynamic>.from(first));
    } on DioException catch (error) {
      throw CloudSyncException(_googleApiError(error));
    }
  }

  Future<String> downloadArchive(String fileId) async {
    final session = await _requireSession();
    try {
      final response = await _dio.get<List<int>>(
        '$_driveFilesApi/$fileId',
        queryParameters: {'alt': 'media'},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
          responseType: ResponseType.bytes,
        ),
      );
      return utf8.decode(response.data ?? const []);
    } on DioException catch (error) {
      throw CloudSyncException(_googleApiError(error));
    }
  }

  Future<int> uploadArchive({
    required String blobId,
    required String archive,
    required int nextRevision,
    String? existingFileId,
  }) async {
    final session = await _requireSession();
    final metadata = <String, Object?>{
      'name': _fileNameForBlob(blobId),
      if (existingFileId == null) 'parents': const ['appDataFolder'],
      'appProperties': {
        _propBlobId: blobId,
        _propRevision: nextRevision.toString(),
        _propSchemeVersion: _schemeVersion,
      },
    };
    final boundary = 'server_manager_${_randomUrlSafe(16)}';
    final body = _buildMultipartRelated(
      boundary: boundary,
      metadataJson: jsonEncode(metadata),
      payloadBytes: utf8.encode(archive),
    );
    final url = existingFileId == null
        ? _driveUploadApi
        : '$_driveUploadApi/$existingFileId';
    try {
      final response = await _dio.request<Map<String, dynamic>>(
        url,
        queryParameters: {
          'uploadType': 'multipart',
          'fields': 'id,modifiedTime,appProperties',
        },
        data: body,
        options: Options(
          method: existingFileId == null ? 'POST' : 'PATCH',
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'Content-Type': 'multipart/related; boundary=$boundary',
          },
        ),
      );
      final props = response.data?['appProperties'];
      if (props is Map) {
        final parsed = int.tryParse(props[_propRevision]?.toString() ?? '');
        if (parsed != null && parsed > 0) return parsed;
      }
      return nextRevision;
    } on DioException catch (error) {
      throw CloudSyncException(_googleApiError(error));
    }
  }

  Future<_GoogleSession> _requireSession() async {
    final session = await _validSession();
    if (session == null) {
      throw const CloudSyncException(
        'Sign in with Google is required to access Google Drive sync.',
      );
    }
    return session;
  }

  Future<_GoogleSession> _authorize(GoogleOAuthClientConfig config) async {
    final verifier = _randomUrlSafe(64);
    final state = _randomUrlSafe(32);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');

    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final mobileScheme = _reversedClientIdScheme(config.clientId);
    final redirectUri = isDesktop
        ? _loopbackRedirectUri
        : '$mobileScheme:/oauth2redirect';
    final callbackScheme = isDesktop ? _loopbackScheme : mobileScheme;

    final authUri = Uri.parse(_authEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': config.clientId,
        'redirect_uri': redirectUri,
        'scope': _scopes,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
      },
    );

    final callback = Uri.parse(
      await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: callbackScheme,
        options: isDesktop
            ? const FlutterWebAuth2Options(useWebview: false)
            : const FlutterWebAuth2Options(),
      ),
    );
    if (callback.queryParameters['state'] != state) {
      throw const CloudSyncException(
        'The Google authorization response could not be verified.',
      );
    }
    final error = callback.queryParameters['error'];
    if (error != null) {
      throw CloudSyncException(
        callback.queryParameters['error_description'] ?? error,
      );
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const CloudSyncException(
        'Google did not return an authorization code.',
      );
    }

    final fields = <String, String>{
      'grant_type': 'authorization_code',
      'client_id': config.clientId,
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': verifier,
      if (config.clientSecret.isNotEmpty) 'client_secret': config.clientSecret,
    };
    final session = await _exchangeToken(fields);
    await _saveSession(session);
    return session;
  }

  Future<_GoogleSession?> _validSession() async {
    final session = await _readSession();
    if (session == null || !session.needsRefresh) return session;
    if (session.refreshToken == null || session.refreshToken!.isEmpty) {
      return null;
    }
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;
    final refresh = _refreshSession(session);
    _refreshFuture = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshFuture, refresh)) _refreshFuture = null;
    }
  }

  Future<_GoogleSession?> _refreshSession(_GoogleSession session) async {
    final config = await loadClientConfig();
    if (!config.isConfigured) return null;
    try {
      final refreshed = await _exchangeToken({
        'grant_type': 'refresh_token',
        'client_id': config.clientId,
        'refresh_token': session.refreshToken!,
        if (config.clientSecret.isNotEmpty)
          'client_secret': config.clientSecret,
      }, previous: session);
      await _saveSession(refreshed);
      return refreshed;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 400 || status == 401) {
        await _storage.delete(key: _sessionKey);
      }
      return null;
    }
  }

  Future<_GoogleSession> _exchangeToken(
    Map<String, String> fields, {
    _GoogleSession? previous,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      _tokenEndpoint,
      data: fields,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data ?? const <String, dynamic>{};
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const CloudSyncException(
        'Google token response did not include an access token.',
      );
    }
    return _GoogleSession(
      accessToken: accessToken,
      refreshToken: data['refresh_token'] as String? ?? previous?.refreshToken,
      expiresAt: data['expires_in'] is num
          ? DateTime.now().add(
              Duration(seconds: (data['expires_in'] as num).toInt()),
            )
          : null,
    );
  }

  Future<_GoogleSession?> _readSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      return _GoogleSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      await _storage.delete(key: _sessionKey);
      return null;
    }
  }

  Future<void> _saveSession(_GoogleSession session) =>
      _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));

  static String _fileNameForBlob(String blobId) => 'vault-$blobId.mkb';

  static GoogleDriveVaultFile? _parseDriveFile(Map<String, dynamic> json) {
    final fileId = (json['id'] as String? ?? '').trim();
    if (fileId.isEmpty) return null;
    final props = json['appProperties'] is Map
        ? Map<String, dynamic>.from(json['appProperties'] as Map)
        : const <String, dynamic>{};
    final name = (json['name'] as String? ?? '').trim();
    var blobId = (props[_propBlobId] as String? ?? '').trim();
    if (blobId.isEmpty && name.startsWith('vault-') && name.endsWith('.mkb')) {
      blobId = name.substring('vault-'.length, name.length - '.mkb'.length);
    }
    if (blobId.isEmpty) return null;
    final revision = int.tryParse(props[_propRevision]?.toString() ?? '') ?? 1;
    final updatedAt = DateTime.tryParse(
      json['modifiedTime']?.toString() ?? '',
    )?.toLocal();
    return GoogleDriveVaultFile(
      fileId: fileId,
      blobId: blobId,
      revision: revision < 1 ? 1 : revision,
      updatedAt: updatedAt,
    );
  }

  static List<int> _buildMultipartRelated({
    required String boundary,
    required String metadataJson,
    required List<int> payloadBytes,
  }) {
    final head = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$metadataJson\r\n'
      '--$boundary\r\n'
      'Content-Type: application/octet-stream\r\n\r\n',
    );
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    return <int>[...head, ...payloadBytes, ...tail];
  }

  static String _reversedClientIdScheme(String clientId) {
    const suffix = '.apps.googleusercontent.com';
    final trimmed = clientId.trim();
    if (trimmed.endsWith(suffix)) {
      final prefix = trimmed.substring(0, trimmed.length - suffix.length);
      return 'com.googleusercontent.apps.$prefix';
    }
    return 'maidkit';
  }

  static String _googleApiError(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map && err['message'] != null) {
        return err['message'].toString();
      }
      final desc = data['error_description'] ?? data['message'] ?? err;
      if (desc != null && desc.toString().isNotEmpty) {
        return desc.toString();
      }
    }
    final status = error.response?.statusCode;
    return status == null
        ? 'Unable to reach Google. Check your network or proxy and try again.'
        : 'Google request failed (HTTP $status).';
  }

  String _randomUrlSafe(int length) => base64UrlEncode(
    List<int>.generate(length, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');
}

class _GoogleSession {
  const _GoogleSession({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool get needsRefresh =>
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!.subtract(const Duration(seconds: 30)));

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
  };

  factory _GoogleSession.fromJson(Map<String, dynamic> json) => _GoogleSession(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String?,
    expiresAt: DateTime.tryParse(
      json['expires_at'] as String? ?? '',
    )?.toLocal(),
  );
}
