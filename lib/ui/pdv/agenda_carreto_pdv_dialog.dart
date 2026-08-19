import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/lan_api_client.dart';
import '../../data/api/venda_api_repository.dart';
import '../../data/venda_repository.dart';
import '../../domain/entregas/agenda_carreto_ocupacao.dart';
import '../entregas/planejamento_entrega_dia.dart';
import '../shell/main_menu_deps.dart';

/// Modal do PDV: calendario de carretos com ocupacao e detalhe do dia.
Future<DateTime?> mostrarAgendaCarretoPdvDialog({
  required BuildContext context,
  required dynamic vendaRepository,
  DateTime? dataInicial,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _AgendaCarretoPdvDialog(
      vendaRepository: vendaRepository,
      dataInicial: dataInicial,
      firstDate: firstDate,
      lastDate: lastDate,
      clienteRepository: MainMenuDeps.maybeOf(context)?.clienteRepository,
      lanApiClient: MainMenuDeps.maybeOf(context)?.lanApiClient,
    ),
  );
}

class _AgendaCarretoPdvDialog extends StatefulWidget {
  const _AgendaCarretoPdvDialog({
    required this.vendaRepository,
    this.dataInicial,
    this.firstDate,
    this.lastDate,
    this.clienteRepository,
    this.lanApiClient,
  });

  final dynamic vendaRepository;
  final DateTime? dataInicial;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final dynamic clienteRepository;
  final LanApiClient? lanApiClient;

  @override
  State<_AgendaCarretoPdvDialog> createState() => _AgendaCarretoPdvDialogState();
}

class _AgendaCarretoPdvDialogState extends State<_AgendaCarretoPdvDialog> {
  late DateTime _mesExibido;
  DateTime? _diaSelecionado;
  AgendaCarretoOcupacaoMes? _ocupacao;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final base = widget.dataInicial ?? DateTime.now();
    _mesExibido = DateTime(base.year, base.month);
    _diaSelecionado = widget.dataInicial == null
        ? null
        : AgendaCarretoOcupacaoMes.soDia(widget.dataInicial!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_carregarMes(_mesExibido));
    });
  }

  Future<void> _carregarMes(DateTime mes) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      // Calendario: so contagens (leve). Produtos entram ao selecionar o dia.
      final ocupacao = await _resolverOcupacao(mes, incluirProdutos: false);
      if (!mounted) return;
      setState(() {
        _ocupacao = ocupacao;
        _carregando = false;
      });
      final dia = _diaSelecionado;
      if (dia != null &&
          dia.year == mes.year &&
          dia.month == mes.month) {
        unawaited(_enriquecerProdutosDia(dia));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  Future<AgendaCarretoOcupacaoMes> _resolverOcupacao(
    DateTime mes, {
    required bool incluirProdutos,
  }) async {
    final repo = widget.vendaRepository;
    if (repo is VendaRepository) {
      return repo.ocupacaoAgendaCarretoMes(
        mes,
        clienteRepository: widget.clienteRepository,
        incluirProdutos: incluirProdutos,
      );
    }
    final client = widget.lanApiClient;
    if (client != null && client.configurado) {
      return client.obterOcupacaoAgendaCarreto(
        mes,
        incluirProdutos: incluirProdutos,
      );
    }
    if (repo is VendaApiRepository) {
      return repo.obterOcupacaoAgendaCarretoMes(
        mes,
        incluirProdutos: incluirProdutos,
      );
    }
    throw StateError('Nao foi possivel carregar a agenda de carretos.');
  }

  /// Preenche produtos so do dia aberto (ObjectBox local ou 2a chamada API).
  Future<void> _enriquecerProdutosDia(DateTime dia) async {
    final ocupacao = _ocupacao;
    if (ocupacao == null) return;
    final chave = AgendaCarretoOcupacaoMes.chaveDia(dia);
    final precisa = ocupacao.itens.any(
      (e) => e.dataChave == chave && e.produtos.isEmpty && e.vendaId > 0,
    );
    if (!precisa) return;

    final repo = widget.vendaRepository;
    if (repo is VendaRepository) {
      final atualizados = ocupacao.itens.map((item) {
        if (item.dataChave != chave || item.produtos.isNotEmpty) return item;
        final venda = repo.obterPorId(item.vendaId);
        if (venda == null) return item;
        final linhas = repo.listarItensDaVendaGarantidos(item.vendaId);
        return item.copyWith(
          produtos: AgendaCarretoOcupacaoHelper.mapearProdutos(venda, linhas),
        );
      }).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _ocupacao = AgendaCarretoOcupacaoMes(
          ano: ocupacao.ano,
          mes: ocupacao.mes,
          quantidadePorDia: ocupacao.quantidadePorDia,
          itens: atualizados,
        );
      });
      return;
    }

    // Terminal: busca o mes ja com produtos e mescla so o dia.
    try {
      final cheia = await _resolverOcupacao(dia, incluirProdutos: true);
      if (!mounted) return;
      final porId = {
        for (final e in cheia.itensDoDia(dia)) e.vendaId: e.produtos,
      };
      final atualizados = ocupacao.itens.map((item) {
        if (item.dataChave != chave) return item;
        final p = porId[item.vendaId];
        if (p == null || p.isEmpty) return item;
        return item.copyWith(produtos: p);
      }).toList(growable: false);
      setState(() {
        _ocupacao = AgendaCarretoOcupacaoMes(
          ano: ocupacao.ano,
          mes: ocupacao.mes,
          quantidadePorDia: ocupacao.quantidadePorDia,
          itens: atualizados,
        );
      });
    } catch (_) {
      // Detalhe de produtos e opcional; calendário ja funciona.
    }
  }

  bool _diaPermitido(DateTime dia) {
    final d = AgendaCarretoOcupacaoMes.soDia(dia);
    final first = widget.firstDate == null
        ? null
        : AgendaCarretoOcupacaoMes.soDia(widget.firstDate!);
    final last = widget.lastDate == null
        ? null
        : AgendaCarretoOcupacaoMes.soDia(widget.lastDate!);
    if (first != null && d.isBefore(first)) return false;
    if (last != null && d.isAfter(last)) return false;
    return true;
  }

  void _usarDataSelecionada() {
    final d = _diaSelecionado;
    if (d == null) return;
    Navigator.pop(context, d);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final celular = screen.width < 720;
    final ocupacao = _ocupacao;
    final diaSel = _diaSelecionado;
    final itensDia = diaSel == null || ocupacao == null
        ? const <AgendaCarretoOcupacaoItem>[]
        : ocupacao.itensDoDia(diaSel);
    final qtdDia = diaSel == null || ocupacao == null
        ? 0
        : ocupacao.quantidadeDoDia(diaSel);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: celular ? 10 : 28,
        vertical: celular ? 16 : 24,
      ),
      child: SizedBox(
        width: celular ? screen.width : 920,
        height: celular ? screen.height * 0.88 : 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Agenda de carretos',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Verde ≤3 · Amarelo 4–7 · Vermelho 8+. Toque no dia e expanda o card para ver os produtos.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: celular
                  ? _buildMobile(theme, ocupacao, itensDia, qtdDia)
                  : _buildDesktop(theme, ocupacao, itensDia, qtdDia),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: diaSel == null || !_diaPermitido(diaSel)
                        ? null
                        : _usarDataSelecionada,
                    icon: const Icon(Icons.check),
                    label: Text(
                      diaSel == null
                          ? 'Usar esta data'
                          : 'Usar ${DateFormat('dd/MM/yyyy').format(diaSel)}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(
    ThemeData theme,
    AgendaCarretoOcupacaoMes? ocupacao,
    List<AgendaCarretoOcupacaoItem> itensDia,
    int qtdDia,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: _buildCalendarioPainel(theme, ocupacao)),
        const VerticalDivider(width: 1),
        Expanded(flex: 4, child: _buildDetalheDia(theme, itensDia, qtdDia)),
      ],
    );
  }

  Widget _buildMobile(
    ThemeData theme,
    AgendaCarretoOcupacaoMes? ocupacao,
    List<AgendaCarretoOcupacaoItem> itensDia,
    int qtdDia,
  ) {
    return ListView(
      children: [
        SizedBox(height: 280, child: _buildCalendarioPainel(theme, ocupacao)),
        const Divider(height: 1),
        SizedBox(height: 260, child: _buildDetalheDia(theme, itensDia, qtdDia)),
      ],
    );
  }

  Widget _buildCalendarioPainel(
    ThemeData theme,
    AgendaCarretoOcupacaoMes? ocupacao,
  ) {
    final mes = _mesExibido;
    final primeiro = DateTime(mes.year, mes.month, 1);
    final diasNoMes = DateUtils.getDaysInMonth(mes.year, mes.month);
    final offset = primeiro.weekday - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {
                  final novo = DateTime(mes.year, mes.month - 1);
                  setState(() => _mesExibido = novo);
                  unawaited(_carregarMes(novo));
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  PlanejamentoEntregaDia.tituloMesAno(primeiro),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  final novo = DateTime(mes.year, mes.month + 1);
                  setState(() => _mesExibido = novo);
                  unawaited(_carregarMes(novo));
                },
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _carregando
                    ? null
                    : () => unawaited(_carregarMes(_mesExibido)),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          if (_carregando) const LinearProgressIndicator(minHeight: 2),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Falha ao carregar agenda: $_erro',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          Row(
            children: ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: offset + diasNoMes,
              itemBuilder: (context, index) {
                if (index < offset) return const SizedBox.shrink();
                final diaNum = index - offset + 1;
                final data = DateTime(mes.year, mes.month, diaNum);
                final permitido = _diaPermitido(data);
                final qtd = ocupacao?.quantidadeDoDia(data) ?? 0;
                final selecionado = _diaSelecionado != null &&
                    AgendaCarretoOcupacaoMes.soDia(_diaSelecionado!) ==
                        AgendaCarretoOcupacaoMes.soDia(data);
                final hoje = AgendaCarretoOcupacaoMes.soDia(DateTime.now()) ==
                    AgendaCarretoOcupacaoMes.soDia(data);
                final corBadge =
                    AgendaCarretoOcupacaoHelper.corVolume(context, qtd);

                return Material(
                  color: selecionado
                      ? theme.colorScheme.primaryContainer
                      : hoje
                          ? theme.colorScheme.surfaceContainerHighest
                          : null,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: !permitido
                        ? null
                        : () {
                            setState(() => _diaSelecionado = data);
                            unawaited(_enriquecerProdutosDia(data));
                          },
                    child: Opacity(
                      opacity: permitido ? 1 : 0.35,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$diaNum',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: hoje || selecionado
                                  ? FontWeight.bold
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: qtd > 0
                                  ? corBadge
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$qtd',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: qtd > 0
                                    ? Colors.white
                                    : theme.colorScheme.onSurfaceVariant,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalheDia(
    ThemeData theme,
    List<AgendaCarretoOcupacaoItem> itens,
    int qtd,
  ) {
    final dia = _diaSelecionado;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            dia == null
                ? 'Selecione um dia'
                : '${DateFormat("EEEE, dd/MM/yyyy", "pt_BR").format(dia)} · $qtd entrega(s)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (dia == null)
            Expanded(
              child: Center(
                child: Text(
                  'Toque em um dia no calendario para ver as entregas.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else if (itens.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Nenhuma entrega marcada neste dia.\nDia livre para agendar.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: itens.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final item = itens[i];
                  return _CardEntregaAgenda(item: item);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Card expansivel: cliente + materiais do carreto (1 toque).
class _CardEntregaAgenda extends StatelessWidget {
  const _CardEntregaAgenda({required this.item});

  final AgendaCarretoOcupacaoItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final produtos = item.produtos;
    final meta =
        '${item.bairro} · ${item.janelaRotulo} · ${item.statusRotulo}'
        '${item.numero > 0 ? ' · #${item.numero}' : ''}';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: item.ehOrcamento
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.primaryContainer,
            child: Text(
              item.ehOrcamento ? 'O' : 'E',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            item.clienteNome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            produtos.isEmpty
                ? meta
                : '$meta · ${produtos.length} item(ns)',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            if (produtos.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sem itens de produto neste registro.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in produtos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          p.rotulo,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
