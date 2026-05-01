import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/funcionario_repository.dart';
import '../main.dart';
import '../model/funcionario.dart';

class FuncionariosPage extends StatefulWidget {
  const FuncionariosPage({super.key, required this.funcionarioRepository});

  final FuncionarioRepository funcionarioRepository;

  @override
  State<FuncionariosPage> createState() => _FuncionariosPageState();
}

class _FuncionariosPageState extends State<FuncionariosPage> {
  final _codigoController = TextEditingController();
  final _nomeController = TextEditingController();
  final _cargoController = TextEditingController();
  final _cpfController = TextEditingController();
  final _rgController = TextEditingController();
  final _pisController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _cepController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _numeroController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _ufController = TextEditingController();
  final _salarioController = TextEditingController();
  final _descontoController = TextEditingController();
  final _adiantamentoController = TextEditingController();
  final _diaPagamentoController = TextEditingController(text: '5');
  final _historicoFinanceiroController = TextEditingController();
  final _observacoesController = TextEditingController();
  final _pesquisaController = TextEditingController();
  final _filtroListaController = TextEditingController();
  final _scrollController = ScrollController();

  int? _funcionarioEmEdicaoId;
  bool _ativo = true;
  DateTime _dataNascimento = DateTime(2000, 1, 1);
  DateTime _dataAdmissao = DateTime.now();
  String _status = '';
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  List<_ValeRegistro> _vales = [];

  @override
  void initState() {
    super.initState();
    _preencherCodigoAutomaticoSeNovo();
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _nomeController.dispose();
    _cargoController.dispose();
    _cpfController.dispose();
    _rgController.dispose();
    _pisController.dispose();
    _telefoneController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _cepController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _ufController.dispose();
    _salarioController.dispose();
    _descontoController.dispose();
    _adiantamentoController.dispose();
    _diaPagamentoController.dispose();
    _historicoFinanceiroController.dispose();
    _observacoesController.dispose();
    _pesquisaController.dispose();
    _filtroListaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _preencherCodigoAutomaticoSeNovo() {
    if (_funcionarioEmEdicaoId != null) return;
    if (_codigoController.text.trim().isNotEmpty) return;
    _codigoController.text = widget.funcionarioRepository.proximoCodigoInterno();
  }

  Future<void> _selecionarDataNascimento() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataNascimento,
      firstDate: DateTime(1950, 1, 1),
      lastDate: DateTime.now(),
    );
    if (escolhida == null) return;
    setState(() => _dataNascimento = escolhida);
  }

  Future<void> _selecionarDataAdmissao() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataAdmissao,
      firstDate: DateTime(1950, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (escolhida == null) return;
    setState(() => _dataAdmissao = escolhida);
  }

  void _limparFormulario() {
    setState(() {
      _codigoController.clear();
      _nomeController.clear();
      _cargoController.clear();
      _cpfController.clear();
      _rgController.clear();
      _pisController.clear();
      _telefoneController.clear();
      _whatsappController.clear();
      _emailController.clear();
      _cepController.clear();
      _enderecoController.clear();
      _numeroController.clear();
      _bairroController.clear();
      _cidadeController.clear();
      _ufController.clear();
      _salarioController.clear();
      _descontoController.clear();
      _adiantamentoController.clear();
      _diaPagamentoController.text = '5';
      _historicoFinanceiroController.clear();
      _vales = [];
      _observacoesController.clear();
      _dataNascimento = DateTime(2000, 1, 1);
      _dataAdmissao = DateTime.now();
      _ativo = true;
      _funcionarioEmEdicaoId = null;
      _status = '';
      _preencherCodigoAutomaticoSeNovo();
    });
  }

  double _parseBr(String text) {
    final n = text.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(n) ?? 0;
  }

  void _salvar() {
    final codigo = _codigoController.text.trim().isEmpty
        ? widget.funcionarioRepository.proximoCodigoInterno()
        : _codigoController.text.trim();
    final nome = _nomeController.text.trim();
    if (codigo.isEmpty || nome.isEmpty) {
      setState(() => _status = 'Informe codigo e nome do funcionario.');
      return;
    }
    final idAtual = _funcionarioEmEdicaoId ?? 0;
    if (widget.funcionarioRepository.existeCodigoParaOutro(
      codigoNormalizado: codigo,
      ignorarId: idAtual,
    )) {
      setState(() => _status = 'Ja existe outro funcionario com este codigo.');
      return;
    }

    final dia = int.tryParse(_diaPagamentoController.text.trim()) ?? 5;
    if (dia < 1 || dia > 31) {
      setState(() => _status = 'Dia de pagamento deve ser entre 1 e 31.');
      return;
    }
    final existente = _funcionarioEmEdicaoId == null
        ? null
        : widget.funcionarioRepository.obterPorId(_funcionarioEmEdicaoId!);
    final funcionario = Funcionario(
      id: existente?.id ?? 0,
      codigoInterno: codigo,
      nomeCompleto: nome,
      cargo: _cargoController.text.trim(),
      cpf: _cpfController.text.trim(),
      rg: _rgController.text.trim(),
      pis: _pisController.text.trim(),
      telefone: _telefoneController.text.trim(),
      whatsapp: _whatsappController.text.trim(),
      email: _emailController.text.trim(),
      endereco: _enderecoController.text.trim(),
      numero: _numeroController.text.trim(),
      bairro: _bairroController.text.trim(),
      cidade: _cidadeController.text.trim(),
      uf: _ufController.text.trim().toUpperCase(),
      cep: _cepController.text.trim(),
      observacoes: _observacoesController.text.trim(),
      salario: _parseBr(_salarioController.text),
      descontoAtual: _parseBr(_descontoController.text),
      adiantamentoAtual: _parseBr(_adiantamentoController.text),
      historicoFinanceiro: _historicoFinanceiroController.text.trim(),
      valesJson: jsonEncode(_vales.map((v) => v.toMap()).toList()),
      diaPagamento: dia,
      ativo: _ativo,
      dataNascimento: _dataNascimento,
      dataAdmissao: _dataAdmissao,
      criadoEm: existente?.criadoEm,
    );
    final id = widget.funcionarioRepository.salvar(funcionario);
    setState(() {
      _funcionarioEmEdicaoId = id;
      _codigoController.text = codigo;
      _status = 'Funcionario salvo com sucesso.';
    });
  }

  void _editar(Funcionario f) {
    setState(() {
      _funcionarioEmEdicaoId = f.id;
      _codigoController.text = f.codigoInterno;
      _nomeController.text = f.nomeCompleto;
      _cargoController.text = f.cargo;
      _cpfController.text = f.cpf;
      _rgController.text = f.rg;
      _pisController.text = f.pis;
      _telefoneController.text = f.telefone;
      _whatsappController.text = f.whatsapp;
      _emailController.text = f.email;
      _cepController.text = f.cep;
      _enderecoController.text = f.endereco;
      _numeroController.text = f.numero;
      _bairroController.text = f.bairro;
      _cidadeController.text = f.cidade;
      _ufController.text = f.uf;
      _salarioController.text = f.salario == 0
          ? ''
          : f.salario.toStringAsFixed(2).replaceAll('.', ',');
      _descontoController.text = f.descontoAtual == 0
          ? ''
          : f.descontoAtual.toStringAsFixed(2).replaceAll('.', ',');
      _adiantamentoController.text = f.adiantamentoAtual == 0
          ? ''
          : f.adiantamentoAtual.toStringAsFixed(2).replaceAll('.', ',');
      _diaPagamentoController.text = f.diaPagamento.toString();
      _historicoFinanceiroController.text = f.historicoFinanceiro;
      _vales = _parseValesJson(f.valesJson);
      _observacoesController.text = f.observacoes;
      _dataNascimento = f.dataNascimento.toLocal();
      _dataAdmissao = f.dataAdmissao.toLocal();
      _ativo = f.ativo;
      _status = 'Editando: ${f.nomeCompleto}';
    });
  }

  List<_ValeRegistro> _parseValesJson(String raw) {
    if (raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => _ValeRegistro.fromMap(e.cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => b.data.compareTo(a.data));
    } catch (_) {
      return [];
    }
  }

  double _totalVales() => _vales.fold<double>(0, (acc, v) => acc + v.valor);

  Future<void> _incluirVale() async {
    final valorController = TextEditingController();
    final obsController = TextEditingController();
    DateTime data = DateTime.now();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Incluir vale'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final escolhida = await showDatePicker(
                          context: context,
                          initialDate: data,
                          firstDate: DateTime(2000, 1, 1),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (escolhida == null) return;
                        setDialogState(() => data = escolhida);
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text('Data: ${_dateFormat.format(data)}'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: valorController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Valor do vale (R\$)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: obsController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Observacao (opcional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Incluir'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmado != true) return;
    final valor = _parseBr(valorController.text);
    if (valor <= 0) {
      setState(() => _status = 'Informe um valor de vale maior que zero.');
      return;
    }
    setState(() {
      _vales.insert(
        0,
        _ValeRegistro(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          data: data,
          valor: valor,
          observacao: obsController.text.trim(),
        ),
      );
      _adiantamentoController.text = _totalVales().toStringAsFixed(2).replaceAll(
        '.',
        ',',
      );
      _status = 'Vale incluido. Clique em Salvar para gravar.';
    });
  }

  void _removerVale(_ValeRegistro vale) {
    setState(() {
      _vales.removeWhere((v) => v.id == vale.id);
      _adiantamentoController.text = _totalVales().toStringAsFixed(2).replaceAll(
        '.',
        ',',
      );
      _status = 'Vale removido. Clique em Salvar para gravar.';
    });
  }

  Future<void> _confirmarRemocao(Funcionario f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover funcionario'),
        content: Text('Remover "${f.nomeCompleto}" da lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.funcionarioRepository.remover(f.id);
    if (_funcionarioEmEdicaoId == f.id) {
      _limparFormulario();
    }
    setState(() => _status = 'Remocao concluida com sucesso.');
  }

  Future<void> _abrirPesquisaFuncionario() async {
    final pesquisaController = TextEditingController();
    final resultadosScrollController = ScrollController();
    final pesquisaFocusNode = FocusNode();
    List<Funcionario> resultados = widget.funcionarioRepository.pesquisar('');
    int indiceSelecionado = resultados.isEmpty ? -1 : 0;

    final funcionarioSelecionado = await showDialog<Funcionario>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            TextSpan spanComDestaque(
              String texto,
              String termo,
              TextStyle estiloBase,
            ) {
              final busca = termo.trim().toLowerCase();
              if (busca.isEmpty) {
                return TextSpan(text: texto, style: estiloBase);
              }
              final textoMinusculo = texto.toLowerCase();
              final spans = <TextSpan>[];
              var cursor = 0;
              while (cursor < texto.length) {
                final indice = textoMinusculo.indexOf(busca, cursor);
                if (indice < 0) {
                  spans.add(TextSpan(text: texto.substring(cursor)));
                  break;
                }
                if (indice > cursor) {
                  spans.add(TextSpan(text: texto.substring(cursor, indice)));
                }
                spans.add(
                  TextSpan(
                    text: texto.substring(indice, indice + busca.length),
                    style: estiloBase.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
                cursor = indice + busca.length;
              }
              return TextSpan(style: estiloBase, children: spans);
            }

            void rolarParaIndiceSelecionado() {
              if (!resultadosScrollController.hasClients || indiceSelecionado < 0) {
                return;
              }
              const alturaEstimadaLinha = 64.0;
              final posicaoDesejada = (indiceSelecionado * alturaEstimadaLinha)
                  .clamp(0.0, resultadosScrollController.position.maxScrollExtent);
              resultadosScrollController.animateTo(
                posicaoDesejada,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
              );
            }

            return Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent || resultados.isEmpty) {
                  return KeyEventResult.ignored;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  setDialogState(() {
                    indiceSelecionado = math.min(
                      indiceSelecionado + 1,
                      resultados.length - 1,
                    );
                  });
                  rolarParaIndiceSelecionado();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  setDialogState(() {
                    indiceSelecionado = math.max(indiceSelecionado - 1, 0);
                  });
                  rolarParaIndiceSelecionado();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                  final indice = indiceSelecionado >= 0 ? indiceSelecionado : 0;
                  Navigator.pop(context, resultados[indice]);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.pop(context);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: AlertDialog(
                title: const Text('Pesquisar funcionario'),
                content: SizedBox(
                  width: 760,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: pesquisaController,
                        focusNode: pesquisaFocusNode,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Nome, codigo, cargo, CPF, telefone...',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            resultados = widget.funcionarioRepository.pesquisar(value);
                            indiceSelecionado = resultados.isEmpty ? -1 : 0;
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (resultadosScrollController.hasClients) {
                              resultadosScrollController.jumpTo(0);
                            }
                            if (pesquisaFocusNode.canRequestFocus) {
                              pesquisaFocusNode.requestFocus();
                            }
                          });
                        },
                        onSubmitted: (_) {
                          if (resultados.isEmpty) return;
                          final indice = indiceSelecionado >= 0 ? indiceSelecionado : 0;
                          Navigator.pop(context, resultados[indice]);
                        },
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: 220,
                          maxHeight: MediaQuery.of(context).size.height * 0.58,
                        ),
                        child: resultados.isEmpty
                            ? const Center(child: Text('Nenhum funcionario encontrado.'))
                            : ListView.builder(
                                controller: resultadosScrollController,
                                shrinkWrap: true,
                                itemCount: resultados.length,
                                itemBuilder: (context, index) {
                                  final f = resultados[index];
                                  final consulta = pesquisaController.text.trim();
                                  final estiloTitulo = Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w600) ??
                                      const TextStyle(fontWeight: FontWeight.w600);
                                  final estiloSubtitulo =
                                      Theme.of(context).textTheme.bodyMedium ??
                                          const TextStyle();
                                  final selecionado = index == indiceSelecionado;
                                  return MouseRegion(
                                    onEnter: (_) {
                                      if (indiceSelecionado == index) return;
                                      setDialogState(() => indiceSelecionado = index);
                                    },
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      selected: selecionado,
                                      selectedTileColor: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.08),
                                      title: RichText(
                                        text: spanComDestaque(
                                          f.nomeCompleto,
                                          consulta,
                                          estiloTitulo,
                                        ),
                                      ),
                                      subtitle: RichText(
                                        text: spanComDestaque(
                                          'Codigo: ${f.codigoInterno} | Cargo: ${f.cargo.isEmpty ? '-' : f.cargo}',
                                          consulta,
                                          estiloSubtitulo,
                                        ),
                                      ),
                                      onTap: () => Navigator.pop(context, f),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    pesquisaController.dispose();
    resultadosScrollController.dispose();
    pesquisaFocusNode.dispose();

    if (!mounted || funcionarioSelecionado == null) return;
    _editar(funcionarioSelecionado);
  }

  List<Funcionario> _funcionariosPorCadastro() {
    final lista = widget.funcionarioRepository.listarTodos();
    lista.sort((a, b) => a.id.compareTo(b.id));
    return lista;
  }

  int _indiceAtualFuncionario(List<Funcionario> lista) {
    final id = _funcionarioEmEdicaoId;
    if (id == null) return -1;
    return lista.indexWhere((f) => f.id == id);
  }

  void _abrirFuncionarioPorIndice(int indice) {
    final lista = _funcionariosPorCadastro();
    if (lista.isEmpty) {
      setState(() => _status = 'Nao ha funcionarios cadastrados para navegar.');
      return;
    }
    final idx = indice.clamp(0, lista.length - 1);
    _editar(lista[idx]);
  }

  void _irPrimeiroFuncionario() => _abrirFuncionarioPorIndice(0);

  void _irUltimoFuncionario() {
    final lista = _funcionariosPorCadastro();
    if (lista.isEmpty) {
      setState(() => _status = 'Nao ha funcionarios cadastrados para navegar.');
      return;
    }
    _abrirFuncionarioPorIndice(lista.length - 1);
  }

  void _irFuncionarioAnterior() {
    final lista = _funcionariosPorCadastro();
    if (lista.isEmpty) {
      setState(() => _status = 'Nao ha funcionarios cadastrados para navegar.');
      return;
    }
    final idxAtual = _indiceAtualFuncionario(lista);
    if (idxAtual <= 0) {
      _abrirFuncionarioPorIndice(0);
      return;
    }
    _abrirFuncionarioPorIndice(idxAtual - 1);
  }

  void _irProximoFuncionario() {
    final lista = _funcionariosPorCadastro();
    if (lista.isEmpty) {
      setState(() => _status = 'Nao ha funcionarios cadastrados para navegar.');
      return;
    }
    final idxAtual = _indiceAtualFuncionario(lista);
    if (idxAtual < 0) {
      _abrirFuncionarioPorIndice(0);
      return;
    }
    if (idxAtual >= lista.length - 1) {
      _abrirFuncionarioPorIndice(lista.length - 1);
      return;
    }
    _abrirFuncionarioPorIndice(idxAtual + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lista = widget.funcionarioRepository.pesquisar(_filtroListaController.text);
    final emEdicao = _funcionarioEmEdicaoId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro de funcionarios')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RawScrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 10,
          radius: const Radius.circular(8),
          child: ListView(
            controller: _scrollController,
            children: [
              if (_status.isNotEmpty) ...[
                _buildStatusBanner(context, _status),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _irPrimeiroFuncionario,
                      child: const Text('|< Primeiro'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _irFuncionarioAnterior,
                      child: const Text('< Anterior'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _irProximoFuncionario,
                      child: const Text('Proximo >'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _irUltimoFuncionario,
                      child: const Text('Ultimo >|'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _abrirPesquisaFuncionario,
                  icon: const Icon(Icons.search),
                  label: const Text('Pesquisar funcionario'),
                ),
              ),
              const SizedBox(height: 10),
              _buildSectionCard(
                context: context,
                title: 'Dados principais',
                icon: Icons.badge_outlined,
                children: [
                  TextField(
                    controller: _codigoController,
                    decoration: const InputDecoration(
                      labelText: 'Codigo interno',
                      hintText: 'Ex.: F01',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nomeController,
                    decoration: const InputDecoration(labelText: 'Nome completo'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cargoController,
                    decoration: const InputDecoration(labelText: 'Cargo'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selecionarDataNascimento,
                          icon: const Icon(Icons.cake_outlined),
                          label: Text(
                            'Nascimento: ${_dateFormat.format(_dataNascimento)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selecionarDataAdmissao,
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text(
                            'Admissao: ${_dateFormat.format(_dataAdmissao)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Funcionario ativo'),
                    value: _ativo,
                    onChanged: (v) => setState(() => _ativo = v),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildSectionCard(
                context: context,
                title: 'Documentacao',
                icon: Icons.assignment_ind_outlined,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cpfController,
                          decoration: const InputDecoration(labelText: 'CPF'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _rgController,
                          decoration: const InputDecoration(labelText: 'RG'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pisController,
                    decoration: const InputDecoration(labelText: 'PIS'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildSectionCard(
                context: context,
                title: 'Contato',
                icon: Icons.phone_outlined,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _telefoneController,
                          decoration: const InputDecoration(labelText: 'Telefone'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _whatsappController,
                          decoration: const InputDecoration(labelText: 'WhatsApp'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildSectionCard(
                context: context,
                title: 'Endereco',
                icon: Icons.location_on_outlined,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cepController,
                          decoration: const InputDecoration(labelText: 'CEP'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _enderecoController,
                          decoration: const InputDecoration(labelText: 'Endereco'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _numeroController,
                          decoration: const InputDecoration(labelText: 'Numero'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _bairroController,
                          decoration: const InputDecoration(labelText: 'Bairro'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _cidadeController,
                          decoration: const InputDecoration(labelText: 'Cidade'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _ufController,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: const InputDecoration(labelText: 'UF'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildSectionCard(
                context: context,
                title: 'Financeiro e observacoes',
                icon: Icons.payments_outlined,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _salarioController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(labelText: 'Salario (R\$)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _diaPagamentoController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Dia pagamento (1-31)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _descontoController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Desconto atual (R\$)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _adiantamentoController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Adiantamento atual (R\$)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _historicoFinanceiroController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Historico financeiro (datas e observacoes)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _observacoesController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Observacoes'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _incluirVale,
                          icon: const Icon(Icons.add_card_outlined),
                          label: const Text('Incluir vale'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Total vales: R\$ ${_totalVales().toStringAsFixed(2).replaceAll('.', ',')}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_vales.isEmpty)
                    const Text('Nenhum vale lancado.')
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _vales.length,
                        itemBuilder: (context, index) {
                          final vale = _vales[index];
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            title: Text(
                              '${_dateFormat.format(vale.data)} - R\$ ${vale.valor.toStringAsFixed(2).replaceAll('.', ',')}',
                            ),
                            subtitle: Text(
                              vale.observacao.isEmpty
                                  ? 'Sem observacao'
                                  : vale.observacao,
                            ),
                            trailing: IconButton(
                              tooltip: 'Remover vale',
                              onPressed: () => _removerVale(vale),
                              icon: Icon(
                                Icons.delete_outline,
                                color: theme.colorScheme.error,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _salvar,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(emEdicao ? 'Atualizar' : 'Salvar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _limparFormulario,
                    icon: const Icon(Icons.add),
                    label: const Text('Novo'),
                  ),
                  if (emEdicao) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        final atualId = _funcionarioEmEdicaoId;
                        if (atualId == null) return;
                        final atual = widget.funcionarioRepository.obterPorId(atualId);
                        if (atual == null) return;
                        _confirmarRemocao(atual);
                      },
                      icon: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                      ),
                      label: Text(
                        'Apagar',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Funcionarios cadastrados (${lista.length})',
                  style: theme.textTheme.titleMedium,
                ),
                initiallyExpanded: false,
                children: [
                  TextField(
                    controller: _filtroListaController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Filtrar lista rapida',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (lista.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Center(child: Text('Nenhum funcionario cadastrado.')),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: lista.length,
                        itemBuilder: (context, index) {
                          final f = lista[index];
                          return Card(
                            child: ListTile(
                              dense: true,
                              title: Text(f.nomeCompleto),
                              subtitle: Text(
                                '${f.codigoInterno} · ${f.cargo.isEmpty ? 'Sem cargo' : f.cargo}'
                                '${f.ativo ? '' : ' · inativo'}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Editar',
                                    onPressed: () => _editar(f),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Remover',
                                    onPressed: () => _confirmarRemocao(f),
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _editar(f),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context, String message) {
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>();
    final sucesso = message.toLowerCase().contains('sucesso');
    final bg = sucesso
        ? semantic?.successBg ?? const Color(0xFFEAF8EF)
        : semantic?.errorBg ?? const Color(0xFFFDECEC);
    final border = sucesso
        ? semantic?.successBorder ?? const Color(0xFF8FD1A8)
        : semantic?.errorBorder ?? const Color(0xFFF1A3A3);
    final fg = sucesso
        ? semantic?.successFg ?? const Color(0xFF166534)
        : semantic?.errorFg ?? const Color(0xFF9B1C1C);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(sucesso ? Icons.check_circle_outline : Icons.info_outline, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ValeRegistro {
  const _ValeRegistro({
    required this.id,
    required this.data,
    required this.valor,
    this.observacao = '',
  });

  final String id;
  final DateTime data;
  final double valor;
  final String observacao;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'data': data.toIso8601String(),
      'valor': valor,
      'observacao': observacao,
    };
  }

  factory _ValeRegistro.fromMap(Map<String, dynamic> map) {
    return _ValeRegistro(
      id: map['id'] as String? ?? '',
      data: DateTime.tryParse(map['data'] as String? ?? '') ?? DateTime.now(),
      valor: (map['valor'] as num?)?.toDouble() ?? 0,
      observacao: map['observacao'] as String? ?? '',
    );
  }
}
