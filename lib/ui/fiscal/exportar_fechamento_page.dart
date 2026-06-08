// Exportacao contabil mensal — leitura fiscal local + download XML Focus (sem estoque/caixa).

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../data/fechamento_fiscal_local_source.dart';
import '../../data/venda_repository.dart';
import '../../domain/fiscal/fiscal_bloqueios_fechamento.dart';
import '../../services/fechamento_contabil_service.dart';
import 'widgets/fiscal_bloqueios_banner.dart';

/// Fechamento do mes: ZIP com XMLs autorizados + planilha Excel para contabilidade.
class ExportarFechamentoPage extends StatefulWidget {
  const ExportarFechamentoPage({
    super.key,
    required this.vendaRepository,
  });

  final VendaRepository vendaRepository;

  @override
  State<ExportarFechamentoPage> createState() => _ExportarFechamentoPageState();
}

class _ExportarFechamentoPageState extends State<ExportarFechamentoPage> {
  late final FechamentoContabilService _service;
  late int _mes;
  late int _ano;

  bool _exportando = false;
  int? _previewQuantidade;

  static const _nomesMes = [
    'Janeiro',
    'Fevereiro',
    'Marco',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    _mes = agora.month;
    _ano = agora.year;
    _service = FechamentoContabilService(
      localSource: FechamentoFiscalLocalSource.fromVendaRepository(
        widget.vendaRepository,
      ),
    );
    _atualizarPreview();
  }

  int? _previewSaidas;
  int? _previewEntradas;
  FiscalBloqueiosFechamento? _bloqueios;

  void _atualizarPreview() {
    final pacote = _service.listarPacoteFiscal(_mes, _ano);
    final bloqueios = FiscalBloqueiosFechamentoService.avaliar(
      vendaRepository: widget.vendaRepository,
      mes: _mes,
      ano: _ano,
    );
    if (mounted) {
      setState(() {
        _previewSaidas = pacote.saidas.length;
        _previewEntradas = pacote.entradas.length;
        _previewQuantidade = pacote.totalDocumentos;
        _bloqueios = bloqueios;
      });
    }
  }

  Future<bool> _confirmarExportacaoComBloqueios(
    FiscalBloqueiosFechamento bloqueios,
  ) async {
    if (bloqueios.bloqueiaExportacao) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            Icons.block_rounded,
            color: Colors.red.shade700,
          ),
          title: const Text('Exportacao bloqueada'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ha NFC-e aguardando autorizacao da SEFAZ neste periodo. '
                  'Essas vendas nao entram no ZIP ate regularizar.',
                ),
                const SizedBox(height: 12),
                FiscalBloqueiosBanner(bloqueios: bloqueios),
                const SizedBox(height: 8),
                const Text(
                  'Abra Notas Fiscais → Pendencias fiscais, reconsulte e '
                  'tente novamente.',
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      return false;
    }
    if (!bloqueios.temAviso) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.info_outline,
          color: Colors.orange.shade800,
        ),
        title: const Text('Avisos no fechamento'),
        content: SingleChildScrollView(
          child: FiscalBloqueiosBanner(bloqueios: bloqueios),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar e resolver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar exportacao'),
          ),
        ],
      ),
    );
    return result == true;
  }

  List<int> get _anosDisponiveis {
    final atual = DateTime.now().year;
    return List.generate(8, (i) => atual - i);
  }

  Future<void> _exportar() async {
    if (_exportando) return;
    final bloqueios = _bloqueios ??
        FiscalBloqueiosFechamentoService.avaliar(
          vendaRepository: widget.vendaRepository,
          mes: _mes,
          ano: _ano,
        );
    if (!await _confirmarExportacaoComBloqueios(bloqueios)) return;

    setState(() => _exportando = true);

    var progressoAtual = 0;
    var progressoTotal = 1;
    var progressoMsg = 'Iniciando...';
    void Function(void Function())? atualizarDialog;

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            atualizarDialog = setDialogState;
            return AlertDialog(
              title: const Text('Exportando fechamento'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: progressoTotal > 0
                          ? progressoAtual / progressoTotal
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      progressoMsg,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    try {
      final resultado = await _service.gerarFechamento(
        mes: _mes,
        ano: _ano,
        onProgresso: (atual, total, msg) {
          progressoAtual = atual;
          progressoTotal = total;
          progressoMsg = msg;
          atualizarDialog?.call(() {});
        },
      );

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;

      await _salvarArquivo(
        bytes: resultado.zipBytes,
        nomeSugerido: '${resultado.nomeBaseArquivo}.zip',
        dialogTitle: 'Salvar ZIP do fechamento contabil',
        extensao: 'zip',
      );

      if (!mounted) return;

      await _salvarArquivo(
        bytes: resultado.excelBytes,
        nomeSugerido: '${resultado.nomeBaseArquivo}.xlsx',
        dialogTitle: 'Salvar planilha Excel do fechamento',
        extensao: 'xlsx',
      );

      if (!mounted) return;

      final t = resultado.totais;
      final avisoFalhas = t.xmlsFalha > 0
          ? ' ${t.xmlsFalha} XML(s) com falha (detalhes na aba Saidas).'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 8),
          content: Text(
            'Fechamento exportado com sucesso! '
            '${t.xmlsBaixados} XML(s) no ZIP; '
            '${t.quantidadeSaidas} saidas, ${t.quantidadeEntradas} entradas.$avisoFalhas',
          ),
        ),
      );
    } on FechamentoContabilException catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao exportar fechamento: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _salvarArquivo({
    required Uint8List bytes,
    required String nomeSugerido,
    required String dialogTitle,
    required String extensao,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: nomeSugerido,
      type: FileType.custom,
      allowedExtensions: [extensao],
    );
    if (path == null || path.trim().isEmpty) return;
    final normalized = path.toLowerCase().endsWith('.$extensao')
        ? path
        : '$path.$extensao';
    await File(normalized).writeAsBytes(bytes, flush: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rotuloPeriodo =
        '${_nomesMes[_mes - 1]} / $_ano';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar Fechamento do Mes'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Gera um ZIP com os XMLs das notas autorizadas (NFC-e e NF-e), '
              'inutilizacoes, CC-e e eventos, mais planilha Excel para a '
              'contabilidade.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _mes,
                    decoration: const InputDecoration(
                      labelText: 'Mes',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(12, (i) {
                      final m = i + 1;
                      return DropdownMenuItem(
                        value: m,
                        child: Text(_nomesMes[i]),
                      );
                    }),
                    onChanged: _exportando
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _mes = v);
                            _atualizarPreview();
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _ano,
                    decoration: const InputDecoration(
                      labelText: 'Ano',
                      border: OutlineInputBorder(),
                    ),
                    items: _anosDisponiveis
                        .map(
                          (a) => DropdownMenuItem(
                            value: a,
                            child: Text(a.toString()),
                          ),
                        )
                        .toList(),
                    onChanged: _exportando
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _ano = v);
                            _atualizarPreview();
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_bloqueios != null && _bloqueios!.temAviso) ...[
              FiscalBloqueiosBanner(bloqueios: _bloqueios!),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Periodo: $rotuloPeriodo',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _previewQuantidade == null
                          ? 'Calculando...'
                          : '${_previewSaidas ?? 0} saida(s) + '
                              '${_previewEntradas ?? 0} entrada(s) no periodo.',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Saidas: autorizadas, canceladas e eventos (NFC-e/NF-e). '
                      'Entradas: NF-e de compra importadas no mes.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (_bloqueios?.bloqueiaExportacao ?? false) ...[
              Text(
                'Exportacao bloqueada: regularize as NFC-e pendentes do '
                'periodo em Pendencias fiscais.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red.shade800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _exportando ||
                      (_previewQuantidade ?? 0) == 0 ||
                      (_bloqueios?.bloqueiaExportacao ?? false)
                  ? null
                  : _exportar,
              icon: _exportando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.archive_outlined),
              label: Text(
                _exportando
                    ? 'Exportando...'
                    : 'Exportar ZIP e Excel',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
