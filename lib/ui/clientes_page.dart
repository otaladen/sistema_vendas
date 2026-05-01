import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../data/cliente_repository.dart';
import '../data/mensageria_repository.dart';
import '../data/venda_repository.dart';
import '../model/cliente.dart';
import '../model/mensagem_log.dart';
import '../model/mensagem_template.dart';
import '../model/venda.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({
    super.key,
    required this.clienteRepository,
    required this.vendaRepository,
    this.retornarClienteAoSalvar = false,
  });

  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final bool retornarClienteAoSalvar;

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _nomeRazaoController = TextEditingController();
  final _nomeFantasiaController = TextEditingController();
  final _documentoController = TextEditingController();
  final _inscricaoController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _cepController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _numeroController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _ufController = TextEditingController();
  final _referenciaController = TextEditingController();
  final _limiteController = TextEditingController();
  final _observacoesController = TextEditingController();

  int? _clienteEmEdicaoId;
  String _tipoPessoa = 'fisica';
  bool _ativo = true;
  String _status = '';
  late final _cpfCnpjFormatter = _CpfCnpjInputFormatter();
  late final _telefoneFormatter = _TelefoneInputFormatter();
  late final _cepFormatter = _CepInputFormatter();
  late final _emailFormatter = _EmailInputFormatter();
  late final _limiteCreditoFormatter = _MoedaInputFormatter();
  final ScrollController _scrollController = ScrollController();
  final MensageriaRepository _mensageriaRepository = MensageriaRepository();
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  String _periodoHistorico = 'todo';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nomeRazaoController.dispose();
    _nomeFantasiaController.dispose();
    _documentoController.dispose();
    _inscricaoController.dispose();
    _telefoneController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _cepController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _ufController.dispose();
    _referenciaController.dispose();
    _limiteController.dispose();
    _observacoesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _abrirPesquisaCliente() async {
    final clientesBase = widget.clienteRepository.listarTodos();
    final pesquisaController = TextEditingController();
    final resultadosScrollController = ScrollController();
    final pesquisaFocusNode = FocusNode();
    List<Cliente> resultados = clientesBase;
    int indiceSelecionado = resultados.isEmpty ? -1 : 0;

    final clienteSelecionado = await showDialog<Cliente>(
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
              final posicaoDesejada = (indiceSelecionado * alturaEstimadaLinha).clamp(
                0.0,
                resultadosScrollController.position.maxScrollExtent,
              );
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
                title: const Text('Pesquisar cliente'),
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
                          labelText: 'Nome, documento, telefone, cidade...',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          final termo = value.trim().toLowerCase();
                          final termoNumerico = _somenteDigitos(value);
                          setDialogState(() {
                            resultados = clientesBase.where((cliente) {
                              final campos = [
                                cliente.nomeRazao,
                                cliente.nomeFantasia,
                                cliente.documento,
                                cliente.telefone,
                                cliente.whatsapp,
                                cliente.email,
                                cliente.cidade,
                              ].map((e) => e.toLowerCase());
                              final matchTexto = campos.any((campo) => campo.contains(termo));
                              if (matchTexto) return true;
                              if (termoNumerico.isEmpty) return false;
                              final camposNumericos = [
                                cliente.documento,
                                cliente.telefone,
                                cliente.whatsapp,
                                cliente.cep,
                              ].map(_somenteDigitos);
                              return camposNumericos.any(
                                (campoNumerico) => campoNumerico.contains(termoNumerico),
                              );
                            }).toList();
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
                          if (resultados.isEmpty) {
                            return;
                          }
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
                            ? const Center(child: Text('Nenhum cliente encontrado.'))
                            : ListView.builder(
                                controller: resultadosScrollController,
                                shrinkWrap: true,
                                itemCount: resultados.length,
                                itemBuilder: (context, index) {
                                  final cliente = resultados[index];
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
                                      if (indiceSelecionado == index) {
                                        return;
                                      }
                                      setDialogState(() {
                                        indiceSelecionado = index;
                                      });
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
                                          .withOpacity(0.08),
                                      title: RichText(
                                        text: spanComDestaque(
                                          cliente.nomeRazao,
                                          consulta,
                                          estiloTitulo,
                                        ),
                                      ),
                                      subtitle: RichText(
                                        text: spanComDestaque(
                                          '${cliente.tipoPessoa == 'fisica' ? 'CPF' : 'CNPJ'}: '
                                          '${cliente.documento.isEmpty ? '-' : cliente.documento} | '
                                          'Cidade: ${cliente.cidade.isEmpty ? '-' : cliente.cidade}',
                                          consulta,
                                          estiloSubtitulo,
                                        ),
                                      ),
                                      onTap: () => Navigator.pop(context, cliente),
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

    if (clienteSelecionado != null) {
      _editarCliente(clienteSelecionado);
    }
  }

  void _limparFormulario() {
    setState(() {
      _nomeRazaoController.clear();
      _nomeFantasiaController.clear();
      _documentoController.clear();
      _inscricaoController.clear();
      _telefoneController.clear();
      _whatsappController.clear();
      _emailController.clear();
      _cepController.clear();
      _enderecoController.clear();
      _numeroController.clear();
      _bairroController.clear();
      _cidadeController.clear();
      _ufController.clear();
      _referenciaController.clear();
      _limiteController.clear();
      _observacoesController.clear();
      _tipoPessoa = 'fisica';
      _ativo = true;
      _clienteEmEdicaoId = null;
    });
  }

  void _salvarCliente() {
    final nomeRazao = _nomeRazaoController.text.trim();
    if (nomeRazao.isEmpty) {
      setState(() {
        _status = 'Nome/Razao social e obrigatorio.';
      });
      return;
    }
    final limiteCredito = double.tryParse(
          _limiteController.text.trim().replaceAll('.', '').replaceAll(',', '.'),
        ) ??
        0;
    final existente = _clienteEmEdicaoId == null
        ? null
        : widget.clienteRepository.obterPorId(_clienteEmEdicaoId!);

    final cliente = Cliente(
      id: existente?.id ?? 0,
      tipoPessoa: _tipoPessoa,
      nomeRazao: nomeRazao,
      nomeFantasia: _nomeFantasiaController.text.trim(),
      documento: _somenteDigitos(_documentoController.text),
      inscricaoEstadual: _tipoPessoa == 'juridica'
          ? _inscricaoController.text.trim().toUpperCase()
          : '',
      telefone: _somenteDigitos(_telefoneController.text),
      whatsapp: _somenteDigitos(_whatsappController.text),
      email: _emailController.text.trim().toLowerCase(),
      cep: _somenteDigitos(_cepController.text),
      endereco: _enderecoController.text.trim(),
      numero: _numeroController.text.trim(),
      bairro: _bairroController.text.trim(),
      cidade: _cidadeController.text.trim(),
      uf: _ufController.text.trim().toUpperCase(),
      referencia: _referenciaController.text.trim(),
      limiteCredito: limiteCredito,
      observacoes: _observacoesController.text.trim(),
      ativo: _ativo,
      criadoEm: existente?.criadoEm,
    );
    final clienteId = widget.clienteRepository.salvar(cliente);
    final clienteSalvo = widget.clienteRepository.obterPorId(clienteId);
    if (widget.retornarClienteAoSalvar && clienteSalvo != null) {
      Navigator.pop(context, clienteSalvo);
      return;
    }
    _limparFormulario();
    setState(() {
      _status = 'Cliente salvo com sucesso.';
    });
  }

  String _somenteDigitos(String valor) {
    return valor.replaceAll(RegExp(r'\D'), '');
  }

  void _editarCliente(Cliente c) {
    setState(() {
      _clienteEmEdicaoId = c.id;
      _tipoPessoa = c.tipoPessoa;
      _nomeRazaoController.text = c.nomeRazao;
      _nomeFantasiaController.text = c.nomeFantasia;
      _documentoController.text = c.documento;
      _inscricaoController.text = c.inscricaoEstadual;
      _telefoneController.text = c.telefone;
      _whatsappController.text = c.whatsapp;
      _emailController.text = c.email;
      _cepController.text = c.cep;
      _enderecoController.text = c.endereco;
      _numeroController.text = c.numero;
      _bairroController.text = c.bairro;
      _cidadeController.text = c.cidade;
      _ufController.text = c.uf;
      _referenciaController.text = c.referencia;
      _limiteController.text = c.limiteCredito.toStringAsFixed(2).replaceAll('.', ',');
      _observacoesController.text = c.observacoes;
      _ativo = c.ativo;
      _status = 'Editando cliente: ${c.nomeRazao}';
    });
    _padronizarMascarasCamposCliente();
  }

  List<Cliente> _clientesOrdenadosPorCadastro() {
    final clientes = widget.clienteRepository.listarTodos();
    clientes.sort((a, b) => a.id.compareTo(b.id));
    return clientes;
  }

  int _indiceClienteAtual(List<Cliente> clientes) {
    final atualId = _clienteEmEdicaoId;
    if (atualId == null) return -1;
    return clientes.indexWhere((c) => c.id == atualId);
  }

  void _abrirClientePorIndice(int indice) {
    final clientes = _clientesOrdenadosPorCadastro();
    if (clientes.isEmpty) {
      setState(() {
        _status = 'Nao ha clientes cadastrados para navegar.';
      });
      return;
    }
    final indiceValido = indice.clamp(0, clientes.length - 1);
    _editarCliente(clientes[indiceValido]);
  }

  void _irParaPrimeiroCliente() {
    _abrirClientePorIndice(0);
  }

  void _irParaUltimoCliente() {
    final clientes = _clientesOrdenadosPorCadastro();
    if (clientes.isEmpty) {
      setState(() {
        _status = 'Nao ha clientes cadastrados para navegar.';
      });
      return;
    }
    _abrirClientePorIndice(clientes.length - 1);
  }

  void _irParaClienteAnterior() {
    final clientes = _clientesOrdenadosPorCadastro();
    if (clientes.isEmpty) {
      setState(() {
        _status = 'Nao ha clientes cadastrados para navegar.';
      });
      return;
    }
    final indiceAtual = _indiceClienteAtual(clientes);
    if (indiceAtual <= 0) {
      _abrirClientePorIndice(0);
      return;
    }
    _abrirClientePorIndice(indiceAtual - 1);
  }

  void _irParaProximoCliente() {
    final clientes = _clientesOrdenadosPorCadastro();
    if (clientes.isEmpty) {
      setState(() {
        _status = 'Nao ha clientes cadastrados para navegar.';
      });
      return;
    }
    final indiceAtual = _indiceClienteAtual(clientes);
    if (indiceAtual < 0) {
      _abrirClientePorIndice(0);
      return;
    }
    if (indiceAtual >= clientes.length - 1) {
      _abrirClientePorIndice(clientes.length - 1);
      return;
    }
    _abrirClientePorIndice(indiceAtual + 1);
  }

  void _padronizarMascarasCamposCliente() {
    _documentoController.value = _cpfCnpjFormatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(text: _documentoController.text),
    );
    _telefoneController.value = _telefoneFormatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(text: _telefoneController.text),
    );
    _whatsappController.value = _telefoneFormatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(text: _whatsappController.text),
    );
    _cepController.value = _cepFormatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(text: _cepController.text),
    );
    _limiteController.value = _limiteCreditoFormatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(text: _limiteController.text),
    );
  }

  (DateTime?, DateTime?) _limitesPeriodoHistorico() {
    final now = DateTime.now();
    final fimDia = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    switch (_periodoHistorico) {
      case 'ultimos_30':
        return (
          DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 29)),
          fimDia,
        );
      case 'ultimos_90':
        return (
          DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 89)),
          fimDia,
        );
      case 'ano_atual':
        return (DateTime(now.year, 1, 1), fimDia);
      case 'todo':
      default:
        return (null, null);
    }
  }

  List<Venda> _comprasDoClienteAtual() {
    final clienteId = _clienteEmEdicaoId;
    if (clienteId == null) return const [];
    final limites = _limitesPeriodoHistorico();
    return widget.vendaRepository.listarComprasFinalizadasPorCliente(
      clienteId,
      inicio: limites.$1,
      fim: limites.$2,
    );
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  String _rotuloStatusMensagem(String status) {
    switch (status) {
      case 'aceito_api':
        return 'Aceito pela API';
      case 'enviado':
        return 'Enviado';
      case 'entregue':
        return 'Entregue';
      case 'lido':
        return 'Lido';
      case 'falhou':
        return 'Falhou';
      default:
        return status;
    }
  }

  Cliente? _clienteEmEdicaoAtual() {
    final id = _clienteEmEdicaoId;
    if (id == null) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  Future<void> _enviarMensagemManualCliente(Cliente cliente) async {
    final templates = await _mensageriaRepository.listarTemplates();
    final templatesManuais = templates
        .where((t) => t.ativo && t.evento == 'manual')
        .toList();
    if (templatesManuais.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cadastre um template manual em Configuracoes > Mensageria.'),
        ),
      );
      return;
    }
    MensagemTemplate selecionado = templatesManuais.first;
    final destinoController = TextEditingController(
      text: cliente.whatsapp.trim().isNotEmpty ? cliente.whatsapp : cliente.telefone,
    );
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Enviar mensagem ao cliente'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selecionado.id,
                      decoration: const InputDecoration(labelText: 'Template'),
                      items: templatesManuais
                          .map(
                            (t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(t.nome),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final t = templatesManuais.firstWhere((e) => e.id == v);
                        setDialogState(() => selecionado = t);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: destinoController,
                      decoration: const InputDecoration(
                        labelText: 'Destino (telefone/whatsapp)',
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
                  child: const Text('Enviar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    final destino = destinoController.text.replaceAll(RegExp(r'\D'), '');
    if (destino.isEmpty) return;
    await _mensageriaRepository.enfileirarMensagem(
      clienteId: cliente.id,
      templateId: selecionado.id,
      destino: destino,
      variaveis: {
        'cliente_nome': cliente.nomeRazao.trim(),
        'valor_total': '0,00',
        'numero_orcamento': '-',
      },
    );
    await _mensageriaRepository.processarFilaPendente(limite: 5);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mensagem enviada para fila e processada.')),
    );
  }

  Future<void> _verErroDetalhadoLogCliente(MensagemLog log) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Erro detalhado do envio'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: SelectableText(
                log.responseJson.trim().isEmpty
                    ? 'Sem detalhe retornado pela API.'
                    : log.responseJson,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emEdicao = _clienteEmEdicaoId != null;
    final compras = _comprasDoClienteAtual();
    final totalGasto = compras.fold<double>(0, (acc, v) => acc + v.total);
    final ticketMedio = compras.isEmpty ? 0.0 : totalGasto / compras.length;
    final ultimaCompra = compras.isEmpty ? null : compras.first;
    final quantidadeItens = compras.fold<int>(
      0,
      (acc, compra) => acc + compra.itens.fold<int>(0, (soma, item) => soma + item.quantidade),
    );
    final topProdutosMap = <String, int>{};
    for (final compra in compras) {
      for (final item in compra.itens) {
        final nome = item.nomeProduto.trim();
        if (nome.isEmpty) continue;
        topProdutosMap[nome] = (topProdutosMap[nome] ?? 0) + item.quantidade;
      }
    }
    final topProdutos = topProdutosMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro de Clientes')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: RawScrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 10,
          radius: const Radius.circular(8),
          crossAxisMargin: 2,
          mainAxisMargin: 4,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.only(right: 10),
            children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.surfaceContainerHighest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 30,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cadastro de Clientes',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          emEdicao
                              ? 'Modo edicao ativo: revise os dados e salve.'
                              : 'Preencha os dados para registrar um novo cliente.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _abrirPesquisaCliente,
                icon: const Icon(Icons.search),
                label: const Text('Pesquisar cliente'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _irParaPrimeiroCliente,
                    child: const Text('|< Primeiro'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _irParaClienteAnterior,
                    child: const Text('< Anterior'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _irParaProximoCliente,
                    child: const Text('Proximo >'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _irParaUltimoCliente,
                    child: const Text('Ultimo >|'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              context: context,
              title: 'Dados principais',
              icon: Icons.person_outline,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _tipoPessoa,
                  decoration: const InputDecoration(labelText: 'Tipo de pessoa'),
                  items: const [
                    DropdownMenuItem(value: 'fisica', child: Text('Fisica')),
                    DropdownMenuItem(value: 'juridica', child: Text('Juridica')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _tipoPessoa = v;
                        _documentoController.clear();
                        if (_tipoPessoa == 'fisica') {
                          _inscricaoController.clear();
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nomeRazaoController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome / Razao social'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nomeFantasiaController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome fantasia (opcional)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _documentoController,
                        decoration: InputDecoration(
                          labelText: _tipoPessoa == 'fisica' ? 'CPF' : 'CNPJ',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [_cpfCnpjFormatter],
                      ),
                    ),
                    if (_tipoPessoa == 'juridica') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _inscricaoController,
                          decoration: const InputDecoration(labelText: 'Inscricao Estadual'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
                            LengthLimitingTextInputFormatter(20),
                          ],
                        ),
                      ),
                    ],
                  ],
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
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_telefoneFormatter],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _whatsappController,
                        decoration: const InputDecoration(labelText: 'WhatsApp'),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_telefoneFormatter],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                        textCapitalization: TextCapitalization.none,
                  inputFormatters: [_emailFormatter],
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
                        keyboardType: TextInputType.number,
                        inputFormatters: [_cepFormatter],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _enderecoController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Endereco'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _numeroController,
                        decoration: const InputDecoration(labelText: 'Numero'),
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(10),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bairroController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Bairro'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _cidadeController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Cidade'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _ufController,
                        decoration: const InputDecoration(labelText: 'UF'),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                          LengthLimitingTextInputFormatter(2),
                          UpperCaseTextFormatter(),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSectionCard(
              context: context,
              title: 'Comercial',
              icon: Icons.payments_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _referenciaController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(labelText: 'Referencia'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _limiteController,
                        decoration: const InputDecoration(labelText: 'Limite de credito'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_limiteCreditoFormatter],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _observacoesController,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Observacoes'),
                ),
                SwitchListTile(
                  value: _ativo,
                  onChanged: (v) => setState(() => _ativo = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cliente ativo'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: Icon(Icons.history_outlined, color: theme.colorScheme.primary),
                title: Text(
                  'Historico de Compras',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                children: [
                  if (!emEdicao)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Salve o cliente para habilitar o historico de compras.',
                        ),
                      ),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      initialValue: _periodoHistorico,
                      decoration: const InputDecoration(
                        labelText: 'Periodo do historico',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'todo', child: Text('Todo o periodo')),
                        DropdownMenuItem(value: 'ultimos_30', child: Text('Ultimos 30 dias')),
                        DropdownMenuItem(value: 'ultimos_90', child: Text('Ultimos 90 dias')),
                        DropdownMenuItem(value: 'ano_atual', child: Text('Ano atual')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _periodoHistorico = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Total ja gasto na loja: ${_formatarMoeda(totalGasto)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Ticket medio: ${_formatarMoeda(ticketMedio)}'),
                    Text('Total de itens comprados: $quantidadeItens'),
                    Text(
                      'Ultima compra: ${ultimaCompra == null ? 'Nao disponivel' : _dataHora.format(ultimaCompra.data.toLocal())}',
                    ),
                    const SizedBox(height: 8),
                    Text('Compras registradas: ${compras.length}'),
                    const SizedBox(height: 8),
                    if (topProdutos.isNotEmpty) ...[
                      Text(
                        'Top produtos comprados',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...topProdutos.take(3).map(
                        (entry) => Text('${entry.key} - ${entry.value} un'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 10),
                    if (compras.isEmpty)
                      const Text('Este cliente ainda nao tem compras finalizadas.')
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: compras.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final compra = compras[index];
                            final nota = compra.numeroOrcamento > 0
                                ? '#${compra.numeroOrcamento}'
                                : 'ID ${compra.id}';
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              leading: const Icon(Icons.receipt_long_outlined),
                              title: Text('Nota/Orcamento: $nota'),
                              subtitle: Text(_dataHora.format(compra.data.toLocal())),
                              trailing: Text(
                                _formatarMoeda(compra.total),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: Icon(Icons.chat_bubble_outline, color: theme.colorScheme.primary),
                title: Text(
                  'Mensagens enviadas',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                children: [
                  if (!emEdicao)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Salve o cliente para habilitar logs de mensagens.',
                      ),
                    )
                  else
                    FutureBuilder<List<MensagemLog>>(
                      future: _mensageriaRepository.listarLogsPorCliente(
                        _clienteEmEdicaoId!,
                      ),
                      builder: (context, snapshot) {
                        final logs = snapshot.data ?? const <MensagemLog>[];
                        final clienteAtual = _clienteEmEdicaoAtual();
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: LinearProgressIndicator(),
                          );
                        }
                        if (clienteAtual == null) {
                          return const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Cliente nao encontrado.'),
                          );
                        }
                        if (logs.isEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _enviarMensagemManualCliente(clienteAtual),
                                  icon: const Icon(Icons.send_outlined),
                                  label: const Text('Enviar mensagem agora'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('Nenhum log de mensagem para este cliente.'),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _enviarMensagemManualCliente(clienteAtual),
                                icon: const Icon(Icons.send_outlined),
                                label: const Text('Enviar mensagem agora'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 220),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: logs.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final log = logs[index];
                                  final enviado = log.resultado == 'enviado';
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    leading: Icon(
                                      enviado
                                          ? Icons.check_circle_outline
                                          : Icons.error_outline,
                                      color: enviado
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.error,
                                    ),
                                    title: Text(
                                      '${log.canal.toUpperCase()} - ${_rotuloStatusMensagem(log.statusEntrega)}',
                                    ),
                                    subtitle: Text(
                                      '${_dataHora.format(log.criadoEm.toLocal())}\nDestino: ${log.destino}',
                                    ),
                                    isThreeLine: true,
                                    trailing: log.resultado == 'falhou'
                                        ? IconButton(
                                            tooltip: 'Ver erro detalhado',
                                            onPressed: () =>
                                                _verErroDetalhadoLogCliente(log),
                                            icon: const Icon(Icons.error_outline),
                                          )
                                        : null,
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _salvarCliente,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(emEdicao ? 'Salvar edicao' : 'Salvar cliente'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _limparFormulario,
                    icon: Icon(emEdicao ? Icons.close : Icons.cleaning_services_outlined),
                    label: Text(emEdicao ? 'Cancelar edicao' : 'Limpar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_status.isNotEmpty) _buildStatusBanner(context, _status),
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
    final bg = sucesso ? semantic?.successBg ?? const Color(0xFFEAF8EF) : semantic?.errorBg ?? const Color(0xFFFDECEC);
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
          Icon(sucesso ? Icons.check_circle_outline : Icons.error_outline, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _CpfCnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > 14 ? digits.substring(0, 14) : digits;
    final masked = truncated.length <= 11 ? _maskCpf(truncated) : _maskCnpj(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  String _maskCpf(String value) {
    if (value.length <= 3) return value;
    if (value.length <= 6) return '${value.substring(0, 3)}.${value.substring(3)}';
    if (value.length <= 9) {
      return '${value.substring(0, 3)}.${value.substring(3, 6)}.${value.substring(6)}';
    }
    return '${value.substring(0, 3)}.${value.substring(3, 6)}.${value.substring(6, 9)}-${value.substring(9)}';
  }

  String _maskCnpj(String value) {
    if (value.length <= 2) return value;
    if (value.length <= 5) return '${value.substring(0, 2)}.${value.substring(2)}';
    if (value.length <= 8) {
      return '${value.substring(0, 2)}.${value.substring(2, 5)}.${value.substring(5)}';
    }
    if (value.length <= 12) {
      return '${value.substring(0, 2)}.${value.substring(2, 5)}.${value.substring(5, 8)}/${value.substring(8)}';
    }
    return '${value.substring(0, 2)}.${value.substring(2, 5)}.${value.substring(5, 8)}/${value.substring(8, 12)}-${value.substring(12)}';
  }
}

class _TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // Permite telefone local (ate 11) e numero com DDI BR (55 + DDD + numero = ate 13).
    final truncated = digits.length > 13 ? digits.substring(0, 13) : digits;
    final masked = _maskTelefone(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  String _maskTelefone(String value) {
    if (value.isEmpty) return '';
    if (value.length > 11) {
      final ddi = value.substring(0, 2);
      final resto = value.substring(2);
      final localMask = _maskTelefoneLocal(resto);
      return '+$ddi $localMask';
    }
    return _maskTelefoneLocal(value);
  }

  String _maskTelefoneLocal(String value) {
    if (value.isEmpty) return '';
    if (value.length <= 2) return '($value';
    if (value.length <= 6) return '(${value.substring(0, 2)}) ${value.substring(2)}';
    if (value.length <= 10) {
      return '(${value.substring(0, 2)}) ${value.substring(2, 6)}-${value.substring(6)}';
    }
    return '(${value.substring(0, 2)}) ${value.substring(2, 7)}-${value.substring(7)}';
  }
}

class _CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > 8 ? digits.substring(0, 8) : digits;
    final masked = truncated.length <= 5
        ? truncated
        : '${truncated.substring(0, 5)}-${truncated.substring(5)}';
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

class _EmailInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sanitized = newValue.text.replaceAll(' ', '').toLowerCase();
    return TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: sanitized.length),
    );
  }
}

class _MoedaInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final valor = double.parse(digits) / 100;
    final partes = valor.toStringAsFixed(2).split('.');
    final inteiro = partes[0];
    final decimal = partes[1];
    final buffer = StringBuffer();
    for (var i = 0; i < inteiro.length; i++) {
      final pos = inteiro.length - i;
      buffer.write(inteiro[i]);
      if (pos > 1 && pos % 3 == 1) {
        buffer.write('.');
      }
    }
    final formatado = '${buffer.toString()},$decimal';
    return TextEditingValue(
      text: formatado,
      selection: TextSelection.collapsed(offset: formatado.length),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
