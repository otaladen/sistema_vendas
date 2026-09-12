import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../data/api/venda_api_repository.dart';
import '../services/configuracoes_service.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../domain/venda_relacao_safe.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/usuario_sistema.dart';
import '../model/venda.dart';
import '../services/esc_pos_orcamento_builder.dart';
import '../services/esc_pos_printer_service.dart';
import '../services/orcamento_pdf_service.dart';
import '../services/print_service.dart';
import 'orcamento_pdv_navigation.dart';
import 'relatorios/relatorio_orcamentos_abertos_page.dart';

/// Orcamentos salvos no PDV que ainda nao foram pagos no caixa.
class OrcamentosPage extends StatelessWidget {
  const OrcamentosPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.produtoRepository,
    required this.vendedorRepository,
    required this.configuracoesService,
    required this.printService,
    required this.usuarioLogado,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final dynamic produtoRepository;
  final dynamic vendedorRepository;
  final ConfiguracoesService configuracoesService;
  final PrintService printService;
  final UsuarioSistema usuarioLogado;

  static const int _validadeOrcamentoDias = 7;

  bool get _podeEditarNoPdv =>
      UsuarioPermissaoHelper.tem(usuarioLogado, PermissaoUsuario.acessarPdv);

  /// Mesma permissao de cancelar venda: apaga orcamento pendente.
  bool get _podeApagar =>
      UsuarioPermissaoHelper.podeCancelarVendas(usuarioLogado);

  Future<void> _editarNoPdv(BuildContext context, Venda venda) {
    return abrirPdvComOrcamento(
      context,
      orcamentoId: venda.id,
      produtoRepository: produtoRepository,
      clienteRepository: clienteRepository,
      vendaRepository: vendaRepository,
      vendedorRepository: vendedorRepository,
      configuracoesService: configuracoesService,
      printService: printService,
      usuarioLogado: usuarioLogado,
    );
  }

  Future<({List<ItemVenda> itens, Map<int, Produto?> produtos})>
      _carregarItensParaImpressao(Venda venda) async {
    var vendaId = venda.id;
    if (vendaId <= 0 && venda.numeroOrcamento > 0) {
      try {
        final porNumero = vendaRepository.buscarOrcamentoPendentePorNumero(
          venda.numeroOrcamento,
        );
        vendaId = porNumero?.id ?? vendaId;
      } catch (_) {}
    }

    var itens = <ItemVenda>[];
    if (vendaId > 0) {
      try {
        final listed = vendaRepository.listarItensPorVenda(vendaId);
        if (listed is List && listed.isNotEmpty) {
          itens = List<ItemVenda>.from(listed);
        }
      } catch (_) {}
      if (itens.isEmpty) {
        final repo = vendaRepository;
        if (repo is VendaApiRepository) {
          try {
            itens = await repo
                .carregarItensRemoto(vendaId)
                .timeout(const Duration(seconds: 12));
          } catch (_) {}
        }
      }
      if (itens.isEmpty) {
        try {
          final recarregada = vendaRepository.obterPorId(vendaId);
          if (recarregada != null) {
            try {
              final toMany = recarregada.itens;
              if (toMany.isNotEmpty) {
                itens = List<ItemVenda>.from(toMany);
              }
            } catch (_) {}
          }
        } catch (_) {}
      }
    }

    final produtosPorItem = <int, Produto?>{};
    for (var i = 0; i < itens.length; i++) {
      final item = itens[i];
      var produto = item.produtoOuNull;
      if (produto == null) {
        final pid = item.produto.targetId;
        if (pid > 0) {
          try {
            produto = produtoRepository.obterPorId(pid);
          } catch (_) {}
        }
        if (produto != null) {
          try {
            item.produto.target = produto;
          } catch (_) {}
        }
      }
      produtosPorItem[i] = produto;
    }
    return (itens: itens, produtos: produtosPorItem);
  }

  Future<void> _imprimirTermica(BuildContext context, Venda venda) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final config = await configuracoesService.carregarEfetiva();
      final carregado = await _carregarItensParaImpressao(venda);
      if (carregado.itens.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Orcamento sem itens para imprimir. Abra no PDV e tente novamente.',
            ),
          ),
        );
        return;
      }

      final cliente = VendaRelacaoSafe.cliente(
        venda,
        clienteRepository: clienteRepository,
      );
      final vendedor = VendaRelacaoSafe.vendedor(
        venda,
        vendedorRepository: vendedorRepository,
      );

      if (config.modoImpressaoBalcao == 'escpos') {
        final r = await EscPosPrinterService.imprimirOrcamentoDireto(
          OrcamentoEscPosDados(
            venda: venda,
            config: config,
            itens: carregado.itens,
            validadeDias: _validadeOrcamentoDias,
            cliente: cliente,
            vendedor: vendedor,
            produtosPorItem: carregado.produtos,
          ),
        );
        messenger.showSnackBar(SnackBar(content: Text(r.mensagem)));
        return;
      }

      final pdf = await OrcamentoPdfService.gerar(
        venda: venda,
        itens: carregado.itens,
        empresa: config,
        validadeDias: _validadeOrcamentoDias,
        cliente: cliente,
        vendedor: vendedor,
        produtosPorItem: carregado.produtos,
      );
      final printer = await printService.resolverImpressoraPorNome(
        config.impressoraPadrao,
      );
      if (printer == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Impressora padrao nao configurada/encontrada. '
              'Configure em Configuracoes > Impressora.',
            ),
          ),
        );
        return;
      }
      final numero = venda.numeroOrcamento > 0
          ? venda.numeroOrcamento
          : venda.id;
      final formatDireto = config.modeloPdf == 'a4'
          ? PdfPageFormat.a4
          : pdf.pageFormat;
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => pdf.bytes,
        name: 'Orcamento $numero',
        format: formatDireto,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Orcamento enviado para a impressora configurada.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Falha ao imprimir orcamento: $e')),
      );
    }
  }

  Future<String?> _salvarPdfBytes({
    required List<int> bytes,
    required String suggestedFileName,
    String? initialDirectory,
  }) async {
    String? dir;
    final rawDir = initialDirectory?.trim() ?? '';
    if (rawDir.isNotEmpty) {
      try {
        if (Directory(rawDir).existsSync()) {
          dir = rawDir;
        }
      } catch (_) {
        dir = null;
      }
    }
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar PDF do orcamento (envie ao cliente depois)',
      fileName: suggestedFileName,
      initialDirectory: dir,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (selectedPath == null) return null;
    final normalizedPath = selectedPath.toLowerCase().endsWith('.pdf')
        ? selectedPath
        : '$selectedPath.pdf';
    final file = File(normalizedPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _gerarPdf(BuildContext context, Venda venda) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final config = await configuracoesService.carregarEfetiva();
      final carregado = await _carregarItensParaImpressao(venda);
      if (carregado.itens.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Orcamento sem itens para gerar PDF. Abra no PDV e tente novamente.',
            ),
          ),
        );
        return;
      }

      final pdf = await OrcamentoPdfService.gerar(
        venda: venda,
        itens: carregado.itens,
        empresa: config,
        validadeDias: _validadeOrcamentoDias,
        cliente: VendaRelacaoSafe.cliente(
          venda,
          clienteRepository: clienteRepository,
        ),
        vendedor: VendaRelacaoSafe.vendedor(
          venda,
          vendedorRepository: vendedorRepository,
        ),
        produtosPorItem: carregado.produtos,
      );

      final numero = venda.numeroOrcamento > 0
          ? venda.numeroOrcamento
          : venda.id;
      final path = await _salvarPdfBytes(
        bytes: pdf.bytes,
        suggestedFileName: 'orcamento_$numero.pdf',
        initialDirectory: config.pastaPadraoPdf.trim().isEmpty
            ? null
            : config.pastaPadraoPdf.trim(),
      );
      if (path == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text('PDF do orcamento salvo em: $path')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Falha ao gerar PDF do orcamento: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RelatorioOrcamentosAbertosPage(
      vendaRepository: vendaRepository,
      clienteRepository: clienteRepository,
      tituloAppBar: 'Orcamentos',
      textoResumo:
          'Salvos no PDV e aguardando pagamento no caixa — ainda nao viraram venda.',
      exibirExportacoesRelatorio: false,
      podeEditarNoPdv: _podeEditarNoPdv,
      onEditarNoPdv: _podeEditarNoPdv ? _editarNoPdv : null,
      onImprimirTermica: _imprimirTermica,
      onGerarPdf: _gerarPdf,
      podeApagarOrcamentos: _podeApagar,
      usuarioExecutor: _podeApagar ? usuarioLogado : null,
    );
  }
}
