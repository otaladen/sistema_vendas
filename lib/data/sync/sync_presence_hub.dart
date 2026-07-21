import 'package:flutter/foundation.dart';

/// Snapshot de estacoes online na LAN (rodape / configuracoes escutam).
class SyncPresenceHub extends ChangeNotifier {
  SyncPresenceHub._();
  static final SyncPresenceHub instance = SyncPresenceHub._();

  int? activeCount;
  List<String> labels = const [];
  DateTime? atualizadoEm;

  bool get temLeitura => activeCount != null;

  void aplicarMap(Map<String, dynamic> map) {
    final n = (map['activeCount'] as num?)?.toInt();
    if (n == null) return;
    final raw = map['stations'];
    final rotulos = <String>[];
    if (raw is List) {
      for (final e in raw) {
        final m = e is Map<String, dynamic>
            ? e
            : e is Map
                ? Map<String, dynamic>.from(e)
                : null;
        if (m == null) continue;
        final lab = (m['label'] ?? '').toString().trim();
        rotulos.add(lab.isEmpty ? 'PC' : lab);
      }
    }
    if (activeCount == n &&
        listEquals(labels, rotulos) &&
        atualizadoEm != null) {
      atualizadoEm = DateTime.now();
      return;
    }
    activeCount = n;
    labels = List<String>.unmodifiable(rotulos);
    atualizadoEm = DateTime.now();
    notifyListeners();
  }

  void marcarIndisponivel() {
    if (activeCount == null && labels.isEmpty) return;
    activeCount = null;
    labels = const [];
    atualizadoEm = DateTime.now();
    notifyListeners();
  }
}
