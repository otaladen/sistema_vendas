import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/app_config_repository.dart';
import '../domain/recebimento_fiado_codec.dart';
import '../model/cliente.dart';
import '../model/recebimento_fiado.dart';
import '../model/titulo_receber.dart';

/// Dados para gerar o extrato de fiado do cliente.
class ExtratoFiadoClienteDados {
  const ExtratoFiadoClienteDados({
    required this.cliente,
    required this.titulosAbertos,
    required this.titulosQuitados,
    required this.recebimentos,
    required this.saldoEmAberto,
    this.limiteCredito = 0,
    this.nomeLoja = '',
    this.telefoneLoja = '',
    this.enderecoLoja = '',
  });

  final Cliente cliente;
  final List<TituloReceber> titulosAbertos;
  final List<TituloReceber> titulosQuitados;
  final List<RecebimentoFiado> recebimentos;
  final double saldoEmAberto;
  final double limiteCredito;
  final String nomeLoja;
  final String telefoneLoja;
  final String enderecoLoja;

  double get limiteDisponivel => limiteCredito > 0
      ? (limiteCredito - saldoEmAberto).clamp(0, double.infinity).toDouble()
      : 0;
}

/// Monta [ExtratoFiadoClienteDados] a partir dos repositórios (uso na UI).
Future<ExtratoFiadoClienteDados> montarExtratoFiadoClienteDados({
  required Cliente cliente,
  required List<TituloReceber> titulosAbertos,
  required List<TituloReceber> titulosQuitados,
  required List<RecebimentoFiado> recebimentos,
  required double saldoEmAberto,
  double limiteCredito = 0,
}) async {
  final config = await AppConfigRepository().carregarEmpresaConfig();
  return ExtratoFiadoClienteDados(
    cliente: cliente,
    titulosAbertos: titulosAbertos,
    titulosQuitados: titulosQuitados,
    recebimentos: recebimentos,
    saldoEmAberto: saldoEmAberto,
    limiteCredito: limiteCredito,
    nomeLoja: config.nomeLoja,
    telefoneLoja: config.telefone,
    enderecoLoja: config.endereco,
  );
}

Future<Uint8List> gerarExtratoFiadoClientePdf(ExtratoFiadoClienteDados dados) async {
  final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final dataFmt = DateFormat('dd/MM/yyyy');

  final doc = pw.Document();
  final font = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();

  pw.TextStyle estilo([bool bold = false, double size = 9]) => pw.TextStyle(
        fontSize: size,
        font: bold ? fontBold : font,
      );

  String rotuloForma(String forma) {
    switch (forma) {
      case 'pix':
        return 'PIX';
      case 'cartao_credito':
        return 'Cartao credito';
      case 'cartao_debito':
        return 'Cartao debito';
      case 'transferencia':
        return 'Transferencia';
      case 'dinheiro':
        return 'Dinheiro';
      default:
        return forma;
    }
  }

  pw.Widget cel(String t, pw.TextStyle Function([bool, double]) e, {bool cab = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(t, style: e(cab, cab ? 8 : 8)),
      );

  pw.Widget tabelaTitulos(
    String tituloSecao,
    List<TituloReceber> titulos, {
    required bool emAberto,
  }) {
    if (titulos.isEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(tituloSecao, style: estilo(true, 11)),
          pw.SizedBox(height: 4),
          pw.Text('Nenhum registro.', style: estilo()),
          pw.SizedBox(height: 12),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(tituloSecao, style: estilo(true, 11)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(0.7),
            1: const pw.FlexColumnWidth(0.6),
            2: const pw.FlexColumnWidth(0.9),
            3: const pw.FlexColumnWidth(0.9),
            4: const pw.FlexColumnWidth(0.9),
            5: const pw.FlexColumnWidth(0.7),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                cel('Venda', estilo, cab: true),
                cel('Parc.', estilo, cab: true),
                cel('Vencimento', estilo, cab: true),
                cel('Original', estilo, cab: true),
                cel(emAberto ? 'Saldo' : 'Quitada em', estilo, cab: true),
                cel('Sit.', estilo, cab: true),
              ],
            ),
            ...titulos.map((t) {
              final venda = t.venda.target;
              final venc = dataFmt.format(t.vencimento.toLocal());
              final sit = emAberto
                  ? (t.vencido ? 'Vencido' : 'Aberto')
                  : 'Quitado';
              return pw.TableRow(
                children: [
                  cel('${venda?.numeroOrcamento ?? '-'}', estilo),
                  cel('${t.numeroParcela}/${t.totalParcelas}', estilo),
                  cel(venc, estilo),
                  cel(moeda.format(t.valorOriginal), estilo),
                  cel(
                    emAberto
                        ? moeda.format(t.saldo)
                        : (t.dataQuitacao != null
                            ? dataFmt.format(t.dataQuitacao!.toLocal())
                            : '-'),
                    estilo,
                  ),
                  cel(sit, estilo),
                ],
              );
            }),
          ],
        ),
        pw.SizedBox(height: 14),
      ],
    );
  }

  final loja = dados.nomeLoja.trim().isEmpty ? 'Loja' : dados.nomeLoja.trim();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        pw.Text(loja, style: estilo(true, 14)),
        if (dados.telefoneLoja.trim().isNotEmpty)
          pw.Text('Tel.: ${dados.telefoneLoja}', style: estilo(false, 8)),
        if (dados.enderecoLoja.trim().isNotEmpty)
          pw.Text(dados.enderecoLoja, style: estilo(false, 8)),
        pw.SizedBox(height: 10),
        pw.Text('Extrato de fiado — cliente', style: estilo(true, 13)),
        pw.SizedBox(height: 6),
        pw.Text(dados.cliente.nomeRazao, style: estilo(true, 11)),
        if (dados.cliente.documento.trim().isNotEmpty)
          pw.Text('Documento: ${dados.cliente.documento}', style: estilo()),
        if (dados.cliente.telefone.trim().isNotEmpty)
          pw.Text('Telefone: ${dados.cliente.telefone}', style: estilo()),
        pw.Text(
          'Emitido em ${dataFmt.format(DateTime.now())}',
          style: estilo(false, 8),
        ),
        pw.SizedBox(height: 14),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(1),
          },
          children: [
            _linhaResumo('Saldo em aberto', moeda.format(dados.saldoEmAberto), estilo,
                destaque: true),
            if (dados.limiteCredito > 0) ...[
              _linhaResumo('Limite de credito', moeda.format(dados.limiteCredito), estilo),
              _linhaResumo(
                'Disponivel para novo fiado',
                moeda.format(dados.limiteDisponivel),
                estilo,
              ),
            ],
          ],
        ),
        pw.SizedBox(height: 16),
        tabelaTitulos('Parcelas em aberto', dados.titulosAbertos, emAberto: true),
        pw.Text('Recebimentos', style: estilo(true, 11)),
        pw.SizedBox(height: 6),
        if (dados.recebimentos.isEmpty)
          pw.Text('Nenhum recebimento registrado.', style: estilo())
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cel('Data', estilo, cab: true),
                  cel('Valor', estilo, cab: true),
                  cel('Forma', estilo, cab: true),
                  cel('Observacao', estilo, cab: true),
                ],
              ),
              ...dados.recebimentos.map((r) {
                final aloc = RecebimentoFiadoCodec.decode(r.alocacoesJson);
                final obs = r.observacao.trim().isEmpty
                    ? (aloc.isEmpty
                        ? ''
                        : '${aloc.length} parcela(s) baixada(s)')
                    : r.observacao;
                return pw.TableRow(
                  children: [
                    cel(dataFmt.format(r.data.toLocal()), estilo),
                    cel(moeda.format(r.valorTotal), estilo),
                    cel(rotuloForma(r.formaPagamento), estilo),
                    cel(obs, estilo),
                  ],
                );
              }),
            ],
          ),
        pw.SizedBox(height: 14),
        tabelaTitulos(
          'Parcelas quitadas (historico)',
          dados.titulosQuitados,
          emAberto: false,
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Documento informativo. Valores referentes a vendas fiado finalizadas e '
          'recebimentos registrados no sistema.',
          style: estilo(false, 7),
        ),
      ],
    ),
  );

  return doc.save();
}

pw.TableRow _linhaResumo(
  String rotulo,
  String valor,
  pw.TextStyle Function([bool, double]) estilo, {
  bool destaque = false,
}) {
  return pw.TableRow(
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(rotulo, style: estilo(destaque, destaque ? 10 : 9)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(
          valor,
          style: estilo(destaque, destaque ? 10 : 9),
          textAlign: pw.TextAlign.right,
        ),
      ),
    ],
  );
}
