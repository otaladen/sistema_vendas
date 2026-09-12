// Exportacao contabil mensal — local no servidor; no terminal baixa ZIP/Excel da API.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/api/lan_api_client.dart';
import '../../data/api/lan_api_event_hub.dart';
import '../../data/api/venda_api_repository.dart';
import '../../data/fechamento_fiscal_local_source.dart';
import '../../data/sync/sync_refresh_hub.dart';
import '../../data/venda_repository.dart';
import '../../domain/fiscal/fechamento_fiscal_resumo.dart';
import '../../domain/fiscal/fiscal_bloqueios_fechamento.dart';
import '../../services/fechamento_contabil_service.dart';
import '../../services/fechamento_email_service.dart';
import '../../services/configuracoes_service.dart';
import '../shell/main_menu_deps.dart';
import '../widgets/lan_api_feedback.dart';
import 'widgets/fiscal_bloqueios_banner.dart';

/// Fechamento do mes: ZIP com XMLs autorizados + planilha Excel para contabilidade.
/// Terminal Leve: preview via relatorio-mensal; ZIP/Excel gerados no PC1 (:8788).
class ExportarFechamentoPage extends StatefulWidget {
  const ExportarFechamentoPage({
    super.key,
    required this.vendaRepository,
  });

  final dynamic vendaRepository;

  @override
  State<ExportarFechamentoPage> createState() => _ExportarFechamentoPageState();
}

class _ExportarFechamentoPageState extends State<ExportarFechamentoPage> {
  FechamentoContabilService? _service;
  late int _mes;
  late int _ano;

  bool _exportando = false;
  bool _enviandoEmail = false;
  bool _carregandoPreview = false;
  int? _previewQuantidade;
  int? _previewSaidas;
  int? _previewEntradas;
  FiscalBloqueiosFechamento? _bloqueios;
  String? _erroPreview;
  Timer? _wsDebounce;
  VoidCallback? _syncHubListener;
  bool? _apiOnlineAnterior;

  bool get _viaApi => widget.vendaRepository is VendaApiRepository;

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
    if (!_viaApi && widget.vendaRepository is VendaRepository) {
      _service = FechamentoContabilService(
        localSource: FechamentoFiscalLocalSource.fromVendaRepository(
          widget.vendaRepository as VendaRepository,
        ),
      );
      _syncHubListener = () {
        if (mounted) unawaited(_atualizarPreview(silencioso: true));
      };
      SyncRefreshHub.instance.addListener(_syncHubListener!);
    } else if (_viaApi) {
      _apiOnlineAnterior = LanApiEventHub.instance.online;
      LanApiEventHub.instance.addListener(_onLanApiEvento);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_atualizarPreview());
    });
  }

  @override
  void dispose() {
    _wsDebounce?.cancel();
    LanApiEventHub.instance.removeListener(_onLanApiEvento);
    if (_syncHubListener != null) {
      SyncRefreshHub.instance.removeListener(_syncHubListener!);
      _syncHubListener = null;
    }
    super.dispose();
  }

  void _onLanApiEvento() {
    if (!_viaApi) return;
    final hub = LanApiEventHub.instance;
    final online = hub.online;
    final ficouOnline = online && _apiOnlineAnterior == false;
    _apiOnlineAnterior = online;
    if (hub.deveBloquearOperacoes) return;
    final ent = hub.ultimaEntidade;
    if (!ficouOnline &&
        ent != 'venda' &&
        ent != 'nfe_saida' &&
        ent != 'nfe_importada' &&
        ent != 'fiscal' &&
        ent != 'produto') {
      return;
    }
    _wsDebounce?.cancel();
    _wsDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) unawaited(_atualizarPreview(silencioso: true));
    });
  }

  Future<void> _atualizarPreview({bool silencioso = false}) async {
    if (_viaApi &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      if (mounted && !silencioso) {
        setState(() {
          _carregandoPreview = false;
          _erroPreview ??= LanApiEventHub.msgServidorOffline;
        });
      }
      return;
    }
    if (!silencioso && mounted) {
      setState(() {
        _carregandoPreview = true;
        _erroPreview = null;
      });
    }
    try {
      if (_viaApi) {
        final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
        if (client == null) {
          throw LanApiException('API do servidor indisponivel.');
        }
        // Endpoint leve (sem pacote completo de XMLs).
        final m = await client.obterRelatorioFiscalMensal(mes: _mes, ano: _ano);
        final resumoRaw = m['resumo'];
        final bloqueiosRaw = m['bloqueios'];
        final resumo = resumoRaw is Map
            ? FechamentoFiscalResumo.fromJson(
                Map<String, dynamic>.from(resumoRaw),
              )
            : null;
        if (!mounted) return;
        setState(() {
          _previewSaidas = resumo?.totalSaidas ?? 0;
          _previewEntradas = resumo?.totalEntradas ?? 0;
          _previewQuantidade =
              (resumo?.totalSaidas ?? 0) + (resumo?.totalEntradas ?? 0);
          _bloqueios = _bloqueiosDeMapApi(
            bloqueiosRaw is Map
                ? Map<String, dynamic>.from(bloqueiosRaw)
                : null,
          );
          _carregandoPreview = false;
          _erroPreview = null;
        });
        return;
      }

      final service = _service;
      final repo = widget.vendaRepository;
      if (service == null || repo is! VendaRepository) {
        throw StateError('Repositorio local indisponivel.');
      }
      final pacote = service.listarPacoteFiscal(_mes, _ano);
      final bloqueios = FiscalBloqueiosFechamentoService.avaliar(
        vendaRepository: repo,
        mes: _mes,
        ano: _ano,
      );
      if (!mounted) return;
      setState(() {
        _previewSaidas = pacote.saidas.length;
        _previewEntradas = pacote.entradas.length;
        _previewQuantidade = pacote.totalDocumentos;
        _bloqueios = bloqueios;
        _carregandoPreview = false;
        _erroPreview = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silencioso) {
          _erroPreview = LanApiFeedback.mensagem(
            e,
            fallback: 'Falha ao calcular preview do fechamento.',
          );
        }
        if (!silencioso) {
          _previewQuantidade = 0;
          _previewSaidas = 0;
          _previewEntradas = 0;
        }
        _carregandoPreview = false;
      });
    }
  }

  FiscalBloqueiosFechamento _bloqueiosDeMapApi(Map<String, dynamic>? m) {
    final previewRaw = m?['nfceProcessandoPreview'];
    final preview = <FiscalBloqueioNfcePreview>[];
    if (previewRaw is List) {
      for (final e in previewRaw) {
        if (e is Map) {
          preview.add(
            FiscalBloqueioNfcePreview.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return FiscalBloqueiosFechamento(
      mes: _mes,
      ano: _ano,
      vendasNfceProcessando: const [],
      nfeProcessando: const [],
      nfeRejeitadas: const [],
      qtdNfceProcessandoOverride: (m?['qtdNfceProcessando'] as num?)?.toInt(),
      qtdNfeProcessandoOverride: (m?['qtdNfeProcessando'] as num?)?.toInt(),
      qtdNfeRejeitadasOverride: (m?['qtdNfeRejeitadas'] as num?)?.toInt(),
      bloqueiaExportacaoOverride: m?['bloqueiaExportacao'] == true,
      nfceProcessandoPreview: preview,
    );
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

  Future<void> _exportarViaApi(LanApiClient client) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        title: Text('Exportando fechamento'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Gerando ZIP e Excel no PC servidor...',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // ZIP gera e popula cache; Excel reaproveita (forcar so no ZIP).
      final zip = await client.baixarFechamentoZip(
        mes: _mes,
        ano: _ano,
        forcar: true,
      );
      final excel = await client.baixarFechamentoExcel(
        mes: _mes,
        ano: _ano,
      );

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;

      await _salvarArquivo(
        bytes: Uint8List.fromList(zip.bytes),
        nomeSugerido: zip.filename,
        dialogTitle: 'Salvar ZIP do fechamento contabil',
        extensao: 'zip',
      );
      if (!mounted) return;
      await _salvarArquivo(
        bytes: Uint8List.fromList(excel.bytes),
        nomeSugerido: excel.filename,
        dialogTitle: 'Salvar planilha Excel do fechamento',
        extensao: 'xlsx',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(
            'Fechamento baixado do servidor '
            '(${_previewSaidas ?? 0} saidas, ${_previewEntradas ?? 0} entradas).',
          ),
        ),
      );
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao baixar fechamento');
    }
  }

  Future<void> _exportar() async {
    if (_exportando) return;
    if (_viaApi &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }
    final bloqueios = _bloqueios;
    if (bloqueios != null &&
        !await _confirmarExportacaoComBloqueios(bloqueios)) {
      return;
    }

    setState(() => _exportando = true);

    if (_viaApi) {
      final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
      if (client == null) {
        if (mounted) {
          setState(() => _exportando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('API do servidor indisponivel.')),
          );
        }
        return;
      }
      await _exportarViaApi(client);
      if (mounted) {
        setState(() => _exportando = false);
        unawaited(_atualizarPreview(silencioso: true));
      }
      return;
    }

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
      final service = _service;
      if (service == null) {
        throw StateError('Servico de fechamento indisponivel.');
      }
      final resultado = await service.gerarFechamento(
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

  Future<void> _enviarParaContador() async {
    if (_enviandoEmail || _exportando) return;
    final bloqueios = _bloqueios;
    if (bloqueios != null &&
        !await _confirmarExportacaoComBloqueios(bloqueios)) {
      return;
    }

    setState(() => _enviandoEmail = true);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        title: Text('Enviando ao contador'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Gerando pacote e enviando por e-mail...',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    try {
      if (_viaApi) {
        final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
        if (client == null) {
          throw StateError('API do servidor indisponivel.');
        }
        final r = await client.enviarFechamentoContador(
          mes: _mes,
          ano: _ano,
          forcar: true,
        );
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        if (!mounted) return;
        final para = (r['destinatario'] ?? '').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              para.isNotEmpty
                  ? 'Fechamento enviado para $para.'
                  : 'Fechamento enviado ao contador.',
            ),
          ),
        );
      } else {
        final service = _service;
        if (service == null) {
          throw StateError('Servico de fechamento indisponivel.');
        }
        final fiscal = await ConfiguracoesService.resolverFiscalGlobal();
        final resultado = await service.gerarFechamento(mes: _mes, ano: _ano);
        await FechamentoEmailService.enviarParaContador(
          mes: resultado.mes,
          ano: resultado.ano,
          zipBytes: resultado.zipBytes,
          excelBytes: resultado.excelBytes,
          nomeBaseArquivo: resultado.nomeBaseArquivo,
        );
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              'Fechamento enviado para '
              '${fiscal.emailContador}.',
            ),
          ),
        );
      }
    } on FechamentoEmailException catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
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
        SnackBar(
          content: Text(LanApiFeedback.mensagem(e, fallback: 'Falha no envio: $e')),
        ),
      );
    } finally {
      if (mounted) setState(() => _enviandoEmail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rotuloPeriodo = '${_nomesMes[_mes - 1]} / $_ano';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar Fechamento do Mes'),
        actions: [
          IconButton(
            tooltip: 'Atualizar preview',
            onPressed: _exportando || _carregandoPreview
                ? null
                : () => unawaited(_atualizarPreview()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_viaApi)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'O PC servidor monta o ZIP/Excel; este terminal apenas '
                      'baixa e salva os arquivos.',
                    ),
                  ),
                ),
              ),
            Text(
              _viaApi
                  ? 'Baixe o pacote contabil gerado no servidor (XMLs NFC-e/NF-e, '
                      'inutilizacoes, CC-e, eventos e planilha Excel).'
                  : 'Gera um ZIP com os XMLs das notas autorizadas (NFC-e e NF-e), '
                      'inutilizacoes, CC-e e eventos, mais planilha Excel para a '
                      'contabilidade.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    // ignore: deprecated_member_use
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
                    onChanged: _exportando || _carregandoPreview
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _mes = v);
                            unawaited(_atualizarPreview());
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    // ignore: deprecated_member_use
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
                    onChanged: _exportando || _carregandoPreview
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _ano = v);
                            unawaited(_atualizarPreview());
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_erroPreview != null) ...[
              Text(
                _erroPreview!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
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
                    if (_carregandoPreview)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      )
                    else ...[
                      Text(
                        _previewQuantidade == null
                            ? 'Calculando...'
                            : '${_previewSaidas ?? 0} saida(s) + '
                                '${_previewEntradas ?? 0} entrada(s) no periodo.',
                      ),
                      if ((_previewQuantidade ?? 0) == 0 &&
                          (_bloqueios?.qtdNfceProcessando ?? 0) > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'As NFC-e ainda processando na SEFAZ nao entram no '
                          'ZIP ate autorizar — por isso o total de saidas '
                          'pode ficar zerado.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'ZIP no padrao contabilidade: Autorizadas/NFCe, '
                      'Autorizadas/NFe, Canceladas, Inutilizadas, Entradas, '
                      'Cartas_Correcao + planilha na raiz.',
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
                      _carregandoPreview ||
                      (_previewQuantidade ?? 0) == 0 ||
                      (_bloqueios?.bloqueiaExportacao ?? false)
                  ? null
                  : () => unawaited(_exportar()),
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
                    : (_viaApi
                        ? 'Baixar ZIP e Excel do servidor'
                        : 'Exportar ZIP e Excel'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _exportando ||
                      _enviandoEmail ||
                      _carregandoPreview ||
                      (_previewQuantidade ?? 0) == 0 ||
                      (_bloqueios?.bloqueiaExportacao ?? false)
                  ? null
                  : () => unawaited(_enviarParaContador()),
              icon: _enviandoEmail
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mark_email_read_outlined),
              label: Text(
                _enviandoEmail
                    ? 'Enviando...'
                    : 'Enviar para o Contador',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
