import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/fiscal_config.dart';
import '../domain/produto_nome_exibicao.dart';
import '../domain/fiscal/fiscal_item_nfce.dart';
import '../domain/fiscal/fiscal_pedido_nfce.dart';
import '../domain/estoque/tipo_movimento_estoque.dart';
import '../domain/fiscal/grupo_tributario_produto.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';

/// Origem de um item para montagem fiscal (carrinho PDV ou venda gravada).
class FiscalItemOrigem {
  const FiscalItemOrigem({
    required this.produto,
    required this.quantidade,
    required this.precoUnitario,
    this.descricaoOverride,
  });

  final Produto produto;
  final int quantidade;
  final double precoUnitario;
  final String? descricaoOverride;

  double get subtotal => quantidade * precoUnitario;
  String get descricao {
    final base = descricaoOverride?.trim();
    if (base != null && base.isNotEmpty) return base;
    final imp = ProdutoNomeExibicao.paraImpressao(produto);
    return imp.isEmpty ? 'Produto' : imp;
  }
}

/// Servico de integracao fiscal (NFC-e) — estrutura pronta para credenciais do contador.
class FiscalService {
  FiscalService({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Resolve CFOP na venda: consumidor final, operacao dentro da Bahia.
  String resolverCfopVenda({
    required Produto produto,
    String ufDestino = FiscalConfig.ufEmitente,
    bool consumidorFinal = true,
    bool operacaoInterna = true,
  }) {
    final cfopProduto = produto.cfopVenda.trim();
    if (cfopProduto.length == 4 && RegExp(r'^\d{4}$').hasMatch(cfopProduto)) {
      return cfopProduto;
    }

    final grupo = grupoTributarioProdutoDeString(produto.grupoTributario);
    final uf = ufDestino.trim().toUpperCase();
    final emitente = FiscalConfig.ufEmitente.toUpperCase();

    if (consumidorFinal && operacaoInterna && uf == emitente) {
      return grupo.cfopVendaConsumidorFinalBahia;
    }

    // Fallback ate o contador definir regras interestaduais / com IE.
    return grupo.cfopVendaConsumidorFinalBahia;
  }

  /// Converte itens do carrinho (PDV) ou equivalente para o formato da API.
  List<FiscalItemNfce> montarItensFiscais(
    List<FiscalItemOrigem> origens, {
    String ufDestino = FiscalConfig.ufEmitente,
    bool consumidorFinal = true,
  }) {
    final itens = <FiscalItemNfce>[];
    var numero = 1;
    for (final o in origens) {
      if (o.quantidade <= 0) continue;
      final p = o.produto;
      final grupo = grupoTributarioProdutoDeString(p.grupoTributario);
      itens.add(
        FiscalItemNfce(
          numeroItem: numero++,
          codigoProduto: p.codigoInterno.trim().isEmpty
              ? 'ID-${p.id}'
              : p.codigoInterno.trim(),
          descricao: o.descricao,
          ncm: normalizarNcm(p.ncm),
          cfop: resolverCfopVenda(
            produto: p,
            ufDestino: ufDestino,
            consumidorFinal: consumidorFinal,
          ),
          unidade: normalizarUnidadeFiscal(p.unidade),
          quantidade: o.quantidade,
          valorUnitario: o.precoUnitario,
          valorTotal: o.subtotal,
          cest: normalizarCest(p.cest),
          grupoTributario: grupo.codigo,
          codigoBarras: p.codigoBarras.trim(),
        ),
      );
    }
    return itens;
  }

  /// Itens a partir da venda finalizada (ObjectBox).
  List<FiscalItemNfce> montarItensDeVenda(
    List<ItemVenda> itensVenda, {
    String ufDestino = FiscalConfig.ufEmitente,
    bool consumidorFinal = true,
  }) {
    final origens = <FiscalItemOrigem>[];
    for (final item in itensVenda) {
      final produto = item.produto.target;
      if (produto == null) {
        throw FiscalValidacaoException(
          'Item "${item.nomeProduto}" sem produto ligado. '
          'Nao e possivel emitir NFC-e.',
        );
      }
      origens.add(
        FiscalItemOrigem(
          produto: produto,
          quantidade: item.quantidade,
          precoUnitario: item.precoUnitario,
          descricaoOverride: ProdutoNomeExibicao.paraImpressaoItem(item),
        ),
      );
    }
    return montarItensFiscais(
      origens,
      ufDestino: ufDestino,
      consumidorFinal: consumidorFinal,
    );
  }

  /// Monta o pedido completo para envio.
  FiscalPedidoNfce montarPedidoNfce({
    required String referenciaInterna,
    required List<FiscalItemOrigem> itensOrigem,
    Cliente? cliente,
    double valorFrete = 0,
    double valorDesconto = 0,
    String observacao = '',
    String ufDestino = FiscalConfig.ufEmitente,
  }) {
    validarCredenciaisConfig();
    final itens = montarItensFiscais(
      itensOrigem,
      ufDestino: ufDestino,
      consumidorFinal: true,
    );
    if (itens.isEmpty) {
      throw FiscalValidacaoException('Nenhum item para emitir NFC-e.');
    }
    for (final item in itens) {
      validarItemFiscal(item);
    }

    final doc = cliente?.documento.replaceAll(RegExp(r'\D'), '') ?? '';
    return FiscalPedidoNfce(
      referenciaInterna: referenciaInterna,
      cnpjEmitente: FiscalConfig.cnpjEmitente,
      ufEmitente: FiscalConfig.ufEmitente,
      itens: itens,
      cpfCnpjDestinatario: doc,
      nomeDestinatario: cliente?.nomeRazao ?? '',
      valorFrete: valorFrete,
      valorDesconto: valorDesconto,
      observacao: observacao,
    );
  }

  /// Envia NFC-e para a API do provedor (estrutura JSON generica).
  Future<FiscalEmissaoResultado> emitirNfce({
    required FiscalPedidoNfce pedido,
  }) async {
    validarCredenciaisConfig();
    if (pedido.itens.isEmpty) {
      return FiscalEmissaoResultado.erro('Pedido sem itens.');
    }

    final uri = Uri.parse(FiscalConfig.endpointEmitirNfce);
    final body = jsonEncode({
      'ambiente': FiscalConfig.ambiente,
      'cnpj': FiscalConfig.cnpjEmitente,
      // Provedores costumam pedir CSC no cadastro da empresa; mantemos no config.
      'csc_id': FiscalConfig.idCsc,
      'csc': FiscalConfig.csc,
      'documento': pedido.toJson(),
    });

    try {
      final response = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${FiscalConfig.apiToken}',
              // Alguns provedores usam header proprio:
              // 'X-API-KEY': FiscalConfig.apiToken,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 60));

      Map<String, dynamic>? jsonBody;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) jsonBody = decoded;
      } catch (_) {}

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final msg = jsonBody?['mensagem'] ??
            jsonBody?['message'] ??
            'HTTP ${response.statusCode}: ${response.body}';
        return FiscalEmissaoResultado.erro(msg.toString());
      }

      if (jsonBody != null) {
        return FiscalEmissaoResultado.deJson(jsonBody);
      }
      return FiscalEmissaoResultado(
        sucesso: true,
        mensagem: 'Resposta recebida (sem JSON estruturado).',
      );
    } catch (e) {
      return FiscalEmissaoResultado.erro('Falha ao comunicar API fiscal: $e');
    }
  }

  /// Fluxo completo: carrinho do PDV → pedido → API.
  Future<FiscalEmissaoResultado> emitirNfceDoCarrinho({
    required List<FiscalItemOrigem> carrinho,
    required String referenciaInterna,
    Cliente? cliente,
    double valorFrete = 0,
    double valorDesconto = 0,
    String observacao = '',
    String ufDestino = FiscalConfig.ufEmitente,
  }) async {
    final pedido = montarPedidoNfce(
      referenciaInterna: referenciaInterna,
      itensOrigem: carrinho,
      cliente: cliente,
      valorFrete: valorFrete,
      valorDesconto: valorDesconto,
      observacao: observacao,
      ufDestino: ufDestino,
    );
    return emitirNfce(pedido: pedido);
  }

  /// Fluxo completo: venda gravada → pedido → API.
  Future<FiscalEmissaoResultado> emitirNfceDaVenda({
    required Venda venda,
    required List<ItemVenda> itens,
    Cliente? cliente,
    double valorDesconto = 0,
    String observacao = '',
    String ufDestino = FiscalConfig.ufEmitente,
  }) async {
    PoliticaMovimentoEstoque.validarNaoAlteraEstoque(
      TipoMovimentoEstoque.nfceEmissao,
    );
    final origens = <FiscalItemOrigem>[];
    for (final item in itens) {
      final p = item.produto.target;
      if (p == null) {
        return FiscalEmissaoResultado.erro(
          'Produto nao encontrado para "${item.nomeProduto}".',
        );
      }
      origens.add(
        FiscalItemOrigem(
          produto: p,
          quantidade: item.quantidade,
          precoUnitario: item.precoUnitario,
          descricaoOverride: ProdutoNomeExibicao.paraImpressaoItem(item),
        ),
      );
    }
    return emitirNfceDoCarrinho(
      carrinho: origens,
      referenciaInterna: 'VENDA-${venda.id}',
      cliente: cliente,
      valorFrete: venda.valorFrete,
      valorDesconto: valorDesconto,
      observacao: observacao,
      ufDestino: ufDestino,
    );
  }

  void validarCredenciaisConfig() {
    if (!FiscalConfig.configurado) {
      throw FiscalConfigIncompletaException(
        'Configure FiscalConfig (apiBaseUrl, apiToken, cnpjEmitente) '
        'em Configuracoes → Fiscal — Focus NFe antes de emitir NFC-e.',
      );
    }
    if (FiscalConfig.csc.trim().isEmpty || FiscalConfig.idCsc.trim().isEmpty) {
      throw FiscalConfigIncompletaException(
        'Informe CSC e ID do CSC em FiscalConfig (dados da SEFAZ-BA).',
      );
    }
  }

  static void validarItemFiscal(FiscalItemNfce item) {
    if (item.ncm.length != 8) {
      throw FiscalValidacaoException(
        'Item ${item.numeroItem} (${item.descricao}): NCM invalido "${item.ncm}". '
        'Cadastre 8 digitos no produto.',
      );
    }
    if (item.cfop.length != 4) {
      throw FiscalValidacaoException(
        'Item ${item.numeroItem}: CFOP invalido "${item.cfop}".',
      );
    }
    if (item.quantidade <= 0) {
      throw FiscalValidacaoException(
        'Item ${item.numeroItem}: quantidade invalida.',
      );
    }
  }

  static String normalizarNcm(String ncm) {
    final digits = ncm.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8) return digits.substring(0, 8);
    return digits.padRight(8, '0').substring(0, 8);
  }

  static String normalizarCest(String cest) {
    final digits = cest.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length >= 7) return digits.substring(0, 7);
    return digits.padLeft(7, '0');
  }

  static String normalizarUnidadeFiscal(String unidade) {
    final u = unidade.trim().toUpperCase();
    if (u.isEmpty) return 'UN';
    if (u == 'MTS' || u == 'METRO') return 'M';
    return u.length > 6 ? u.substring(0, 6) : u;
  }
}

class FiscalValidacaoException implements Exception {
  FiscalValidacaoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FiscalConfigIncompletaException implements Exception {
  FiscalConfigIncompletaException(this.message);
  final String message;
  @override
  String toString() => message;
}
