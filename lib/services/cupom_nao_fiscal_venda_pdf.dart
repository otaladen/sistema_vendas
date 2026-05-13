import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/app_config_repository.dart';
import '../domain/pagamento_orcamento.dart';
import '../model/cliente.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';

/// PDF do cupom nao fiscal (venda finalizada), reutilizado no Caixa e na listagem.
class CupomNaoFiscalVendaPdf {
  CupomNaoFiscalVendaPdf._();

  static final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');

  static String formatarMoeda(double valor) =>
      'R\$ ${_currency.format(valor)}';

  static String rotuloFormaPagamento(String forma) {
    switch (forma) {
      case 'pix':
        return 'PIX';
      case 'cartao_credito':
        return 'Cartao de credito';
      case 'cartao_debito':
        return 'Cartao de debito';
      case 'fiado':
        return 'Fiado';
      case 'transferencia':
        return 'Transferencia';
      case 'misto':
        return 'Misto';
      case 'dinheiro':
      default:
        if (forma.startsWith('cartao')) return forma;
        return 'Dinheiro';
    }
  }

  static String _textoDetalheLinhasPagamento(List<PagamentoOrcamentoLinha> linhas) {
    if (linhas.isEmpty) return '';
    return linhas
        .map(
          (l) =>
              '${rotuloFormaPagamento(l.meio)} ${formatarMoeda(l.valor)}'
              '${l.meio == 'cartao_credito' ? ' ${l.parcelas}x' : ''}',
        )
        .join(' + ');
  }

  static String rotuloPagamentoCabecalho(Venda v) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return '${rotuloFormaPagamento(v.formaPagamento)}'
          '${v.formaPagamento == 'cartao_credito' ? ' | ${v.quantidadeParcelas}x' : ''}';
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    if (linhas.isEmpty) return 'Misto';
    return _textoDetalheLinhasPagamento(linhas);
  }

  static String rotuloTipoEntrega(String tipoEntrega) {
    switch (tipoEntrega) {
      case 'entrega_loja':
        return 'Carreto';
      case 'retirada_futura':
        return 'Retirada Futura';
      case 'retirada':
      default:
        return 'Leva Agora';
    }
  }

  static String rotuloVendedorUmLinha(Vendedor? v) {
    if (v == null) return 'Sem vendedor';
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  /// Estimativa para segunda via (valores exatos de dinheiro nao ficam gravados).
  static ({double recebido, double troco}) inferirRecebidoTrocoSegundaVia(
    Venda v,
  ) {
    final t = v.total;
    if (v.formaPagamento == 'misto' && v.pagamentosJson.trim().isNotEmpty) {
      final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
      if (linhas.isEmpty) return (recebido: t, troco: 0.0);
      final soma = PagamentoOrcamentoCodec.soma(linhas);
      final troco = (soma - t).clamp(0.0, double.infinity).toDouble();
      return (recebido: soma, troco: troco);
    }
    return (recebido: t, troco: 0.0);
  }

  static Future<Uint8List> gerarBytes({
    required Venda venda,
    required EmpresaConfig config,
    Cliente? cliente,
    Vendedor? vendedor,
    required double totalRecebido,
    required double troco,
    bool segundaVia = false,
    DateTime? dataCabecalhoVenda,
  }) async {
    final logoBytes = config.logoPath.trim().isNotEmpty
        ? await File(
            config.logoPath,
          ).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    final doc = pw.Document();
    final agora = DateTime.now();
    final dataLinhaPrincipal = DateFormat('dd/MM/yyyy HH:mm').format(
      (dataCabecalhoVenda ?? agora).toLocal(),
    );
    final dataReimpressao = segundaVia
        ? DateFormat('dd/MM/yyyy HH:mm').format(agora.toLocal())
        : null;

    doc.addPage(
      pw.Page(
        pageFormat: config.modeloPdf == 'a4'
            ? PdfPageFormat.a4
            : PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          final descontoNota = venda.descontoImplicitoTotal;
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  config.nomeLoja,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (logoBytes.isNotEmpty)
                pw.Center(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
                    child: pw.Image(pw.MemoryImage(logoBytes), height: 45),
                  ),
                ),
              if (config.telefone.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Tel: ${config.telefone}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              if (config.endereco.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    config.endereco,
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.Center(
                child: pw.Text(
                  'CUPOM NAO FISCAL',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              if (segundaVia) ...[
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'SEGUNDA VIA',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
              pw.SizedBox(height: 6),
              pw.Divider(),
              pw.Text(
                'VENDA ${venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id}',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                segundaVia
                    ? 'Data da venda: $dataLinhaPrincipal'
                    : 'Data: $dataLinhaPrincipal',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if (dataReimpressao != null)
                pw.Text(
                  'Reimpressao: $dataReimpressao',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              pw.Text(
                'Cliente: ${cliente?.nomeRazao ?? 'Sem cliente'}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Vendedor: ${rotuloVendedorUmLinha(vendedor)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if ((cliente?.documento.trim().isNotEmpty ?? false))
                pw.Text(
                  'Documento: ${cliente!.documento}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              if ((cliente?.telefone.trim().isNotEmpty ?? false))
                pw.Text(
                  'Telefone: ${cliente!.telefone}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.RichText(
                text: pw.TextSpan(
                  style: const pw.TextStyle(fontSize: 9),
                  children: [
                    const pw.TextSpan(text: 'Entrega: '),
                    pw.TextSpan(
                      text: rotuloTipoEntrega(venda.tipoEntrega),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (venda.tipoEntrega == 'entrega_loja')
                      pw.TextSpan(
                        text:
                            ' | Frete: ${formatarMoeda(venda.valorFrete)}',
                      ),
                  ],
                ),
              ),
              if (venda.enderecoEntrega.trim().isNotEmpty)
                pw.Text(
                  'Endereco: ${venda.enderecoEntrega}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.SizedBox(height: 10),
              pw.Text(
                'ITENS',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              ...venda.itens.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        item.nomeProduto,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        '${item.quantidade} x ${formatarMoeda(item.precoUnitario)} = ${formatarMoeda(item.subtotal)}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Divider(),
              pw.Text(
                'Subtotal produtos: ${formatarMoeda(venda.somaSubtotalItens)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Frete: ${formatarMoeda(venda.valorFrete)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if (descontoNota > 0)
                pw.Text(
                  'Desconto: - ${formatarMoeda(descontoNota)}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.Text(
                'TOTAL: ${formatarMoeda(venda.total)}',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Pagamento: ${rotuloPagamentoCabecalho(venda)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Recebido: ${formatarMoeda(totalRecebido)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Troco: ${formatarMoeda(troco)}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (segundaVia)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text(
                    'Valores recebido/troco podem ser aproximados na segunda via.',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  config.rodapeNota,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }
}
