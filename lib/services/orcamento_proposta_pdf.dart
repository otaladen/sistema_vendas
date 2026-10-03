import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config/fiscal_config.dart';
import '../data/app_config_repository.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/orcamento_condicoes_pagamento.dart';
import '../domain/orcamento_totais_impressao.dart';
import '../domain/plano_fiado.dart';
import '../domain/produto_embalagem.dart';
import '../domain/produto_nome_exibicao.dart';
import '../model/cliente.dart';
import '../model/config_layout_impressao.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import 'configuracoes_service.dart';
import 'cupom_pdf_gerado.dart';
import 'cupom_pdf_layout.dart';
import 'orcamento_pdf_service.dart';

/// Orçamento em A4 para enviar ao cliente (arquivo e WhatsApp).
///
/// A bobina térmica continua em [OrcamentoPdfService.gerar].
abstract final class OrcamentoPropostaPdf {
  OrcamentoPropostaPdf._();

  static const _avisoFiscal =
      'Este documento é uma cotação e não possui valor fiscal.';

  static Future<CupomPdfGerado> gerar({
    required Venda venda,
    required List<ItemVenda> itens,
    required EmpresaConfig empresa,
    required int validadeDias,
    Cliente? cliente,
    Vendedor? vendedor,
    Map<int, Produto?>? produtosPorItem,
    Uint8List? logoBytesOverride,
    String? cnpjEmitente,
    String Function(double)? formatarMoedaFn,
  }) async {
    final formatar = formatarMoedaFn ?? OrcamentoPdfService.formatarMoeda;
    final itensOrcamento = List<ItemVenda>.from(itens);
    final produtos = <int, Produto?>{};
    for (var i = 0; i < itensOrcamento.length; i++) {
      final informado = produtosPorItem;
      if (informado != null && informado.containsKey(i)) {
        produtos[i] = informado[i];
        continue;
      }
      try {
        produtos[i] = itensOrcamento[i].produto.target;
      } catch (_) {
        produtos[i] = null;
      }
    }

    final totais = OrcamentoTotaisImpressao.calcular(
      venda: venda,
      itens: itensOrcamento,
    );
    final valorFrete = OrcamentoTotaisImpressao.freteInformado(venda);
    final dataEmissao = DateTime.now();
    final validade = dataEmissao.add(Duration(days: validadeDias));
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(dataEmissao);
    final validadeFmt = DateFormat('dd/MM/yyyy').format(validade);
    final numero = venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id;

    var cnpj = (cnpjEmitente ?? '').trim();
    if (cnpj.isEmpty) {
      final fiscal = await ConfiguracoesService.resolverFiscalGlobal();
      cnpj = fiscal.cnpjEmitente.trim().isNotEmpty
          ? fiscal.cnpjEmitente
          : FiscalConfig.cnpjEmitente;
    }
    final cnpjFmt = CupomPdfLayout.formatarCnpjCupom(cnpj);

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

    final linhasEntrega = EntregaVendaHelper.linhasBlocoEntregaImpressao(
      venda: venda,
      cliente: cliente,
      itens: itensOrcamento,
    );
    final pagamento = OrcamentoCondicoesPagamento.linhasColunasDaVenda(
      venda,
      total: totais.total,
      formatarMoeda: formatar,
    );
    final linhasFiado = PlanoFiadoCodec.vendaTemPlanoQuitacao(venda)
        ? PlanoFiadoCodec.linhasTextoPdf(venda)
        : const <String>[];

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 22, 28, 28),
        header: (context) => _cabecalho(
          empresa: empresa,
          logoBytes: logoBytes,
          cnpjFmt: cnpjFmt,
          numero: numero,
          dataHora: dataHora,
          validadeFmt: validadeFmt,
          validadeDias: validadeDias,
        ),
        footer: (context) => _rodape(
          nomeLoja: empresa.nomeLoja,
          pagina: context.pageNumber,
          paginas: context.pagesCount,
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          _blocoCliente(
            cliente: cliente,
            vendedor: vendedor,
            linhasEntrega: linhasEntrega,
          ),
          pw.SizedBox(height: 14),
          _tituloSecao('Itens'),
          pw.SizedBox(height: 6),
          _tabelaItens(
            itens: itensOrcamento,
            produtos: produtos,
            formatar: formatar,
          ),
          pw.SizedBox(height: 12),
          _totais(
            subtotal: totais.subtotalItens,
            frete: valorFrete,
            desconto: totais.desconto,
            total: totais.total,
            formatar: formatar,
          ),
          pw.SizedBox(height: 14),
          _tituloSecao('Condições de pagamento'),
          pw.SizedBox(height: 6),
          _pagamento(pagamento, linhasFiado),
          pw.SizedBox(height: 14),
          _aviso(empresa.rodapeOrcamento),
        ],
      ),
    );

    return CupomPdfGerado(
      bytes: await doc.save(),
      pageFormat: PdfPageFormat.a4,
      layout: const ConfigLayoutImpressao(),
    );
  }
}

const _navy = PdfColor.fromInt(0xFF1B3A4B);
const _amber = PdfColor.fromInt(0xFFC2410C);
const _sand = PdfColor.fromInt(0xFFF6F3EE);
const _ink = PdfColor.fromInt(0xFF1C2430);
const _muted = PdfColor.fromInt(0xFF5E6A75);
const _line = PdfColor.fromInt(0xFFE6E1D8);
const _zebra = PdfColor.fromInt(0xFFFAF8F5);
const _white = PdfColors.white;

final _font = pw.Font.helvetica();
final _fontBold = pw.Font.helveticaBold();

/// Helvetica do PDF usa WinAnsi. Acentos do português ficam; o resto vira hífen.
String _pdf(String valor) {
  final buffer = StringBuffer();
  for (final r in valor.runes) {
    if (r == 0x2013 || r == 0x2014 || r == 0x2212) {
      buffer.write('-');
    } else if (r == 0x2018 || r == 0x2019) {
      buffer.write("'");
    } else if (r == 0x201C || r == 0x201D) {
      buffer.write('"');
    } else if (r == 0x2026) {
      buffer.write('...');
    } else if (r == 0x2022) {
      buffer.write('-');
    } else if (r == 10 || r == 13) {
      buffer.write(' ');
    } else if (r >= 32 && r <= 255) {
      buffer.writeCharCode(r);
    }
  }
  return buffer.toString();
}

pw.TextStyle _estilo({
  double size = 9,
  bool bold = false,
  PdfColor? color,
}) {
  return pw.TextStyle(
    font: bold ? _fontBold : _font,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    fontSize: size,
    color: color ?? _ink,
  );
}

pw.Widget _cabecalho({
  required EmpresaConfig empresa,
  required Uint8List logoBytes,
  required String cnpjFmt,
  required int numero,
  required String dataHora,
  required String validadeFmt,
  required int validadeDias,
}) {
  final nome = empresa.nomeLoja.trim().isEmpty
      ? 'LOJA DE MATERIAIS'
      : empresa.nomeLoja.trim();
  final endereco = empresa.endereco.trim();
  final telefone = empresa.telefone.trim();
  final contatos = <String>[
    if (telefone.isNotEmpty) telefone,
    if (cnpjFmt.isNotEmpty) 'CNPJ $cnpjFmt',
  ];

  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: const pw.BoxDecoration(
      color: _sand,
      border: pw.Border(
        left: pw.BorderSide(color: _amber, width: 4),
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes.isNotEmpty) ...[
          pw.Container(
            width: 58,
            height: 52,
            margin: const pw.EdgeInsets.only(right: 10),
            child: pw.Image(
              pw.MemoryImage(logoBytes),
              fit: pw.BoxFit.contain,
            ),
          ),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _pdf(nome),
                style: _estilo(size: 14, bold: true, color: _navy),
              ),
              if (endereco.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text(_pdf(endereco), style: _estilo(size: 8, color: _muted)),
              ],
              if (contatos.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  _pdf(contatos.join('  ·  ')),
                  style: _estilo(size: 8, color: _muted),
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.SizedBox(
          width: 168,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'ORÇAMENTO',
                style: _estilo(size: 9, bold: true, color: _amber),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Nº $numero',
                textAlign: pw.TextAlign.right,
                style: _estilo(size: 16, bold: true, color: _navy),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Emitido em $dataHora',
                textAlign: pw.TextAlign.right,
                style: _estilo(size: 8, color: _muted),
              ),
              pw.Text(
                'Válido até $validadeFmt ($validadeDias dias)',
                textAlign: pw.TextAlign.right,
                style: _estilo(size: 8, color: _muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _blocoCliente({
  required Cliente? cliente,
  required Vendedor? vendedor,
  required List<String> linhasEntrega,
}) {
  final nome = cliente?.nomeRazao.trim() ?? '';
  final telBruto = cliente?.telefone.trim() ?? '';
  final tel = telBruto.isEmpty
      ? ''
      : EntregaVendaHelper.formatarTelefoneImpressao(telBruto);
  String rotuloVend = '';
  if (vendedor != null) {
    final nomeVend = vendedor.apelido.trim().isNotEmpty
        ? vendedor.apelido.trim()
        : vendedor.nomeCompleto.trim();
    final codigo = vendedor.codigoInterno.trim();
    rotuloVend = codigo.isNotEmpty ? '$codigo · $nomeVend' : nomeVend;
  }

  final esquerda = <pw.Widget>[
    if (nome.isNotEmpty) _par('Cliente', _pdf(nome)),
    if (tel.isNotEmpty) _par('Telefone', _pdf(tel)),
  ];
  final direita = <pw.Widget>[
    if (rotuloVend.isNotEmpty) _par('Vendedor', _pdf(rotuloVend)),
  ];
  final temFicha = esquerda.isNotEmpty || direita.isNotEmpty;
  final temEntrega = linhasEntrega.isNotEmpty;
  if (!temFicha && !temEntrega) return pw.SizedBox();

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 8),
    decoration: pw.BoxDecoration(
      borderRadius: pw.BorderRadius.circular(6),
      border: pw.Border.all(color: _line, width: 0.6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (temFicha)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: esquerda.isEmpty ? [pw.SizedBox()] : esquerda,
                ),
              ),
              if (direita.isNotEmpty) ...[
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: direita,
                  ),
                ),
              ],
            ],
          ),
        if (temEntrega) ...[
          if (temFicha) pw.SizedBox(height: 6),
          pw.Text('Entrega', style: _estilo(size: 8, bold: true, color: _muted)),
          for (final linha in linhasEntrega)
            pw.Text(_pdf(linha), style: _estilo(size: 9)),
        ],
      ],
    ),
  );
}

pw.Widget _par(String rotulo, String valor) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$rotulo   ',
            style: _estilo(size: 8, bold: true, color: _muted),
          ),
          pw.TextSpan(text: valor, style: _estilo(size: 9)),
        ],
      ),
    ),
  );
}

pw.Widget _tituloSecao(String texto) {
  return pw.Text(texto, style: _estilo(size: 11, bold: true, color: _navy));
}

pw.Widget _tabelaItens({
  required List<ItemVenda> itens,
  required Map<int, Produto?> produtos,
  required String Function(double) formatar,
}) {
  pw.Widget celula(
    String texto, {
    bool cabecalho = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        _pdf(texto),
        textAlign: align,
        style: cabecalho
            ? _estilo(size: 8, bold: true, color: _white)
            : _estilo(size: 8.5),
      ),
    );
  }

  final linhas = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: _navy),
      children: [
        celula('CÓD.', cabecalho: true),
        celula('DESCRIÇÃO', cabecalho: true),
        celula('QTD', cabecalho: true, align: pw.TextAlign.right),
        celula('UNITÁRIO', cabecalho: true, align: pw.TextAlign.right),
        celula('TOTAL', cabecalho: true, align: pw.TextAlign.right),
      ],
    ),
  ];

  if (itens.isEmpty) {
    linhas.add(
      pw.TableRow(
        children: [
          celula(''),
          celula('Nenhum item neste orçamento.'),
          celula(''),
          celula(''),
          celula(''),
        ],
      ),
    );
  }

  for (var i = 0; i < itens.length; i++) {
    final item = itens[i];
    final produto = produtos[i];
    final snap = item.nomeProduto.trim();
    final nome = produto != null
        ? ProdutoNomeExibicao.paraImpressao(produto)
        : (snap.isEmpty ? 'Produto' : snap);
    final sku = (produto?.codigoInterno ?? '').trim();
    final qtdEfetiva = ProdutoEmbalagem.quantidadeVendaEfetivaItem(
      produto: produto,
      quantidadeArmazenada: item.quantidade,
      emMilesimos: item.quantidadeEmMilesimosPersistida,
    );
    final qtd = OrcamentoPdfService.quantidadeComUnidade(
      item: item,
      produto: produto,
    );
    linhas.add(
      pw.TableRow(
        decoration: i.isOdd ? const pw.BoxDecoration(color: _zebra) : null,
        children: [
          celula(sku.isEmpty ? '-' : sku),
          celula(nome),
          celula(qtd, align: pw.TextAlign.right),
          celula(formatar(item.precoUnitario), align: pw.TextAlign.right),
          celula(
            formatar(qtdEfetiva * item.precoUnitario),
            align: pw.TextAlign.right,
          ),
        ],
      ),
    );
  }

  return pw.Table(
    border: const pw.TableBorder(
      bottom: pw.BorderSide(color: _line, width: 0.6),
      horizontalInside: pw.BorderSide(color: _line, width: 0.4),
    ),
    columnWidths: const {
      0: pw.FixedColumnWidth(52),
      1: pw.FlexColumnWidth(),
      2: pw.FixedColumnWidth(62),
      3: pw.FixedColumnWidth(74),
      4: pw.FixedColumnWidth(78),
    },
    children: linhas,
  );
}

pw.Widget _totais({
  required double subtotal,
  required double frete,
  required double desconto,
  required double total,
  required String Function(double) formatar,
}) {
  pw.Widget linha(String rotulo, String valor, {bool destaque = false}) {
    final estilo = destaque
        ? _estilo(size: 11, bold: true, color: _white)
        : _estilo(size: 9);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(_pdf(rotulo), style: estilo),
          pw.SizedBox(width: 16),
          pw.Text(_pdf(valor), style: estilo),
        ],
      ),
    );
  }

  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Container(
      width: 250,
      child: pw.Column(
        children: [
          linha('Subtotal', formatar(subtotal)),
          if (frete > 0) linha('Frete / entrega', formatar(frete)),
          if (OrcamentoTotaisImpressao.imprimirLinhaDesconto(desconto))
            linha('Desconto', '- ${formatar(desconto)}'),
          pw.SizedBox(height: 4),
          pw.Container(
            decoration: pw.BoxDecoration(
              color: _navy,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: linha('Valor total', formatar(total), destaque: true),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _pagamento(
  List<({String rotulo, String valor, String descricao})> linhas,
  List<String> linhasFiado,
) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
    decoration: pw.BoxDecoration(
      color: _sand,
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final linha in linhas)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(_pdf(linha.rotulo), style: _estilo(size: 9)),
                ),
                pw.Text(
                  _pdf(linha.valor),
                  style: _estilo(size: 9, bold: true),
                ),
              ],
            ),
          ),
        if (linhasFiado.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Condição de quitação (fiado)',
            style: _estilo(size: 8, bold: true, color: _muted),
          ),
          for (final linha in linhasFiado)
            pw.Text(_pdf(linha), style: _estilo(size: 8.5)),
        ],
      ],
    ),
  );
}

pw.Widget _aviso(String rodapeConfig) {
  final rodape = rodapeConfig.trim();
  final rodapeNorm = rodape.toLowerCase();
  final rodapeProprio = rodape.isNotEmpty &&
      rodapeNorm != 'este orcamento nao possui valor fiscal.' &&
      rodapeNorm != 'este orçamento não possui valor fiscal.';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        OrcamentoPropostaPdf._avisoFiscal,
        style: _estilo(size: 8, color: _muted),
      ),
      if (rodapeProprio) ...[
        pw.SizedBox(height: 3),
        pw.Text(_pdf(rodape), style: _estilo(size: 8, color: _muted)),
      ],
    ],
  );
}

pw.Widget _rodape({
  required String nomeLoja,
  required int pagina,
  required int paginas,
}) {
  final loja = nomeLoja.trim().isEmpty ? 'Orçamento' : nomeLoja.trim();
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 8),
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _line, width: 0.6)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Text(_pdf(loja), style: _estilo(size: 8, color: _muted)),
        ),
        pw.Text(
          'Página $pagina de $paginas',
          style: _estilo(size: 8, color: _muted),
        ),
      ],
    ),
  );
}
