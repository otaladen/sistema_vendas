import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/venda_api_repository.dart';
import '../../model/historico_entrega.dart';
import '../../model/venda.dart';
import 'relatorio_entregas_helper.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioHistoricoEntregasPage extends StatefulWidget {
  const RelatorioHistoricoEntregasPage({
    super.key,
    required this.vendaRepository,
    this.clienteRepository,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;

  @override
  State<RelatorioHistoricoEntregasPage> createState() =>
      _RelatorioHistoricoEntregasPageState();
}

class _RelatorioHistoricoEntregasPageState
    extends State<RelatorioHistoricoEntregasPage> {
  final DateFormat _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  final _buscaController = TextEditingController();

  LimitesPeriodo? _limites;
  List<HistoricoEntrega> _eventos = [];

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _carregar(LimitesPeriodo limites) {
    unawaited(_carregarAsync(limites));
  }

  Future<void> _carregarAsync(LimitesPeriodo limites) async {
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      try {
        await repo.garantirPeriodoRelatorioCarregado(limites.$1, limites.$2);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Historico de entregas: $e')),
          );
        }
      }
    }
    if (!mounted) return;
    final lista = (widget.vendaRepository.listarHistoricoEntregaGlobal(
      inicio: limites.$1,
      fim: limites.$2,
      termoBusca: _buscaController.text,
    ) as List)
        .cast<HistoricoEntrega>();
    setState(() {
      _limites = limites;
      _eventos = lista;
    });
  }

  Venda? _vendaDoHistorico(HistoricoEntrega h) {
    try {
      final ligado = h.venda.target;
      if (ligado != null) return ligado;
    } catch (_) {}
    final id = h.venda.targetId;
    if (id <= 0) return null;
    try {
      return widget.vendaRepository.obterPorId(id) as Venda?;
    } catch (_) {
      return null;
    }
  }

  String _clienteDoHistorico(HistoricoEntrega h) {
    final v = _vendaDoHistorico(h);
    if (v == null) return '-';
    return relatorioNomeCliente(
      v,
      clienteRepository: widget.clienteRepository,
    );
  }

  List<List<String>> _linhasCsv() => [
        [
          'Data/hora',
          'Nota',
          'Cliente',
          'Evento',
          'Status anterior',
          'Status novo',
          'Usuario',
        ],
        ..._eventos.map((h) {
          final v = _vendaDoHistorico(h);
          return [
            _fmtDataHora.format(h.dataHora.toLocal()),
            '${v?.numeroOrcamento ?? ''}',
            _clienteDoHistorico(h),
            HistoricoEntregaEventos.rotulo(h.statusNovo),
            HistoricoEntregaEventos.rotulo(h.statusAnterior),
            HistoricoEntregaEventos.rotulo(h.statusNovo),
            h.usuario,
          ];
        }),
      ];

  List<String> _paginasPdf() {
    if (_limites == null) return [];
    return relatorioMontarPaginasTabela(
      titulo: 'HISTORICO DE ENTREGAS',
      subtitulo: formatarIntervaloPeriodo(_limites!),
      cabecalho: ['Data', 'Nota', 'Cliente', 'Evento', 'Usuario'],
      linhas: _eventos
          .take(500)
          .map((h) {
            final v = _vendaDoHistorico(h);
            return [
              _fmtDataHora.format(h.dataHora.toLocal()),
              '${v?.numeroOrcamento ?? ''}',
              _clienteDoHistorico(h),
              HistoricoEntregaEventos.rotulo(h.statusNovo),
              h.usuario,
            ];
          })
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lim = _limites;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historico de entregas'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'historico_entregas',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          RelatorioPeriodoPainel(
            vendaRepository: widget.vendaRepository,
            onPeriodoChanged: _carregar,
            onAtualizar: lim != null ? () => _carregar(lim) : null,
            filtrosExtras: [
              TextField(
                controller: _buscaController,
                decoration: const InputDecoration(
                  labelText: 'Buscar (nota, usuario, status)',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  if (lim != null) _carregar(lim);
                },
              ),
            ],
            resumo: lim == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatarIntervaloPeriodo(lim),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text('${_eventos.length} evento(s)'),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _eventos.isEmpty
                ? const Center(
                    child: Text('Nenhum evento de entrega no periodo.'),
                  )
                : ListView.separated(
                    itemCount: _eventos.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final h = _eventos[i];
                      final v = _vendaDoHistorico(h);
                      final cliente = _clienteDoHistorico(h);
                      final evento = HistoricoEntregaEventos.rotulo(h.statusNovo);
                      final anterior = h.statusAnterior.trim().isEmpty
                          ? null
                          : HistoricoEntregaEventos.rotulo(h.statusAnterior);
                      return ListTile(
                        title: Text(
                          'Nota ${v?.numeroOrcamento ?? '?'} · '
                          '${cliente == '-' ? 'Sem cliente' : cliente}',
                        ),
                        subtitle: Text(
                          '${_fmtDataHora.format(h.dataHora.toLocal())} · $evento'
                          '${anterior != null && anterior != evento ? " (de $anterior)" : ""}'
                          '${h.usuario.isNotEmpty ? " · ${h.usuario}" : ""}'
                          '${v != null ? " · ${relatorioRotuloStatusEntrega(v.statusEntrega)}" : ""}',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
