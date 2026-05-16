import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../model/venda.dart';

/// Utilitarios compartilhados do planejamento por dia (aba Entregas).
class PlanejamentoEntregaDia {
  PlanejamentoEntregaDia._();

  static const semData = 'Sem data marcada';

  static final DateFormat chaveDia = DateFormat('dd/MM/yyyy');

  static String chaveDeDateTime(DateTime d) {
    final local = d.toLocal();
    return chaveDia.format(
      DateTime(local.year, local.month, local.day),
    );
  }

  static DateTime? parseChave(String chave) {
    if (chave == semData) return null;
    try {
      return chaveDia.parse(chave);
    } catch (_) {
      return null;
    }
  }

  static DateTime soDia(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// Mapa `dd/MM/yyyy` -> quantidade; inclui [semData] quando houver.
  static Map<String, int> resumoDeEntregas(List<Venda> entregas) {
    final map = <String, int>{};
    for (final venda in entregas) {
      final marcada = venda.dataEntregaMarcada;
      final chave =
          marcada == null ? semData : chaveDeDateTime(marcada);
      map.update(chave, (n) => n + 1, ifAbsent: () => 1);
    }
    return map;
  }

  static String tituloMesAno(DateTime mes) {
    const nomes = [
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
    return '${nomes[mes.month - 1]} ${mes.year}';
  }

  static List<String> chavesOrdenadas(Map<String, int> resumo) {
    final keys = resumo.keys.toList()
      ..sort((a, b) {
        if (a == semData) return 1;
        if (b == semData) return -1;
        return chaveDia.parse(a).compareTo(chaveDia.parse(b));
      });
    return keys;
  }

  /// Dias com entrega a partir de [referencia] (inclusive), ate [maxItens].
  static List<String> proximosDiasComEntrega(
    Map<String, int> resumo, {
    DateTime? referencia,
    int maxItens = 7,
  }) {
    final hoje = soDia(referencia ?? DateTime.now());
    final futuros = <String>[];
    for (final chave in chavesOrdenadas(resumo)) {
      if (chave == semData) continue;
      final d = parseChave(chave);
      if (d == null) continue;
      if (!soDia(d).isBefore(hoje)) futuros.add(chave);
    }
    return futuros.take(maxItens).toList();
  }

  static Map<DateTime, int> resumoPorDateTime(Map<String, int> resumo) {
    final out = <DateTime, int>{};
    for (final e in resumo.entries) {
      if (e.key == semData) continue;
      final d = parseChave(e.key);
      if (d != null) out[soDia(d)] = e.value;
    }
    return out;
  }
}

/// Barra fixa: Hoje, Amanha, Sem data, Todas + escolher data.
class BarraPlanejamentoEntregaDia extends StatelessWidget {
  const BarraPlanejamentoEntregaDia({
    super.key,
    required this.resumoPorDia,
    required this.chaveSelecionada,
    required this.onSelecionar,
    required this.onAbrirSeletor,
  });

  final Map<String, int> resumoPorDia;
  final String? chaveSelecionada;
  final ValueChanged<String?> onSelecionar;
  final VoidCallback onAbrirSeletor;

  int _contagem(String chave) => resumoPorDia[chave] ?? 0;

  bool _estaAtivo(String chave) => chaveSelecionada == chave;

  bool get _todasAtivas => chaveSelecionada == null;

  @override
  Widget build(BuildContext context) {
    final hoje = PlanejamentoEntregaDia.chaveDeDateTime(DateTime.now());
    final amanha = PlanejamentoEntregaDia.chaveDeDateTime(
      DateTime.now().add(const Duration(days: 1)),
    );
    final semDataN = _contagem(PlanejamentoEntregaDia.semData);

    final chave = chaveSelecionada;
    final rotuloData = chave == null
        ? 'Escolher data…'
        : chave == PlanejamentoEntregaDia.semData
            ? 'Sem data · $semDataN'
            : '${chave.split('/').take(2).join('/')} · ${_contagem(chave)}';

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _atalho(context, 'Hoje', hoje, _contagem(hoje)),
        _atalho(context, 'Amanha', amanha, _contagem(amanha)),
        FilterChip(
          label: Text('Sem data · $semDataN'),
          selected: _estaAtivo(PlanejamentoEntregaDia.semData),
          onSelected: (ligar) => onSelecionar(
            ligar ? PlanejamentoEntregaDia.semData : null,
          ),
        ),
        FilterChip(
          label: const Text('Todas'),
          selected: _todasAtivas,
          onSelected: (ligar) {
            if (ligar) onSelecionar(null);
          },
        ),
        const SizedBox(width: 4),
        OutlinedButton.icon(
          onPressed: onAbrirSeletor,
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: Text(rotuloData),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _atalho(
    BuildContext context,
    String titulo,
    String chave,
    int qtd,
  ) {
    return FilterChip(
      label: Text(qtd > 0 ? '$titulo · $qtd' : titulo),
      selected: _estaAtivo(chave),
      onSelected: (ligar) => onSelecionar(ligar ? chave : null),
    );
  }
}

/// Chips dos proximos dias com entrega (linha opcional abaixo da barra).
class ProximosDiasPlanejamentoEntrega extends StatelessWidget {
  const ProximosDiasPlanejamentoEntrega({
    super.key,
    required this.resumoPorDia,
    required this.chaveSelecionada,
    required this.onSelecionar,
    this.maxItens = 7,
    this.mostrarTitulo = true,
  });

  final Map<String, int> resumoPorDia;
  final String? chaveSelecionada;
  final ValueChanged<String?> onSelecionar;
  final int maxItens;
  final bool mostrarTitulo;

  @override
  Widget build(BuildContext context) {
    final dias = PlanejamentoEntregaDia.proximosDiasComEntrega(
      resumoPorDia,
      maxItens: maxItens,
    );
    if (dias.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mostrarTitulo) ...[
          Text(
            'Proximos dias com entrega',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < dias.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                FilterChip(
                  label: Text(
                    '${dias[i]} · ${resumoPorDia[dias[i]]}',
                  ),
                  selected: chaveSelecionada == dias[i],
                  onSelected: (ligar) => onSelecionar(ligar ? dias[i] : null),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Painel inferior: calendario + lista com busca.
/// Retorno: `null` = cancelou; `''` = todas as datas; demais = chave do dia.
Future<String?> showSeletorPlanejamentoEntregaDia({
  required BuildContext context,
  required Map<String, int> resumoPorDia,
  String? chaveInicial,
}) {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _SeletorPlanejamentoSheet(
      resumoPorDia: resumoPorDia,
      chaveInicial: chaveInicial,
    ),
  );
}

class _SeletorPlanejamentoSheet extends StatefulWidget {
  const _SeletorPlanejamentoSheet({
    required this.resumoPorDia,
    this.chaveInicial,
  });

  final Map<String, int> resumoPorDia;
  final String? chaveInicial;

  @override
  State<_SeletorPlanejamentoSheet> createState() =>
      _SeletorPlanejamentoSheetState();
}

class _SeletorPlanejamentoSheetState extends State<_SeletorPlanejamentoSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late DateTime _mesExibido;
  final _buscaCtrl = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    final inicial = PlanejamentoEntregaDia.parseChave(
          widget.chaveInicial ?? '',
        ) ??
        DateTime.now();
    _mesExibido = DateTime(inicial.year, inicial.month);
    _buscaCtrl.addListener(() {
      setState(() => _busca = _buscaCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _buscaCtrl.dispose();
    super.dispose();
  }

  /// [chave] null envia `''` = filtro "Todas as datas".
  void _aplicar(String? chave) {
    Navigator.pop(context, chave ?? '');
  }

  void _cancelar() {
    Navigator.pop(context);
  }

  Map<DateTime, int> get _porDia =>
      PlanejamentoEntregaDia.resumoPorDateTime(widget.resumoPorDia);

  List<String> get _chavesFiltradas {
    final todas = PlanejamentoEntregaDia.chavesOrdenadas(widget.resumoPorDia);
    if (_busca.isEmpty) return todas;
    return todas.where((chave) {
      if (chave.toLowerCase().contains(_busca)) return true;
      if (chave == PlanejamentoEntregaDia.semData) {
        return 'sem data'.contains(_busca);
      }
      final d = PlanejamentoEntregaDia.parseChave(chave);
      if (d == null) return false;
      final mes = PlanejamentoEntregaDia.tituloMesAno(d).toLowerCase();
      return mes.contains(_busca);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.82;

    return SizedBox(
      height: maxH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Text(
                  'Escolher dia',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _cancelar,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ActionChip(
                  label: const Text('Todas as datas'),
                  onPressed: () => _aplicar(null),
                ),
                if (widget.resumoPorDia.containsKey(
                  PlanejamentoEntregaDia.semData,
                ))
                  ActionChip(
                    label: Text(
                      'Sem data (${widget.resumoPorDia[PlanejamentoEntregaDia.semData]})',
                    ),
                    onPressed: () =>
                        _aplicar(PlanejamentoEntregaDia.semData),
                  ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Calendario', icon: Icon(Icons.calendar_month, size: 20)),
              Tab(text: 'Lista', icon: Icon(Icons.list, size: 20)),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildCalendario(theme),
                _buildLista(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendario(ThemeData theme) {
    final porDia = _porDia;
    final mes = _mesExibido;
    final primeiro = DateTime(mes.year, mes.month, 1);
    final diasNoMes = DateUtils.getDaysInMonth(mes.year, mes.month);
    final offset = primeiro.weekday - 1;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _mesExibido = DateTime(mes.year, mes.month - 1);
                });
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              PlanejamentoEntregaDia.tituloMesAno(primeiro),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _mesExibido = DateTime(mes.year, mes.month + 1);
                });
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: offset + diasNoMes,
          itemBuilder: (context, index) {
            if (index < offset) return const SizedBox.shrink();
            final dia = index - offset + 1;
            final data = DateTime(mes.year, mes.month, dia);
            final chave = PlanejamentoEntregaDia.chaveDeDateTime(data);
            final qtd = porDia[PlanejamentoEntregaDia.soDia(data)] ?? 0;
            final temEntrega = qtd > 0;
            final selecionado = widget.chaveInicial == chave;
            final hoje = PlanejamentoEntregaDia.soDia(DateTime.now());
            final ehHoje = PlanejamentoEntregaDia.soDia(data) == hoje;

            return Material(
              color: selecionado
                  ? theme.colorScheme.primaryContainer
                  : ehHoje
                      ? theme.colorScheme.surfaceContainerHighest
                      : null,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: temEntrega ? () => _aplicar(chave) : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$dia',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: ehHoje ? FontWeight.bold : null,
                        color: temEntrega
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.38,
                              ),
                      ),
                    ),
                    if (temEntrega)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$qtd',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Toque em um dia com numero para filtrar. Dias sem entrega ficam desabilitados.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildLista(ThemeData theme) {
    final chaves = _chavesFiltradas;
    final agrupado = <String, List<String>>{};
    for (final chave in chaves) {
      if (chave == PlanejamentoEntregaDia.semData) {
        agrupado.putIfAbsent('Sem data', () => []).add(chave);
        continue;
      }
      final d = PlanejamentoEntregaDia.parseChave(chave)!;
      final titulo = PlanejamentoEntregaDia.tituloMesAno(d);
      agrupado.putIfAbsent(titulo, () => []).add(chave);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _buscaCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar data ou mes…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              suffixIcon: _busca.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _buscaCtrl.clear(),
                    ),
            ),
          ),
        ),
        Expanded(
          child: chaves.isEmpty
              ? Center(
                  child: Text(
                    'Nenhuma data encontrada.',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    for (final grupo in agrupado.keys)
                      ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            grupo,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        ...agrupado[grupo]!.map((chave) {
                          final qtd = widget.resumoPorDia[chave] ?? 0;
                          final titulo = chave == PlanejamentoEntregaDia.semData
                              ? 'Sem data marcada'
                              : chave;
                          return ListTile(
                            dense: true,
                            title: Text(titulo),
                            trailing: Chip(
                              label: Text('$qtd'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                            selected: widget.chaveInicial == chave,
                            onTap: () => _aplicar(chave),
                          );
                        }),
                      ],
                  ],
                ),
        ),
      ],
    );
  }
}
