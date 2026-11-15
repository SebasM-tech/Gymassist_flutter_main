import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// MODO SIN CONEXIÓN
///
/// Cada vez que la app lee datos del servidor con internet, la respuesta se guarda
/// en un archivo dentro de la carpeta privada de la app. Si después no hay conexión
/// (modo avión, sin señal), la app muestra esa última copia en vez de un error.
///
/// Solo se guardan LECTURAS. Crear, editar, pagar o borrar siempre necesitan internet.
/// En la web no hay carpeta de archivos: ahí la caché simplemente no hace nada.

/// Una respuesta guardada y cuándo se guardó.
class CachedResponse {
  const CachedResponse(this.body, this.savedAt);
  final String body;
  final DateTime savedAt;
}

class OfflineCache {
  OfflineCache({Future<Directory> Function()? baseDir}) : _baseDir = baseDir ?? getApplicationSupportDirectory;

  /// La caché que usa toda la app.
  static final instance = OfflineCache();

  final Future<Directory> Function() _baseDir;
  Future<Directory?>? _dir;

  Future<Directory?> _folder() => _dir ??= () async {
        try {
          final d = Directory(p.join((await _baseDir()).path, 'offline_cache'));
          await d.create(recursive: true);
          return d;
        } catch (_) {
          return null; // web, o no se pudo crear la carpeta: la app sigue funcionando sin caché
        }
      }();

  /// Nombre de archivo seguro para una clave como "GET /api/m/admin/clientes?x=1".
  static String fileNameFor(String key) {
    // Hash FNV-1a de 32 bits: distingue claves que quedarían iguales al limpiar los símbolos.
    var h = 0x811c9dc5;
    for (final c in utf8.encode(key)) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    final limpio = key.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final corto = limpio.length > 60 ? limpio.substring(0, 60) : limpio;
    return '${corto}_${h.toRadixString(16).padLeft(8, '0')}.json';
  }

  Future<void> write(String key, String body) async {
    try {
      final dir = await _folder();
      if (dir == null) return;
      final contenido = jsonEncode({'guardado': DateTime.now().toIso8601String(), 'body': body});
      // Se escribe en un temporal y se renombra, para no dejar un archivo a medias.
      final tmp = File(p.join(dir.path, '${fileNameFor(key)}.tmp'));
      await tmp.writeAsString(contenido, flush: true);
      await tmp.rename(p.join(dir.path, fileNameFor(key)));
    } catch (_) {
      // La caché nunca debe hacer fallar una petición que salió bien.
    }
  }

  Future<CachedResponse?> read(String key) async {
    try {
      final dir = await _folder();
      if (dir == null) return null;
      final f = File(p.join(dir.path, fileNameFor(key)));
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map || j['body'] is! String) return null;
      return CachedResponse(j['body'] as String, DateTime.tryParse('${j['guardado']}') ?? DateTime.now());
    } catch (_) {
      return null;
    }
  }

  /// Borra todo lo guardado (al cerrar sesión o al entrar con otra cuenta).
  Future<void> clear() async {
    try {
      final dir = await _folder();
      if (dir == null) return;
      await for (final f in dir.list()) {
        if (f is File) await f.delete();
      }
    } catch (_) {}
  }
}

/// Indica si la app está mostrando datos guardados (para la franja "Sin conexión").
class OfflineStatus {
  OfflineStatus._();
  static final instance = OfflineStatus._();

  final _changes = StreamController<DateTime?>.broadcast();
  DateTime? _cachedAt;

  /// Fecha de los datos guardados que se están mostrando, o null si hay conexión.
  DateTime? get cachedAt => _cachedAt;
  Stream<DateTime?> get changes => _changes.stream;

  /// Una lectura falló por falta de conexión y se respondió con la copia guardada.
  void servedFromCache(DateTime savedAt) => _set(savedAt);

  /// El servidor respondió: hay conexión otra vez.
  void online() => _set(null);

  void _set(DateTime? v) {
    if (v == _cachedAt) return;
    _cachedAt = v;
    _changes.add(v);
  }
}
