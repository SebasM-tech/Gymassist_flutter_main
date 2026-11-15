import 'package:flutter/material.dart';
import 'package:gymassist/core/api/offline_cache.dart';

/// Franja superior "Sin conexión" que aparece cuando la app está mostrando datos guardados.
/// Desaparece sola en cuanto el servidor vuelve a responder.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.child});
  final Widget child;

  static const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  /// "14 nov, 8:33 p. m."
  static String cuando(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.day} ${_meses[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DateTime?>(
        stream: OfflineStatus.instance.changes,
        initialData: OfflineStatus.instance.cachedAt,
        builder: (context, snap) {
          final at = snap.data;
          // La estructura es siempre la misma (con o sin franja) para que la pantalla de abajo no se reinicie.
          return Column(children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: at == null
                  ? const SizedBox(width: double.infinity)
                  : Material(
                      color: const Color(0xFFB45309),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(children: [
                            const Icon(Icons.cloud_off_outlined, size: 16, color: Colors.white),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sin conexión · datos guardados del ${cuando(at.toLocal())}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
            ),
            Expanded(
              // Con la franja visible, ella ya ocupa el espacio de la barra de estado.
              child: MediaQuery.removePadding(context: context, removeTop: at != null, child: child),
            ),
          ]);
        },
      );
}
