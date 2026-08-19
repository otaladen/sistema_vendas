import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/api/lan_api_client.dart';
import '../data/api/lan_api_event_hub.dart';
import '../data/api/venda_api_repository.dart';
import '../data/entrega_baixa_outbox.dart';
import '../domain/entrega_baixa_motorista_visao.dart';
import '../domain/entrega_baixa_pendente.dart';
import '../domain/entrega_baixa_sync_regras.dart';
import '../domain/entrega_status_transicao.dart';
import '../model/venda.dart';
import 'entrega_pod_lan_service.dart';

class EntregaBaixaResultado {
  const EntregaBaixaResultado({required this.enviadoAoServidor});

  final bool enviadoAoServidor;
}

/// Enfileira a baixa no aparelho e reenvia para a API quando o Tailscale volta.
class EntregaBaixaSyncService extends ChangeNotifier {
  EntregaBaixaSyncService._();
  static final instance = EntregaBaixaSyncService._();

  static const _intervaloCiclo = Duration(seconds: 15);
  static const _ttlSincronizada = Duration(seconds: 20);

  LanApiClient? _client;
  VendaApiRepository? _vendaApi;
  EntregaPodLanService? _podLan;
  Timer? _timer;
  VoidCallback? _hubListener;
  bool _ligado = false;
  bool _cicloEmAndamento = false;
  List<EntregaBaixaPendente> _pendentes = [];
  final Map<int, _SincronizadaRecente> _sincronizadas = {};
  final Set<int> _emVoo = {};
  final List<EntregaBaixaFalha> _falhas = [];
  int _falhasGeracao = 0;

  List<EntregaBaixaPendente> get pendentes =>
      List<EntregaBaixaPendente>.unmodifiable(_pendentes);

  List<Venda> get sincronizadasRecentes {
    _expirarSincronizadas();
    return _sincronizadas.values.map((e) => e.venda).toList();
  }

  List<EntregaBaixaFalha> get falhas =>
      List<EntregaBaixaFalha>.unmodifiable(_falhas);

  int get falhasGeracao => _falhasGeracao;

  void dispensarFalha(int vendaId) {
    final antes = _falhas.length;
    _falhas.removeWhere((f) => f.vendaId == vendaId);
    if (_falhas.length != antes) notifyListeners();
  }

  bool isPendente(int vendaId) =>
      EntregaBaixaFila.contem(_pendentes, vendaId);

  void ligar({
    required LanApiClient client,
    VendaApiRepository? vendaApi,
    EntregaPodLanService? podLan,
  }) {
    _client = client;
    _vendaApi = vendaApi;
    _podLan = podLan ?? EntregaPodLanService(lanClient: client);
    if (_ligado) {
      unawaited(processarFila());
      return;
    }
    _ligado = true;
    _hubListener = () {
      if (LanApiEventHub.instance.online) {
        unawaited(processarFila());
      }
    };
    LanApiEventHub.instance.addListener(_hubListener!);
    _timer?.cancel();
    _timer = Timer.periodic(_intervaloCiclo, (_) {
      unawaited(processarFila());
    });
    unawaited(_recarregarOutbox());
    unawaited(processarFila());
  }

  void desligar() {
    _timer?.cancel();
    _timer = null;
    if (_hubListener != null) {
      LanApiEventHub.instance.removeListener(_hubListener!);
      _hubListener = null;
    }
    _ligado = false;
    _client = null;
    _vendaApi = null;
    _podLan = null;
    _emVoo.clear();
  }

  Future<void> aoRetomarApp() async {
    if (!_ligado) return;
    await processarFila();
  }

  Future<EntregaBaixaResultado> enfileirarETentar(
    EntregaBaixaPendente item,
  ) async {
    await EntregaBaixaOutbox.upsert(item);
    _pendentes = EntregaBaixaFila.upsert(_pendentes, item);
    notifyListeners();
    unawaited(_enviarUm(item));
    return const EntregaBaixaResultado(enviadoAoServidor: false);
  }

  Future<void> processarFila() async {
    if (_cicloEmAndamento) return;
    _cicloEmAndamento = true;
    try {
      await _recarregarOutbox();
      if (_pendentes.isEmpty) return;
      final fila = List<EntregaBaixaPendente>.from(_pendentes);
      for (final item in fila) {
        await _enviarUm(item);
      }
    } finally {
      _cicloEmAndamento = false;
    }
  }

  Future<void> _recarregarOutbox() async {
    _pendentes = await EntregaBaixaOutbox.listar();
    notifyListeners();
  }

  LanApiClient? get _api => _client ?? LanApiEventHub.instance.client;

  Future<bool> _enviarUm(EntregaBaixaPendente item) async {
    if (!_emVoo.add(item.vendaId)) return false;
    try {
      return await _enviarUmSerializado(item);
    } finally {
      _emVoo.remove(item.vendaId);
    }
  }

  Future<bool> _enviarUmSerializado(EntregaBaixaPendente item) async {
    final api = _api;
    if (api == null || !api.configurado) return false;

    var atual = item;
    final localExiste = atual.fotoPathLocal.trim().isNotEmpty &&
        File(atual.fotoPathLocal).existsSync();
    if (EntregaBaixaSyncRegras.precisaEnviarFoto(
      ehNaoEntregue: atual.ehNaoEntregue,
      fotoPathLocal: atual.fotoPathLocal,
      fotoPathServidor: atual.fotoPathServidor,
      arquivoLocalExiste: localExiste,
    )) {
      try {
        final lan = _podLan ?? EntregaPodLanService(lanClient: api);
        final path = await lan.enviarFotoSeRedeAtiva(
          arquivoLocal: atual.fotoPathLocal,
        );
        if (path != null && path.trim().isNotEmpty) {
          atual = item.copyWith(fotoPathServidor: path);
          await EntregaBaixaOutbox.upsert(atual);
          _pendentes = EntregaBaixaFila.upsert(_pendentes, atual);
        }
      } catch (_) {}
      if (atual.fotoPathServidor.trim().isEmpty) {
        return false;
      }
    }

    try {
      Venda? confirmada;
      final repo = _vendaApi;
      if (atual.ehNaoEntregue) {
        if (repo != null) {
          confirmada = await repo.registrarNaoEntregueMotoristaRemoto(
            vendaId: atual.vendaId,
            motivoCodigo: atual.motivoCodigo,
            motivoDetalhe: atual.motivoDetalhe,
            usuarioLogin: atual.usuarioLogin,
            statusAnterior: atual.statusAnterior,
            retornouParaLoja: atual.retornouParaLoja,
          );
        } else {
          final m = await api.registrarNaoEntregueMotorista(
            vendaId: atual.vendaId,
            motivoCodigo: atual.motivoCodigo,
            motivoDetalhe: atual.motivoDetalhe,
            usuarioLogin: atual.usuarioLogin,
            statusAnterior: atual.statusAnterior,
            retornouParaLoja: atual.retornouParaLoja,
          );
          final itemMap = m['item'];
          if (itemMap is Map) {
            confirmada = LanApiClient.vendaCompletaDeMap(
              Map<String, dynamic>.from(itemMap),
            );
          }
        }
      } else if (repo != null) {
        confirmada = await repo.baixarEntregaMotoristaRemoto(
          vendaId: atual.vendaId,
          recebidoPor: atual.recebidoPor,
          usuarioLogin: atual.usuarioLogin,
          fotoPathLocal: atual.fotoPathLocal,
          fotoPathServidor: atual.fotoPathServidor,
          statusAnterior: atual.statusAnterior,
        );
      } else {
        final m = await api.baixarEntregaMotorista(
          vendaId: atual.vendaId,
          recebidoPor: atual.recebidoPor,
          usuarioLogin: atual.usuarioLogin,
          fotoPathLocal: atual.fotoPathLocal,
          fotoPathServidor: atual.fotoPathServidor,
          statusAnterior: atual.statusAnterior,
        );
        final itemMap = m['item'];
        if (itemMap is Map) {
          confirmada = LanApiClient.vendaCompletaDeMap(
            Map<String, dynamic>.from(itemMap),
          );
        }
      }

      final pathServidor = confirmada?.podFotoPathServidor.trim().isNotEmpty ==
              true
          ? confirmada!.podFotoPathServidor
          : atual.fotoPathServidor;
      if (pathServidor.trim().isNotEmpty &&
          pathServidor != atual.fotoPathServidor) {
        atual = atual.copyWith(fotoPathServidor: pathServidor);
        await EntregaBaixaOutbox.upsert(atual);
        _pendentes = EntregaBaixaFila.upsert(_pendentes, atual);
      }

      final arquivoAindaExiste = atual.fotoPathLocal.trim().isNotEmpty &&
          File(atual.fotoPathLocal).existsSync();
      if (!EntregaBaixaSyncRegras.podeConfirmarRemocao(
        servidorConfirmou: confirmada != null,
        ehNaoEntregue: atual.ehNaoEntregue,
        fotoPathLocal: atual.fotoPathLocal,
        fotoPathServidor: atual.fotoPathServidor,
        arquivoLocalExiste: arquivoAindaExiste,
      )) {
        return false;
      }

      await EntregaBaixaOutbox.remover(atual.vendaId);
      _pendentes = EntregaBaixaFila.remover(_pendentes, atual.vendaId);
      final vendaUi = confirmada ?? atual.paraVendaStub();
      vendaUi.statusEntrega =
          atual.ehNaoEntregue ? 'reagendada' : 'entregue';
      _sincronizadas[atual.vendaId] = _SincronizadaRecente(
        venda: vendaUi,
        ate: DateTime.now().add(_ttlSincronizada),
      );
      notifyListeners();
      return true;
    } catch (e) {
      if (_ehErroPermanente(e)) {
        await EntregaBaixaOutbox.remover(atual.vendaId);
        _pendentes = EntregaBaixaFila.remover(_pendentes, atual.vendaId);
        _registrarFalha(atual, e);
        notifyListeners();
        return false;
      }
      return false;
    }
  }

  void _registrarFalha(EntregaBaixaPendente item, Object e) {
    _falhas.removeWhere((f) => f.vendaId == item.vendaId);
    _falhas.add(
      EntregaBaixaFalha(
        vendaId: item.vendaId,
        numeroOrcamento: item.numeroOrcamento,
        mensagem: EntregaBaixaSyncRegras.mensagemErroPermanente(
          e is LanApiException ? '${e.code ?? ''} ${e.message}' : e,
        ),
      ),
    );
    _falhasGeracao++;
  }

  bool _ehErroPermanente(Object e) {
    if (e is TimeoutException || e is SocketException) return false;
    if (e is LanApiException) {
      if (e.code == EntregaStatusConflitoException.codigoTerminal) {
        return true;
      }
      final c = e.cause;
      if (c is TimeoutException || c is SocketException) return false;
    }
    final m = '$e'.toLowerCase();
    if (m.contains('tempo esgotado') ||
        m.contains('timeout') ||
        m.contains('sem conexao') ||
        m.contains('tailscale') ||
        m.contains('socket') ||
        m.contains('falha de rede')) {
      return false;
    }
    return m.contains('nao encontrada') ||
        m.contains('nao encontrado') ||
        m.contains('recebidopor obrigatorio') ||
        m.contains('motivocodigo obrigatorio') ||
        m.contains('motivo de nao entrega') ||
        m.contains('json invalido') ||
        m.contains('ja foi marcada como entregue') ||
        m.contains('ja foi reagendada') ||
        m.contains('entrega cancelada');
  }

  void _expirarSincronizadas() {
    final agora = DateTime.now();
    _sincronizadas.removeWhere((_, v) => v.ate.isBefore(agora));
  }
}

class _SincronizadaRecente {
  const _SincronizadaRecente({required this.venda, required this.ate});
  final Venda venda;
  final DateTime ate;
}
