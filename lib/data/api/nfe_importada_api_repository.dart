import 'package:flutter/foundation.dart';

import '../../data/devolucao_fornecedor_fiscal_store.dart';
import '../../data/nfe_entrada_repository.dart';
import '../../model/nfe_importada_registro.dart';
import '../../services/devolucao_fornecedor_fiscal_service.dart';
import '../sync/sync_entity_codec_extras.dart';
import 'lan_api_client.dart';
import 'lan_api_event_hub.dart';

/// Resultado de `GET /api/nfe-importadas` (itens + cards).
class NfeImportadasListagemRemota {
  const NfeImportadasListagemRemota({
    required this.items,
    required this.totalNotas,
    required this.fornecedoresDistintos,
    this.ultimaImportacao,
  });

  final List<NfeImportadaRegistro> items;
  final int totalNotas;
  final int fornecedoresDistintos;
  final DateTime? ultimaImportacao;
}

/// Linha do espelho (historico) sem ToOne ObjectBox.
class NfeImportadaLinhaRemota {
  const NfeImportadaLinhaRemota({
    required this.produtoNome,
    required this.quantidadeFornecedor,
    required this.unidadeFornecedor,
    required this.quantidadeEntradaEstoque,
    required this.fatorConversaoUtilizado,
    this.produtoCodigoInterno = '',
  });

  final String produtoNome;
  final String produtoCodigoInterno;
  final double quantidadeFornecedor;
  final String unidadeFornecedor;
  final double quantidadeEntradaEstoque;
  final double fatorConversaoUtilizado;
}

/// Detalhe completo para o bottom sheet / espelho.
class NfeImportadaDetalheRemoto {
  const NfeImportadaDetalheRemoto({
    required this.item,
    required this.itens,
    required this.temXml,
  });

  final NfeImportadaRegistro item;
  final List<NfeImportadaLinhaRemota> itens;
  final bool temXml;
}

/// Historico de NF-e de entrada via API do PC servidor (:8788).
class NfeImportadaApiRepository extends ChangeNotifier {
  NfeImportadaApiRepository(this._client);

  final LanApiClient _client;

  List<NfeImportadaRegistro> _lista = const [];
  int _totalNotas = 0;
  int _fornecedoresDistintos = 0;
  DateTime? _ultimaImportacao;

  List<NfeImportadaRegistro> get lista => _lista;
  int get totalNotas => _totalNotas;
  int get fornecedoresDistintos => _fornecedoresDistintos;
  DateTime? get ultimaImportacao => _ultimaImportacao;

  void _exigirOnline() {
    if (LanApiEventHub.instance.deveBloquearOperacoes) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  Future<NfeImportadasListagemRemota> listarImportadasRemoto({
    String q = '',
    String tipoData = 'importacao',
    DateTime? periodoInicio,
    DateTime? periodoFim,
    String ordenacao = 'importacaoDesc',
  }) async {
    _exigirOnline();
    final m = await _client.listarNfeImportadas(
      q: q,
      tipoData: tipoData,
      periodoInicio: periodoInicio,
      periodoFim: periodoFim,
      ordenacao: ordenacao,
    );
    final list = m['items'];
    final items = list is List
        ? list
            .whereType<Map>()
            .map((e) => SyncEntityCodecExtras.nfeImportadaDeMap(
                  Map<String, dynamic>.from(e),
                ))
            .toList(growable: false)
        : <NfeImportadaRegistro>[];
    final meta = m['meta'];
    DateTime? ultima;
    var total = items.length;
    var forn = 0;
    if (meta is Map) {
      total = (meta['totalNotas'] as num?)?.toInt() ?? total;
      forn = (meta['fornecedoresDistintos'] as num?)?.toInt() ?? 0;
      final u = meta['ultimaImportacao']?.toString();
      if (u != null && u.isNotEmpty) {
        ultima = DateTime.tryParse(u)?.toLocal();
      }
    }
    final result = NfeImportadasListagemRemota(
      items: items,
      totalNotas: total,
      fornecedoresDistintos: forn,
      ultimaImportacao: ultima,
    );
    _lista = items;
    _totalNotas = result.totalNotas;
    _fornecedoresDistintos = result.fornecedoresDistintos;
    _ultimaImportacao = result.ultimaImportacao;
    notifyListeners();
    return result;
  }

  Future<NfeImportadaDetalheRemoto> obterDetalhesRemoto(int id) async {
    _exigirOnline();
    if (id <= 0) {
      throw StateError('id invalido');
    }
    final m = await _client.obterNfeImportadaDetalhe(id);
    final itemRaw = m['item'];
    if (itemRaw is! Map) {
      throw LanApiException('Detalhe da NF-e sem item.');
    }
    final item = SyncEntityCodecExtras.nfeImportadaDeMap(
      Map<String, dynamic>.from(itemRaw),
    );
    final itensRaw = m['itens'];
    final itens = <NfeImportadaLinhaRemota>[];
    if (itensRaw is List) {
      for (final e in itensRaw) {
        if (e is! Map) continue;
        final map = Map<String, dynamic>.from(e);
        itens.add(
          NfeImportadaLinhaRemota(
            produtoNome: (map['produtoNome'] ?? 'Produto').toString(),
            produtoCodigoInterno:
                (map['produtoCodigoInterno'] ?? '').toString(),
            quantidadeFornecedor:
                (map['quantidadeFornecedor'] as num?)?.toDouble() ?? 0,
            unidadeFornecedor: (map['unidadeFornecedor'] ?? '').toString(),
            quantidadeEntradaEstoque:
                (map['quantidadeEntradaEstoque'] as num?)?.toDouble() ?? 0,
            fatorConversaoUtilizado:
                (map['fatorConversaoUtilizado'] as num?)?.toDouble() ?? 1,
          ),
        );
      }
    }
    return NfeImportadaDetalheRemoto(
      item: item,
      itens: itens,
      temXml: m['temXml'] == true,
    );
  }

  Future<({List<int> bytes, String filename})> baixarXmlRemoto(int id) async {
    _exigirOnline();
    final r = await _client.baixarXmlNfeImportada(id);
    final nome = (r.filename != null && r.filename!.trim().isNotEmpty)
        ? r.filename!.trim()
        : 'nfe_$id.xml';
    return (bytes: r.bytes, filename: nome);
  }

  /// Linhas prontas para devolucao (qtd disponivel + espelho fiscal) e historico.
  Future<
      ({
        List<DevolucaoFornecedorLinha> linhas,
        List<DevolucaoFornecedorFiscalRegistro> historico,
      })> obterDevolucaoFornecedorRemoto(int id) async {
    _exigirOnline();
    final m = await _client.obterLinhasDevolucaoFornecedor(id);
    final list = m['linhas'];
    final linhas = list is List
        ? list
            .whereType<Map>()
            .map(
              (e) => DevolucaoFornecedorFiscalService.linhaDeMap(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList(growable: false)
        : const <DevolucaoFornecedorLinha>[];
    final histRaw = m['historico'];
    final historico = histRaw is List
        ? histRaw
            .whereType<Map>()
            .map(
              (e) => DevolucaoFornecedorFiscalRegistro.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList(growable: false)
        : const <DevolucaoFornecedorFiscalRegistro>[];
    return (linhas: linhas, historico: historico);
  }

  /// Linhas prontas para devolucao (qtd disponivel + espelho fiscal).
  Future<List<DevolucaoFornecedorLinha>> obterLinhasDevolucaoRemoto(int id) async {
    final r = await obterDevolucaoFornecedorRemoto(id);
    return r.linhas;
  }

  Future<DevolucaoFornecedorReconsultaResultado>
      reconsultarDevolucaoRemoto(String referencia) async {
    _exigirOnline();
    final m = await _client.reconsultarDevolucaoFornecedor(referencia);
    if (m['ok'] != true) {
      return DevolucaoFornecedorReconsultaResultado.erro(
        (m['error'] ?? m['mensagem'] ?? 'Falha na reconsulta.').toString(),
      );
    }
    DevolucaoFornecedorFiscalRegistro? registro;
    final raw = m['registro'];
    if (raw is Map) {
      registro = DevolucaoFornecedorFiscalRegistro.fromJson(
        Map<String, dynamic>.from(raw),
      );
    }
    final ids = <int>[];
    final idsRaw = m['produtoIds'];
    if (idsRaw is List) {
      for (final e in idsRaw) {
        final n = (e as num?)?.toInt() ?? 0;
        if (n > 0) ids.add(n);
      }
    }
    return DevolucaoFornecedorReconsultaResultado(
      sucesso: true,
      mensagem: (m['mensagem'] ?? '').toString(),
      autorizada: m['autorizada'] == true,
      rejeitada: m['rejeitada'] == true,
      estoqueBaixadoAgora: m['estoqueBaixadoAgora'] == true,
      produtoIds: ids,
      registro: registro,
    );
  }

  Future<DevolucaoFornecedorReconsultaLote>
      reconsultarDevolucaoProcessandoRemoto() async {
    _exigirOnline();
    final m = await _client.reconsultarDevolucaoFornecedorProcessando();
    final ids = <int>[];
    final idsRaw = m['produtoIds'];
    if (idsRaw is List) {
      for (final e in idsRaw) {
        final n = (e as num?)?.toInt() ?? 0;
        if (n > 0) ids.add(n);
      }
    }
    return DevolucaoFornecedorReconsultaLote(
      total: (m['total'] as num?)?.toInt() ?? 0,
      autorizadas: (m['autorizadas'] as num?)?.toInt() ?? 0,
      rejeitadas: (m['rejeitadas'] as num?)?.toInt() ?? 0,
      estoqueBaixado: (m['estoqueBaixado'] as num?)?.toInt() ?? 0,
      produtoIds: ids,
    );
  }

  /// Emite NF-e de devolucao no PC servidor (Focus + baixa).
  Future<DevolucaoFornecedorOperacaoResultado> emitirDevolucaoRemoto({
    required int importacaoId,
    required String motivo,
    required List<DevolucaoFornecedorLinha> linhas,
  }) async {
    _exigirOnline();
    final itens = <Map<String, dynamic>>[];
    for (final l in linhas) {
      if (l.quantidade <= 0) continue;
      itens.add({
        'historicoEntradaId': l.historico.id,
        'produtoId': l.produto.id,
        'quantidade': l.quantidade,
        'espelho': DevolucaoFornecedorFiscalService.espelhoParaMap(l.espelho),
      });
    }
    final m = await _client.emitirDevolucaoFornecedor(importacaoId, {
      'motivo': motivo,
      'itens': itens,
    });
    if (m['ok'] != true) {
      return DevolucaoFornecedorOperacaoResultado.erro(
        (m['error'] ?? m['mensagem'] ?? 'Falha ao emitir devolucao.').toString(),
      );
    }
    return DevolucaoFornecedorOperacaoResultado.ok(
      mensagem: (m['mensagem'] ?? 'NF-e processada.').toString(),
      autorizada: m['autorizada'] == true,
      chaveNfe: (m['chaveNfe'] ?? '').toString(),
      urlDanfe: (m['urlDanfe'] ?? '').toString(),
      referencia: (m['referencia'] ?? '').toString(),
      numero: (m['numero'] ?? '').toString(),
      serie: (m['serie'] ?? '').toString(),
      urlXml: (m['urlXml'] ?? '').toString(),
    );
  }

  /// Preview do estorno (estoque + contas a pagar) sem mutar.
  Future<({ValidacaoEstornoNfe validacao, int qtdContasPagar})>
      validarEstornoRemoto(int entradaId) async {
    _exigirOnline();
    if (entradaId <= 0) {
      throw LanApiException('ID da importacao invalido.');
    }
    final m = await _client.validarEstornoNfeImportada(entradaId);
    final linhas = <LinhaPreviaEstornoNfe>[];
    final rawLinhas = m['linhas'];
    if (rawLinhas is List) {
      for (final e in rawLinhas) {
        if (e is! Map) continue;
        final map = Map<String, dynamic>.from(e);
        linhas.add(
          LinhaPreviaEstornoNfe(
            nomeProduto: (map['nomeProduto'] ?? '').toString(),
            quantidadeEstorno:
                (map['quantidadeEstorno'] as num?)?.toInt() ?? 0,
            estoqueAtual: (map['estoqueAtual'] as num?)?.toInt() ?? 0,
            rotuloEstorno: (map['rotuloEstorno'] ?? '').toString(),
            rotuloEstoqueAtual: (map['rotuloEstoqueAtual'] ?? '').toString(),
          ),
        );
      }
    }
    final pode = m['podeEstornar'] == true;
    final motivo = (m['motivoBloqueio'] ?? '').toString().trim();
    return (
      validacao: ValidacaoEstornoNfe(
        podeEstornar: pode,
        motivoBloqueio: motivo.isEmpty ? null : motivo,
        linhas: linhas,
      ),
      qtdContasPagar: (m['qtdContasPagar'] as num?)?.toInt() ?? 0,
    );
  }

  /// Desfaz entrada por XML no PC1 (estoque, custo medio, contas a pagar).
  Future<Map<String, dynamic>> estornarEntradaRemoto(int entradaId) async {
    _exigirOnline();
    if (entradaId <= 0) {
      throw LanApiException('ID da importacao invalido.');
    }
    final m = await _client.estornarNfeImportada(entradaId);
    if (m['ok'] != true) {
      throw LanApiException(
        (m['error'] ?? m['mensagem'] ?? 'Falha ao estornar importacao.')
            .toString(),
      );
    }
    _lista = List.unmodifiable(_lista.where((e) => e.id != entradaId));
    if (_totalNotas > 0) _totalNotas -= 1;
    notifyListeners();
    return m;
  }
}
