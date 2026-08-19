import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/inventario_gateway.dart';
import '../../data/sync/safe_sync_refresh_mixin.dart';
import '../../domain/inventario_codec.dart';
import '../../domain/inventario_constantes.dart';
import '../../model/sessao_inventario.dart';
import '../../model/usuario_sistema.dart';
import '../theme/app_semantic_helper.dart';
import '../widgets/lan_api_feedback.dart';
import '../widgets/operacao_feedback.dart';
import 'inventario_contagem_page.dart';
import 'inventario_resumo_page.dart';

final _dataFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
final _diaFmt = DateFormat('dd/MM', 'pt_BR');

class InventarioSessoesPage extends StatefulWidget {
  const InventarioSessoesPage({
    super.key,
    required this.gateway,
    required this.usuarioLogado,
  });

  final InventarioGateway gateway;
  final UsuarioSistema usuarioLogado;

  @override
  State<InventarioSessoesPage> createState() => _InventarioSessoesPageState();
}

class _InventarioSessoesPageState extends State<InventarioSessoesPage>
    with SafeSyncRefreshMixin {
  List<SessaoInventario> _sessoes = [];
  bool _carregando = true;
  String? _erro;

  InventarioGateway get _gw => widget.gateway;
  String get _login => widget.usuarioLogado.login;

  @override
  void initState() {
    super.initState();
    initSafeSyncRefresh(onReload: _recarregar);
    _recarregar();
  }

  @override
  void dispose() {
    disposeSafeSyncRefresh();
    super.dispose();
  }

  Future<void> _recarregar() async {
    try {
      final list = await _gw.listarSessoes();
      if (!mounted) return;
      setState(() {
        _sessoes = list;
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = '$e';
      });
    }
  }

  Future<void> _novaSessao() async {
    final criada = await mostrarNovaSessaoInventarioDialog(
      context,
      gateway: _gw,
      criadoPor: _login,
    );
    if (criada == null || !mounted) return;
    await _recarregar();
    if (!mounted) return;
    await _abrirSessao(criada);
  }

  Future<void> _abrirSessao(SessaoInventario sessao) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InventarioContagemPage(
          gateway: _gw,
          sessaoId: sessao.id,
          usuarioLogado: widget.usuarioLogado,
        ),
      ),
    );
    if (mounted) _recarregar();
  }

  Future<void> _abrirResumo(SessaoInventario sessao) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InventarioResumoPage(
          gateway: _gw,
          sessaoId: sessao.id,
          usuarioLogado: widget.usuarioLogado,
        ),
      ),
    );
    if (mounted) _recarregar();
  }

  Future<void> _cancelar(SessaoInventario sessao) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar esta contagem?'),
        content: Text(
          'A sessao "${sessao.nome}" sera excluida da lista. '
          'O estoque nao sera alterado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _gw.cancelarSessao(sessaoId: sessao.id, usuarioLogin: _login);
      if (mounted) {
        OperacaoFeedback.aviso(context, 'Contagem apagada.');
        _recarregar();
      }
    } catch (e) {
      if (mounted) LanApiFeedback.snackErro(context, e, prefixo: 'Inventario');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Balanço / Inventário'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _recarregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novaSessao,
        icon: const Icon(Icons.add),
        label: const Text('Nova sessao'),
      ),
      body: _corpo(),
    );
  }

  Widget _corpo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_erro!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_sessoes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhuma sessao de balanco.\nToque em Nova sessao para iniciar uma contagem.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: _sessoes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _cartao(_sessoes[i]),
    );
  }

  Widget _cartao(SessaoInventario s) {
    final semantic = context.semanticColors;
    final Color accent;
    switch (s.status) {
      case InventarioSessaoStatus.aplicada:
        accent = semantic.successFg;
      case InventarioSessaoStatus.cancelada:
        accent = Theme.of(context).colorScheme.outline;
      default:
        accent = semantic.infoFg;
    }
    return Card(
      child: InkWell(
        onTap: () {
          if (s.aberta) {
            _abrirSessao(s);
          } else if (s.status == InventarioSessaoStatus.cancelada) {
            _cancelar(s);
          } else {
            _abrirResumo(s);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.nome,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(InventarioSessaoStatus.rotulo(s.status)),
                    side: BorderSide(color: accent.withValues(alpha: 0.4)),
                    labelStyle: TextStyle(color: accent, fontSize: 12),
                  ),
                  if (s.aberta ||
                      s.status == InventarioSessaoStatus.cancelada)
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'resumo') _abrirResumo(s);
                        if (v == 'cancelar') _cancelar(s);
                      },
                      itemBuilder: (_) => [
                        if (s.aberta)
                          const PopupMenuItem(
                            value: 'resumo',
                            child: Text('Resumo e ajustes'),
                          ),
                        const PopupMenuItem(
                          value: 'cancelar',
                          child: Text('Apagar sessao'),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${s.escopoTexto} · ${_dataFmt.format(s.criadoEm.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (s.contagemCega)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Contagem cega (saldo do sistema oculto)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: semantic.warningFg,
                        ),
                  ),
                ),
              if (s.totalItens > 0) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: s.progressoFracao,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                Text(
                  '${s.progressoTexto}'
                  '${s.totalDivergentes > 0 ? ' · ${s.totalDivergentes} divergente(s)' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<SessaoInventario?> mostrarNovaSessaoInventarioDialog(
  BuildContext context, {
  required InventarioGateway gateway,
  required String criadoPor,
}) {
  return showDialog<SessaoInventario>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _NovaSessaoDialog(
      gateway: gateway,
      criadoPor: criadoPor,
    ),
  );
}

class _NovaSessaoDialog extends StatefulWidget {
  const _NovaSessaoDialog({
    required this.gateway,
    required this.criadoPor,
  });

  final InventarioGateway gateway;
  final String criadoPor;

  @override
  State<_NovaSessaoDialog> createState() => _NovaSessaoDialogState();
}

class _NovaSessaoDialogState extends State<_NovaSessaoDialog> {
  final _nomeCtrl = TextEditingController();
  InventarioCategoriasInfo? _info;
  String? _categoria;
  String? _subcategoria;
  bool _cega = false;
  bool _salvando = false;
  int _totalFiltro = 0;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _nomeCtrl.text = 'Contagem Loja ${_diaFmt.format(DateTime.now())}';
    _carregar();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final info = await widget.gateway.obterCategorias();
      final total = await widget.gateway.contarProdutosNoFiltro();
      if (!mounted) return;
      setState(() {
        _info = info;
        _totalFiltro = total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = '$e');
    }
  }

  Future<void> _atualizarContagem() async {
    final total = await widget.gateway.contarProdutosNoFiltro(
      categoria: _categoria ?? '',
      subcategoria: _subcategoria ?? '',
    );
    if (!mounted) return;
    setState(() => _totalFiltro = total);
    final escopo = (_categoria == null || _categoria!.isEmpty)
        ? 'Loja'
        : _categoria!;
    if (_nomeCtrl.text.startsWith('Contagem ')) {
      _nomeCtrl.text = 'Contagem $escopo ${_diaFmt.format(DateTime.now())}';
    }
  }

  Future<void> _confirmar() async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) return;
    setState(() => _salvando = true);
    try {
      final sessao = await widget.gateway.criarSessao(
        nome: nome,
        categoria: _categoria ?? '',
        subcategoria: _subcategoria ?? '',
        contagemCega: _cega,
        criadoPor: widget.criadoPor,
      );
      if (mounted) Navigator.pop(context, sessao);
    } catch (e) {
      if (mounted) {
        setState(() => _salvando = false);
        LanApiFeedback.snackErro(context, e, prefixo: 'Inventario');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = _info?.categorias ?? const <String>[];
    final subs = (_categoria != null && _categoria!.isNotEmpty)
        ? (_info?.subcategoriasPorCategoria[_categoria!] ?? const <String>[])
        : const <String>[];
    return AlertDialog(
      title: const Text('Nova sessao de balanco'),
      content: SizedBox(
        width: 420,
        child: _erro != null
            ? Text(_erro!)
            : _info == null
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _nomeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nome da sessao',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          key: ValueKey<String?>('cat-$_categoria'),
                          initialValue: _categoria,
                          decoration: const InputDecoration(
                            labelText: 'Grupo / categoria',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Loja inteira'),
                            ),
                            for (final c in cats)
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _categoria = v;
                              _subcategoria = null;
                            });
                            _atualizarContagem();
                          },
                        ),
                        if (subs.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String?>(
                            key: ValueKey<String?>('sub-$_subcategoria'),
                            initialValue: _subcategoria,
                            decoration: const InputDecoration(
                              labelText: 'Subcategoria (opcional)',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Todas'),
                              ),
                              for (final s in subs)
                                DropdownMenuItem(value: s, child: Text(s)),
                            ],
                            onChanged: (v) {
                              setState(() => _subcategoria = v);
                              _atualizarContagem();
                            },
                          ),
                        ],
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Contagem cega'),
                          subtitle: const Text(
                            'Ocultar saldo do sistema durante a contagem',
                          ),
                          value: _cega,
                          onChanged: (v) => setState(() => _cega = v),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '$_totalFiltro produto(s) no snapshot',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        FilledButton(
          onPressed: _salvando || _totalFiltro <= 0 ? null : _confirmar,
          child: _salvando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Iniciar'),
        ),
      ],
    );
  }
}
