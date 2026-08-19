import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/inventario_gateway.dart';
import '../../domain/inventario_codec.dart';
import '../../domain/inventario_constantes.dart';
import '../../domain/inventario_contagem.dart';
import '../../model/item_inventario.dart';
import '../../model/sessao_inventario.dart';
import '../../model/usuario_sistema.dart';
import '../theme/app_semantic_helper.dart';
import '../widgets/lan_api_feedback.dart';
import '../widgets/operacao_feedback.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

class InventarioResumoPage extends StatefulWidget {
  const InventarioResumoPage({
    super.key,
    required this.gateway,
    required this.sessaoId,
    required this.usuarioLogado,
  });

  final InventarioGateway gateway;
  final int sessaoId;
  final UsuarioSistema usuarioLogado;

  @override
  State<InventarioResumoPage> createState() => _InventarioResumoPageState();
}

class _InventarioResumoPageState extends State<InventarioResumoPage> {
  SessaoInventario? _sessao;
  List<ItemInventario> _divergentes = [];
  bool _carregando = true;
  bool _aplicando = false;

  InventarioGateway get _gw => widget.gateway;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final sessao = await _gw.obterSessao(widget.sessaoId);
      final itens = await _gw.listarItens(
        widget.sessaoId,
        filtro: InventarioFiltroLista.divergentes,
      );
      if (!mounted) return;
      setState(() {
        _sessao = sessao;
        _divergentes = itens;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      LanApiFeedback.snackErro(context, e, prefixo: 'Inventario');
    }
  }

  Future<void> _aplicar() async {
    final s = _sessao;
    if (s == null || !s.aberta) return;
    final pendentes = s.totalPendentes;
    final avisoPendentes = pendentes > 0
        ? '\n\nAinda ha $pendentes item(ns) sem contar. Somente os divergentes conferidos serao ajustados.'
        : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aplicar ajustes de estoque?'),
        content: Text(
          'Serao geradas movimentacoes manuais no kardex apenas para os '
          '${s.totalDivergentes} item(ns) divergente(s), com o motivo '
          '"Ajuste por Inventário - Sessão #${s.id}".'
          '\n\nSobras estimadas: ${_moeda.format(s.valorSobras)}'
          '\nPerdas estimadas: ${_moeda.format(s.valorPerdas)}'
          '$avisoPendentes',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _aplicando = true);
    try {
      final resultado = await _gw.aplicarAjustes(
        sessaoId: widget.sessaoId,
        usuarioLogin: widget.usuarioLogado.login,
      );
      if (!mounted) return;
      setState(() {
        _aplicando = false;
        _sessao = resultado.sessao;
      });
      await _mostrarResultado(resultado);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _aplicando = false);
      LanApiFeedback.snackErro(context, e, prefixo: 'Inventario');
    }
  }

  Future<void> _mostrarResultado(InventarioAplicacaoResultado r) async {
    if (!mounted) return;
    if (r.falhas.isEmpty) {
      OperacaoFeedback.sucesso(
        context,
        r.aplicados == 0
            ? 'Nenhum ajuste necessario. Sessao encerrada.'
            : '${r.aplicados} ajuste(s) aplicados no estoque.',
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajustes parciais'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${r.aplicados} item(ns) ajustado(s).'),
              const SizedBox(height: 8),
              Text('${r.falhas.length} falha(s):'),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: ListView(
                  children: [
                    for (final f in r.falhas)
                      ListTile(
                        dense: true,
                        title: Text(f.nome),
                        subtitle: Text(f.erro),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _sessao;
    return Scaffold(
      appBar: AppBar(title: const Text('Resumo do balanco')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : s == null
              ? const Center(child: Text('Sessao nao encontrada.'))
              : Column(
                  children: [
                    _kpis(s),
                    const Divider(height: 1),
                    Expanded(
                      child: _divergentes.isEmpty
                          ? const Center(
                              child: Text('Nenhum item divergente nesta sessao.'),
                            )
                          : ListView.separated(
                              itemCount: _divergentes.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) =>
                                  _linha(_divergentes[i]),
                            ),
                    ),
                    if (s.aberta)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _aplicando ? null : _aplicar,
                              icon: _aplicando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.inventory_2_outlined),
                              label: const Text('Aplicar ajustes de estoque'),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _kpis(SessaoInventario s) {
    final semantic = context.semanticColors;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.nome, style: Theme.of(context).textTheme.titleMedium),
          Text(
            '${s.escopoTexto} · ${InventarioSessaoStatus.rotulo(s.status)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _kpi('Itens', '${s.totalItens}'),
              _kpi('Contados', '${s.totalConferidos}'),
              _kpi('Pendentes', '${s.totalPendentes}'),
              _kpi('Divergentes', '${s.totalDivergentes}'),
              _kpi(
                'Sobras',
                _moeda.format(s.valorSobras),
                cor: semantic.successFg,
              ),
              _kpi(
                'Perdas',
                _moeda.format(s.valorPerdas),
                cor: semantic.errorFg,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(String rotulo, String valor, {Color? cor}) {
    return Chip(
      label: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$rotulo: ',
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
            TextSpan(
              text: valor,
              style: TextStyle(fontWeight: FontWeight.w700, color: cor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linha(ItemInventario item) {
    final live = _gw.produtoDe(item);
    final sistema = InventarioContagem.formatarQtd(
      item,
      item.snapshotFisico,
      live: live,
    );
    final fisico = InventarioContagem.formatarQtd(
      item,
      item.quantidadeContada,
      live: live,
    );
    final delta = item.deltaArmazenado;
    final valor = InventarioContagem.valorDiferencaAbs(item, delta, live: live);
    final semantic = context.semanticColors;
    final sobra = delta > 0;
    return ListTile(
      title: Text(item.nomeSnapshot),
      subtitle: Text(
        'Sistema: $sistema  →  Fisico: $fisico'
        '${item.aplicado ? ' · ja ajustado' : ''}',
      ),
      trailing: Text(
        '${sobra ? '+' : '-'}${_moeda.format(valor)}',
        style: TextStyle(
          color: sobra ? semantic.successFg : semantic.errorFg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
