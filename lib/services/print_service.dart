import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/app_config_repository.dart';

/// Resultado de [imprimirTeste].
enum PrintTestOutcome {
  /// Enviado direto para a impressora salva (desktop).
  sentToDefaultPrinter,

  /// Aberto fluxo nativo (dialogo de impressao / compartilhar).
  usedSystemDialog,

  /// Nao ha impressora salva ou lista vazia — apenas dialogo.
  noSavedPrinter,
}

/// Servico de impressao com foco em **PDF / fluxo nativo do SO** via pacote `printing`.
///
/// **Por que `printing` + `pdf` (e nao ESC/POS na primeira versao)?**
/// - Funciona em **Windows/macOS/Linux** (lista de impressoras + impressao direta).
/// - Em **Web** e **mobile**, a lista de impressoras costuma ser vazia ou limitada;
///   o mesmo fluxo cai no **dialogo do sistema** (`layoutPdf`), mantendo um codigo unico.
/// - Para **termica pura (USB/BT rede ESC/POS)** no futuro, recomenda-se um pacote
///   dedicado (ex.: ecossistemas `esc_pos_*` / `flutter_pos_printer_platform`), em
///   servico separado (ex.: esc_pos / flutter_pos_printer_platform), sem misturar
///   bytes ESC/POS com este fluxo PDF.
class PrintService {
  PrintService(this._configRepository);

  final AppConfigRepository _configRepository;

  /// Impressoras instaladas no sistema (tipicamente **desktop**).
  /// Em Web/mobile pode retornar lista vazia.
  Future<List<Printer>> listarImpressorasDisponiveis() async {
    try {
      final list = await Printing.listPrinters();
      return List<Printer>.unmodifiable(list);
    } catch (e, st) {
      debugPrint('PrintService.listarImpressorasDisponiveis: $e\n$st');
      return const [];
    }
  }

  /// Nome salvo em [EmpresaConfig.impressoraPadrao] (SharedPreferences).
  Future<String> obterNomeImpressoraSalva() async {
    final c = await _configRepository.carregarEmpresaConfig();
    return c.impressoraPadrao.trim();
  }

  /// Persiste apenas o nome da impressora (merge com demais dados da empresa).
  Future<void> salvarImpressoraSelecionada(String nomeImpressora) async {
    final c = await _configRepository.carregarEmpresaConfig();
    await _configRepository.salvarEmpresaConfig(
      c.copyWith(impressoraPadrao: nomeImpressora.trim()),
    );
  }

  /// Resolve [Printer] pelo nome exatamente como retornado por [listarImpressorasDisponiveis].
  Future<Printer?> resolverImpressoraPorNome(String nome) async {
    final n = nome.trim();
    if (n.isEmpty) return null;
    final list = await listarImpressorasDisponiveis();
    for (final p in list) {
      if (p.name == n) return p;
    }
    return null;
  }

  /// PDF compacto para etiqueta de gondola / teste.
  Future<Uint8List> _montarPdfEtiquetaProduto({
    required String nomeProduto,
    required String codigoBarrasOuSku,
    required String precoAVistaFormatado,
    required double larguraMm,
    required double alturaMm,
  }) async {
    final nome = nomeProduto.trim();
    final codigo = codigoBarrasOuSku.trim();
    final w = larguraMm * PdfPageFormat.mm;
    final h = alturaMm * PdfPageFormat.mm;
    final margemMm = (larguraMm * 0.04).clamp(2.0, 4.0);
    final margem = margemMm * PdfPageFormat.mm;
    final pageFormat = PdfPageFormat(
      w,
      h,
      marginTop: margem,
      marginBottom: margem,
      marginLeft: margem,
      marginRight: margem,
    );
    final larguraUtilMm = (larguraMm - 2 * margemMm).clamp(16.0, larguraMm);
    final alturaBarcodeMm =
        (alturaMm * 0.26).clamp(9.0, 16.0).toDouble();
    final larguraBarcodeMm =
        (larguraUtilMm - 2).clamp(20.0, larguraUtilMm).toDouble();
    final fontNome = (alturaMm * 0.2).clamp(7.0, 10.0);
    final fontRotuloPreco = (alturaMm * 0.14).clamp(6.0, 8.5);
    final fontPreco = (alturaMm * 0.34).clamp(11.0, 17.0);
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) {
          final linhasNome = nome.isEmpty
              ? 'Sem nome'
              : (nome.length > 120 ? '${nome.substring(0, 117)}...' : nome);
          final codigoSeguro = _sanitizarParaCode128(codigo);
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                linhasNome,
                maxLines: 3,
                style: pw.TextStyle(
                  fontSize: fontNome,
                  fontWeight: pw.FontWeight.normal,
                ),
              ),
              pw.SizedBox(height: 2 * PdfPageFormat.mm),
              if (codigo.isNotEmpty) ...[
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: codigoSeguro,
                    width: larguraBarcodeMm * PdfPageFormat.mm,
                    height: alturaBarcodeMm * PdfPageFormat.mm,
                    drawText: true,
                  ),
                ),
              ] else
                pw.Text(
                  'Codigo: (nao informado)',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              pw.Spacer(),
              pw.Center(
                child: pw.Container(
                  padding: pw.EdgeInsets.symmetric(
                    horizontal: 3 * PdfPageFormat.mm,
                    vertical: 2.2 * PdfPageFormat.mm,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.8),
                    borderRadius:
                        pw.BorderRadius.circular(1.2 * PdfPageFormat.mm),
                  ),
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text(
                        'A vista',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: fontRotuloPreco,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      pw.SizedBox(height: 0.6 * PdfPageFormat.mm),
                      pw.Text(
                        precoAVistaFormatado,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: fontPreco,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  /// Mantem apenas caracteres imprimiveis ASCII para [Barcode.code128].
  String _sanitizarParaCode128(String raw) {
    final b = StringBuffer();
    for (final c in raw.runes) {
      if (c >= 32 && c <= 126) {
        b.writeCharCode(c);
      }
      if (b.length >= 80) {
        break;
      }
    }
    final s = b.toString().trim();
    return s.isEmpty ? '-' : s;
  }

  /// Gera etiqueta de teste (nome, codigo de barras ou SKU, preco a vista) e imprime
  /// na impressora padrao salva, ou abre o dialogo do sistema.
  ///
  /// [larguraMm] e [alturaMm] definem o tamanho da folha em milimetros (padrao atual
  /// 80 x 50, comum em impressoras de etiqueta). Para outros formatos de mercado,
  /// altere os **valores padrao** destes parametros aqui (ex.: 40 x 25, 50 x 30)
  /// ou passe medidas explicitas na chamada (ex.: `imprimirEtiquetaProdutoTeste(...,
  /// larguraMm: 50, alturaMm: 30)`).
  Future<void> imprimirEtiquetaProdutoTeste({
    required String nomeProduto,
    required String codigoBarrasOuSku,
    required String precoAVistaFormatado,
    double larguraMm = 80,
    double alturaMm = 50,
  }) async {
    final bytes = await _montarPdfEtiquetaProduto(
      nomeProduto: nomeProduto,
      codigoBarrasOuSku: codigoBarrasOuSku,
      precoAVistaFormatado: precoAVistaFormatado,
      larguraMm: larguraMm,
      alturaMm: alturaMm,
    );
    final nomeSalvo = await obterNomeImpressoraSalva();
    if (nomeSalvo.isNotEmpty) {
      final printer = await resolverImpressoraPorNome(nomeSalvo);
      if (printer != null) {
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => bytes,
          name: 'Etiqueta produto',
          format: PdfPageFormat(
            larguraMm * PdfPageFormat.mm,
            alturaMm * PdfPageFormat.mm,
            marginAll: 0,
          ),
        );
        return;
      }
    }
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<Uint8List> _montarPdfPaginaDeTeste() async {
    final doc = pw.Document();
    final agora = DateTime.now();
    final linhaData =
        '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year} '
        '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Pagina de teste — Sistema de Vendas',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text('Data/hora: $linhaData'),
              pw.SizedBox(height: 12),
              pw.Text(
                'Se esta folha saiu corretamente, a impressao via PDF esta operante.',
                style: const pw.TextStyle(fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  /// Envia uma **pagina PDF de teste** para a impressora configurada, ou abre o fluxo nativo.
  Future<PrintTestOutcome> imprimirTeste() async {
    final bytes = await _montarPdfPaginaDeTeste();
    final nomeSalvo = await obterNomeImpressoraSalva();
    if (nomeSalvo.isNotEmpty) {
      final printer = await resolverImpressoraPorNome(nomeSalvo);
      if (printer != null) {
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => bytes,
        );
        return PrintTestOutcome.sentToDefaultPrinter;
      }
    }
    await Printing.layoutPdf(onLayout: (_) async => bytes);
    return nomeSalvo.isEmpty
        ? PrintTestOutcome.noSavedPrinter
        : PrintTestOutcome.usedSystemDialog;
  }
}
