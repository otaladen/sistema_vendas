import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/reajuste_preco_lote.dart';
import '../model/produto.dart';
import '../model/usuario_sistema.dart';
import 'layout/app_layout.dart';
import 'reajuste_preco_autorizacao.dart';
import 'reajuste_preco_historico_page.dart';
import 'widgets/lan_api_feedback.dart';

final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
final NumberFormat _pct = NumberFormat('#,##0.0', 'pt_BR');

/// Assistente de reajuste de precos em lote.
class ReajustePrecoLotePage extends StatefulWidget {
  const ReajustePrecoLotePage({
    super.key,
    required this.produtoRepository,
    required this.reajusteRepository,
    required this.usuarioRepository,
    required this.usuarioLogado,
    required this.escopoInicial,
    this.tituloEscopo,
  });

  final dynamic produtoRepository;
  final dynamic reajusteRepository;
  /// [UsuarioRepository] no PC1 ou [UsuarioApiRepository] no Terminal Leve.
  final dynamic usuarioRepository;
  final UsuarioSistema usuarioLogado;
  final List<Produto> escopoInicial;
  final String? tituloEscopo;

  @override
  State<ReajustePrecoLotePage> createState() => _ReajustePrecoLotePageState();
}

class _ReajustePrecoLotePageState extends State<ReajustePrecoLotePage> {
  int _passo = 0;
  bool _somenteAtivos = true;
  String? _filtroCategoria;
  String? _filtroMarca;
  String? _filtroFornecedor;
  ReajustePrecoModo _modo = ReajustePrecoModo.percentualSobrePrecoAtual;
  ReajusteBaseCusto _baseCusto = ReajusteBaseCusto.custoDigitado;
  final Set<ReajusteTabelaPreco> _tabelas = {
    ReajusteTabelaPreco.preco1,
    ReajusteTabelaPreco.preco2,
    ReajusteTabelaPreco.preco3,
  };
  bool _protegerAbaixoCusto = true;
  ReajusteArredondamento _arredondamento = ReajusteArredondamento.centavos;

  final _percentualController = TextEditingController(text: '5');
  final _margemController = TextEditingController(text: '35');
  final _margemMinimaController = TextEditingController(text: '5');
  final _motivoController = TextEditingController();

  bool _selecaoManual = false;
  final Set<int> _idsSelecionados = {};
  ReajustePrecoSimulacaoResumo? _resumo;
  bool _simulando = false;
  bool _aplicando = false;

  List<Produto> get _escopoFiltrado {
    var lista = widget.escopoInicial;
    if (_somenteAtivos) {
      lista = lista.where((p) => p.ativo).toList();
    }
    if (_filtroCategoria != null && _filtroCategoria!.isNotEmpty) {
      lista = lista.where((p) => p.categoria == _filtroCategoria).toList();
    }
    if (_filtroMarca != null && _filtroMarca!.isNotEmpty) {
      lista = lista.where((p) => p.marca == _filtroMarca).toList();
    }
    if (_filtroFornecedor != null && _filtroFornecedor!.isNotEmpty) {
      lista = lista.where((p) => p.fornecedor == _filtroFornecedor).toList();
    }
    return lista;
  }

  List<Produto> get _escopoEfetivo {
    if (!_selecaoManual) return _escopoFiltrado;
    return _escopoFiltrado
        .where((p) => _idsSelecionados.contains(p.id))
        .toList();
  }

  void _sincronizarSelecaoComFiltros() {
    if (!_selecaoManual) return;
    final idsAtuais = _escopoFiltrado.map((p) => p.id).toSet();
    _idsSelecionados.removeWhere((id) => !idsAtuais.contains(id));
    if (_idsSelecionados.isEmpty) {
      _idsSelecionados.addAll(idsAtuais);
    }
  }

  void _atualizarFiltroEscopo(VoidCallback fn) {
    setState(() {
      fn();
      _sincronizarSelecaoComFiltros();
    });
  }

  List<String> _valoresDistintos(String Function(Produto) selector) {
    final valores = <String>{};
    for (final p in widget.escopoInicial) {
      final v = selector(p).trim();
      if (v.isNotEmpty) valores.add(v);
    }
    final lista = valores.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return lista;
  }

  Widget _dropdownFiltroEscopo({
    required String label,
    required String? value,
    required List<String> opcoes,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          hint: Text('Todos ($label)'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Todos'),
            ),
            ...opcoes.map(
              (o) => DropdownMenuItem<String?>(value: o, child: Text(o)),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (!usuarioPodeReajustePrecoLote(widget.usuarioLogado)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _snack(
          'Sem permissao para reajuste em lote. Ative em Usuarios ou use administrador.',
          erro: true,
        );
        Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _percentualController.dispose();
    _margemController.dispose();
    _margemMinimaController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  double? _lerMargemMinima() {
    final t = _margemMinimaController.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    return double.tryParse(t);
  }

  ReajustePrecoParametros? _montarParametros() {
    if (_tabelas.isEmpty) return null;
    final margemMin = _lerMargemMinima();
    if (margemMin == null) return null;

    if (_modo == ReajustePrecoModo.percentualSobrePrecoAtual) {
      final pct = double.tryParse(
        _percentualController.text.trim().replaceAll(',', '.'),
      );
      if (pct == null) return null;
      return ReajustePrecoParametros(
        modo: _modo,
        tabelas: Set<ReajusteTabelaPreco>.from(_tabelas),
        percentualSobrePreco: pct,
        baseCusto: _baseCusto,
        arredondamento: _arredondamento,
        naoAlterarSeAbaixoDoCusto: _protegerAbaixoCusto,
        somenteAtivos: _somenteAtivos,
        margemMinimaPercentual: margemMin.clamp(0, 95),
      );
    }

    final margem = double.tryParse(
      _margemController.text.trim().replaceAll(',', '.'),
    );
    if (margem == null) return null;
    return ReajustePrecoParametros(
      modo: _modo,
      tabelas: Set<ReajusteTabelaPreco>.from(_tabelas),
      margemPercentual: margem.clamp(0, 95),
      baseCusto: _baseCusto,
      arredondamento: _arredondamento,
      naoAlterarSeAbaixoDoCusto: _protegerAbaixoCusto,
      somenteAtivos: _somenteAtivos,
      margemMinimaPercentual: margemMin.clamp(0, 95),
    );
  }

  String _resumoRegraTexto(ReajustePrecoParametros params) {
    final arr = switch (params.arredondamento) {
      ReajusteArredondamento.dezena90 => 'arred. ,90',
      ReajusteArredondamento.final99 => 'arred. ,99',
      ReajusteArredondamento.centavos => 'centavos',
    };
    if (params.modo == ReajustePrecoModo.margemFixaSobreCusto) {
      return 'Margem ${params.margemPercentual}% · $arr';
    }
    return '${params.percentualSobrePreco}% no preco · $arr';
  }

  String _fmtMoeda(double v) => 'R\$ ${_moeda.format(v)}';

  Future<void> _rodarSimulacao() async {
    final params = _montarParametros();
    if (params == null) {
      _snack('Revise os parametros do reajuste.', erro: true);
      return;
    }
    final escopo = _escopoEfetivo;
    if (escopo.isEmpty) {
      _snack('Nenhum produto no escopo.', erro: true);
      return;
    }

    setState(() => _simulando = true);
    await Future<void>.delayed(Duration.zero);
    final resumo = ReajustePrecoLoteService.simular(escopo, params);
    if (!mounted) return;
    setState(() {
      _resumo = resumo;
      _simulando = false;
      _passo = 2;
    });
  }

  Future<void> _confirmarAplicacao() async {
    final params = _montarParametros();
    final resumo = _resumo;
    if (params == null || resumo == null) return;
    if (resumo.totalAlterados == 0) {
      _snack('Nenhum item sera alterado.', erro: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar reajuste'),
        content: Text(
          'Aplicar novo preco em ${resumo.totalAlterados} produto(s)?\n'
          '${resumo.totalIgnorados} item(ns) permanecem sem alteracao.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    if (resumo.precisaAutorizacaoGerente &&
        !usuarioPodeAutorizarReajustePreco(widget.usuarioLogado)) {
      final authOk = await solicitarAutorizacaoReajustePreco(
        context,
        widget.usuarioRepository,
        itensComAlerta: resumo.totalExigemAutorizacao,
        resumoRegra: _resumoRegraTexto(params),
      );
      if (!authOk || !mounted) return;
    }

    setState(() => _aplicando = true);
    try {
      final resultadoRaw = widget.reajusteRepository.aplicarLote(
        parametros: params,
        linhas: resumo.linhas,
        usuario: widget.usuarioLogado,
        motivo: _motivoController.text.trim(),
      );
      final resultado = resultadoRaw is Future
          ? await resultadoRaw
          : resultadoRaw;
      if (!mounted) return;
      setState(() => _aplicando = false);

      final motivo = _motivoController.text.trim();
      final extra = motivo.isEmpty ? '' : ' Motivo: $motivo.';
      final hist = resultado.reajustePrecoId > 0
          ? ' Registro #${resultado.reajustePrecoId} no historico.'
          : '';
      _snack(
        '${resultado.produtosGravados} produto(s) atualizado(s).'
        '${resultado.ignorados > 0 ? ' ${resultado.ignorados} ignorado(s).' : ''}'
        '$extra$hist',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aplicando = false);
      LanApiFeedback.snackErro(context, e, prefixo: 'Reajuste');
    }
  }

  Future<void> _abrirHistorico() async {
    final repo = widget.reajusteRepository;
    try {
      await repo.hidratarHistorico();
    } catch (_) {
      // Repositorio local nao tem hidratarHistorico.
    }
    if (!mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReajustePrecoHistoricoPage(
          reajusteRepository: widget.reajusteRepository,
          usuarioRepository: widget.usuarioRepository,
          usuarioLogado: widget.usuarioLogado,
        ),
      ),
    );
  }

  void _snack(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: erro ? Theme.of(context).colorScheme.error : null,
        content: Text(msg),
      ),
    );
  }

  void _avancar() {
    if (_passo == 0) {
      if (_escopoEfetivo.isEmpty) {
        _snack('Escopo vazio. Ajuste os filtros na tela de Estoque.', erro: true);
        return;
      }
      setState(() => _passo = 1);
      return;
    }
    if (_passo == 1) {
      _rodarSimulacao();
      return;
    }
    if (_passo == 2) {
      setState(() => _passo = 3);
    }
  }

  void _voltar() {
    if (_passo <= 0) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      if (_passo == 2) _resumo = null;
      _passo--;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reajuste de precos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _aplicando ? null : _voltar,
        ),
        actions: [
          IconButton(
            tooltip: 'Historico de reajustes',
            icon: const Icon(Icons.history),
            onPressed: _aplicando ? null : _abrirHistorico,
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_passo + 1) / 4,
            minHeight: 3,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: context.isCompactLayout
                ? Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _chipPasso(0, 'Escopo'),
                      _chipPasso(1, 'Regra'),
                      _chipPasso(2, 'Simulacao'),
                      _chipPasso(3, 'Confirmar'),
                    ],
                  )
                : Row(
                    children: [
                      _chipPasso(0, 'Escopo'),
                      _chipPasso(1, 'Regra'),
                      _chipPasso(2, 'Simulacao'),
                      _chipPasso(3, 'Confirmar'),
                    ],
                  ),
          ),
          Expanded(
            child: _aplicando
                ? const Center(child: CircularProgressIndicator())
                : _simulando
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Simulando reajuste...'),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _conteudoPasso(theme),
                      ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: AdaptiveBottomActions(
              leading: TextButton(
                onPressed: _aplicando || _simulando ? null : _voltar,
                child: Text(_passo == 0 ? 'Cancelar' : 'Voltar'),
              ),
              primary: _passo == 3
                  ? FilledButton(
                      onPressed: _aplicando ? null : _confirmarAplicacao,
                      child: const Text('Aplicar reajuste'),
                    )
                  : FilledButton(
                      onPressed: _aplicando || _simulando ? null : _avancar,
                      child: Text(_passo == 1 ? 'Simular' : 'Avancar'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipPasso(int indice, String label) {
    final ativo = _passo == indice;
    final feito = _passo > indice;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
            color: feito
                ? Theme.of(context).colorScheme.primary
                : ativo
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }

  Widget _conteudoPasso(ThemeData theme) {
    switch (_passo) {
      case 0:
        return _passoEscopo(theme);
      case 1:
        return _passoRegra(theme);
      case 2:
        return _passoSimulacao(theme);
      case 3:
        return _passoConfirmar(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _passoEscopo(ThemeData theme) {
    final total = widget.escopoInicial.length;
    final efetivo = _escopoEfetivo.length;
    final categorias = _valoresDistintos((p) => p.categoria);
    final marcas = _valoresDistintos((p) => p.marca);
    final fornecedores = _valoresDistintos((p) => p.fornecedor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Escopo do reajuste',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (widget.tituloEscopo != null)
          Text(widget.tituloEscopo!, style: theme.textTheme.bodyMedium),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$efetivo produto(s) serao considerados'),
                Text(
                  'Lista filtrada na Estoque: $total item(ns) no total.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Somente produtos ativos'),
          subtitle: const Text('Inativos ficam fora do reajuste'),
          value: _somenteAtivos,
          onChanged: (v) => _atualizarFiltroEscopo(() => _somenteAtivos = v),
        ),
        if (categorias.isNotEmpty) ...[
          const SizedBox(height: 8),
          _dropdownFiltroEscopo(
            label: 'Categoria',
            value: _filtroCategoria,
            opcoes: categorias,
            onChanged: (v) => _atualizarFiltroEscopo(() => _filtroCategoria = v),
          ),
        ],
        if (marcas.isNotEmpty) ...[
          const SizedBox(height: 8),
          _dropdownFiltroEscopo(
            label: 'Marca',
            value: _filtroMarca,
            opcoes: marcas,
            onChanged: (v) => _atualizarFiltroEscopo(() => _filtroMarca = v),
          ),
        ],
        if (fornecedores.isNotEmpty) ...[
          const SizedBox(height: 8),
          _dropdownFiltroEscopo(
            label: 'Fornecedor',
            value: _filtroFornecedor,
            opcoes: fornecedores,
            onChanged: (v) =>
                _atualizarFiltroEscopo(() => _filtroFornecedor = v),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Selecionar produtos manualmente'),
          subtitle: Text(
            _selecaoManual
                ? '${_idsSelecionados.length} de ${_escopoFiltrado.length} marcado(s)'
                : 'Marque apenas os itens que entrarao no reajuste',
          ),
          value: _selecaoManual,
          onChanged: (v) {
            setState(() {
              _selecaoManual = v;
              if (v) {
                _idsSelecionados
                  ..clear()
                  ..addAll(_escopoFiltrado.map((p) => p.id));
              } else {
                _idsSelecionados.clear();
              }
            });
          },
        ),
        if (_selecaoManual && _escopoFiltrado.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _idsSelecionados
                    ..clear()
                    ..addAll(_escopoFiltrado.map((p) => p.id));
                }),
                child: const Text('Marcar todos'),
              ),
              TextButton(
                onPressed: () => setState(_idsSelecionados.clear),
                child: const Text('Desmarcar todos'),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _escopoFiltrado.length,
              itemBuilder: (ctx, i) {
                final p = _escopoFiltrado[i];
                return CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    p.nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${p.codigoInterno} · P1 ${_moeda.format(p.preco1)}',
                  ),
                  value: _idsSelecionados.contains(p.id),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _idsSelecionados.add(p.id);
                      } else {
                        _idsSelecionados.remove(p.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Refine o escopo por categoria, marca, fornecedor ou selecao manual. '
          'Para escopos amplos, use busca e filtros na Estoque antes de abrir o reajuste.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _passoRegra(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Regra de calculo',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        SegmentedButton<ReajustePrecoModo>(
          segments: const [
            ButtonSegment(
              value: ReajustePrecoModo.percentualSobrePrecoAtual,
              label: Text('% no preco'),
            ),
            ButtonSegment(
              value: ReajustePrecoModo.margemFixaSobreCusto,
              label: Text('Margem no custo'),
            ),
          ],
          selected: {_modo},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            setState(() => _modo = s.first);
          },
        ),
        const SizedBox(height: 16),
        if (_modo == ReajustePrecoModo.percentualSobrePrecoAtual)
          TextField(
            controller: _percentualController,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Percentual sobre o preco atual (%)',
              hintText: 'Ex.: 5 ou -3 para reduzir',
              border: OutlineInputBorder(),
            ),
          )
        else ...[
          SegmentedButton<ReajusteBaseCusto>(
            segments: const [
              ButtonSegment(
                value: ReajusteBaseCusto.custoDigitado,
                label: Text('Custo digitado'),
              ),
              ButtonSegment(
                value: ReajusteBaseCusto.custoMedio,
                label: Text('Custo medio'),
              ),
            ],
            selected: {_baseCusto},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              setState(() => _baseCusto = s.first);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _margemController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Margem alvo sobre o preco de venda (%)',
              hintText: 'Ex.: 35',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Tabelas afetadas', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        CheckboxListTile(
          dense: true,
          title: const Text('Preco 1'),
          value: _tabelas.contains(ReajusteTabelaPreco.preco1),
          onChanged: (v) => _toggleTabela(ReajusteTabelaPreco.preco1, v),
        ),
        CheckboxListTile(
          dense: true,
          title: const Text('Preco 2'),
          value: _tabelas.contains(ReajusteTabelaPreco.preco2),
          onChanged: (v) => _toggleTabela(ReajusteTabelaPreco.preco2, v),
        ),
        CheckboxListTile(
          dense: true,
          title: const Text('Preco 3'),
          value: _tabelas.contains(ReajusteTabelaPreco.preco3),
          onChanged: (v) => _toggleTabela(ReajusteTabelaPreco.preco3, v),
        ),
        const SizedBox(height: 12),
        Text('Arredondamento', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ReajusteArredondamento>(
          segments: const [
            ButtonSegment(
              value: ReajusteArredondamento.centavos,
              label: Text('Centavos'),
            ),
            ButtonSegment(
              value: ReajusteArredondamento.dezena90,
              label: Text(',90'),
            ),
            ButtonSegment(
              value: ReajusteArredondamento.final99,
              label: Text(',99'),
            ),
          ],
          selected: {_arredondamento},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            setState(() => _arredondamento = s.first);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _margemMinimaController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Margem minima apos reajuste (%)',
            hintText: '0 = sem trava; exige gerente se violar',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Nao alterar se ficar abaixo do custo'),
          subtitle: const Text(
            'Desligado: permite preco abaixo do custo com autorizacao de gerente',
          ),
          value: _protegerAbaixoCusto,
          onChanged: (v) => setState(() => _protegerAbaixoCusto = v),
        ),
      ],
    );
  }

  void _toggleTabela(ReajusteTabelaPreco t, bool? marcado) {
    setState(() {
      if (marcado == true) {
        _tabelas.add(t);
      } else {
        _tabelas.remove(t);
      }
    });
  }

  Widget _passoSimulacao(ThemeData theme) {
    final resumo = _resumo;
    if (resumo == null) {
      return const Text('Execute a simulacao no passo anterior.');
    }

    final amostra = resumo.linhas
        .where((l) => l.seraAlterado)
        .take(80)
        .toList();
    final params = _montarParametros()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _resumoCards(theme, resumo),
        const SizedBox(height: 12),
        Text(
          'Amostra de alteracoes (ate 80 itens)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 32,
            dataRowMaxHeight: 48,
            columns: [
              const DataColumn(label: Text('SKU')),
              const DataColumn(label: Text('Nome')),
              if (params.tabelas.contains(ReajusteTabelaPreco.preco1))
                const DataColumn(label: Text('P1 antes')),
              if (params.tabelas.contains(ReajusteTabelaPreco.preco1))
                const DataColumn(label: Text('P1 depois')),
              if (params.tabelas.contains(ReajusteTabelaPreco.preco2))
                const DataColumn(label: Text('P2 antes')),
              if (params.tabelas.contains(ReajusteTabelaPreco.preco2))
                const DataColumn(label: Text('P2 depois')),
            ],
            rows: amostra.map((l) {
              return DataRow(
                cells: [
                  DataCell(Text(l.codigoInterno)),
                  DataCell(
                    SizedBox(
                      width: 180,
                      child: Text(
                        l.nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (params.tabelas.contains(ReajusteTabelaPreco.preco1))
                    DataCell(Text(_fmtMoeda(l.preco1Antes))),
                  if (params.tabelas.contains(ReajusteTabelaPreco.preco1))
                    DataCell(Text(_fmtMoeda(l.preco1Depois))),
                  if (params.tabelas.contains(ReajusteTabelaPreco.preco2))
                    DataCell(Text(_fmtMoeda(l.preco2Antes))),
                  if (params.tabelas.contains(ReajusteTabelaPreco.preco2))
                    DataCell(Text(_fmtMoeda(l.preco2Depois))),
                ],
              );
            }).toList(),
          ),
        ),
        if (resumo.totalAlterados > amostra.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '... e mais ${resumo.totalAlterados - amostra.length} produto(s).',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _resumoCards(ThemeData theme, ReajustePrecoSimulacaoResumo resumo) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _cardResumo(
          theme,
          'Alterados',
          '${resumo.totalAlterados}',
          theme.colorScheme.primaryContainer,
        ),
        _cardResumo(
          theme,
          'Ignorados',
          '${resumo.totalIgnorados}',
          theme.colorScheme.surfaceContainerHighest,
        ),
        _cardResumo(
          theme,
          'Abaixo custo',
          '${resumo.totalBloqueadosAbaixoCusto}',
          theme.colorScheme.errorContainer,
        ),
        if (resumo.totalExigemAutorizacao > 0)
          _cardResumo(
            theme,
            'Alerta gerente',
            '${resumo.totalExigemAutorizacao}',
            theme.colorScheme.tertiaryContainer,
          ),
        _cardResumo(
          theme,
          'Variacao media',
          '${_pct.format(resumo.variacaoMediaPercentual)}%',
          theme.colorScheme.tertiaryContainer,
        ),
      ],
    );
  }

  Widget _cardResumo(
    ThemeData theme,
    String titulo,
    String valor,
    Color? cor,
  ) {
    return Card(
      color: cor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: theme.textTheme.labelSmall),
            Text(
              valor,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passoConfirmar(ThemeData theme) {
    final resumo = _resumo;
    if (resumo == null) {
      return const Text('Volte e execute a simulacao.');
    }

    final params = _montarParametros();
    final modoTxt = params?.modo == ReajustePrecoModo.margemFixaSobreCusto
        ? 'Margem ${_margemController.text}% sobre '
            '${_baseCusto == ReajusteBaseCusto.custoMedio ? 'custo medio' : 'custo digitado'}'
        : '${_percentualController.text}% sobre preco atual';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Confirmar aplicacao',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _resumoCards(theme, resumo),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Regra'),
          subtitle: Text(modoTxt),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tabelas'),
          subtitle: Text(_rotuloTabelas()),
        ),
        TextField(
          controller: _motivoController,
          decoration: const InputDecoration(
            labelText: 'Motivo / referencia (opcional)',
            hintText: 'Ex.: Reajuste fornecedor maio/2026',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        if (resumo.precisaAutorizacaoGerente &&
            !usuarioPodeAutorizarReajustePreco(widget.usuarioLogado))
          Text(
            '${resumo.totalExigemAutorizacao} item(ns) exigem login de gerente ao aplicar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        Text(
          'Os precos serao gravados no cadastro, sincronizados na rede e registrados '
          'no historico (estorno disponivel em Historico).',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  String _rotuloTabelas() {
    final partes = <String>[];
    if (_tabelas.contains(ReajusteTabelaPreco.preco1)) partes.add('Preco 1');
    if (_tabelas.contains(ReajusteTabelaPreco.preco2)) partes.add('Preco 2');
    if (_tabelas.contains(ReajusteTabelaPreco.preco3)) partes.add('Preco 3');
    return partes.join(' · ');
  }
}
