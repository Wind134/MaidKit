import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/shared/services/update_service.dart';

/// Dio adapter that answers every request with a canned HTTP response.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: const {
        'content-type': ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

UpdateService _serviceWith(int statusCode, String body) {
  return UpdateService(
    dio: Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = _FakeAdapter(statusCode, body),
  );
}

void main() {
  group('fetchLatestRelease', () {
    test('parses a full release payload', () async {
      final release = await _serviceWith(
        200,
        jsonEncode({
          'tag_name': '1.1.0+4',
          'name': 'MaidKit 1.1.0',
          'body': '## Changelog\n- Fixed things',
          'html_url': 'https://github.com/Wind134/MaidKit/releases/tag/v1.1.0',
          'created_at': '2026-08-01T12:00:00Z',
        }),
      ).fetchLatestRelease();

      expect(release, isNotNull);
      expect(release!.tagName, '1.1.0+4');
      expect(release.name, 'MaidKit 1.1.0');
      expect(release.body, '## Changelog\n- Fixed things');
      expect(
        release.htmlUrl,
        'https://github.com/Wind134/MaidKit/releases/tag/v1.1.0',
      );
      expect(release.createdAt, DateTime.utc(2026, 8, 1, 12));
    });

    test('falls back to tag name when name is absent', () async {
      final release = await _serviceWith(
        200,
        jsonEncode({
          'tag_name': '1.0.1',
          'html_url': 'https://github.com/Wind134/MaidKit/releases/tag/1.0.1',
        }),
      ).fetchLatestRelease();

      expect(release, isNotNull);
      expect(release!.name, '1.0.1');
    });

    test('returns null on non-200 responses', () async {
      final release = await _serviceWith(
        500,
        '{"message": "boom"}',
      ).fetchLatestRelease();

      expect(release, isNull);
    });

    test('returns null when tag_name or html_url is missing', () async {
      final missingTag = await _serviceWith(
        200,
        jsonEncode({
          'html_url': 'https://github.com/Wind134/MaidKit/releases/tag/1.0.1',
        }),
      ).fetchLatestRelease();
      expect(missingTag, isNull);

      final missingUrl = await _serviceWith(
        200,
        jsonEncode({'tag_name': '1.0.1'}),
      ).fetchLatestRelease();
      expect(missingUrl, isNull);
    });

    test('queries the Wind134/MaidKit latest-release endpoint', () async {
      final adapter = _FakeAdapter(200, jsonEncode({'tag_name': '1.0.1'}));
      await UpdateService(
        dio: Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = adapter,
      ).fetchLatestRelease();

      expect(
        adapter.requests.single.uri.toString(),
        'https://api.github.com/repos/Wind134/MaidKit/releases/latest',
      );
    });
  });

  group('download urls', () {
    const base = 'https://github.com/Wind134/MaidKit/releases/download/1.0.3';

    test('resolves versioned android split-abi apks', () {
      final service = UpdateService();
      expect(
        service.getAndroidDownloadUrl('arm64', tagName: '1.0.3'),
        '$base/server_manager_android_arm64-v8a_1.0.3.apk',
      );
      expect(
        service.getAndroidDownloadUrl('armeabi', tagName: '1.0.3'),
        '$base/server_manager_android_armeabi-v7a_1.0.3.apk',
      );
      expect(
        service.getAndroidDownloadUrl('x86_64', tagName: '1.0.3'),
        '$base/server_manager_android_x86_64_1.0.3.apk',
      );
    });

    test('resolves versioned windows installer and linux appimage zips', () {
      final service = UpdateService();
      expect(
        service.getWindowsDownloadUrl(tagName: '1.0.3'),
        '$base/server_manager_windows_1.0.3.zip',
      );
      expect(
        service.getLinuxDownloadUrl(tagName: '1.0.3'),
        '$base/server_manager_linux_1.0.3.zip',
      );
    });
  });
}
