import 'dart:async';
import 'dart:convert';

import 'package:gymassist/core/api/offline_cache.dart';
import 'package:gymassist/core/config/api_config.dart';
import 'package:gymassist/features/predictions/domain/prediction_domain.dart';
import 'package:http/http.dart' as http;

/// Cliente HTTP de la API de predicción hecha en Python (FastAPI + TensorFlow).
///
/// Endpoints que usa:
///   GET  /salud           -> estado y métricas del modelo
///   POST /predecir/lote   -> probabilidad de abandono + factores + recomendación por cliente
///
/// Modo sin conexión: la última respuesta de cada endpoint se guarda en [OfflineCache];
/// sin internet se muestran las últimas predicciones calculadas.
class PredictionApiClient {
  PredictionApiClient({http.Client? client, String? baseUrl, OfflineCache? cache, OfflineStatus? status})
      : _http = client ?? http.Client(),
        baseUrl = baseUrl ?? ApiConfig.mlApiBaseUrl,
        _cache = cache ?? OfflineCache.instance,
        _status = status ?? OfflineStatus.instance;

  final http.Client _http;
  final String baseUrl;
  final OfflineCache _cache;
  final OfflineStatus _status;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<ModelHealth> health() async {
    final text = await _send(() => _http.get(_uri('/salud')).timeout(ApiConfig.healthTimeout), cacheKey: 'ML GET /salud');
    return ModelHealth.fromJson(_decode(text));
  }

  /// `clientes` es la lista en el formato que espera FastAPI (ver `Cliente` en prediccion-ml/app/main.py).
  /// Devuelve el JSON de cada resultado (la pantalla lo combina con correo y teléfono locales).
  Future<List<Map<String, dynamic>>> predictBatch(List<Map<String, dynamic>> clientes, {DateTime? fechaReferencia}) async {
    if (clientes.isEmpty) return const [];
    final body = jsonEncode({
      'clientes': clientes,
      if (fechaReferencia != null) 'fechaReferencia': fechaReferencia.toIso8601String().substring(0, 10),
    });
    final text = await _send(
        () => _http
            .post(_uri('/predecir/lote'), headers: const {'Content-Type': 'application/json'}, body: body)
            .timeout(ApiConfig.predictTimeout),
        cacheKey: 'ML POST /predecir/lote');
    final json = _decode(text);
    return [for (final r in (json['resultados'] as List? ?? const [])) (r as Map).cast<String, dynamic>()];
  }

  /// Intentos cuando la API de Railway está despertando (Serverless).
  static const _intentos = 5;

  /// ¿El error es por falta de internet en el teléfono (y no porque Railway esté despertando)?
  bool _sinInternet(Object e) {
    if (_status.cachedAt != null) return true; // el backend principal ya respondió desde la caché
    final m = '$e';
    return m.contains('Failed host lookup') || m.contains('Network is unreachable');
  }

  /// Devuelve el cuerpo de la respuesta como texto. Si no hay conexión, usa la última copia guardada.
  Future<String> _send(Future<http.Response> Function() call, {required String cacheKey}) async {
    for (var intento = 1;; intento++) {
      try {
        final res = await call();
        // 502/504: Railway todavía está despertando la API. Se espera 3, 6, 9 y 12 s y se reintenta.
        if ((res.statusCode == 502 || res.statusCode == 504) && intento < _intentos) {
          await Future<void>.delayed(Duration(seconds: 3 * intento));
          continue;
        }
        if (res.statusCode == 503) {
          throw PredictionApiException(_detail(res) ?? 'La API está encendida pero no tiene un modelo entrenado. Ejecuta: python -m scripts.entrenar');
        }
        if (res.statusCode >= 400) {
          throw PredictionApiException('La API respondió ${res.statusCode}: ${_detail(res) ?? res.reasonPhrase ?? ''}');
        }
        final text = utf8.decode(res.bodyBytes);
        _status.online();
        unawaited(_cache.write(cacheKey, text));
        return text;
      } on PredictionApiException {
        rethrow;
      } on TimeoutException {
        final guardado = await _guardado(cacheKey);
        if (guardado != null) return guardado;
        throw PredictionApiException('La API de predicción no respondió a tiempo ($baseUrl).', apiOffline: true);
      } catch (e) {
        // http.ClientException, SocketException (móvil/escritorio) y errores de red del navegador.
        // En la web, un 502 de Railway sin CORS también llega aquí: se reintenta igual.
        // Si el teléfono no tiene internet no vale la pena reintentar: se va directo a la copia guardada.
        if (!_sinInternet(e) && intento < _intentos) {
          await Future<void>.delayed(Duration(seconds: 3 * intento));
          continue;
        }
        final guardado = await _guardado(cacheKey);
        if (guardado != null) return guardado;
        throw PredictionApiException('No se pudo conectar con la API de predicción en $baseUrl.', apiOffline: true);
      }
    }
  }

  Future<String?> _guardado(String cacheKey) async {
    final c = await _cache.read(cacheKey);
    if (c == null) return null;
    _status.servedFromCache(c.savedAt);
    return c.body;
  }

  Map<String, dynamic> _decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const PredictionApiException('Respuesta inesperada de la API.');
  }

  String? _detail(http.Response res) {
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is Map && j['detail'] != null) return '${j['detail']}';
    } catch (_) {}
    return null;
  }

  void close() => _http.close();
}
