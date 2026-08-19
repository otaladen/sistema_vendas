import 'package:flutter/foundation.dart';

import '../../domain/promocao_cadastro.dart';
import '../../domain/promocao_info_vigente.dart';
import '../../domain/promocao_preco_service.dart';
import '../../model/kit_orcamento.dart';
import '../../model/produto.dart';
import '../../model/promocao.dart';
import '../../model/promocao_combo_item.dart';
import '../../model/promocao_item.dart';
import '../sync/sync_entity_codec_extras.dart';
import 'lan_api_client.dart';
import 'lan_api_event_hub.dart';

class KitOrcamentoApiRepository extends ChangeNotifier {
  KitOrcamentoApiRepository(this._client);

  final LanApiClient _client;
  List<KitOrcamento> _lista = [];

  /// Itens embutidos da API (ToMany ObjectBox nao funciona em entidade detached).
  static final Expando<List<KitOrcamentoItem>> _itensExtraidos =
      Expando<List<KitOrcamentoItem>>();

  bool get _offline => LanApiEventHub.instance.deveBloquearOperacoes;

  void _exigirServidorOnline() {
    if (_offline) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  Future<void> hidratar() async {
    _exigirServidorOnline();
    final raw = await _client.listarKits();
    _lista = raw.map(_kitDeMap).toList(growable: false);
    notifyListeners();
  }

  static KitOrcamento _kitDeMap(Map<String, dynamic> m) {
    final kit = KitOrcamento(
      id: (m['id'] as num?)?.toInt() ?? 0,
      nome: (m['nome'] ?? '').toString(),
      descricao: (m['descricao'] ?? '').toString(),
      ativo: m['ativo'] != false,
      criadoEm: DateTime.tryParse((m['criadoEm'] ?? '').toString())?.toUtc(),
    );
    final carregados = <KitOrcamentoItem>[];
    final itensRaw = m['itens'];
    if (itensRaw is List) {
      for (final raw in itensRaw.whereType<Map>()) {
        final im = Map<String, dynamic>.from(raw);
        final item = KitOrcamentoItem(
          id: (im['id'] as num?)?.toInt() ?? 0,
          quantidade: (im['quantidade'] as num?)?.toInt() ?? 0,
          ordem: (im['ordem'] as num?)?.toInt() ?? 0,
        );
        item.produto.targetId = (im['produtoId'] as num?)?.toInt() ?? 0;
        try {
          item.kit.target = kit;
        } catch (_) {}
        try {
          kit.itens.add(item);
        } catch (_) {
          // ToMany Backlink detached — usa [_itensExtraidos].
        }
        carregados.add(item);
      }
    }
    if (carregados.isNotEmpty) {
      _itensExtraidos[kit] = carregados;
    }
    return kit;
  }

  /// Itens do kit sem depender de ToMany ObjectBox.
  List<KitOrcamentoItem> itensDoKit(KitOrcamento kit) {
    final cached = _itensExtraidos[kit];
    if (cached != null) return List.unmodifiable(cached);
    try {
      return List.unmodifiable(kit.itens.toList());
    } catch (_) {
      return const [];
    }
  }

  List<KitOrcamento> listarPorNome({bool somenteAtivos = false}) {
    if (_offline) return const [];
    var base = List<KitOrcamento>.from(_lista);
    if (somenteAtivos) base = base.where((k) => k.ativo).toList();
    base.sort((a, b) => a.nome.compareTo(b.nome));
    return base;
  }

  KitOrcamento? obterPorId(int id) {
    for (final k in _lista) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// Kits ativos que contem o produto (consulta PDV / sugestao).
  List<KitOrcamento> listarAtivosComProduto(int produtoId, {int limite = 3}) {
    if (_offline || produtoId <= 0 || limite <= 0) return const [];
    final out = <KitOrcamento>[];
    for (final kit in _lista) {
      if (!kit.ativo) continue;
      final tem = itensDoKit(kit).any((it) => it.produto.targetId == produtoId);
      if (!tem) continue;
      out.add(kit);
      if (out.length >= limite) break;
    }
    return out;
  }

  /// Grava no PC1 e devolve o id persistido.
  Future<int> salvarRemoto(
    KitOrcamento kit,
    List<KitOrcamentoItem> itens,
  ) async {
    _exigirServidorOnline();
    final m = await _client.salvarKit({
      'kit': SyncEntityCodecExtras.kitParaMap(kit),
      'itens': itens
          .map(
            (i) => {
              'produtoId': i.produto.targetId,
              'quantidade': i.quantidade,
              'ordem': i.ordem,
            },
          )
          .toList(),
    });
    final id = (m['id'] as num?)?.toInt() ?? 0;
    await hidratar();
    return id;
  }

  void salvar(KitOrcamento kit, List<KitOrcamentoItem> itens) {
    throw StateError('Use salvarRemoto() no terminal leve.');
  }

  Future<bool> removerRemoto(int id) async {
    _exigirServidorOnline();
    final ok = await _client.removerKit(id);
    if (ok) {
      _lista = _lista.where((k) => k.id != id).toList(growable: false);
      notifyListeners();
    }
    return ok;
  }

  bool remover(int id) {
    throw StateError('Use removerRemoto() no terminal leve.');
  }
}

class PromocaoApiRepository extends ChangeNotifier {
  PromocaoApiRepository(this._client);

  final LanApiClient _client;
  List<Promocao> _lista = [];

  /// Itens embutidos da API (Backlink ObjectBox nao funciona em entidade detached).
  static final Expando<List<PromocaoItem>> _itensExtraidos =
      Expando<List<PromocaoItem>>();
  static final Expando<List<PromocaoComboItem>> _comboExtraidos =
      Expando<List<PromocaoComboItem>>();

  bool get _offline => LanApiEventHub.instance.deveBloquearOperacoes;

  void _exigirServidorOnline() {
    if (_offline) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  Future<void> hidratar() async {
    _exigirServidorOnline();
    final raw = await _client.listarPromocoes();
    _lista = raw.map(_promocaoDeMap).toList(growable: false);
    notifyListeners();
  }

  static Promocao _promocaoDeMap(Map<String, dynamic> m) {
    final agora = DateTime.now().toUtc();
    final p = Promocao(
      id: (m['id'] as num?)?.toInt() ?? 0,
      nome: (m['nome'] ?? '').toString(),
      descricao: (m['descricao'] ?? '').toString(),
      dataInicio:
          DateTime.tryParse((m['dataInicio'] ?? '').toString())?.toUtc() ??
              agora,
      dataFim:
          DateTime.tryParse((m['dataFim'] ?? '').toString())?.toUtc() ?? agora,
      ativa: m['ativa'] != false,
      prioridade: (m['prioridade'] as num?)?.toInt() ?? 0,
      tipoRegra: (m['tipoRegra'] ?? '').toString(),
      valorRegra: (m['valorRegra'] as num?)?.toDouble() ?? 0,
      segmentoCliente: (m['segmentoCliente'] ?? '').toString(),
      tipoCampanha: (m['tipoCampanha'] ?? '').toString(),
      margemMinimaPercentual:
          (m['margemMinimaPercentual'] as num?)?.toDouble() ?? 0,
      limiteQuantidadeTotal: (m['limiteQuantidadeTotal'] as num?)?.toInt() ?? 0,
      quantidadeVendidaPromo:
          (m['quantidadeVendidaPromo'] as num?)?.toInt() ?? 0,
      leveQuantidade: (m['leveQuantidade'] as num?)?.toInt() ?? 0,
      pagueQuantidade: (m['pagueQuantidade'] as num?)?.toInt() ?? 0,
      precoCombo: (m['precoCombo'] as num?)?.toDouble() ?? 0,
      criadoEm: DateTime.tryParse((m['criadoEm'] ?? '').toString())?.toUtc(),
    );
    final carregados = <PromocaoItem>[];
    final itensRaw = m['itens'];
    if (itensRaw is List) {
      for (final raw in itensRaw.whereType<Map>()) {
        final im = Map<String, dynamic>.from(raw);
        final item = PromocaoItem(
          id: (im['id'] as num?)?.toInt() ?? 0,
          produtoAlvoId: (im['produtoAlvoId'] as num?)?.toInt() ?? 0,
          categoria: (im['categoria'] ?? '').toString(),
          subcategoria: (im['subcategoria'] ?? '').toString(),
          quantidadeMinima: (im['quantidadeMinima'] as num?)?.toInt() ?? 0,
          quantidadeMaximaPromo:
              (im['quantidadeMaximaPromo'] as num?)?.toInt() ?? 0,
          ordem: (im['ordem'] as num?)?.toInt() ?? 0,
        );
        try {
          item.promocao.target = p;
        } catch (_) {}
        try {
          p.itens.add(item);
        } catch (_) {
          // Backlink detached — usa [_itensExtraidos].
        }
        carregados.add(item);
      }
    }
    if (carregados.isNotEmpty) {
      _itensExtraidos[p] = carregados;
    }

    final comboCarregados = <PromocaoComboItem>[];
    final comboRaw = m['comboItens'];
    if (comboRaw is List) {
      for (final raw in comboRaw.whereType<Map>()) {
        final im = Map<String, dynamic>.from(raw);
        final item = PromocaoComboItem(
          id: (im['id'] as num?)?.toInt() ?? 0,
          produtoAlvoId: (im['produtoAlvoId'] as num?)?.toInt() ?? 0,
          quantidade: (im['quantidade'] as num?)?.toInt() ?? 0,
          ordem: (im['ordem'] as num?)?.toInt() ?? 0,
        );
        try {
          item.promocao.target = p;
        } catch (_) {}
        try {
          p.comboItens.add(item);
        } catch (_) {
          // Backlink detached — usa [_comboExtraidos].
        }
        comboCarregados.add(item);
      }
    }
    if (comboCarregados.isNotEmpty) {
      _comboExtraidos[p] = comboCarregados;
    }
    return p;
  }

  /// Itens da promocao sem depender de Backlink ObjectBox.
  List<PromocaoItem> itensDaPromocao(Promocao p) {
    final cached = _itensExtraidos[p];
    if (cached != null) return List.unmodifiable(cached);
    try {
      return List.unmodifiable(p.itens.toList());
    } catch (_) {
      return const [];
    }
  }

  /// Combo A+B sem depender de Backlink ObjectBox.
  List<PromocaoComboItem> comboItensDaPromocao(Promocao p) {
    final cached = _comboExtraidos[p];
    if (cached != null) return List.unmodifiable(cached);
    try {
      return List.unmodifiable(p.comboItens.toList());
    } catch (_) {
      return const [];
    }
  }

  List<Promocao> listarPorNome() {
    if (_offline) return const [];
    final base = List<Promocao>.from(_lista);
    base.sort((a, b) => a.nome.compareTo(b.nome));
    return base;
  }

  List<Promocao> listarVigentesNaData(DateTime data) {
    final local = DateTime(data.year, data.month, data.day);
    final inicioDia = DateTime.utc(local.year, local.month, local.day);
    final fimDia = DateTime.utc(
      local.year,
      local.month,
      local.day,
      23,
      59,
      59,
      999,
    );
    final lista = _lista.where((p) {
      if (!p.ativa) return false;
      final ini = p.dataInicio.toUtc();
      final fim = p.dataFim.toUtc();
      return !ini.isAfter(fimDia) && !fim.isBefore(inicioDia);
    }).toList()
      ..sort((a, b) => b.prioridade.compareTo(a.prioridade));
    return lista;
  }

  Promocao? obterPorId(int id) {
    for (final p in _lista) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Grava no PC1 e devolve o id persistido.
  Future<int> salvarRemoto(Map<String, dynamic> body) async {
    _exigirServidorOnline();
    final m = await _client.salvarPromocao(body);
    final id = (m['id'] as num?)?.toInt() ?? 0;
    await hidratar();
    return id;
  }

  void salvar(
    Promocao promocao,
    List<PromocaoItem> itens, {
    List<PromocaoComboItem> comboItens = const [],
  }) {
    throw StateError('Use salvarRemoto() no terminal leve.');
  }

  Future<bool> removerRemoto(int id) async {
    _exigirServidorOnline();
    final ok = await _client.removerPromocao(id);
    if (ok) {
      _lista = _lista.where((p) => p.id != id).toList(growable: false);
      notifyListeners();
    }
    return ok;
  }

  void excluir(int id) {
    throw StateError('Use removerRemoto() no terminal leve.');
  }

  Future<Promocao?> alterarStatusRemoto(int id, {bool? ativa}) async {
    _exigirServidorOnline();
    final m = await _client.alterarStatusPromocao(id, ativa: ativa);
    if (m['ok'] != true) return null;
    await hidratar();
    return obterPorId(id);
  }

  Promocao? alterarStatus(int id, {bool? ativa}) {
    throw StateError('Use alterarStatusRemoto() no terminal leve.');
  }

  /// Etiquetas no terminal: usa cache de promocoes + resolver de produto.
  List<({Produto produto, PromocaoInfoVigente info})> listarProdutosEtiquetaGondola(
    DateTime data, {
    Produto? Function(int id)? obterProduto,
  }) {
    final svc = PromocaoPrecoService(this);
    final out = <({Produto produto, PromocaoInfoVigente info})>[];
    final vistos = <int>{};
    for (final promo in listarVigentesNaData(data)) {
      if (PromocaoCadastro.normalizarTipoCampanha(promo.tipoCampanha) ==
          PromocaoCadastro.tipoComboAb) {
        continue;
      }
      for (final it in itensDaPromocao(promo)) {
        if (it.produtoAlvoId <= 0 || vistos.contains(it.produtoAlvoId)) {
          continue;
        }
        final p = obterProduto?.call(it.produtoAlvoId);
        if (p == null || !p.ativo) continue;
        vistos.add(p.id);
        final infos =
            svc.listarCampanhasVigentesParaProduto(p, dataReferencia: data);
        if (infos.isEmpty) continue;
        out.add((produto: p, info: infos.first));
      }
    }
    out.sort((a, b) => a.produto.nome.compareTo(b.produto.nome));
    return out;
  }
}
