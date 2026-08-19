import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/estoque/movimento_estoque_helper.dart';
import '../../model/movimento_estoque.dart';
import '../theme/app_semantic_colors.dart';
import '../theme/app_semantic_helper.dart';
import '../widgets/lan_api_feedback.dart';

/// Kardex de movimentacoes de estoque de um produto.
class ExtratoMovimentoEstoquePanel extends StatefulWidget {
  const ExtratoMovimentoEstoquePanel({
    super.key,
    required this.produtoRepository,
    required this.produtoId,
  });

  /// [ProdutoRepository] local ou API no terminal leve.
  final dynamic produtoRepository;
  final int? produtoId;

  @override
  State<ExtratoMovimentoEstoquePanel> createState() =>
      _ExtratoMovimentoEstoquePanelState();
}

enum _FiltroKardex { todas, entradas, saidas, reservas }

class _ExtratoMovimentoEstoquePanelState
    extends State<ExtratoMovimentoEstoquePanel> {
  static final _dataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final _dataDia = DateFormat("EEEE, d 'de' MMMM", 'pt_BR');
  static final _dataCurta = DateFormat('dd/MM/yyyy', 'pt_BR');

  List<MovimentoEstoque> _lista = const [];
  bool _carregando = true;
  String? _erro;
  _FiltroKardex _filtro = _FiltroKardex.todas;
  final _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_recarregar());
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ExtratoMovimentoEstoquePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.produtoId != widget.produtoId) unawaited(_recarregar());
  }

  Future<void> _recarregar() async {
    final id = widget.produtoId;
    if (id == null || id <= 0) {
      setState(() {
        _lista = const [];
        _carregando = false;
        _erro = null;
      });
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final raw =
          widget.produtoRepository.listarMovimentosEstoquePorProduto(id);
      final resolved = raw is Future ? await raw : raw;
      List<MovimentoEstoque> itens = const [];
      if (resolved is List<MovimentoEstoque>) {
        itens = resolved;
      } else if (resolved is List) {
        itens = resolved.whereType<MovimentoEstoque>().toList();
      }
      if (!mounted) return;
      setState(() {
        _lista = itens;
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lista = const [];
        _carregando = false;
        _erro = LanApiFeedback.mensagem(e);
      });
    }
  }

  List<MovimentoEstoque> get _filtrada {
    final q = _buscaCtrl.text.trim().toLowerCase();
    return _lista.where((m) {
      final nat = MovimentoEstoqueHelper.natureza(
        deltaFisico: m.deltaFisico,
        deltaReserva: m.deltaReserva,
      );
      final okFiltro = switch (_filtro) {
        _FiltroKardex.todas => true,
        _FiltroKardex.entradas => nat == NaturezaKardex.entrada,
        _FiltroKardex.saidas => nat == NaturezaKardex.saida,
        _FiltroKardex.reservas => nat == NaturezaKardex.reserva,
      };
      if (!okFiltro) return false;
      if (q.isEmpty) return true;
      final tipo = MovimentoEstoqueHelper.rotuloTipo(m.tipoMovimento);
      return tipo.toLowerCase().contains(q) ||
          m.documentoReferencia.toLowerCase().contains(q) ||
          m.motivo.toLowerCase().contains(q) ||
          m.usuarioLogin.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.produtoId == null || widget.produtoId! <= 0) {
      return _vazio('Salve o produto para ver o kardex de movimentacoes.');
    }
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Nao foi possivel carregar o extrato.\n$_erro',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => unawaited(_recarregar()),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_lista.isEmpty) {
      return _vazio(
        'Nenhuma movimentacao registrada ainda.\n'
        'Vendas, carreto, NF-e e ajustes passam a aparecer aqui.',
      );
    }

    final visivel = _filtrada;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecalho(visivel.length),
        Expanded(
          child: visivel.isEmpty
              ? _vazio('Nenhum movimento neste filtro.')
              : RefreshIndicator(
                  onRefresh: _recarregar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                    itemCount: visivel.length,
                    itemBuilder: (context, i) {
                      final m = visivel[i];
                      final mostrarDia = i == 0 ||
                          !_mesmoDia(
                            visivel[i - 1].registradoEm,
                            m.registradoEm,
                          );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (mostrarDia) _cabecalhoDia(m.registradoEm),
                          _cartaoMovimento(m),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _vazio(String texto) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  Widget _cabecalho(int visiveis) {
    final semantic = context.semanticColors;
    final ultimo = _lista.isEmpty ? null : _lista.first;
    final fisico = ultimo?.saldoFisicoDepois;
    final reserva = ultimo?.saldoReservaDepois;
    final livre = (fisico != null && reserva != null) ? fisico - reserva : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  visiveis == _lista.length
                      ? '${_lista.length} movimentos'
                      : '$visiveis de ${_lista.length}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (fisico != null && reserva != null) ...[
                _kpi('Fis', '$fisico', semantic.infoFg, semantic.infoBg),
                const SizedBox(width: 4),
                _kpi('Res', '$reserva', semantic.warningFg, semantic.warningBg),
                const SizedBox(width: 4),
                _kpi(
                  'Livre',
                  '${livre ?? 0}',
                  semantic.successFg,
                  semantic.successBg,
                ),
                const SizedBox(width: 2),
              ],
              IconButton(
                tooltip: 'Atualizar',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => unawaited(_recarregar()),
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _chipFiltro(_FiltroKardex.todas, 'Todas'),
              const SizedBox(width: 4),
              _chipFiltro(_FiltroKardex.entradas, 'Entradas'),
              const SizedBox(width: 4),
              _chipFiltro(_FiltroKardex.saidas, 'Saidas'),
              const SizedBox(width: 4),
              _chipFiltro(_FiltroKardex.reservas, 'Reservas'),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _buscaCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      hintText: 'Buscar',
                      border: const OutlineInputBorder(),
                      suffixIcon: _buscaCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                _buscaCtrl.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close, size: 16),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(String rotulo, String valor, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$rotulo $valor',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  Widget _chipFiltro(_FiltroKardex valor, String rotulo) {
    return FilterChip(
      label: Text(rotulo, style: const TextStyle(fontSize: 12)),
      selected: _filtro == valor,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (_) => setState(() => _filtro = valor),
    );
  }

  bool _mesmoDia(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  Widget _cabecalhoDia(DateTime utc) {
    final local = utc.toLocal();
    final hoje = DateTime.now();
    final ontem = hoje.subtract(const Duration(days: 1));
    String texto;
    if (_mesmoDia(local, hoje)) {
      texto = 'Hoje · ${_dataCurta.format(local)}';
    } else if (_mesmoDia(local, ontem)) {
      texto = 'Ontem · ${_dataCurta.format(local)}';
    } else {
      texto = _dataDia.format(local);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 3),
      child: Text(
        texto,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _cartaoMovimento(MovimentoEstoque m) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    final tipo = MovimentoEstoqueHelper.rotuloTipo(m.tipoMovimento);
    final nat = MovimentoEstoqueHelper.natureza(
      deltaFisico: m.deltaFisico,
      deltaReserva: m.deltaReserva,
    );
    final barra = switch (nat) {
      NaturezaKardex.entrada => semantic.successFg,
      NaturezaKardex.saida => semantic.errorFg,
      NaturezaKardex.reserva => semantic.warningFg,
      NaturezaKardex.neutro => scheme.outline,
    };
    final detalhes = [
      _dataHora.format(m.registradoEm.toLocal()),
      if (m.documentoReferencia.isNotEmpty) m.documentoReferencia,
      'Fis ${m.saldoFisicoAntes}→${m.saldoFisicoDepois}',
      'Res ${m.saldoReservaAntes}→${m.saldoReservaDepois}',
      if (m.usuarioLogin.isNotEmpty) m.usuarioLogin,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: barra),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                  child: Row(
                    children: [
                      Icon(
                        MovimentoEstoqueHelper.iconeTipo(m.tipoMovimento),
                        size: 16,
                        color: barra,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tipo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              detalhes,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (m.motivo.isNotEmpty)
                              Text(
                                m.motivo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _badgesDelta(m, semantic),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badgesDelta(MovimentoEstoque m, AppSemanticColors semantic) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.deltaFisico != 0)
          _badge(
            'Fis ${MovimentoEstoqueHelper.formatarDelta(m.deltaFisico)}',
            m.deltaFisico > 0 ? semantic.successFg : semantic.errorFg,
            m.deltaFisico > 0 ? semantic.successBg : semantic.errorBg,
          ),
        if (m.deltaFisico != 0 && m.deltaReserva != 0) const SizedBox(width: 4),
        if (m.deltaReserva != 0)
          _badge(
            'Res ${MovimentoEstoqueHelper.formatarDelta(m.deltaReserva)}',
            m.deltaReserva > 0
                ? semantic.warningFg
                : Theme.of(context).colorScheme.onSurfaceVariant,
            semantic.warningBg,
          ),
      ],
    );
  }

  Widget _badge(String texto, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        texto,
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: fg),
      ),
    );
  }
}
