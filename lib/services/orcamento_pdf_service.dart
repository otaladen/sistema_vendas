import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config/fiscal_config.dart';
import '../data/app_config_repository.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/orcamento_condicoes_pagamento.dart';
import '../domain/pagamento_orcamento.dart';
import '../domain/plano_fiado.dart';
import '../domain/produto_embalagem.dart';
import '../domain/produto_nome_exibicao.dart';
import '../domain/quantidade_venda_util.dart';
import '../domain/venda_relacao_safe.dart';
import '../model/cliente.dart';
import '../model/config_layout_impressao.dart';
import 'impressoes_service.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import 'configuracoes_service.dart';
import 'cupom_pdf_gerado.dart';
import 'cupom_pdf_layout.dart';

/// Gera PDF profissional de orcamento (materiais de construcao / ERP).
///
/// Regras: sem CPF/CNPJ do cliente; cabecalho da loja com CNPJ; itens com
/// SKU + qtd/unidade; totais + condicoes de pagamento; aviso sem valor fiscal.
abstract final class OrcamentoPdfService {
  OrcamentoPdfService._();

  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');

  static String formatarMoeda(double v) => 'R\$ ${_moeda.format(v)}';

  static String rotuloFormaPagamento(String forma) {
    switch (forma) {
      case 'dinheiro':
        return 'Dinheiro';
      case 'pix':
        return 'PIX';
      case 'cartao_debito':
        return 'Cartao debito';
      case 'cartao_credito':
        return 'Cartao credito';
      case 'transferencia':
        return 'Transferencia';
      case 'fiado':
        return 'Fiado';
      case 'misto':
        return 'Misto';
      default:
        if (forma.startsWith('cartao')) return forma;
        return forma.isEmpty ? '-' : forma;
    }
  }

  static String textoPagamento(Venda v) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      final base = rotuloFormaPagamento(v.formaPagamento);
      if (v.formaPagamento == 'cartao_credito' && v.quantidadeParcelas > 1) {
        return '$base ${v.quantidadeParcelas}x';
      }
      if (v.formaPagamento == 'cartao_credito') {
        return '$base a vista';
      }
      if (v.formaPagamento == 'pix' || v.formaPagamento == 'dinheiro') {
        return '$base a vista';
      }
      return base;
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    return linhas
        .map((l) {
          final base = '${rotuloFormaPagamento(l.meio)} ${formatarMoeda(l.valor)}';
          if (l.meio == 'cartao_credito' && l.parcelas > 0) {
            final vp = l.valor / l.parcelas;
            return '$base ${l.parcelas}x de ${formatarMoeda(vp)}';
          }
          return base;
        })
        .join('; ');
  }

  static String rotuloVendedor(Venda venda, {dynamic vendedorRepository}) {
    final v = VendaRelacaoSafe.vendedor(
      venda,
      vendedorRepository: vendedorRepository,
    );
    if (v == null) return 'Sem vendedor';
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isNotEmpty ? '$codigo · $nome' : nome;
  }

  static String quantidadeComUnidade({
    required ItemVenda item,
    Produto? produto,
  }) {
    final qtdEfetiva = ProdutoEmbalagem.quantidadeVendaEfetivaItem(
      produto: produto,
      quantidadeArmazenada: item.quantidade,
    );
    if (produto != null) {
      final qTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
        produto,
        qtdEfetiva,
      );
      final u = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
      return u.isEmpty ? qTxt : '$qTxt $u';
    }
    return QuantidadeVendaUtil.formatarExibicao(
      qtdEfetiva,
      fracionada: false,
    );
  }

  static Future<CupomPdfGerado> gerar({
    required Venda venda,
    required List<ItemVenda> itens,
    required EmpresaConfig empresa,
    required int validadeDias,
    Cliente? cliente,
    Vendedor? vendedor,
    Map<int, Produto?>? produtosPorItem,
    Uint8List? logoBytesOverride,
    String Function(double)? formatarMoedaFn,
  }) async {
    final fiscal = await ConfiguracoesService.resolverFiscalGlobal();
    final formatar = formatarMoedaFn ?? formatarMoeda;
    final itensOrcamento = List<ItemVenda>.from(itens);
    final produtos = <int, Produto?>{};
    for (var i = 0; i < itensOrcamento.length; i++) {
      final item = itensOrcamento[i];
      var produto = produtosPorItem?[i];
      if (produto == null) {
        try {
          produto = item.produto.target;
        } catch (_) {
          produto = null;
        }
      }
      produtos[i] = produto;
    }

    final subtotalItens = itensOrcamento.fold<double>(
      0,
      (s, item) => s + item.subtotal,
    );
    final bruto =
        subtotalItens + (venda.valorFrete > 0 ? venda.valorFrete : 0);
    final total = itensOrcamento.isEmpty
        ? venda.total
        : (bruto - venda.descontoImplicitoTotal).clamp(0.0, double.infinity);
    final desconto = venda.descontoImplicitoTotal;
    final temFrete = venda.valorFrete > 0;

    Uint8List logoBytes = logoBytesOverride ?? Uint8List(0);
    if (logoBytes.isEmpty) {
      final logoPath = empresa.logoPath.trim();
      if (logoPath.isNotEmpty) {
        try {
          logoBytes = await File(logoPath).readAsBytes();
        } catch (_) {
          logoBytes = Uint8List(0);
        }
      }
    }

    final dataEmissao = DateTime.now();
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(dataEmissao);
    final validade = dataEmissao.add(Duration(days: validadeDias));
    final validadeFmt = DateFormat('dd/MM/yyyy').format(validade);

    final c = cliente;
    final temCliente = c != null && c.nomeRazao.trim().isNotEmpty;
    final v = vendedor;
    final temVendedor = v != null;
    final modelo = empresaModeloPdfDeString(empresa.modeloPdf);
    final comLogo = logoBytes.isNotEmpty;

    // LGPD: forca ocultar documento do cliente no papel de cotacao.
    final layout = ImpressoesService.layoutOrcamentoEfetivo(empresa).copyWith(
      familiaFonte: LayoutFamiliaFonte.courier,
      linhaQuantidadePreco: true,
      exibirDocumentoCliente: false,
      exibirValidadeOrcamento: true,
      exibirVendedor: true,
      exibirTelefoneCliente: true,
      exibirTelefone: true,
    );

    final cnpjEmpresa = fiscal.cnpjEmitente.trim().isNotEmpty
        ? fiscal.cnpjEmitente
        : FiscalConfig.cnpjEmitente;
    final telLoja = empresa.telefone.trim();
    const whatsappLoja = '';

    final doc = CupomPdfLayout.criarDocumento(layout);
    final nomesItens = List<String>.generate(itensOrcamento.length, (i) {
      final item = itensOrcamento[i];
      final produto = produtos[i];
      final snap = item.nomeProduto.trim();
      final nome = produto != null
          ? ProdutoNomeExibicao.paraImpressao(produto)
          : (snap.isEmpty ? 'Produto' : snap);
      final sku = (produto?.codigoInterno ?? '').trim();
      return sku.isEmpty ? nome : '$sku - $nome';
    });
    final unidadesItens = CupomPdfLayout.unidadesAlturaItensOrcamento(
      nomesItens,
      comModalidade: false,
    );
    final linhasEntrega = EntregaVendaHelper.linhasBlocoEntregaImpressao(
      venda: venda,
      cliente: c,
      itens: itensOrcamento,
    );
    final linhasEntregaExtra =
        EntregaVendaHelper.contarLinhasBlocoEntregaImpressao(
      venda: venda,
      cliente: c,
      itens: itensOrcamento,
    );
    final pageFormat = CupomPdfLayout.formatoPaginaOrcamentoSalvar(
      modelo: modelo,
      layout: layout,
      qtdItens: unidadesItens > 0 ? unidadesItens : itensOrcamento.length,
      linhasTexto: 12 +
          (temCliente ? 2 : 0) +
          (temVendedor ? 1 : 0) +
          (layout.exibirValidadeOrcamento ? 1 : 0) +
          (telLoja.isNotEmpty || whatsappLoja.isNotEmpty ? 1 : 0) +
          (cnpjEmpresa.trim().isNotEmpty ? 1 : 0),
      // Folga: aviso fiscal + forma de pagamento escolhida (+ rodape config).
      linhasExtras: 6 +
          OrcamentoCondicoesPagamento.quantidadeLinhasLayout(
            formaPagamento: venda.formaPagamento,
            quantidadeParcelas: venda.quantidadeParcelas,
            pagamentosJson: venda.pagamentosJson,
          ) +
          (temFrete ? 1 : 0) +
          (desconto > 0 ? 1 : 0) +
          (PlanoFiadoCodec.vendaTemPlanoQuitacao(venda) ? 3 : 0) +
          linhasEntregaExtra +
          (empresa.rodapeOrcamento.trim().isEmpty ? 0 : 2),
      comLogo: comLogo,
    );

    final nomeCliente = CupomPdfLayout.textoTermicoAscii(c?.nomeRazao.trim() ?? '');
    final telCliente = CupomPdfLayout.textoTermicoAscii(c?.telefone.trim() ?? '');
    String rotuloVend = '';
    if (v != null) {
      final nome = v.apelido.trim().isNotEmpty
          ? v.apelido.trim()
          : v.nomeCompleto.trim();
      final codigo = v.codigoInterno.trim();
      rotuloVend = CupomPdfLayout.textoTermicoAscii(
        codigo.isNotEmpty ? '$codigo - $nome' : nome,
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              ...CupomPdfLayout.cabecalhoEmpresa(
                layout: layout,
                nomeLoja: empresa.nomeLoja,
                logoBytes: comLogo ? logoBytes : null,
                telefone: telLoja,
                whatsapp: whatsappLoja,
                endereco: empresa.endereco,
                cnpj: cnpjEmpresa,
              ),
              CupomPdfLayout.faixaTipoDocumento(
                layout: layout,
                titulo: layout.tituloDocumentoEfetivoOrcamento,
              ),
              CupomPdfLayout.textoCorpo(
                'ORCAMENTO N. ${venda.numeroOrcamento}',
                layout,
                fontWeight: pw.FontWeight.bold,
              ),
              CupomPdfLayout.textoCorpo(
                'Emissao: $dataHora',
                layout,
                fontWeight: pw.FontWeight.bold,
              ),
              CupomPdfLayout.textoCorpo(
                'Validade: $validadeFmt ($validadeDias dias)',
                layout,
                fontWeight: pw.FontWeight.bold,
              ),
              CupomPdfLayout.divisoriaSecao(layout: layout),
              if (temCliente) ...[
                CupomPdfLayout.tituloSecao('CLIENTE', layout),
                CupomPdfLayout.textoCorpo('Nome: $nomeCliente', layout),
                if (layout.exibirTelefoneCliente && telCliente.isNotEmpty)
                  CupomPdfLayout.textoCorpo('Telefone: $telCliente', layout),
                // Documento do cliente propositalmente omitido (LGPD).
              ],
              if (temVendedor && layout.exibirVendedor)
                CupomPdfLayout.textoCorpo(
                  'Vendedor/Atendente: $rotuloVend',
                  layout,
                ),
              ...CupomPdfLayout.blocoDadosEntregaCarreto(
                layout: layout,
                linhas: linhasEntrega,
              ),
              CupomPdfLayout.divisoriaSecao(layout: layout),
              CupomPdfLayout.tituloSecao('ITENS', layout),
              if (CupomPdfLayout.cabecalhoColunasItens(layout) != null)
                CupomPdfLayout.cabecalhoColunasItens(layout)!,
              if (itensOrcamento.isEmpty)
                CupomPdfLayout.textoCorpo('(Sem itens)', layout)
              else
                ...List<pw.Widget>.generate(itensOrcamento.length, (index) {
                  final item = itensOrcamento[index];
                  final produto = produtos[index];
                  final qtdEfetiva =
                      ProdutoEmbalagem.quantidadeVendaEfetivaItem(
                    produto: produto,
                    quantidadeArmazenada: item.quantidade,
                  );
                  final snap = item.nomeProduto.trim();
                  final nome = produto != null
                      ? ProdutoNomeExibicao.paraImpressao(produto)
                      : (snap.isEmpty ? 'Produto' : snap);
                  final sku = (produto?.codigoInterno ?? '').trim();
                  final qtdUnidade = quantidadeComUnidade(
                    item: item,
                    produto: produto,
                  );
                  return CupomPdfLayout.itemVenda(
                    layout: layout,
                    nomeProduto: CupomPdfLayout.textoTermicoAscii(nome),
                    codigoSku: sku.isEmpty ? null : sku,
                    quantidade: item.quantidade,
                    quantidadeExibicao:
                        CupomPdfLayout.textoTermicoAscii(qtdUnidade),
                    precoUnitario: item.precoUnitario,
                    subtotal: qtdEfetiva * item.precoUnitario,
                    formatarMoeda: formatar,
                  );
                }),
              if (layout.divisoriaDestaqueAntesTotais)
                CupomPdfLayout.divisoriaSecao(layout: layout, destaque: true)
              else
                CupomPdfLayout.divisoriaSecao(layout: layout),
              CupomPdfLayout.tituloSecao('RESUMO', layout),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Subtotal produtos:',
                valor: formatar(subtotalItens),
              ),
              if (temFrete)
                CupomPdfLayout.linhaTotal(
                  layout: layout,
                  rotulo: 'Frete/Entrega:',
                  valor: formatar(venda.valorFrete),
                ),
              if (desconto > 0)
                CupomPdfLayout.linhaTotal(
                  layout: layout,
                  rotulo: 'Desconto:',
                  valor: '- ${formatar(desconto)}',
                ),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'VALOR TOTAL:',
                valor: formatar(total),
                destaque: true,
              ),
              CupomPdfLayout.divisoriaSecao(layout: layout),
              CupomPdfLayout.tituloSecao(
                OrcamentoCondicoesPagamento.tituloSecao,
                layout,
              ),
              ...OrcamentoCondicoesPagamento.linhasDaVenda(
                venda,
                total: total,
                formatarMoeda: formatar,
              ).map(
                (linha) => CupomPdfLayout.textoCorpo(
                  CupomPdfLayout.textoTermicoAscii(linha),
                  layout,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (PlanoFiadoCodec.vendaTemPlanoQuitacao(venda)) ...[
                CupomPdfLayout.textoCorpo(
                  'Condicao de quitacao (fiado):',
                  layout,
                  fontWeight: pw.FontWeight.bold,
                ),
                ...PlanoFiadoCodec.linhasTextoPdf(
                  venda,
                ).map(
                  (linha) => CupomPdfLayout.textoCorpo(
                    CupomPdfLayout.textoTermicoAscii(linha),
                    layout,
                  ),
                ),
              ],
              ...CupomPdfLayout.avisoCotacaoSemValorFiscal(layout),
              ...CupomPdfLayout.rodapeDocumento(
                layout: layout,
                textoRodape: empresa.rodapeOrcamento.trim().isEmpty
                    ? ''
                    : CupomPdfLayout.textoTermicoAscii(empresa.rodapeOrcamento),
              ),
            ],
          );
        },
      ),
    );

    return CupomPdfGerado(
      bytes: await doc.save(),
      pageFormat: pageFormat,
      layout: layout,
    );
  }
}
