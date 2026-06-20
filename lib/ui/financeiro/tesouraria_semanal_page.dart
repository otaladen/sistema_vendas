import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/objectbox.dart';
import '../../data/venda_repository.dart';
import '../../domain/financeiro_resumo.dart';
import '../../domain/tesouraria_semanal.dart';
import '../theme/app_modulo_cores.dart';
import '../theme/app_semantic_helper.dart';
import '../../model/caixa_sessao.dart';
import '../../data/caixa_sessao_repository.dart';

final NumberFormat _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final DateFormat _diaFmt = DateFormat('EEE, dd/MM', 'pt_BR');
final DateFormat _diaCurto = DateFormat('dd/MM');

/// Visao semanal: vencimentos previstos e movimentos realizados.
class TesourariaSemanalPage extends StatefulWidget {
  const TesourariaSemanalPage({
    super.key,
    required this.objectBox,
    required this.vendaRepository,
  });

  final ObjectBox objectBox;
  final VendaRepository vendaRepository;

  @override
  State<TesourariaSemanalPage> createState() => _TesourariaSemanalPageState();
}

class _TesourariaSemanalPageState extends State<TesourariaSemanalPage> {
  TesourariaSemanalSnapshot? _snapshot;
  FinanceiroResumoSnapshot? _resumo;
  bool _carregando = true;
  DateTime? _diaExpandido;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final repo = CaixaSessaoRepository();
    final terminalId = await repo.obterTerminalId();
    final sessoes = await repo.listarTodasSessoes();
    final CaixaSessao? sessao = sessoes[terminalId];

    final snap = TesourariaSemanalService.montar(
      vendaRepository: widget.vendaRepository,
      objectBox: widget.objectBox,
    );
    final resumo = FinanceiroResumoService.montar(
      vendaRepository: widget.vendaRepository,
      objectBox: widget.objectBox,
      sessaoCaixaLocal: sessao,
    );
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _resumo = resumo;
      _carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final scheme = theme.colorScheme;
    final snap = _snapshot;
    final resumo = _resumo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tesouraria semanal'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : snap == null
              ? const Center(child: Text('Sem dados.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (resumo != null) _buildResumoTopo(context, resumo),
                    const SizedBox(height: 16),
                    _buildBlocoResumo(
                      context,
                      titulo: 'Realizado (ultimos 7 dias)',
                      entradas: snap.totalEntradasRealizadas,
                      saidas: snap.totalSaidasRealizadas,
                      corEntrada: semantic.successFg,
                      corSaida: semantic.errorFg,
                    ),
                    const SizedBox(height: 12),
                    _buildBlocoResumo(
                      context,
                      titulo: 'Previsto (proximos 7 dias)',
                      entradas: snap.totalEntradasPrevistas,
                      saidas: snap.totalSaidasPrevistas,
                      corEntrada: scheme.primary,
                      corSaida: AppModuloCores.harmonizar(scheme, 320),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Linha do tempo',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...snap.dias.map((d) => _buildDiaCard(context, d, snap)),
                  ],
                ),
    );
  }

  Widget _buildResumoTopo(BuildContext context, FinanceiroResumoSnapshot r) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Posicao atual',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _chipValor('A receber', r.totalAReceber, Colors.blue.shade800),
                _chipValor('A pagar', r.totalAPagarPendente, Colors.blueGrey),
                if (r.saldoCaixaEstimado != null)
                  _chipValor(
                    'Caixa (ref.)',
                    r.saldoCaixaEstimado!,
                    Colors.teal.shade800,
                  ),
                _chipValor(
                  'Liquido proj.',
                  r.saldoLiquidoProjetado,
                  r.saldoLiquidoProjetado >= 0
                      ? Colors.green.shade800
                      : Colors.red.shade800,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipValor(String rotulo, double valor, Color cor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rotulo,
          style: TextStyle(fontSize: 11, color: cor.withValues(alpha: 0.85)),
        ),
        Text(
          _moeda.format(valor),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: cor,
          ),
        ),
      ],
    );
  }

  Widget _buildBlocoResumo(
    BuildContext context, {
    required String titulo,
    required double entradas,
    required double saidas,
    required Color corEntrada,
    required Color corSaida,
  }) {
    final saldo = entradas - saidas;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _miniKpi('Entradas', entradas, corEntrada),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _miniKpi('Saidas', saidas, corSaida),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _miniKpi(
                    'Saldo',
                    saldo,
                    saldo >= 0 ? corEntrada : corSaida,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniKpi(String rotulo, double valor, Color cor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: TextStyle(fontSize: 11, color: cor)),
          Text(
            _moeda.format(valor),
            style: TextStyle(fontWeight: FontWeight.w700, color: cor),
          ),
        ],
      ),
    );
  }

  Widget _buildDiaCard(
    BuildContext context,
    TesourariaLinhaDia d,
    TesourariaSemanalSnapshot snap,
  ) {
    final theme = Theme.of(context);
    final itens = snap.itensPorDia[d.dia] ?? const [];
    final expandido = _diaExpandido != null &&
        _diaExpandido!.year == d.dia.year &&
        _diaExpandido!.month == d.dia.month &&
        _diaExpandido!.day == d.dia.day;
    final temMovimento = d.entradasPrevistas > 0 ||
        d.saidasPrevistas > 0 ||
        d.entradasRealizadas > 0 ||
        d.saidasRealizadas > 0;

    if (!temMovimento) return const SizedBox.shrink();

    Color? borda;
    if (d.ehHoje) {
      borda = theme.colorScheme.primary;
    } else if (d.ehPassado) {
      borda = theme.colorScheme.outlineVariant;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: borda != null
            ? BorderSide(color: borda, width: d.ehHoje ? 2 : 1)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: itens.isEmpty
            ? null
            : () => setState(() {
                  _diaExpandido = expandido ? null : d.dia;
                }),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      d.ehHoje
                          ? 'Hoje · ${_diaCurto.format(d.dia)}'
                          : _diaFmt.format(d.dia),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (d.entradasRealizadas > 0 || d.saidasRealizadas > 0)
                    Text(
                      'Real: ${_moeda.format(d.saldoRealizado)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: d.saldoRealizado >= 0
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                    ),
                  if (!d.ehPassado &&
                      (d.entradasPrevistas > 0 || d.saidasPrevistas > 0)) ...[
                    const SizedBox(width: 8),
                    Text(
                      'Prev: ${_moeda.format(d.saldoPrevisto)}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (d.entradasPrevistas > 0)
                    _tag(
                      '+${_moeda.format(d.entradasPrevistas)} a receber (${d.qtdEntradasPrevistas})',
                      Colors.blue.shade800,
                    ),
                  if (d.saidasPrevistas > 0)
                    _tag(
                      '-${_moeda.format(d.saidasPrevistas)} a pagar (${d.qtdSaidasPrevistas})',
                      Colors.blueGrey.shade800,
                    ),
                  if (d.entradasRealizadas > 0)
                    _tag(
                      '+${_moeda.format(d.entradasRealizadas)} recebido',
                      Colors.green.shade800,
                    ),
                  if (d.saidasRealizadas > 0)
                    _tag(
                      '-${_moeda.format(d.saidasRealizadas)} pago',
                      Colors.red.shade800,
                    ),
                ],
              ),
              if (expandido && itens.isNotEmpty) ...[
                const Divider(height: 20),
                ...itens.map(
                  (i) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      i.realizado
                          ? Icons.check_circle_outline
                          : Icons.schedule_outlined,
                      size: 20,
                      color: i.tipo.contains('receber') ||
                              i.tipo.contains('Recebido')
                          ? Colors.blue.shade700
                          : Colors.blueGrey.shade700,
                    ),
                    title: Text(i.descricao),
                    subtitle: Text('${i.tipo} · ${i.referencia}'),
                    trailing: Text(
                      _moeda.format(i.valor),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w600),
      ),
    );
  }
}
