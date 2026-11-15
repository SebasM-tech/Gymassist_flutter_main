import 'dart:async';
import 'dart:convert';

import 'package:gymassist/core/api/offline_cache.dart';
import 'package:gymassist/core/config/api_config.dart';
import 'package:http/http.dart' as http;

/// Error del backend con un mensaje listo para mostrar.
class ApiException implements Exception {
  const ApiException(this.message, {this.status = 0});
  final String message;
  final int status;

  bool get unauthorized => status == 401;
  bool get paymentRequired => status == 402;
  bool get conflict => status == 409;
  bool get offline => status == 0;

  @override
  String toString() => message;
}

/// Un archivo para subir en multipart (por ejemplo, la foto de una rutina).
class UploadFile {
  const UploadFile({required this.field, required this.bytes, required this.filename});
  final String field;
  final List<int> bytes;
  final String filename;
}

/// Cliente HTTP del backend Spring Boot (rutas /api/m/**). Agrega el token JWT en cada petición.
///
/// Modo sin conexión: cada lectura (GET) que sale bien se guarda en [OfflineCache]; si luego
/// no hay internet, se responde con esa copia. Las escrituras siempre necesitan conexión.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, OfflineCache? cache, OfflineStatus? status})
      : _http = client ?? http.Client(),
        baseUrl = baseUrl ?? ApiConfig.springApiBaseUrl,
        _cache = cache ?? OfflineCache.instance,
        _status = status ?? OfflineStatus.instance;

  final http.Client _http;
  final OfflineCache _cache;
  final OfflineStatus _status;
  final String baseUrl;
  String? token;

  /// Se llama cuando el backend responde 401 (token vencido): la sesión se cierra.
  void Function()? onUnauthorized;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: (query == null || query.isEmpty) ? null : query);

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, String>? query}) {
    final uri = _uri(path, query);
    return _send(() => _http.get(uri, headers: _headers), cacheKey: 'GET ${uri.path}?${uri.query}');
  }

  Future<dynamic> post(String path, [Object? body]) => _send(() => _http.post(_uri(path),
      headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body ?? const {})));

  Future<dynamic> put(String path, [Object? body]) => _send(() => _http.put(_uri(path),
      headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body ?? const {})));

  Future<dynamic> delete(String path) => _send(() => _http.delete(_uri(path), headers: _headers));

  Future<dynamic> multipart(String path, {required Map<String, String> fields, Map<String, List<String>> listFields = const {}, List<UploadFile> files = const []}) {
    return _send(() async {
      final req = http.MultipartRequest('POST', _uri(path))..headers.addAll(_headers);
      req.fields.addAll(fields);
      // MultipartRequest.fields no admite claves repetidas: las listas van como partes de texto.
      for (final e in listFields.entries) {
        for (final v in e.value) {
          req.files.add(http.MultipartFile.fromString(e.key, v));
        }
      }
      for (final f in files) {
        req.files.add(http.MultipartFile.fromBytes(f.field, f.bytes, filename: f.filename));
      }
      return http.Response.fromStream(await _http.send(req));
    });
  }

  /// [cacheKey] solo se pasa en las lecturas (GET): es el nombre con que se guarda la respuesta.
  Future<dynamic> _send(Future<http.Response> Function() call, {String? cacheKey}) async {
    http.Response res;
    try {
      res = await call().timeout(ApiConfig.springTimeout);
    } catch (e) {
      // No hubo respuesta (sin internet o servidor inalcanzable): se usa la copia guardada, si existe.
      if (cacheKey != null) {
        final guardado = await _cache.read(cacheKey);
        if (guardado != null) {
          _status.servedFromCache(guardado.savedAt);
          return _decode(guardado.body);
        }
      }
      if (e is TimeoutException) throw const ApiException('El servidor no respondió a tiempo. Revisa tu conexión.');
      throw ApiException(cacheKey == null
          ? 'Sin conexión con el servidor. Esta acción necesita internet.'
          : 'Sin conexión con el servidor y aún no hay datos guardados de esta pantalla.');
    }
    _status.online();
    final text = utf8.decode(res.bodyBytes);
    final json = _decode(text);
    if (cacheKey != null && res.statusCode >= 200 && res.statusCode < 300) {
      unawaited(_cache.write(cacheKey, text));
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    if (res.statusCode == 401) onUnauthorized?.call();
    final msg = (json is Map && json['error'] != null)
        ? '${json['error']}'
        : switch (res.statusCode) {
            401 => 'Tu sesión expiró. Vuelve a iniciar sesión.',
            403 => 'No tienes permiso para esta acción.',
            404 => 'No encontrado.',
            _ => 'Error del servidor (${res.statusCode}).',
          };
    throw ApiException(msg, status: res.statusCode);
  }

  static dynamic _decode(String text) {
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
}
