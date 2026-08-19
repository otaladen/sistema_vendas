import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api/lan_api_event_hub.dart';
import '../../data/inventario_gateway.dart';
import '../../data/sync/safe_sync_refresh_mixin.dart';
import '../../domain/inventario_constantes.dart';
import '../../domain/inventario_contagem.dart';
import '../../domain/produto_embalagem.dart';
import '../../model/item_inventario.dart';
import '../../model/sessao_inventario.dart';
import '../../model/usuario_sistema.dart';
import '../theme/app_semantic_helper.dart';
import '../widgets/lan_api_feedback.dart';
import '../widgets/operacao_feedback.dart';
import '../widgets/produto_busca_input.dart';
import 'inventario_resumo_page.dart';

class InventarioContagemPage extends StatefulWidget {
  const InventarioContagemPage({
    super.key,
    required this.gateway,
    required this.sessaoId,
    required this.usuarioLogado,
  });

  final InventarioGateway gateway;
  final int sessaoId;
  final UsuarioSistema usuarioLogado;

  @override
  State<InventarioContagemPage> createState() => _InventarioContagemPageState();
}

class _InventarioContagemPageState extends State<InventarioContagemPage>
    with SafeSyncRefreshMixin {
  final _buscaCtrl = TextEditingController();
  SessaoInventario? _sessao;
  List<ItemInventario> _itens = [];
  String _filtro = InventarioFiltroLista.todos;
  bool _carregando = true;
  bool _cegaLocal = false;

  InventarioGateway get _gw => widget.gateway;
  String get _login => widget.usuarioLogado.login;

  @override
  void initState() {
    super.initState();
    initSafeSyncRefresh(onReload: _recarregar);
    LanApiEventHub.instance.addListener(_onLan);
    _recarregar();
  }

  @override
  void dispose() {
    LanApiEventHub.instance.removeListener(_onLan);
    disposeSafeSyncRefresh();
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _onLan() {
    if (LanApiEventHub.instance.ultimaEntidade == 'inventario') {
      _recarregar();
    }
  }

  Future<void> _recarregar() async {
    try {
      final sessao = await _gw.obterSessao(widget.sessaoId);
      final itens = await _gw.listarItens(
        widget.sessaoId,
        filtro: _filtro,
        busca: _buscaCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _sessao = sessao;
        _cegaLocal = sessao?.contagemCega ?? _cegaLocal;
        _itens = itens;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      LanApiFeedback.snackErro(context, e, prefixo: 'Inventario');
    }
  }

  Future<void> _buscar() async {
    setState(() => _carregando = true);
    await _recarregar();
    if (!mounted || _itens.length != 1) return;
    final q = _buscaCtrl.text.trim();
    if (q.isEmpty) return;
    final item = _itens.first;
    final exact = item.codigoBarras.trim().toLowerCase() == q.toLowerCase() ||
        item.codigoInterno.trim().toLowerCase() == q.toLowerCase();
    if (exact) {
      await _abrirFicha(item);
    }
  }

  Future<void> _toggleCega(bool v) async {
    try {
      final s = await _gw.definirContagemCega(
        sessaoId: widget.sessaoId,
        contagemCega: v,
      );
      if (!mounted) return;
      setState(() {
        _sessao = s;
        _cegaLocal = s.contagemCega;
      });
    } catch (e) {
      if (mounted) LanApiFeedback.snackErro(context, e, prefixo: 'Inventario');
    }
  }

  Future<void> _abrirFicha(ItemInventario item) async {
    final sessao = _sessao;
    if (sessao == null || !sessao.aberta || item.aplicado) return;
    final gravou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _FichaContagemSheet(
        item: item,
        gateway: _gw,
        sessao: sessao,
        usuarioLogin: _login,
        cega: _cegaLocal,
      ),
    );
    if (gravou == true && mounted) {
      _recarregar();
    }
  }

  Future<void> _abrirResumo() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InventarioResumoPage(
          gateway: _gw,
          sessaoId: widget.sessaoId,
          usuarioLogado: widget.usuarioLogado,
        ),
      ),
    );
    if (mounted) _recarregar();
  }

  @override
  Widget build(BuildContext context) {
    final s = _sessao;
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      appBar: AppBar(
        title: Text(s?.nome ?? 'Contagem'),
        actions: [
          if (s != null && s.aberta)
            IconButton(
              tooltip: 'Resumo e ajustes',
              onPressed: _abrirResumo,
              icon: const Icon(Icons.summarize_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          if (s != null) _cabecalho(s, compact),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _buscaCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _buscar(),
              decoration: produtoBuscaInputDecoration(
                labelText: 'Buscar ou ler codigo de barras',
                helperText: 'Nome, SKU ou EAN. Enter confirma a leitura.',
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Buscar',
                  onPressed: _buscar,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _filtros(),
          const Divider(height: 1),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _itens.isEmpty
                    ? const Center(child: Text('Nenhum item neste filtro.'))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _itens.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _linha(_itens[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho(SessaoInventario s, bool compact) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.progressoTexto,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: s.progressoFracao,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            Text(
              '${s.escopoTexto}'
              '${s.totalDivergentes > 0 ? ' · ${s.totalDivergentes} divergente(s)' : ''}'
              '${s.totalPendentes > 0 ? ' · ${s.totalPendentes} faltando' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (s.aberta)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                title: Text(
                  compact
                      ? 'Ocultar saldo do sistema'
                      : 'Contagem cega — ocultar saldo do sistema',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                value: _cegaLocal,
                onChanged: _toggleCega,
              ),
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    const opcoes = [
      InventarioFiltroLista.todos,
      InventarioFiltroLista.faltaContar,
      InventarioFiltroLista.conferidosOk,
      InventarioFiltroLista.divergentes,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          for (final f in opcoes) ...[
            FilterChip(
              label: Text(InventarioFiltroLista.rotulo(f)),
              selected: _filtro == f,
              onSelected: (_) {
                setState(() {
                  _filtro = f;
                  _carregando = true;
                });
                _recarregar();
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _linha(ItemInventario item) {
    final semantic = context.semanticColors;
    final Color cor;
    final IconData icone;
    switch (item.estado) {
      case InventarioItemEstado.conferidoOk:
        cor = semantic.successFg;
        icone = Icons.check_circle_outline;
      case InventarioItemEstado.divergente:
        cor = semantic.errorFg;
        icone = Icons.warning_amber_outlined;
      default:
        cor = Theme.of(context).colorScheme.outline;
        icone = Icons.radio_button_unchecked;
    }
    final live = _gw.produtoDe(item);
    final qtdTxt = item.conferido
        ? InventarioContagem.formatarQtd(item, item.quantidadeContada, live: live)
        : 'Falta contar';
    final sistemaTxt = _cegaLocal
        ? null
        : InventarioContagem.formatarQtd(item, item.snapshotFisico, live: live);
    return ListTile(
      leading: Icon(icone, color: cor),
      title: Text(item.nomeSnapshot),
      subtitle: Text(
        [
          if (item.codigoInterno.trim().isNotEmpty) item.codigoInterno.trim(),
          if (sistemaTxt != null) 'Sistema: $sistemaTxt',
          'Fisico: $qtdTxt',
        ].join(' · '),
      ),
      trailing: item.aplicado
          ? const Chip(label: Text('Ajustado'), visualDensity: VisualDensity.compact)
          : Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
            ),
      onTap: () => _abrirFicha(item),
    );
  }
}

class _FichaContagemSheet extends StatefulWidget {
  const _FichaContagemSheet({
    required this.item,
    required this.gateway,
    required this.sessao,
    required this.usuarioLogin,
    required this.cega,
  });

  final ItemInventario item;
  final InventarioGateway gateway;
  final SessaoInventario sessao;
  final String usuarioLogin;
  final bool cega;

  @override
  State<_FichaContagemSheet> createState() => _FichaContagemSheetState();
}

class _FichaContagemSheetState extends State<_FichaContagemSheet> {
  late final TextEditingController _qtdCtrl;
  String? _erro;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final live = widget.gateway.produtoDe(widget.item);
    final ctx = InventarioContagem.contextoProduto(widget.item, live);
    _qtdCtrl = TextEditingController(
      text: widget.item.conferido
          ? ProdutoEmbalagem.formatarEstoque(ctx, widget.item.quantidadeContada)
          : '',
    );
  }

  @override
  void dispose() {
    _qtdCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final live = widget.gateway.produtoDe(widget.item);
    final ctx = InventarioContagem.contextoProduto(widget.item, live);
    final qtd = InventarioContagem.parseQuantidade(_qtdCtrl.text, ctx);
    if (qtd == null) {
      setState(() => _erro = 'Informe a quantidade fisica (use 0 se vazio).');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await widget.gateway.registrarContagem(
        sessaoId: widget.sessao.id,
        itemId: widget.item.id,
        quantidadeArmazenada: qtd,
        usuarioLogin: widget.usuarioLogin,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      OperacaoFeedback.sucesso(context, 'Item conferido.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final live = widget.gateway.produtoDe(item);
    final detalhe = InventarioContagem.formatarQtd(
      item,
      item.snapshotFisico,
      live: live,
      detalhado: true,
    );
    final livreTxt = InventarioContagem.formatarQtd(
      item,
      item.snapshotLivre,
      live: live,
    );
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.nomeSnapshot, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            [
              if (item.codigoInterno.trim().isNotEmpty) 'SKU ${item.codigoInterno}',
              if (item.codigoBarras.trim().isNotEmpty) 'EAN ${item.codigoBarras}',
              ProdutoEmbalagem.normalizarUnidade(item.unidade),
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!widget.cega) ...[
            const SizedBox(height: 12),
            Text('Saldo do sistema: $detalhe'),
            Text('Livre para venda: $livreTxt'),
            if (item.snapshotReservado > 0)
              Text(
                'Reservado: ${InventarioContagem.formatarQtd(item, item.snapshotReservado, live: live)}',
              ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Contagem cega: informe apenas o que ha na prateleira.',
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _qtdCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _salvar(),
            decoration: InputDecoration(
              labelText: 'Quantidade fisica',
              hintText: '0',
              helperText:
                  'Use a unidade de exibicao (${ProdutoEmbalagem.normalizarUnidade(item.unidade)}).',
              border: const OutlineInputBorder(),
              errorText: _erro,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Marcar conferido'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
