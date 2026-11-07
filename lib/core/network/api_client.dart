import 'dart:async';
import 'dart:convert';

import 'api_exceptions.dart';
import 'transport.dart';

/// JSON API client used by every remote data source.
///
/// * GET requests are retried with exponential backoff.
/// * Saves bandwidth on flaky campus / mobile networks.
/// * POST requests are never retried automatically.
class ApiClient {
  ApiClient(
    this._transport, {
    this.maxRetries = 2,
    this.timeout = const Duration(seconds: 8),
    this.retryBaseDelay = const Duration(milliseconds: 200),
    this.responseCacheTtl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Transport _transport;
  final int maxRetries;
  final Duration timeout;
  final Duration retryBaseDelay;
  final Duration responseCacheTtl;
  final DateTime Function() _clock;

  final Map<String, _CachedResponse> _responseCache = {};

  Future<dynamic> get(
    String path, {
    Map<String, String> query = const {},
    bool refresh = false,
  }) {
    return _getWithRetry(
      TransportRequest(method: 'GET', path: path, query: query),
      refresh: refresh,
    );
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) {
    return _send(
      TransportRequest(
        method: 'POST',
        path: path,
        headers: {'content-type': 'application/json', ...headers},
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<dynamic> _getWithRetry(
    TransportRequest request, {
    bool refresh = false,
  }) async {
    if (!refresh) {
      final cached = _responseCache[request.cacheKey];
      if (cached != null &&
          _clock().difference(cached.storedAt) < responseCacheTtl) {
        return jsonDecode(cached.body);
      }
    }

    ApiException? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final result = await _send(request);
        return result;
      } on ApiException catch (e) {
        lastError = e;
        if (attempt < maxRetries) {
          await Future<void>.delayed(retryBaseDelay * (1 << attempt));
        }
      }
    }
    throw lastError!;
  }

  Future<dynamic> _send(TransportRequest request) async {
    final TransportResponse response;
    try {
      response = await _transport.send(request).timeout(timeout);
    } on TransportUnreachable {
      throw const NetworkException();
    } on TransportTimeout {
      throw const ApiTimeoutException();
    } on TimeoutException {
      throw const ApiTimeoutException();
    }

    final decoded = _decode(response.body);

    if (response.isSuccess) {
      if (request.method == 'GET') {
        _responseCache[request.cacheKey] =
            _CachedResponse(response.body, _clock());
      }
      return decoded;
    }

    final code = decoded is Map ? decoded['error'] as String? : null;
    final message = decoded is Map
        ? (decoded['message'] as String? ?? 'Request failed')
        : 'Request failed';
    if (response.statusCode >= 500) {
      throw ServerException(response.statusCode, message, code: code);
    }
    throw ClientException(
      response.statusCode,
      message,
      code: code,
      details: decoded is Map ? decoded['details'] : null,
    );
  }

  dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

class _CachedResponse {
  _CachedResponse(this.body, this.storedAt);

  final String body;
  final DateTime storedAt;
}
