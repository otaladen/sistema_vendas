import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_config_repository.dart';
import '../data/produto_repository.dart';
import '../data/usuario_repository.dart';
import '../data/venda_repository.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import 'widgets/produto_busca_input.dart';

/// Fluxo de devolucao (estoque de volta) ou troca (devolucao + saida de produtos).
class RegistrarDevolucaoTrocaPage extends StatefulWidget {
  const RegistrarDevolucaoTrocaPage({
    super.key,
    required this.vendaRepository,
    required this.produtoRepository,
    required this.vendaId,
    required this.usuarioAtual,
    required this.podeRegistrarSemSenha,
  });

  final VendaRepository vendaRepository;
  final ProdutoRepository produtoRepository;
  final int vendaId;
  final String usuarioAtual;
  final bool podeRegistrarSemSenha;

  @override
  State<RegistrarDevolucaoTrocaPage> createState() =>
      _RegistrarDevolucaoTrocaPageState();
}

class _LinhaTrocaEdit {
  _LinhaTrocaEdit({
    required this.produto,
    int quantidadeInicial = 1,
  })  : qtdController = TextEditingController(text: '$quantidadeInicial'),
        precoTipo = 'preco1';

  final Produto produto;
  final TextEditingController qtdController;
  String precoTipo;

  int get quantidade => int.tryParse(qtdController.text.trim()) ?? 0;

  void dispose() => qtdController.dispose();
}

class _RegistrarDevolucaoTrocaPageState extends State<RegistrarDevolucaoTrocaPage> {
  final _motivoController = TextEditingController();
  final _obsFinanceiraController = TextEditingController();
  final _usuarioRepository = UsuarioRepository();
  final _currency = NumberFormat('#,##0.00', 'pt_BR');

  Venda? _venda;
  final Map<int, TextEditingController> _qtdDevolucaoPorItem = {};
  bool _modoTroca = false;
  final List<_LinhaTrocaEdit> _linhasTroca = [];
  bool _permitirVendaSemEstoque = true;
  bool _carregando = true;
  String? _erroCarregamento;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    final config = await AppConfigRepository().carregarEmpresaConfig();
    if (!mounted) return;
    setState(() {
      _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
    });
    _recarregarVenda();
  }

  void _recarregarVenda() {
    for (final c in _qtdDevolucaoPorItem.values) {
      c.dispose();
    }
    _qtdDevolucaoPorItem.clear();

    final v = widget.vendaRepository.obterPorId(widget.vendaId);
    if (v == null) {
      setState(() {
        _venda = null;
        _carregando = false;
        _erroCarregamento = 'Venda nao encontrada.';
      });
      return;
    }
    for (final item in v.itens) {
      final maxD = item.quantidade - item.quantidadeDevolvida;
      _qtdDevolucaoPorItem[item.id] = TextEditingController(
        text: maxD > 0 ? '' : '0',
      );
    }
    setState(() {
      _venda = v;
      _carregando = false;
      _erroCarregamento = null;
    });
  }

  @override
  void dispose() {
    _motivoController.dispose();
    _obsFinanceiraController.dispose();
    for (final c in _qtdDevolucaoPorItem.values) {
      c.dispose();
    }
    for (final l in _linhasTroca) {
      l.dispose();
    }
    super.dispose();
  }

  String _formatarMoeda(double v) => 'R\$ ${_currency.format(v)}';

  double _precoProdutoTipo(Produto p, String tipo) {
    switch (tipo) {
      case 'preco2':
        return p.preco2 > 0 ? p.preco2 : p.precoVenda;
      case 'preco3':
        return p.preco3 > 0 ? p.preco3 : p.precoVenda;
      case 'preco1':
      default:
        return p.preco1 > 0 ? p.preco1 : p.precoVenda;
    }
  }

  int _parseQtd(String t) {
    final n = int.tryParse(t.trim());
    return n == null || n < 0 ? 0 : n;
  }

  Future<(bool ok, String usuario)> _autorizar() async {
    if (widget.podeRegistrarSemSenha) {
      return (true, widget.usuarioAtual);
    }
    final loginController = TextEditingController();
    final senhaController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Autorizacao'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Usuario com permissao (admin, financeiro ou manutencao de caixa).',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: loginController,
                decoration: const InputDecoration(labelText: 'Login'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: senhaController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) {
      loginController.dispose();
      senhaController.dispose();
      return (false, '');
    }
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    loginController.dispose();
    senhaController.dispose();
    final u = await _usuarioRepository.autenticar(login, senha);
    final autorizado =
        u != null && UsuarioPermissaoHelper.podeCancelarVendas(u);
    if (!autorizado) return (false, '');
    return (true, u.login);
  }

  Future<void> _confirmar() async {
    final v = _venda;
    if (v == null) return;
    final motivo = _motivoController.text.trim();
    if (motivo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o motivo.')),
      );
      return;
    }

    final entradas = <LinhaDevolucaoEntradaInput>[];
    for (final item in v.itens) {
      final ctl = _qtdDevolucaoPorItem[item.id];
      if (ctl == null) continue;
      final q = _parseQtd(ctl.text);
      if (q <= 0) continue;
      final maxD = item.quantidade - item.quantidadeDevolvida;
      if (q > maxD) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Quantidade invalida para "${item.nomeProduto}" (max. $maxD).',
            ),
          ),
        );
        return;
      }
      entradas.add(
        LinhaDevolucaoEntradaInput(itemVendaId: item.id, quantidade: q),
      );
    }
    if (entradas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe quantidade em ao menos um item devolvido.'),
        ),
      );
      return;
    }

    final saidas = <LinhaTrocaSaidaInput>[];
    if (_modoTroca) {
      for (final linha in _linhasTroca) {
        if (linha.quantidade <= 0) continue;
        final pu = _precoProdutoTipo(linha.produto, linha.precoTipo);
        final custo = linha.produto.precoCusto;
        saidas.add(
          LinhaTrocaSaidaInput(
            produtoId: linha.produto.id,
            quantidade: linha.quantidade,
            precoUnitario: pu,
            precoTipo: linha.precoTipo,
            precoCustoUnitario: custo,
          ),
        );
      }
      if (saidas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Em troca, adicione ao menos um produto de saida.'),
          ),
        );
        return;
      }
    }

    final auth = await _autorizar();
    if (!mounted || !auth.$1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Operacao nao autorizada.')),
        );
      }
      return;
    }

    try {
      widget.vendaRepository.registrarDevolucaoOuTroca(
        vendaOrigemId: v.id,
        tipo: _modoTroca ? 'troca' : 'devolucao',
        motivo: motivo,
        observacaoFinanceira: _obsFinanceiraController.text,
        registradoPor: auth.$2,
        entradas: entradas,
        saidasTroca: saidas,
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registro salvo com sucesso.')),
    );
    Navigator.pop(context, true);
  }

  Future<void> _abrirBuscaProdutoTroca() async {
    final busca = TextEditingController();
    List<Produto> resultados = widget.produtoRepository.pesquisarPadraoPdv(
      '',
      limite: 50,
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            void pesquisar() {
              resultados = widget.produtoRepository.pesquisarPadraoPdv(
                busca.text,
                limite: 50,
              );
              setD(() {});
            }

            return AlertDialog(
              title: const Text('Produto na troca'),
              content: SizedBox(
                width: 520,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      controller: busca,
                      autofocus: true,
                      decoration: produtoBuscaInputDecoration(isDense: true),
                      onChanged: (_) => pesquisar(),
                      onSubmitted: (_) => pesquisar(),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: resultados.length,
                        itemBuilder: (_, i) {
                          final p = resultados[i];
                          return ListTile(
                            title: Text(p.nome),
                            subtitle: Text(
                              _formatarMoeda(
                                _precoProdutoTipo(p, 'preco1'),
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(() {
                                _linhasTroca.add(
                                  _LinhaTrocaEdit(produto: p),
                                );
                              });
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
    busca.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_erroCarregamento != null || _venda == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Devolucao / troca')),
        body: Center(child: Text(_erroCarregamento ?? 'Erro')),
      );
    }

    final v = _venda!;
    final registros =
        widget.vendaRepository.listarRegistrosDevolucaoPorVenda(v.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devolucao / troca'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            v.numeroOrcamento > 0
                ? 'Venda ${v.numeroOrcamento} (id ${v.id})'
                : 'Venda ${v.id}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (registros.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${registros.length} registro(s) anterior(es) nesta venda.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Devolucao')),
              ButtonSegment(value: true, label: Text('Troca')),
            ],
            selected: {_modoTroca},
            onSelectionChanged: (s) {
              setState(() => _modoTroca = s.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _modoTroca
                ? 'Itens voltam ao estoque; em seguida os produtos da troca saem do estoque.'
                : 'Apenas entrada de mercadoria devolvida no estoque.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text(
            'Itens da venda (quantidade a devolver)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...v.itens.map((ItemVenda item) {
            final maxD = item.quantidade - item.quantidadeDevolvida;
            final ctl = _qtdDevolucaoPorItem[item.id]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.nomeProduto,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Vendido: ${item.quantidade} · Ja devolvido: ${item.quantidadeDevolvida} · Max: $maxD',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: ctl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Qtd',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_modoTroca) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'Produtos da troca (saida)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _abrirBuscaProdutoTroca,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_linhasTroca.isEmpty)
              Text(
                'Nenhum produto adicionado.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ..._linhasTroca.asMap().entries.map((e) {
                final i = e.key;
                final linha = e.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(linha.produto.nome),
                    subtitle: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 88,
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Qtd',
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            controller: linha.qtdController,
                          ),
                        ),
                        DropdownButton<String>(
                          value: linha.precoTipo,
                          items: const [
                            DropdownMenuItem(
                              value: 'preco1',
                              child: Text('A prazo'),
                            ),
                            DropdownMenuItem(
                              value: 'preco2',
                              child: Text('A vista'),
                            ),
                            DropdownMenuItem(
                              value: 'preco3',
                              child: Text('Atacado'),
                            ),
                          ],
                          onChanged: (nv) {
                            if (nv == null) return;
                            setState(() => linha.precoTipo = nv);
                          },
                        ),
                        Text(
                          _formatarMoeda(
                            _precoProdutoTipo(
                              linha.produto,
                              linha.precoTipo,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        setState(() {
                          _linhasTroca.removeAt(i).dispose();
                        });
                      },
                    ),
                  ),
                );
              }),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _motivoController,
            decoration: const InputDecoration(
              labelText: 'Motivo (obrigatorio)',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _obsFinanceiraController,
            decoration: const InputDecoration(
              labelText: 'Observacao financeira (opcional)',
              hintText:
                  'Ex.: R\$ devolvido em dinheiro, cliente pagou diferenca...',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _confirmar,
            icon: const Icon(Icons.check),
            label: const Text('Registrar'),
          ),
        ],
      ),
    );
  }
}
