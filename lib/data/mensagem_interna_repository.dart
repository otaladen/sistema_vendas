import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/chat_interno_parser.dart';
import '../model/mensagem_interna.dart';

/// Persistencia ultra-leve do chat interno (JSON no disco do PC servidor).
///
/// Mantem no maximo [maxMensagens] e descarta itens com mais de [ttl].
class MensagemInternaRepository {
  MensagemInternaRepository({
    required String storeDirectoryPath,
    this.maxMensagens = 250,
    this.ttl = const Duration(hours: 36),
  }) : _arquivo = File(p.join(storeDirectoryPath, 'chat_interno.json'));

  final File _arquivo;
  final int maxMensagens;
  final Duration ttl;

  static final Map<String, Future<void>> _cadeados = {};

  List<MensagemInterna> _cache = [];
  bool _carregado = false;
  int _proxId = 1;

  Future<T> _serial<T>(Future<T> Function() fn) async {
    final key = _arquivo.path;
    final anterior = _cadeados[key] ?? Future.value();
    final gate = Completer<void>();
    _cadeados[key] = gate.future;
    await anterior;
    try {
      return await fn();
    } finally {
      gate.complete();
    }
  }

  Future<void> _garantirCarregado({bool forcarDisco = false}) async {
    if (_carregado && !forcarDisco) return;
    _carregado = true;
    try {
      if (!await _arquivo.exists()) {
        _cache = [];
        return;
      }
      final raw = await _arquivo.readAsString();
      if (raw.trim().isEmpty) {
        _cache = [];
        return;
      }
      final decoded = jsonDecode(raw);
      final items = <MensagemInterna>[];
      if (decoded is Map && decoded['items'] is List) {
        for (final e in decoded['items'] as List) {
          if (e is Map) {
            items.add(
              MensagemInterna.fromMap(Map<String, dynamic>.from(e)),
            );
          }
        }
      } else if (decoded is List) {
        for (final e in decoded) {
          if (e is Map) {
            items.add(
              MensagemInterna.fromMap(Map<String, dynamic>.from(e)),
            );
          }
        }
      }
      items.sort((a, b) => a.dataHora.compareTo(b.dataHora));
      _cache = items;
      var maior = 0;
      for (final m in _cache) {
        if (m.id > maior) maior = m.id;
      }
      _proxId = maior + 1;
      _podar();
    } catch (_) {
      _cache = [];
    }
  }

  void _podar() {
    final limite = DateTime.now().toUtc().subtract(ttl);
    _cache = _cache.where((m) => !m.dataHora.isBefore(limite)).toList();
    if (_cache.length > maxMensagens) {
      _cache = _cache.sublist(_cache.length - maxMensagens);
    }
  }

  Future<void> _persistir() async {
    _podar();
    final dir = _arquivo.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final payload = jsonEncode({
      'items': _cache.map((m) => m.toMap()).toList(),
    });
    await _arquivo.writeAsString(payload);
  }

  /// Historico recente (cronologico crescente).
  ///
  /// Sempre rele do disco: a API Lan e a UI do PC1 usam instancias
  /// diferentes do mesmo arquivo — cache em memoria ficaria defasado.
  Future<List<MensagemInterna>> listarHistorico() {
    return _serial(() async {
      await _garantirCarregado(forcarDisco: true);
      _podar();
      return List<MensagemInterna>.unmodifiable(_cache);
    });
  }

  /// Historico do dia local (00:00 → agora).
  Future<List<MensagemInterna>> listarDoDia() async {
    final todos = await listarHistorico();
    final agora = DateTime.now();
    final inicioDia = DateTime(agora.year, agora.month, agora.day).toUtc();
    return todos.where((m) => !m.dataHora.isBefore(inicioDia)).toList();
  }

  Future<MensagemInterna> enviar({
    required String vendedor,
    required String texto,
    String clientId = '',
  }) {
    return _serial(() async {
      await _garantirCarregado(forcarDisco: true);
      final autor = vendedor.trim();
      final msg = texto.trim();
      final cid = clientId.trim();
      if (autor.isEmpty) {
        throw ArgumentError('Informe o vendedor/autor do recado.');
      }
      if (msg.isEmpty) {
        throw ArgumentError('Informe o texto do recado.');
      }
      if (msg.length > 500) {
        throw ArgumentError('Recado muito longo (max. 500 caracteres).');
      }
      if (cid.isNotEmpty) {
        for (final m in _cache) {
          if (m.clientId == cid) return m;
        }
      }
      final parsed = ChatInternoParser.parse(msg);
      final item = MensagemInterna(
        id: _proxId++,
        vendedor: autor,
        texto: msg,
        dataHora: DateTime.now().toUtc(),
        clientId: cid,
        pedidoNumero: parsed.pedidoNumero ?? 0,
        mencoes: parsed.mencoes.toList(),
      );
      _cache.add(item);
      await _persistir();
      return item;
    });
  }
}
