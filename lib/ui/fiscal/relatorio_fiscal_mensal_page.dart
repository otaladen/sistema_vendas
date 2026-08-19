import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/lan_api_client.dart';
import '../../data/api/lan_api_event_hub.dart';
import '../../data/api/venda_api_repository.dart';
import '../../data/fechamento_fiscal_local_source.dart';
import '../../data/sync/sync_refresh_hub.dart';
import '../../data/venda_repository.dart';
import '../../domain/fiscal/fechamento_fiscal_resumo.dart';
import '../../domain/fiscal/fiscal_bloqueios_fechamento.dart';
import '../../services/fechamento_contabil_service.dart';
import '../shell/main_menu_deps.dart';
import '../widgets/lan_api_feedback.dart';
import 'exportar_fechamento_page.dart';
import 'widgets/fiscal_bloqueios_banner.dart';

/// Visao mensal do fiscal (saidas, entradas, totais) sem gerar ZIP.
/// Terminal Leve: KPIs via `GET /api/fiscal/relatorio-mensal` no PC servidor.
class RelatorioFiscalMensalPage extends StatefulWidget {
  const RelatorioFiscalMensalPage({
    super.key,
    required this.vendaRepository,
  });

  final dynamic vendaRepository;

  @override
  State<RelatorioFiscalMensalPage> createState() =>
      _RelatorioFiscalMensalPageState();
}

class _RelatorioFiscalMensalPageState extends State<RelatorioFiscalMensalPage> {
  FechamentoContabilService? _service;
  late int _mes;
  late int _ano;
  FechamentoFiscalResumo? _resumo;
  FiscalBloqueiosFechamento? _bloqueios;
  bool _carregando = false;
  String? _erro;
  bool _avisoApi = false;
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

  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');

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
        if (mounted) unawaited(_atualizar(silencioso: true));
      };
      SyncRefreshHub.instance.addListener(_syncHubListener!);
    } else if (_viaApi) {
      _apiOnlineAnterior = LanApiEventHub.instance.online;
      LanApiEventHub.instance.addListener(_onLanApiEvento);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_atualizar());
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
      if (mounted) unawaited(_atualizar(silencioso: true));
    });
  }

  Future<void> _atualizar({bool silencioso = false}) async {
    if (_viaApi &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      if (mounted && !silencioso) {
        setState(() {
          _carregando = false;
          _erro ??= LanApiEventHub.msgServidorOffline;
        });
      }
      return;
    }
    if (!silencioso && mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }
    try {
      if (_viaApi) {
        final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
        if (client == null) {
          throw LanApiException('API do servidor indisponivel.');
        }
        final m = await client.obterRelatorioFiscalMensal(mes: _mes, ano: _ano);
        final resumoRaw = m['resumo'];
        final bloqueiosRaw = m['bloqueios'];
        if (!mounted) return;
        setState(() {
          _resumo = resumoRaw is Map
              ? FechamentoFiscalResumo.fromJson(
                  Map<String, dynamic>.from(resumoRaw),
                )
              : null;
          _bloqueios = _bloqueiosLevesDeMap(
            bloqueiosRaw is Map
                ? Map<String, dynamic>.from(bloqueiosRaw)
                : null,
            mes: _mes,
            ano: _ano,
          );
          _avisoApi = true;
          _carregando = false;
          _erro = null;
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
        _resumo = FechamentoFiscalResumo.calcular(_mes, _ano, pacote);
        _bloqueios = bloqueios;
        _avisoApi = false;
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silencioso) {
          _erro = LanApiFeedback.mensagem(
            e,
            fallback: 'Falha ao carregar relatorio fiscal.',
          );
        }
        _carregando = false;
      });
      if (!silencioso && _viaApi) {
        LanApiFeedback.snackErro(context, e, prefixo: 'Relatorio fiscal');
      }
    }
  }

  static FiscalBloqueiosFechamento _bloqueiosLevesDeMap(
    Map<String, dynamic>? m, {
    required int mes,
    required int ano,
  }) {
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
      mes: mes,
      ano: ano,
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

  List<int> get _anos {
    final a = DateTime.now().year;
    return List.generate(8, (i) => a - i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _resumo;
    final b = _bloqueios;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatorio fiscal do mes'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _carregando ? null : () => unawaited(_atualizar()),
          ),
          IconButton(
            tooltip: 'Exportar ZIP + Excel',
            icon: const Icon(Icons.folder_zip_outlined),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ExportarFechamentoPage(
                    vendaRepository: widget.vendaRepository,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _atualizar(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_avisoApi)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Dados calculados no PC servidor (terminal leve).',
                    ),
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        // ignore: deprecated_member_use
                        value: _mes,
                        decoration: const InputDecoration(labelText: 'Mes'),
                        items: [
                          for (var i = 1; i <= 12; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(_nomesMes[i - 1]),
                            ),
                        ],
                        onChanged: _carregando
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _mes = v);
                                unawaited(_atualizar());
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        // ignore: deprecated_member_use
                        value: _ano,
                        decoration: const InputDecoration(labelText: 'Ano'),
                        items: [
                          for (final a in _anos)
                            DropdownMenuItem(value: a, child: Text('$a')),
                        ],
                        onChanged: _carregando
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _ano = v);
                                unawaited(_atualizar());
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _erro!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            else if (r != null) ...[
              const SizedBox(height: 12),
              Text(
                'Periodo: ${_nomesMes[r.mes - 1]}/${r.ano}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _kpiGrid(theme, r, b),
              if (r.totalSaidas == 0 &&
                  r.totalEntradas == 0 &&
                  (b == null || !b.temAviso)) ...[
                const SizedBox(height: 12),
                Material(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Nenhuma NF-e/NFC-e autorizada ou entrada importada '
                      'neste mes. Notas ainda processando na SEFAZ nao entram '
                      'nos totais ate autorizar.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
              if (b != null && b.temAviso) ...[
                const SizedBox(height: 12),
                FiscalBloqueiosBanner(bloqueios: b),
              ],
              if (r.alertasVendaCancelada > 0) ...[
                const SizedBox(height: 12),
                Material(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${r.alertasVendaCancelada} nota(s) com venda cancelada no ERP — '
                      'confira com o contador.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpiGrid(
    ThemeData theme,
    FechamentoFiscalResumo r,
    FiscalBloqueiosFechamento? b,
  ) {
    Widget tile(String titulo, String valor, {Color? cor}) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                valor,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 700 ? 3 : 2;
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        final tiles = <Widget>[
          SizedBox(
            width: w,
            child: tile('Saidas (total)', '${r.totalSaidas}'),
          ),
          SizedBox(
            width: w,
            child: tile(
              'Autorizadas',
              'R\$ ${_moeda.format(r.valorSaidasAutorizadas)}',
              cor: Colors.green.shade700,
            ),
          ),
          SizedBox(
            width: w,
            child: tile('Canceladas', '${r.saidasCanceladas}'),
          ),
          SizedBox(
            width: w,
            child: tile('Rejeitadas', '${r.saidasRejeitadas}'),
          ),
          SizedBox(
            width: w,
            child: tile('NF-e 55', '${r.nfe55}'),
          ),
          SizedBox(
            width: w,
            child: tile('NFC-e 65', '${r.nfce65}'),
          ),
          if (b != null && b.qtdNfceProcessando > 0)
            SizedBox(
              width: w,
              child: tile(
                'NFC-e processando',
                '${b.qtdNfceProcessando}',
                cor: Colors.orange.shade800,
              ),
            ),
          if (b != null && b.qtdNfeProcessando > 0)
            SizedBox(
              width: w,
              child: tile(
                'NF-e processando',
                '${b.qtdNfeProcessando}',
                cor: Colors.orange.shade800,
              ),
            ),
          SizedBox(
            width: w,
            child: tile('Entradas (compras)', '${r.totalEntradas}'),
          ),
          SizedBox(
            width: w,
            child: tile(
              'Valor entradas',
              'R\$ ${_moeda.format(r.valorEntradas)}',
            ),
          ),
        ];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tiles,
        );
      },
    );
  }
}
