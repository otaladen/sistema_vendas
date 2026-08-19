import '../../domain/conferencia_nfe_opcoes.dart';
import '../../domain/produto_embalagem.dart';
import '../../model/item_nota_temporario.dart';
import '../../model/produto.dart';
import '../../services/xml_nfe_parser_service.dart';
import '../nfe_entrada_repository.dart';
import 'lan_api_client.dart';
import 'lan_api_event_hub.dart';
import 'produto_api_repository.dart';

/// Resultado do parse remoto (`POST /api/nfe/ler-xml`).
class NfeEntradaParseRemoto {
  const NfeEntradaParseRemoto({
    required this.nfe,
    required this.jaImportada,
    required this.sugestoes,
  });

  final NfeXmlParseResult nfe;
  final bool jaImportada;
  final List<SugestaoLinhaConferencia> sugestoes;
}

/// Importacao de NF-e de entrada via API do PC servidor (:8788).
class NfeEntradaApiRepository {
  NfeEntradaApiRepository(this._client, this._produtoRepository);

  final LanApiClient _client;
  final dynamic _produtoRepository;

  void _exigirOnline() {
    if (LanApiEventHub.instance.deveBloquearOperacoes) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  Future<bool> chaveNfeJaImportada(String chaveAcesso) async {
    _exigirOnline();
    return _client.verificarChaveNfe(chaveAcesso);
  }

  /// Parse + sugestoes de de-para no PC1 (fonte oficial).
  Future<NfeEntradaParseRemoto> lerXmlRemoto(String xml) async {
    _exigirOnline();
    final xmlLimpo = xml.trim();
    if (xmlLimpo.isEmpty) {
      throw StateError('XML obrigatorio para ler via API.');
    }
    final m = await _client.prepararNfeEntrada(xmlLimpo);
    final nfeRaw = m['nfe'];
    final NfeXmlParseResult nfe;
    if (nfeRaw is Map) {
      nfe = _nfeDeMap(Map<String, dynamic>.from(nfeRaw));
    } else {
      // Fallback: parse local se o servidor for versao antiga sem bloco `nfe`.
      nfe = XmlParserService.parseNfeXmlString(xmlLimpo);
    }
    return NfeEntradaParseRemoto(
      nfe: nfe,
      jaImportada: m['jaImportada'] == true,
      sugestoes: _sugestoesDeResposta(m),
    );
  }

  /// Casamento simplificado usando cache de produtos do terminal.
  List<SugestaoLinhaConferencia> prepararSugestoesConferencia(
    NfeXmlParseResult nfe,
  ) {
    final sugestoes = <SugestaoLinhaConferencia>[];
    for (final item in nfe.itens) {
      Produto? produtoResolvido;
      var resolvidoPorEan = false;
      if (item.codigoBarras.isNotEmpty) {
        produtoResolvido = _produtoRepository.resolverLeitorCodigoBarras(
          item.codigoBarras,
          somenteAtivos: false,
        ) as dynamic;
        if (produtoResolvido != null) {
          resolvidoPorEan = true;
        }
      }
      final fatorInicial = produtoResolvido != null
          ? (ProdutoEmbalagem.fatorSugeridoNotaParaEstoque(
                  produto: produtoResolvido,
                  unidadeNota: item.unidadeComercial,
                ) ??
                1.0)
          : 1.0;
      if (produtoResolvido != null) {
        sugestoes.add(
          SugestaoLinhaConferencia(
            item: item,
            produtoNovo: false,
            produtoExistenteId: produtoResolvido.id,
            fatorInicial: fatorInicial,
            unidadeInternaInicial: produtoResolvido.unidade.trim().isEmpty
                ? 'UN'
                : produtoResolvido.unidade.trim(),
            embalagemMultiplicaInicial: produtoResolvido.embalagemMultiplica,
            tipoMatch: resolvidoPorEan
                ? ConferenciaNfeMatchTipo.vinculadoPorEan
                : ConferenciaNfeMatchTipo.vinculoFornecedor,
          ),
        );
      } else {
        sugestoes.add(
          SugestaoLinhaConferencia(
            item: item,
            produtoNovo: true,
            produtoExistenteId: null,
            fatorInicial: fatorInicial,
            unidadeInternaInicial: 'UN',
            embalagemMultiplicaInicial: true,
            tipoMatch: ConferenciaNfeMatchTipo.produtoNovo,
          ),
        );
      }
    }
    return sugestoes;
  }

  /// Casamento completo no PC1 (EAN + fornecedor) via API.
  Future<List<SugestaoLinhaConferencia>> prepararSugestoesConferenciaRemoto(
    String xml,
  ) async {
    final parse = await lerXmlRemoto(xml);
    if (parse.sugestoes.isNotEmpty) return parse.sugestoes;
    return prepararSugestoesConferencia(parse.nfe);
  }

  Future<void> confirmarEntrada({
    required NfeXmlParseResult nfe,
    required List<ConferenciaNfeLinhaConfirmacao> linhas,
    ConferenciaNfeOpcoes opcoes = const ConferenciaNfeOpcoes(),
    double margemMinimaVendaPercentual = 20,
    String? xmlOriginal,
  }) async {
    _exigirOnline();
    final xml = xmlOriginal?.trim() ?? '';
    if (xml.isEmpty) {
      throw StateError('XML original obrigatorio para confirmar via API.');
    }
    final m = await _client.confirmarNfeEntrada({
      'xml': xml,
      'margemMinimaVendaPercentual': margemMinimaVendaPercentual,
      'opcoes': {
        'lancarEstoque': opcoes.lancarEstoque,
        'gerarContasPagar': opcoes.gerarContasPagar,
        'atualizarPrecoCusto': opcoes.atualizarPrecoCusto,
        'atualizarPrecosVenda': opcoes.atualizarPrecosVenda,
      },
      'linhas': linhas
          .map(
            (l) => {
              'numeroItem': l.item.numeroItem,
              'fatorConversao': l.fatorConversao,
              'unidadeInterna': l.unidadeInterna,
              'embalagemMultiplica': l.embalagemMultiplica,
              'produtoExistenteId': l.produtoExistenteId,
              if (l.numeroLoteEfetivo.isNotEmpty)
                'numeroLote': l.numeroLoteEfetivo,
              if (l.dataValidadeEfetiva != null)
                'dataValidade':
                    l.dataValidadeEfetiva!.toUtc().toIso8601String(),
            },
          )
          .toList(),
    });
    final repo = _produtoRepository;
    if (repo is ProdutoApiRepository) {
      final idsRaw = m['produtoIds'];
      final ids = idsRaw is List
          ? idsRaw
              .map((e) => (e as num?)?.toInt() ?? 0)
              .where((id) => id > 0)
              .toList()
          : <int>[
              for (final l in linhas)
                if ((l.produtoExistenteId ?? 0) > 0) l.produtoExistenteId!,
            ];
      if (ids.isNotEmpty) {
        await repo.atualizarEstoquePorIds(ids);
      } else {
        await repo.hidratar();
      }
      repo.invalidarCacheBusca();
    }
  }

  Future<Map<String, dynamic>> solicitarDevolucaoRemoto({
    required int importacaoId,
    required String usuarioLogin,
    String terminalId = '',
    Map<String, dynamic>? detalhes,
  }) =>
      _client.solicitarDevolucaoFornecedor(importacaoId, {
        'usuarioLogin': usuarioLogin,
        'terminalId': terminalId,
        if (detalhes != null) ...detalhes,
      });

  /// Listagem remota do historico de entradas (Terminal Leve).
  Future<Map<String, dynamic>> listarImportadasRemoto({
    String q = '',
    String tipoData = 'importacao',
    DateTime? periodoInicio,
    DateTime? periodoFim,
    String ordenacao = 'importacaoDesc',
  }) async {
    _exigirOnline();
    return _client.listarNfeImportadas(
      q: q,
      tipoData: tipoData,
      periodoInicio: periodoInicio,
      periodoFim: periodoFim,
      ordenacao: ordenacao,
    );
  }

  /// Detalhe + itens do espelho via API.
  Future<Map<String, dynamic>> obterDetalhesRemoto(int id) async {
    _exigirOnline();
    return _client.obterNfeImportadaDetalhe(id);
  }

  static List<SugestaoLinhaConferencia> _sugestoesDeResposta(
    Map<String, dynamic> m,
  ) {
    final raw = m['sugestoes'];
    if (raw is! List) return const [];
    final out = <SugestaoLinhaConferencia>[];
    for (final s in raw.whereType<Map>()) {
      final sm = Map<String, dynamic>.from(s);
      final itemRaw = sm['item'];
      if (itemRaw is! Map) continue;
      final item = _itemDeMap(Map<String, dynamic>.from(itemRaw));
      final tipoNome = (sm['tipoMatch'] ?? 'produtoNovo').toString();
      final tipo = ConferenciaNfeMatchTipo.values.firstWhere(
        (e) => e.name == tipoNome,
        orElse: () => ConferenciaNfeMatchTipo.produtoNovo,
      );
      out.add(
        SugestaoLinhaConferencia(
          item: item,
          produtoNovo: sm['produtoNovo'] == true,
          produtoExistenteId: (sm['produtoExistenteId'] as num?)?.toInt(),
          fatorInicial: (sm['fatorInicial'] as num?)?.toDouble() ?? 1,
          unidadeInternaInicial:
              (sm['unidadeInternaInicial'] ?? 'UN').toString(),
          embalagemMultiplicaInicial: sm['embalagemMultiplicaInicial'] != false,
          tipoMatch: tipo,
        ),
      );
    }
    return out;
  }

  static NfeXmlParseResult _nfeDeMap(Map<String, dynamic> m) {
    final emitRaw = m['emitente'];
    final emit = emitRaw is Map
        ? Map<String, dynamic>.from(emitRaw)
        : <String, dynamic>{};
    final itensRaw = m['itens'];
    final dupsRaw = m['duplicatas'];
    return NfeXmlParseResult(
      chaveAcesso: (m['chaveAcesso'] ?? '').toString(),
      numeroNota: (m['numeroNota'] as num?)?.toInt() ?? 0,
      dataEmissao:
          DateTime.tryParse((m['dataEmissao'] ?? '').toString())?.toUtc() ??
              DateTime.now().toUtc(),
      emitente: EmitenteNfeTemporario(
        cnpj: (emit['cnpj'] ?? '').toString(),
        razaoSocial: (emit['razaoSocial'] ?? '').toString(),
        nomeFantasia: (emit['nomeFantasia'] ?? '').toString(),
        inscricaoEstadual: (emit['inscricaoEstadual'] ?? '').toString(),
        logradouro: (emit['logradouro'] ?? '').toString(),
        numero: (emit['numero'] ?? '').toString(),
        complemento: (emit['complemento'] ?? '').toString(),
        bairro: (emit['bairro'] ?? '').toString(),
        municipio: (emit['municipio'] ?? '').toString(),
        codigoMunicipioIbge: (emit['codigoMunicipioIbge'] ?? '').toString(),
        uf: (emit['uf'] ?? '').toString(),
        cep: (emit['cep'] ?? '').toString(),
        telefone: (emit['telefone'] ?? '').toString(),
        email: (emit['email'] ?? '').toString(),
      ),
      itens: itensRaw is List
          ? itensRaw
              .whereType<Map>()
              .map((e) => _itemDeMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      duplicatas: dupsRaw is List
          ? dupsRaw.whereType<Map>().map((e) {
              final dm = Map<String, dynamic>.from(e);
              return NfeDuplicataXml(
                numeroParcela: (dm['numeroParcela'] ?? '').toString(),
                dataVencimento: DateTime.tryParse(
                      (dm['dataVencimento'] ?? '').toString(),
                    )?.toUtc() ??
                    DateTime.now().toUtc(),
                valorParcela: (dm['valorParcela'] as num?)?.toDouble() ?? 0,
              );
            }).toList()
          : const [],
      valorTotalNota: (m['valorTotalNota'] as num?)?.toDouble() ?? 0,
    );
  }

  static ItemNotaTemporario _itemDeMap(Map<String, dynamic> im) =>
      ItemNotaTemporario(
        numeroItem: (im['numeroItem'] as num?)?.toInt() ?? 0,
        codigo: (im['codigo'] ?? '').toString(),
        descricao: (im['descricao'] ?? '').toString(),
        unidadeComercial: (im['unidadeComercial'] ?? '').toString(),
        quantidadeComercial:
            (im['quantidadeComercial'] as num?)?.toDouble() ?? 0,
        valorUnitarioComercial:
            (im['valorUnitarioComercial'] as num?)?.toDouble() ?? 0,
        codigoBarras: (im['codigoBarras'] ?? '').toString(),
        ncm: (im['ncm'] ?? '').toString(),
        cfop: (im['cfop'] ?? '').toString(),
        icmsOrigem: (im['icmsOrigem'] ?? '').toString(),
        icmsSituacaoTributaria: (im['icmsSituacaoTributaria'] ?? '').toString(),
        icmsBaseCalculo: (im['icmsBaseCalculo'] as num?)?.toDouble() ?? 0,
        icmsAliquota: (im['icmsAliquota'] as num?)?.toDouble() ?? 0,
        icmsValor: (im['icmsValor'] as num?)?.toDouble() ?? 0,
        icmsBaseCalculoSt: (im['icmsBaseCalculoSt'] as num?)?.toDouble() ?? 0,
        icmsAliquotaSt: (im['icmsAliquotaSt'] as num?)?.toDouble() ?? 0,
        icmsValorSt: (im['icmsValorSt'] as num?)?.toDouble() ?? 0,
        ipiValor: (im['ipiValor'] as num?)?.toDouble() ?? 0,
        numeroLote: (im['numeroLote'] ?? '').toString(),
        dataValidade: DateTime.tryParse(
          (im['dataValidade'] ?? '').toString(),
        )?.toUtc(),
      );
}
