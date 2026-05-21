import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../data/produto_repository.dart';
import '../data/promocao_repository.dart';
import '../domain/cliente_cadastro.dart';
import '../domain/promocao_cadastro.dart';
import '../model/produto.dart';
import '../model/promocao.dart';
import '../model/promocao_combo_item.dart';
import '../model/promocao_item.dart';
import '../services/promocao_etiqueta_pdf.dart';
import 'widgets/produto_busca_input.dart';

const Color _corPromocoes = Color(0xFFC62828);

class PromocoesPage extends StatefulWidget {
  const PromocoesPage({
    super.key,
    required this.promocaoRepository,
    required this.produtoRepository,
  });

  final PromocaoRepository promocaoRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<PromocoesPage> createState() => _PromocoesPageState();
}

class _PromocoesPageState extends State<PromocoesPage> {
  final _fmtData = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final lista = widget.promocaoRepository.listarPorNome();
    final hoje = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promocoes'),
        actions: [
          IconButton(
            tooltip: 'Etiquetas de gondola (vigentes hoje)',
            onPressed: () async {
              final itens = widget.promocaoRepository.listarProdutosEtiquetaGondola(
                DateTime.now(),
                obterProduto: widget.produtoRepository.obterPorId,
              );
              if (!context.mounted) return;
              if (itens.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Nenhum produto com promocao vigente hoje.'),
                  ),
                );
                return;
              }
              final bytes = await gerarPdfEtiquetasGondolaPromocao(itens);
              if (!context.mounted) return;
              await Printing.layoutPdf(onLayout: (_) async => bytes);
            },
            icon: const Icon(Icons.label_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => PromocaoEditPage(
                promocaoRepository: widget.promocaoRepository,
                produtoRepository: widget.produtoRepository,
              ),
            ),
          );
          if (mounted) setState(() {});
        },
        icon: const Icon(Icons.add),
        label: const Text('Nova promocao'),
      ),
      body: lista.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nenhuma promocao cadastrada.\n'
                  'Defina vigencia, regra (% sobre preco 1 ou preco fixo) e produtos.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: lista.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = lista[i];
                final vigente = widget.promocaoRepository
                    .listarVigentesNaData(hoje)
                    .any((x) => x.id == p.id);
                return Card(
                  child: ListTile(
                    leading: Icon(
                      vigente ? Icons.local_offer : Icons.event_busy_outlined,
                      color: vigente ? _corPromocoes : null,
                    ),
                    title: Text(p.nome),
                    subtitle: Text(
                      '${_fmtData.format(p.dataInicio.toLocal())} a '
                      '${_fmtData.format(p.dataFim.toLocal())} · '
                      '${PromocaoCadastro.rotuloTipoCampanha(p.tipoCampanha)} · '
                      '${PromocaoCadastro.rotuloSegmentoCliente(p.segmentoCliente)} · '
                      '${p.ativa ? "Ativa" : "Inativa"}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => PromocaoEditPage(
                            promocaoId: p.id,
                            promocaoRepository: widget.promocaoRepository,
                            produtoRepository: widget.produtoRepository,
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _LinhaPromocaoDraft {
  _LinhaPromocaoDraft({
    this.produto,
    this.categoria = '',
    this.subcategoria = '',
    required this.qtdMinController,
    required this.qtdMaxController,
  });

  Produto? produto;
  String categoria;
  String subcategoria;
  final TextEditingController qtdMinController;
  final TextEditingController qtdMaxController;

  void dispose() {
    qtdMinController.dispose();
    qtdMaxController.dispose();
  }
}

class _LinhaComboDraft {
  _LinhaComboDraft({
    required this.produto,
    required this.qtdController,
  });

  final Produto produto;
  final TextEditingController qtdController;

  void dispose() => qtdController.dispose();
}

class PromocaoEditPage extends StatefulWidget {
  const PromocaoEditPage({
    super.key,
    this.promocaoId,
    required this.promocaoRepository,
    required this.produtoRepository,
  });

  final int? promocaoId;
  final PromocaoRepository promocaoRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<PromocaoEditPage> createState() => _PromocaoEditPageState();
}

class _PromocaoEditPageState extends State<PromocaoEditPage> {
  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _valorCtrl = TextEditingController();
  final _prioridadeCtrl = TextEditingController(text: '0');
  DateTime _inicio = DateTime.now();
  DateTime _fim = DateTime.now().add(const Duration(days: 7));
  bool _ativa = true;
  String _tipoRegra = 'preco_fixo';
  String _tipoCampanha = PromocaoCadastro.tipoProduto;
  String _segmentoCliente = PromocaoCadastro.segmentoTodos;
  final _margemCtrl = TextEditingController(text: '0');
  final _limiteGlobalCtrl = TextEditingController(text: '0');
  final _leveCtrl = TextEditingController(text: '3');
  final _pagueCtrl = TextEditingController(text: '2');
  final _precoComboCtrl = TextEditingController();
  final List<_LinhaPromocaoDraft> _linhas = [];
  final List<_LinhaComboDraft> _linhasCombo = [];
  bool _salvando = false;

  static final _fmtMoeda = NumberFormat('#,##0.00', 'pt_BR');

  String _fmt(double v) => 'R\$ ${_fmtMoeda.format(v)}';

  void _registrarListenersPreview() {
    void tick() {
      if (mounted) setState(() {});
    }
    for (final c in [
      _valorCtrl,
      _margemCtrl,
      _leveCtrl,
      _pagueCtrl,
      _precoComboCtrl,
    ]) {
      c.addListener(tick);
    }
  }

  double get _valorRegra =>
      double.tryParse(_valorCtrl.text.replaceAll(',', '.')) ?? 0;

  double get _precoComboValor =>
      double.tryParse(_precoComboCtrl.text.replaceAll(',', '.')) ?? 0;

  int get _leveQtd => int.tryParse(_leveCtrl.text.trim()) ?? 0;

  int get _pagueQtd => int.tryParse(_pagueCtrl.text.trim()) ?? 0;

  bool get _ehCombo =>
      _tipoCampanha == PromocaoCadastro.tipoComboAb;

  bool get _ehLevePague =>
      _tipoCampanha == PromocaoCadastro.tipoLevePague;

  bool get _mostraRegraPreco => !_ehCombo;

  @override
  void initState() {
    super.initState();
    _registrarListenersPreview();
    final id = widget.promocaoId;
    if (id != null) {
      final p = widget.promocaoRepository.obterPorId(id);
      if (p != null) {
        _nomeCtrl.text = p.nome;
        _descCtrl.text = p.descricao;
        _inicio = p.dataInicio.toLocal();
        _fim = p.dataFim.toLocal();
        _ativa = p.ativa;
        _tipoRegra = PromocaoCadastro.normalizarTipoRegra(p.tipoRegra);
        _valorCtrl.text = p.valorRegra.toStringAsFixed(2);
        _prioridadeCtrl.text = '${p.prioridade}';
        _segmentoCliente =
            PromocaoCadastro.normalizarSegmentoCliente(p.segmentoCliente);
        _tipoCampanha = PromocaoCadastro.normalizarTipoCampanha(p.tipoCampanha);
        _margemCtrl.text = p.margemMinimaPercentual.toStringAsFixed(1);
        _limiteGlobalCtrl.text = '${p.limiteQuantidadeTotal}';
        _leveCtrl.text = '${p.leveQuantidade > 0 ? p.leveQuantidade : 3}';
        _pagueCtrl.text = '${p.pagueQuantidade > 0 ? p.pagueQuantidade : 2}';
        _precoComboCtrl.text = p.precoCombo > 0
            ? p.precoCombo.toStringAsFixed(2)
            : '';
        for (final c in p.comboItens) {
          final prod = c.produtoAlvoId > 0
              ? widget.produtoRepository.obterPorId(c.produtoAlvoId)
              : null;
          if (prod == null) continue;
          _linhasCombo.add(
            _LinhaComboDraft(
              produto: prod,
              qtdController: TextEditingController(text: '${c.quantidade}'),
            ),
          );
        }
        for (final it in p.itens) {
          Produto? prod;
          if (it.produtoAlvoId > 0) {
            prod = widget.produtoRepository.obterPorId(it.produtoAlvoId);
          }
          _linhas.add(
            _LinhaPromocaoDraft(
              produto: prod,
              categoria: it.categoria,
              subcategoria: it.subcategoria,
              qtdMinController: TextEditingController(
                text: '${it.quantidadeMinima}',
              ),
              qtdMaxController: TextEditingController(
                text: it.quantidadeMaximaPromo > 0
                    ? '${it.quantidadeMaximaPromo}'
                    : '',
              ),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    _valorCtrl.dispose();
    _prioridadeCtrl.dispose();
    _margemCtrl.dispose();
    _limiteGlobalCtrl.dispose();
    _leveCtrl.dispose();
    _pagueCtrl.dispose();
    _precoComboCtrl.dispose();
    for (final l in _linhas) {
      l.dispose();
    }
    for (final l in _linhasCombo) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _pickData({required bool inicio}) async {
    final base = inicio ? _inicio : _fim;
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (inicio) {
        _inicio = d;
        if (_fim.isBefore(_inicio)) _fim = _inicio;
      } else {
        _fim = d;
      }
    });
  }

  Future<void> _adicionarProduto() async {
    final buscaCtrl = TextEditingController();
    var resultados = widget.produtoRepository.pesquisarPadraoPdv('', limite: 40);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              title: const Text('Produto na promocao'),
              content: SizedBox(
                width: 420,
                height: 380,
                child: Column(
                  children: [
                    TextField(
                      controller: buscaCtrl,
                      autofocus: true,
                      decoration: produtoBuscaInputDecoration(isDense: true),
                      onChanged: (t) {
                        resultados = widget.produtoRepository.pesquisarPadraoPdv(
                          t,
                          limite: 40,
                          somenteAtivos: false,
                        );
                        setDlg(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: resultados.length,
                        itemBuilder: (_, i) {
                          final p = resultados[i];
                          return ListTile(
                            dense: true,
                            title: Text(p.nome, maxLines: 2),
                            subtitle: Text(p.codigoInterno),
                            onTap: () {
                              setState(() {
                                _linhas.add(
                                  _LinhaPromocaoDraft(
                                    produto: p,
                                    qtdMinController: TextEditingController(
                                      text: '1',
                                    ),
                                    qtdMaxController: TextEditingController(),
                                  ),
                                );
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        },
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
            );
          },
        );
      },
    );
    buscaCtrl.dispose();
  }

  void _adicionarCategoria() {
    final catCtrl = TextEditingController();
    final subCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Categoria na promocao'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: catCtrl,
              decoration: const InputDecoration(labelText: 'Categoria'),
            ),
            TextField(
              controller: subCtrl,
              decoration: const InputDecoration(
                labelText: 'Subcategoria (opcional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (catCtrl.text.trim().isEmpty) return;
              setState(() {
                _linhas.add(
                  _LinhaPromocaoDraft(
                    categoria: catCtrl.text.trim(),
                    subcategoria: subCtrl.text.trim(),
                    qtdMinController: TextEditingController(text: '1'),
                    qtdMaxController: TextEditingController(),
                  ),
                );
              });
              Navigator.pop(ctx);
            },
            child: const Text('Incluir'),
          ),
        ],
      ),
    );
  }

  Future<void> _adicionarProdutoCombo() async {
    final buscaCtrl = TextEditingController();
    var resultados = widget.produtoRepository.pesquisarPadraoPdv('', limite: 40);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              title: const Text('Produto do combo'),
              content: SizedBox(
                width: 420,
                height: 380,
                child: Column(
                  children: [
                    TextField(
                      controller: buscaCtrl,
                      autofocus: true,
                      decoration: produtoBuscaInputDecoration(isDense: true),
                      onChanged: (t) {
                        resultados = widget.produtoRepository.pesquisarPadraoPdv(
                          t,
                          limite: 40,
                          somenteAtivos: false,
                        );
                        setDlg(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: resultados.length,
                        itemBuilder: (_, i) {
                          final p = resultados[i];
                          return ListTile(
                            dense: true,
                            title: Text(p.nome, maxLines: 2),
                            subtitle: Text(p.codigoInterno),
                            onTap: () {
                              setState(() {
                                _linhasCombo.add(
                                  _LinhaComboDraft(
                                    produto: p,
                                    qtdController: TextEditingController(
                                      text: '1',
                                    ),
                                  ),
                                );
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        },
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
            );
          },
        );
      },
    );
    buscaCtrl.dispose();
  }

  Future<void> _salvar() async {
    final tipo = PromocaoCadastro.normalizarTipoCampanha(_tipoCampanha);
    final valor = _valorRegra;
    final precoCombo = _precoComboValor;
    final margem =
        double.tryParse(_margemCtrl.text.replaceAll(',', '.')) ?? 0;
    final limiteGlobal = int.tryParse(_limiteGlobalCtrl.text.trim()) ?? 0;
    final erros = PromocaoCadastro.validarFormulario(
      nome: _nomeCtrl.text,
      tipoCampanha: tipo,
      tipoRegra: _tipoRegra,
      valorRegra: valor,
      precoCombo: precoCombo,
      leveQuantidade: _leveQtd,
      pagueQuantidade: _pagueQtd,
      qtdItensProduto: _linhas.length,
      qtdItensCombo: _linhasCombo.length,
      margemMinima: margem,
      limiteGlobal: limiteGlobal,
    );
    if (erros.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erros.first)),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      final promo = Promocao(
        id: widget.promocaoId ?? 0,
        nome: _nomeCtrl.text.trim(),
        descricao: _descCtrl.text.trim(),
        dataInicio: DateTime.utc(_inicio.year, _inicio.month, _inicio.day),
        dataFim: DateTime.utc(_fim.year, _fim.month, _fim.day, 23, 59, 59),
        ativa: _ativa,
        prioridade: int.tryParse(_prioridadeCtrl.text.trim()) ?? 0,
        tipoRegra: _tipoRegra,
        valorRegra: valor < 0 ? 0 : valor,
        segmentoCliente: _segmentoCliente,
        tipoCampanha: tipo,
        margemMinimaPercentual:
            double.tryParse(_margemCtrl.text.replaceAll(',', '.')) ?? 0,
        limiteQuantidadeTotal:
            int.tryParse(_limiteGlobalCtrl.text.trim()) ?? 0,
        leveQuantidade: _ehLevePague ? _leveQtd : 0,
        pagueQuantidade: _ehLevePague ? _pagueQtd : 0,
        precoCombo: _ehCombo ? precoCombo : 0,
      );
      final itens = <PromocaoItem>[];
      for (final l in _linhas) {
        final qtd = int.tryParse(l.qtdMinController.text.trim()) ?? 0;
        final qMax = int.tryParse(l.qtdMaxController.text.trim()) ?? 0;
        itens.add(
          PromocaoItem(
            produtoAlvoId: l.produto?.id ?? 0,
            categoria: l.categoria,
            subcategoria: l.subcategoria,
            quantidadeMinima: qtd < 1 ? 1 : qtd,
            quantidadeMaximaPromo: qMax < 0 ? 0 : qMax,
          ),
        );
      }
      final comboItens = <PromocaoComboItem>[];
      for (final l in _linhasCombo) {
        final q = int.tryParse(l.qtdController.text.trim()) ?? 0;
        comboItens.add(
          PromocaoComboItem(
            produtoAlvoId: l.produto.id,
            quantidade: q < 1 ? 1 : q,
          ),
        );
      }
      widget.promocaoRepository.salvar(
        promo,
        itens,
        comboItens: comboItens,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _secao({
    required String titulo,
    required List<Widget> children,
    String? subtitulo,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titulo,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitulo != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitulo,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _painelExplicacaoCampanha() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        PromocaoCadastro.explicacaoTipoCampanha(_tipoCampanha),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _painelSimulacaoPreco() {
    final scheme = Theme.of(context).colorScheme;
    final resumo = PromocaoCadastro.resumoRegraPreco(
      tipoCampanha: _tipoCampanha,
      tipoRegra: _tipoRegra,
      valorRegra: _valorRegra,
      leveQuantidade: _leveQtd,
      pagueQuantidade: _pagueQtd,
      precoCombo: _precoComboValor,
    );

    if (_ehCombo) {
      var ref = 0.0;
      for (final l in _linhasCombo) {
        final q = int.tryParse(l.qtdController.text.trim()) ?? 1;
        ref += PromocaoCadastro.preco1DoProduto(l.produto) * (q < 1 ? 1 : q);
      }
      if (_linhasCombo.isEmpty) {
        return const SizedBox.shrink();
      }
      final combo = _precoComboValor;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Simulacao do combo', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text('Soma preco 1 dos itens: ${_fmt(ref)}'),
            Text('Preco do pacote: ${_fmt(combo)}'),
            if (ref > 0 && combo > 0)
              Text(
                combo < ref
                    ? 'Desconto total: ${_fmt(ref - combo)} (${((1 - combo / ref) * 100).toStringAsFixed(1)}%)'
                    : 'Pacote acima da soma preco 1 (sem desconto)',
                style: TextStyle(
                  color: combo < ref ? Colors.green.shade800 : scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      );
    }

    Produto? produtoExemplo;
    for (final l in _linhas) {
      if (l.produto != null) {
        produtoExemplo = l.produto;
        break;
      }
    }
    if (produtoExemplo == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Adicione um produto para ver a simulacao de preco (preco 1, '
          'preco na promo e margem).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final p1 = PromocaoCadastro.preco1DoProduto(produtoExemplo);
    final qtdSim = _ehLevePague && _leveQtd >= 2 ? _leveQtd : 1;
    final precoBasePromo = PromocaoCadastro.calcularPrecoBasePromocional(
      tipoRegra: _tipoRegra,
      valorRegra: _valorRegra,
      precoBasePreco1: p1,
    );
    final precoUnitEfetivo = PromocaoCadastro.calcularPrecoUnitarioEfetivo(
      tipoCampanha: _tipoCampanha,
      tipoRegra: _tipoRegra,
      valorRegra: _valorRegra,
      precoBasePreco1: p1,
      quantidade: qtdSim,
      leveQuantidade: _leveQtd,
      pagueQuantidade: _pagueQtd,
    );
    final totalLinha = PromocaoCadastro.calcularTotalLinhaPromocional(
      tipoCampanha: _tipoCampanha,
      tipoRegra: _tipoRegra,
      valorRegra: _valorRegra,
      precoBasePreco1: p1,
      quantidade: qtdSim,
      leveQuantidade: _leveQtd,
      pagueQuantidade: _pagueQtd,
    );
    final margem = PromocaoCadastro.margemSobrePrecoVenda(
      precoCusto: produtoExemplo.precoCusto,
      precoVenda: precoUnitEfetivo,
    );
    final margemMin =
        double.tryParse(_margemCtrl.text.replaceAll(',', '.')) ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Simulacao: ${produtoExemplo.nome}',
            style: Theme.of(context).textTheme.labelLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text('Regra: $resumo'),
          Text('Preco 1 (a prazo): ${_fmt(p1)}'),
          Text('Preco promocional (1 un.): ${_fmt(precoBasePromo)}'),
          if (_ehLevePague && qtdSim >= _leveQtd && _leveQtd >= 2) ...[
            Text(
              'Com $qtdSim un. (leve $_leveQtd pague $_pagueQtd): '
              'total ${_fmt(totalLinha)} = paga $_pagueQtd x ${_fmt(precoBasePromo)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _corPromocoes,
              ),
            ),
            Text(
              'No orcamento/cupom: ${qtdSim} un. x ${_fmt(precoUnitEfetivo)} = '
              '${_fmt(totalLinha)} (preco medio; o cliente paga $_pagueQtd x '
              '${_fmt(precoBasePromo)}, nao $qtdSim x ${_fmt(precoBasePromo)})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ] else
            Text(
              'Preco na venda: ${_fmt(precoUnitEfetivo)} / un.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          if (produtoExemplo.precoCusto > 0) ...[
            Text('Margem sobre custo: ${margem.toStringAsFixed(1)}%'),
            if (margemMin > 0 && margem + 0.05 < margemMin)
              Text(
                'Abaixo da margem minima (${margemMin.toStringAsFixed(1)}%) — '
                'PDV pedira gerente.',
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
          ],
        ],
      ),
    );
  }

  Widget _linhaProdutoCard(int index, _LinhaPromocaoDraft l) {
    final titulo = l.produto != null
        ? '${l.produto!.codigoInterno} · ${l.produto!.nome}'
        : 'Categoria: ${l.categoria}'
            '${l.subcategoria.isNotEmpty ? " / ${l.subcategoria}" : ""}';

    String? detalhePreco;
    if (l.produto != null) {
      final p1 = PromocaoCadastro.preco1DoProduto(l.produto!);
      final qMin = int.tryParse(l.qtdMinController.text.trim()) ?? 1;
      final qSim = _ehLevePague && _leveQtd >= 2 ? _leveQtd : qMin;
      final base = PromocaoCadastro.calcularPrecoBasePromocional(
        tipoRegra: _tipoRegra,
        valorRegra: _valorRegra,
        precoBasePreco1: p1,
      );
      final total = PromocaoCadastro.calcularTotalLinhaPromocional(
        tipoCampanha: _tipoCampanha,
        tipoRegra: _tipoRegra,
        valorRegra: _valorRegra,
        precoBasePreco1: p1,
        quantidade: qSim,
        leveQuantidade: _leveQtd,
        pagueQuantidade: _pagueQtd,
      );
      detalhePreco = _ehLevePague && qSim >= _leveQtd
          ? 'Paga $_pagueQtd x ${_fmt(base)} = ${_fmt(total)} ($qSim un. na nota)'
          : 'Preco 1 ${_fmt(p1)} → promo ${_fmt(base)}/un.';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, maxLines: 2),
                      if (detalhePreco != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            detalhePreco,
                            style: TextStyle(
                              color: _corPromocoes,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      l.dispose();
                      _linhas.removeAt(index);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: l.qtdMinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Qtd minima para entrar',
                      isDense: true,
                      helperText: 'Ex.: 1 = qualquer qtd',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: l.qtdMaxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max por venda',
                      isDense: true,
                      helperText: '0 = sem limite',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.promocaoId == null ? 'Nova promocao' : 'Editar promocao'),
        actions: [
          if (widget.promocaoId != null)
            IconButton(
              tooltip: 'Excluir',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Excluir promocao?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Excluir'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  widget.promocaoRepository.excluir(widget.promocaoId!);
                  if (mounted) Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _secao(
              titulo: '1. Identificacao',
              children: [
                TextField(
                  controller: _nomeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome da campanha',
                    hintText: 'Ex.: Black Friday tintas',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descricao (opcional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickData(inicio: true),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          'Inicio ${DateFormat('dd/MM/yy').format(_inicio)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickData(inicio: false),
                        icon: const Icon(Icons.event, size: 18),
                        label: Text('Fim ${DateFormat('dd/MM/yy').format(_fim)}'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _ativa,
                  onChanged: (v) => setState(() => _ativa = v),
                  title: const Text('Campanha ativa'),
                ),
              ],
            ),
            _secao(
              titulo: '2. Quem pode usar',
              subtitulo:
                  'Segmento restringe o PDV a clientes daquele tipo. Prioridade '
                  'desempata quando dois precos promocionais cabem no mesmo produto.',
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(_segmentoCliente),
                  initialValue: _segmentoCliente.isEmpty
                      ? PromocaoCadastro.segmentoTodos
                      : _segmentoCliente,
                  decoration: const InputDecoration(labelText: 'Segmento de cliente'),
                  items: [
                    const DropdownMenuItem(
                      value: PromocaoCadastro.segmentoTodos,
                      child: Text('Todos os segmentos'),
                    ),
                    ...ClienteCadastro.segmentos.map(
                      (s) => DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(
                      () => _segmentoCliente =
                          PromocaoCadastro.normalizarSegmentoCliente(v),
                    );
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _prioridadeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prioridade (0 = normal)',
                    helperText: 'Maior numero vence no empate.',
                  ),
                ),
              ],
            ),
            _secao(
              titulo: '3. Tipo de campanha',
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(_tipoCampanha),
                  initialValue: _tipoCampanha,
                  decoration: const InputDecoration(labelText: 'Como a promo funciona'),
                  items: PromocaoCadastro.tiposCampanha
                      .map(
                        (t) => DropdownMenuItem(value: t.$1, child: Text(t.$2)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _tipoCampanha = v);
                  },
                ),
                const SizedBox(height: 10),
                _painelExplicacaoCampanha(),
              ],
            ),
            if (_mostraRegraPreco)
              _secao(
                titulo: '4. Preco promocional',
                subtitulo:
                    'O desconto % sempre usa o preco 1 (a prazo) do cadastro do produto, '
                    'igual ao PDV.',
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(_tipoRegra),
                    initialValue: _tipoRegra,
                    decoration: const InputDecoration(labelText: 'Forma do desconto'),
                    items: PromocaoCadastro.tiposRegra
                        .map(
                          (t) => DropdownMenuItem(value: t.$1, child: Text(t.$2)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _tipoRegra = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _valorCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _tipoRegra == 'desconto_percentual'
                          ? 'Percentual de desconto'
                          : 'Preco fixo na promo',
                      helperText: _tipoRegra == 'desconto_percentual'
                          ? 'Ex.: 10 = 10% off sobre preco 1'
                          : 'Valor final por unidade na promocao',
                      suffixText: _tipoRegra == 'desconto_percentual' ? '%' : 'R\$',
                    ),
                  ),
                  if (_ehLevePague) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Leve X pague Y (aplica sobre o preco acima)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _leveCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Leve (unidades)',
                              helperText: 'Ex.: 3',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _pagueCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Pague (unidades)',
                              helperText: 'Ex.: 2 (menor que leve)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  _painelSimulacaoPreco(),
                ],
              )
            else
              _secao(
                titulo: '4. Preco do combo',
                subtitulo: 'Valor total do pacote quando todos os itens estiverem no carrinho.',
                children: [
                  TextField(
                    controller: _precoComboCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Preco fechado do combo',
                      suffixText: 'R\$',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _painelSimulacaoPreco(),
                ],
              ),
            _secao(
              titulo: '5. Limites e margem',
              children: [
                TextField(
                  controller: _margemCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Margem minima (%)',
                    helperText:
                        '0 = desligado. Se a margem (preco promo − custo) ficar '
                        'abaixo, o PDV pede senha de gerente.',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _limiteGlobalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Limite total de unidades vendidas',
                    helperText: '0 = ilimitado. Conta ao finalizar no caixa.',
                  ),
                ),
              ],
            ),
            _secao(
              titulo: _ehCombo ? '6. Produtos do combo' : '6. Produtos e categorias',
              subtitulo: _ehCombo
                  ? 'Todos devem estar no carrinho com as quantidades abaixo.'
                  : 'Produto especifico ou categoria/subcategoria inteira.',
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    if (_ehCombo)
                      FilledButton.icon(
                        onPressed: _adicionarProdutoCombo,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar ao combo'),
                      )
                    else ...[
                      FilledButton.icon(
                        onPressed: _adicionarProduto,
                        icon: const Icon(Icons.add),
                        label: const Text('Produto'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _adicionarCategoria,
                        icon: const Icon(Icons.category_outlined),
                        label: const Text('Categoria'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (_ehCombo)
                  ..._linhasCombo.asMap().entries.map((e) {
                    final l = e.value;
                    final q = int.tryParse(l.qtdController.text.trim()) ?? 1;
                    final p1 = PromocaoCadastro.preco1DoProduto(l.produto) *
                        (q < 1 ? 1 : q);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          l.produto.nome,
                          maxLines: 2,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SKU ${l.produto.codigoInterno} · preco 1 ${_fmt(p1)}'),
                            TextField(
                              controller: l.qtdController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Quantidade no combo',
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              l.dispose();
                              _linhasCombo.removeAt(e.key);
                            });
                          },
                        ),
                      ),
                    );
                  })
                else if (_linhas.isEmpty)
                  Text(
                    'Nenhum item. Toque em Produto ou Categoria.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                else
                  ..._linhas.asMap().entries.map(
                        (e) => _linhaProdutoCard(e.key, e.value),
                      ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: _salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_salvando ? 'Salvando...' : 'Salvar campanha'),
            ),
          ],
        ),
      ),
    );
  }
}
