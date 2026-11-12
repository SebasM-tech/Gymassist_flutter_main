/// Dirección de la API de predicción (FastAPI + TensorFlow, carpeta `prediccion-ml/` del repo GymAssist2.0).
///
/// Por defecto se usa la API desplegada en Railway (se duerme cuando no se usa y despierta sola).
///
/// Para usar la API local se puede cambiar sin tocar código:
///   flutter run -d chrome --dart-define=ML_API_URL=http://localhost:8000
///   flutter run -d <emulador android> --dart-define=ML_API_URL=http://10.0.2.2:8000
///   flutter run -d <android> --dart-define=ML_API_URL=http://192.168.1.50:8000   (celular real, misma Wi-Fi)
class ApiConfig {
  ApiConfig._();

  static const _fromEnv = String.fromEnvironment('ML_API_URL');

  /// API de predicción desplegada en Railway.
  static const mlApiRailway = 'https://feisty-possibility-production.up.railway.app';

  static String get mlApiBaseUrl {
    final v = _fromEnv.isNotEmpty ? _fromEnv : mlApiRailway;
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  /// true si la API apunta a un PC (localhost, emulador o red Wi-Fi) y no a la nube.
  static bool get mlApiEsLocal {
    final host = Uri.tryParse(mlApiBaseUrl)?.host ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2' || host.startsWith('192.168.');
  }

  static const _springFromEnv = String.fromEnvironment('SPRING_API_URL');

  /// Backend Spring Boot (MongoDB, S3, Mercado Pago). Por defecto el de Railway.
  ///   flutter run -d chrome --dart-define=SPRING_API_URL=http://localhost:8080   (backend local)
  static String get springApiBaseUrl {
    const def = 'https://gymassist20-production.up.railway.app';
    final v = _springFromEnv.isNotEmpty ? _springFromEnv : def;
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  static const springTimeout = Duration(seconds: 30);

  /// La red LSTM + la explicación por oclusión tardan un poco con muchos clientes.
  static const predictTimeout = Duration(seconds: 90);

  /// Alto a propósito: si la API de Railway está dormida, la primera petición tarda en despertarla.
  static const healthTimeout = Duration(seconds: 45);
}
