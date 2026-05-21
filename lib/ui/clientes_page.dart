import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../domain/cliente_cadastro.dart';
import '../main.dart';
import '../data/cliente_repository.dart';
import '../data/mensageria_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/cliente.dart';
import '../model/mensagem_log.dart';
import '../model/vendedor.dart';
import '../services/brasil_api_cep_service.dart';
import '../services/brasil_api_cnpj_service.dart';
import '../model/mensagem_template.dart';
import '../model/venda.dart';
import 'widgets/cliente/cliente_cadastro_header.dart';
import 'widgets/cliente/cliente_cadastro_rodape.dart';
import 'widgets/extrato_fiado_cliente_card.dart';

class _CadastroClienteSalvarIntent extends Intent {
  const _CadastroClienteSalvarIntent();
}

class _CadastroClienteCancelarIntent extends Intent {
  const _CadastroClienteCancelarIntent();
}

class ClientesPage extends StatefulWidget {
  const ClientesPage({
    super.key,
    required this.clienteRepository,
    required this.vendaRepository,
    this.vendedorRepository,
    this.retornarClienteAoSalvar = false,
    this.clienteIdInicial,
  });

  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository? vendedorRepository;
  final bool retornarClienteAoSalvar;
  /// Abre direto o cadastro deste cliente (ex.: drill-down de relatorios).
  final int? clienteIdInicial;

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _AlvoPreenchimentoCep {
  const _AlvoPreenchimentoCep({
    required this.cep,
    required this.endereco,
    required this.numero,
    required this.bairro,
    required this.cidade,
    required this.uf,
  });

  final TextEditingController cep;
  final TextEditingController endereco;
  final TextEditingController numero;
  final TextEditingController bairro;
  final TextEditingController cidade;
  final TextEditingController uf;
}

class _ClientesPageState extends State<ClientesPage>
    with SingleTickerProviderStateMixin {
  static ButtonStyle get _estiloBotaoContornoCompacto => OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  static const double _wTipoPessoa = 172;
  static const double _wDoc = 228;
  static const double _wIe = 200;
  static const double _wCep = 120;
  static const double _wNumero = 88;
  static const double _wUf = 72;
  static const double _maxLarguraFormulario = 1120;
  static const Color _fundoPainelCadastro = Color(0xFFE8EEF5);
  static const Color _bordaPainelCadastro = Color(0xFFB0BEC5);
  static const Color _corLimiteDestaque = Color(0xFF1B5E20);
  static const Color _fundoLimiteCredito = Color(0xFFE8F5E9);
  static const Color _bordaLimiteCredito = Color(0xFFC8E6C9);

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
  final _rgController = TextEditingController();
  final _ocupacaoController = TextEditingController();
  final _codigoInternoController = TextEditingController();
  final _inscricaoMunicipalController = TextEditingController();
  final _contatoPrincipalNomeController = TextEditingController();
  final _contatoPrincipalCargoController = TextEditingController();
  final _motivoBloqueioController = TextEditingController();
  final _prazoPagamentoController = TextEditingController();
  String _sexoCliente = '';
  DateTime? _dataNascimentoCliente;
  final List<_EnderecoFormControllers> _enderecosExtras = [];
  bool _principalPadraoCarreto = true;

  int? _clienteEmEdicaoId;
  String _tipoPessoa = 'fisica';
  String _segmento = '';
  String _categoriaComercial = '';
  String _tabelaPrecoPadrao = 'preco1';
  String _indicadorIe = '';
  String _origemCadastro = '';
  int? _vendedorResponsavelId;
  bool _bloqueadoFiado = false;
  bool _ativo = true;
  List<Vendedor> _vendedoresAtivos = [];
  String _status = '';
  late final _cpfCnpjFormatter = _CpfCnpjInputFormatter();
  late final _telefoneFormatter = _TelefoneInputFormatter();
  late final _cepFormatter = _CepInputFormatter();
  late final _emailFormatter = _EmailInputFormatter();
  late final _limiteCreditoFormatter = _MoedaInputFormatter();
  final MensageriaRepository _mensageriaRepository = MensageriaRepository();
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat _dataNascimentoFmt = DateFormat('dd/MM/yyyy');
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  String _periodoHistorico = 'todo';

  Timer? _debounceConsultaCnpj;
  Timer? _debounceConsultaCep;
  bool _carregandoClienteNoFormulario = false;
  bool _consultaCnpjEmAndamento = false;
  bool _consultaCepEmAndamento = false;
  TextEditingController? _cepControllerEmConsulta;
  final ScrollController _scrollAbaIdentificacao = ScrollController();
  final ScrollController _scrollAbaContato = ScrollController();
  final ScrollController _scrollAbaComercial = ScrollController();
  final ScrollController _scrollAbaEndereco = ScrollController();
  final ScrollController _scrollAbaRelacionamento = ScrollController();

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _documentoController.addListener(_onDocumentoChanged);
    _vendedoresAtivos =
        widget.vendedorRepository?.listarAtivos() ?? const [];
    final idInicial = widget.clienteIdInicial;
    if (idInicial != null && idInicial > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = widget.clienteRepository.obterPorId(idInicial);
        if (c != null && mounted) _editarCliente(c);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounceConsultaCnpj?.cancel();
    _debounceConsultaCep?.cancel();
    _documentoController.removeListener(_onDocumentoChanged);
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
    _rgController.dispose();
    _ocupacaoController.dispose();
    _codigoInternoController.dispose();
    _inscricaoMunicipalController.dispose();
    _contatoPrincipalNomeController.dispose();
    _contatoPrincipalCargoController.dispose();
    _motivoBloqueioController.dispose();
    _prazoPagamentoController.dispose();
    for (final endereco in _enderecosExtras) {
      endereco.dispose();
    }
    _scrollAbaIdentificacao.dispose();
    _scrollAbaContato.dispose();
    _scrollAbaComercial.dispose();
    _scrollAbaEndereco.dispose();
    _scrollAbaRelacionamento.dispose();
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
              if (!resultadosScrollController.hasClients ||
                  indiceSelecionado < 0) {
                return;
              }
              const alturaEstimadaLinha = 64.0;
              final posicaoDesejada = (indiceSelecionado * alturaEstimadaLinha)
                  .clamp(
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
                              final matchTexto = campos.any(
                                (campo) => campo.contains(termo),
                              );
                              if (matchTexto) return true;
                              if (termoNumerico.isEmpty) return false;
                              final camposNumericos = [
                                cliente.documento,
                                cliente.telefone,
                                cliente.whatsapp,
                                cliente.cep,
                              ].map(_somenteDigitos);
                              return camposNumericos.any(
                                (campoNumerico) =>
                                    campoNumerico.contains(termoNumerico),
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
                          final indice = indiceSelecionado >= 0
                              ? indiceSelecionado
                              : 0;
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
                            ? const Center(
                                child: Text('Nenhum cliente encontrado.'),
                              )
                            : ListView.builder(
                                controller: resultadosScrollController,
                                shrinkWrap: true,
                                itemCount: resultados.length,
                                itemBuilder: (context, index) {
                                  final cliente = resultados[index];
                                  final consulta = pesquisaController.text
                                      .trim();
                                  final estiloTitulo =
                                      Theme.of(
                                        context,
                                      ).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ) ??
                                      const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      );
                                  final estiloSubtitulo =
                                      Theme.of(context).textTheme.bodyMedium ??
                                      const TextStyle();
                                  final selecionado =
                                      index == indiceSelecionado;

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
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                      selected: selecionado,
                                      selectedTileColor: Theme.of(
                                        context,
                                      ).colorScheme.primary.withValues(alpha: 0.08),
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
                                      onTap: () =>
                                          Navigator.pop(context, cliente),
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
    _debounceConsultaCnpj?.cancel();
    _debounceConsultaCep?.cancel();
    for (final endereco in _enderecosExtras) {
      endereco.dispose();
    }
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
      _enderecosExtras.clear();
      _limiteController.clear();
      _observacoesController.clear();
      _rgController.clear();
      _ocupacaoController.clear();
      _codigoInternoController.clear();
      _inscricaoMunicipalController.clear();
      _contatoPrincipalNomeController.clear();
      _contatoPrincipalCargoController.clear();
      _motivoBloqueioController.clear();
      _prazoPagamentoController.clear();
      _sexoCliente = '';
      _dataNascimentoCliente = null;
      _tipoPessoa = 'fisica';
      _segmento = '';
      _categoriaComercial = '';
      _tabelaPrecoPadrao = 'preco1';
      _indicadorIe = '';
      _origemCadastro = '';
      _vendedorResponsavelId = null;
      _bloqueadoFiado = false;
      _principalPadraoCarreto = true;
      _ativo = true;
      _clienteEmEdicaoId = null;
      _status = '';
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
    final limiteCredito =
        double.tryParse(
          _limiteController.text
              .trim()
              .replaceAll('.', '')
              .replaceAll(',', '.'),
        ) ??
        0;
    final existente = _clienteEmEdicaoId == null
        ? null
        : widget.clienteRepository.obterPorId(_clienteEmEdicaoId!);

    final enderecos = _enderecosDoFormulario();
    final prazoDias = int.tryParse(_prazoPagamentoController.text.trim()) ?? 0;
    final agora = DateTime.now().toUtc();
    final cliente = Cliente(
      id: existente?.id ?? 0,
      tipoPessoa: _tipoPessoa,
      codigoInterno: _codigoInternoController.text.trim(),
      segmento: _segmento,
      categoriaComercial: _categoriaComercial,
      vendedorResponsavelId: _vendedorResponsavelId ?? 0,
      tabelaPrecoPadrao:
          ClienteCadastro.normalizarTabelaPreco(_tabelaPrecoPadrao),
      prazoPagamentoDias: prazoDias < 0 ? 0 : prazoDias,
      bloqueadoFiado: _bloqueadoFiado,
      motivoBloqueio: _motivoBloqueioController.text.trim(),
      nomeRazao: nomeRazao,
      nomeFantasia: _nomeFantasiaController.text.trim(),
      documento: _somenteDigitos(_documentoController.text),
      rg: _tipoPessoa == 'fisica' ? _rgController.text.trim() : '',
      dataNascimento: _tipoPessoa == 'fisica' && _dataNascimentoCliente != null
          ? DateTime.utc(
              _dataNascimentoCliente!.year,
              _dataNascimentoCliente!.month,
              _dataNascimentoCliente!.day,
            )
          : null,
      sexo: _tipoPessoa == 'fisica' ? _sexoCliente : '',
      inscricaoEstadual: _tipoPessoa == 'juridica'
          ? _inscricaoController.text.trim().toUpperCase()
          : '',
      inscricaoMunicipal: _tipoPessoa == 'juridica'
          ? _inscricaoMunicipalController.text.trim()
          : '',
      indicadorIe: _tipoPessoa == 'juridica' ? _indicadorIe : '',
      telefone: _somenteDigitos(_telefoneController.text),
      whatsapp: _somenteDigitos(_whatsappController.text),
      email: _emailController.text.trim().toLowerCase(),
      contatoPrincipalNome: _contatoPrincipalNomeController.text.trim(),
      contatoPrincipalCargo: _contatoPrincipalCargoController.text.trim(),
      cep: '',
      endereco: '',
      numero: '',
      bairro: '',
      cidade: '',
      uf: '',
      referencia: '',
      enderecosJson: existente?.enderecosJson ?? '',
      limiteCredito: limiteCredito,
      observacoes: _observacoesController.text.trim(),
      ocupacao: _ocupacaoController.text.trim(),
      origemCadastro: _origemCadastro,
      ativo: _ativo,
      criadoEm: existente?.criadoEm,
      atualizadoEm: agora,
    );
    cliente.definirEnderecos(enderecos);
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

  Future<void> _selecionarDataNascimentoCliente() async {
    final hoje = DateTime.now();
    final inicial = _dataNascimentoCliente ??
        DateTime(hoje.year - 25, hoje.month, hoje.day);
    final d = await showDatePicker(
      context: context,
      initialDate: inicial.isAfter(hoje) ? hoje : inicial,
      firstDate: DateTime(1900),
      lastDate: hoje,
    );
    if (d != null && mounted) {
      setState(() => _dataNascimentoCliente = d);
    }
  }

  List<Widget> _camposPessoaFisicaIdentificacao() {
    if (_tipoPessoa != 'fisica') return const [];
    final theme = Theme.of(context);
    final textoNasc = _dataNascimentoCliente == null
        ? 'Nao informado'
        : _dataNascimentoFmt.format(_dataNascimentoCliente!);
    return [
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 168,
            child: TextField(
              controller: _rgController,
              decoration: const InputDecoration(
                labelText: 'RG',
                isDense: true,
              ),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z.\-\s]')),
                LengthLimitingTextInputFormatter(18),
              ],
            ),
          ),
          SizedBox(
            width: 212,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Nascimento',
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Limpar data',
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: _dataNascimentoCliente == null
                      ? null
                      : () => setState(() => _dataNascimentoCliente = null),
                ),
              ),
              child: InkWell(
                onTap: _selecionarDataNascimentoCliente,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          textoNasc,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              key: ValueKey<String>(_sexoCliente),
              initialValue: _sexoCliente,
              decoration: const InputDecoration(
                labelText: 'Sexo',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: '', child: Text('Nao informado')),
                DropdownMenuItem(value: 'M', child: Text('Masculino')),
                DropdownMenuItem(value: 'F', child: Text('Feminino')),
                DropdownMenuItem(value: 'O', child: Text('Outro')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _sexoCliente = v);
              },
            ),
          ),
        ],
      ),
    ];
  }

  void _onDocumentoChanged() {
    _debounceConsultaCnpj?.cancel();
    if (_carregandoClienteNoFormulario) return;
    if (_tipoPessoa != 'juridica') return;
    final digitos = _somenteDigitos(_documentoController.text);
    if (digitos.length != 14) return;
    _debounceConsultaCnpj = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      unawaited(_executarConsultaCnpjSeAplicavel(digitos));
    });
  }

  Future<void> _executarConsultaCnpjSeAplicavel(String cnpj14) async {
    if (_carregandoClienteNoFormulario) return;
    if (_tipoPessoa != 'juridica') return;
    if (_somenteDigitos(_documentoController.text) != cnpj14) return;
    if (_consultaCnpjEmAndamento) return;
    setState(() => _consultaCnpjEmAndamento = true);
    try {
      final dados = await BrasilApiCnpjService.consultar(cnpj14);
      if (!mounted) return;
      if (_carregandoClienteNoFormulario) return;
      if (_tipoPessoa != 'juridica') return;
      if (_somenteDigitos(_documentoController.text) != cnpj14) return;
      if (dados == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CNPJ nao encontrado na base publica (BrasilAPI).'),
          ),
        );
        return;
      }
      setState(() {
        _nomeRazaoController.text = dados.razaoSocial;
        if (dados.nomeFantasia.isNotEmpty &&
            _nomeFantasiaController.text.trim().isEmpty) {
          _nomeFantasiaController.text = dados.nomeFantasia;
        }
        _cepController.text = dados.cep;
        _enderecoController.text = dados.logradouro;
        _numeroController.text = dados.numero;
        _bairroController.text = dados.bairro;
        _cidadeController.text = dados.municipio;
        _ufController.text = dados.uf;
      });
      _cepController.value = _cepFormatter.formatEditUpdate(
        const TextEditingValue(),
        TextEditingValue(text: _cepController.text),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao consultar CNPJ: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _consultaCnpjEmAndamento = false);
      }
    }
  }

  void _buscarCnpjManualmente() {
    final digitos = _somenteDigitos(_documentoController.text);
    if (digitos.length != 14) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o CNPJ completo (14 digitos) para buscar.'),
        ),
      );
      return;
    }
    _debounceConsultaCnpj?.cancel();
    unawaited(_executarConsultaCnpjSeAplicavel(digitos));
  }

  void _agendarConsultaCep(_AlvoPreenchimentoCep alvo) {
    _debounceConsultaCep?.cancel();
    if (_carregandoClienteNoFormulario) return;
    final digitos = _somenteDigitos(alvo.cep.text);
    if (digitos.length != 8) return;
    _debounceConsultaCep = Timer(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      unawaited(_executarConsultaCep(alvo));
    });
  }

  Future<void> _executarConsultaCep(_AlvoPreenchimentoCep alvo) async {
    if (_carregandoClienteNoFormulario) return;
    final digitos = _somenteDigitos(alvo.cep.text);
    if (digitos.length != 8) return;
    if (_consultaCepEmAndamento) return;
    setState(() {
      _consultaCepEmAndamento = true;
      _cepControllerEmConsulta = alvo.cep;
    });
    try {
      final dados = await BrasilApiCepService.consultar(digitos);
      if (!mounted) return;
      if (_carregandoClienteNoFormulario) return;
      if (_somenteDigitos(alvo.cep.text) != digitos) return;
      if (dados == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CEP nao encontrado na base publica (BrasilAPI).'),
          ),
        );
        return;
      }
      setState(() {
        alvo.endereco.text = dados.logradouro;
        alvo.bairro.text = dados.bairro;
        alvo.cidade.text = dados.cidade;
        alvo.uf.text = dados.uf;
        alvo.cep.text = dados.cep;
      });
      alvo.cep.value = _cepFormatter.formatEditUpdate(
        const TextEditingValue(),
        TextEditingValue(text: alvo.cep.text),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao consultar CEP: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _consultaCepEmAndamento = false;
          _cepControllerEmConsulta = null;
        });
      }
    }
  }

  void _buscarCepManual(_AlvoPreenchimentoCep alvo) {
    final digitos = _somenteDigitos(alvo.cep.text);
    if (digitos.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o CEP completo (8 digitos) para buscar.'),
        ),
      );
      return;
    }
    _debounceConsultaCep?.cancel();
    unawaited(_executarConsultaCep(alvo));
  }

  void _editarCliente(Cliente c) {
    _debounceConsultaCnpj?.cancel();
    _debounceConsultaCep?.cancel();
    _carregandoClienteNoFormulario = true;
    final enderecos = c.listarEnderecos();
    EnderecoCliente principal;
    List<EnderecoCliente> extras;
    if (enderecos.isEmpty) {
      principal = EnderecoCliente();
      extras = const [];
    } else {
      final idxPrincipal = enderecos.indexWhere((e) => e.tipo == 'principal');
      final idx = idxPrincipal >= 0 ? idxPrincipal : 0;
      principal = enderecos[idx];
      extras = [
        for (var i = 0; i < enderecos.length; i++)
          if (i != idx) enderecos[i],
      ];
    }
    for (final endereco in _enderecosExtras) {
      endereco.dispose();
    }
    setState(() {
      _clienteEmEdicaoId = c.id;
      _tipoPessoa = c.tipoPessoa;
      _nomeRazaoController.text = c.nomeRazao;
      _nomeFantasiaController.text = c.nomeFantasia;
      _documentoController.text = c.documento;
      _rgController.text = c.rg;
      _dataNascimentoCliente = c.dataNascimento == null
          ? null
          : DateTime(
              c.dataNascimento!.toUtc().year,
              c.dataNascimento!.toUtc().month,
              c.dataNascimento!.toUtc().day,
            );
      _sexoCliente = c.sexo;
      _inscricaoController.text = c.inscricaoEstadual;
      _telefoneController.text = c.telefone;
      _whatsappController.text = c.whatsapp;
      _emailController.text = c.email;
      _cepController.text = principal.cep;
      _enderecoController.text = principal.endereco;
      _numeroController.text = principal.numero;
      _bairroController.text = principal.bairro;
      _cidadeController.text = principal.cidade;
      _ufController.text = principal.uf;
      _referenciaController.text = principal.referencia;
      _enderecosExtras
        ..clear()
        ..addAll(extras.map(_EnderecoFormControllers.fromEndereco));
      _codigoInternoController.text = c.codigoInterno;
      _segmento = c.segmento;
      _categoriaComercial = c.categoriaComercial;
      _tabelaPrecoPadrao =
          ClienteCadastro.normalizarTabelaPreco(c.tabelaPrecoPadrao);
      _prazoPagamentoController.text = c.prazoPagamentoDias > 0
          ? '${c.prazoPagamentoDias}'
          : '';
      _vendedorResponsavelId =
          c.vendedorResponsavelId > 0 ? c.vendedorResponsavelId : null;
      _bloqueadoFiado = c.bloqueadoFiado;
      _motivoBloqueioController.text = c.motivoBloqueio;
      _inscricaoMunicipalController.text = c.inscricaoMunicipal;
      _indicadorIe = c.indicadorIe;
      _contatoPrincipalNomeController.text = c.contatoPrincipalNome;
      _contatoPrincipalCargoController.text = c.contatoPrincipalCargo;
      _origemCadastro = c.origemCadastro;
      _principalPadraoCarreto = principal.padraoCarreto;
      _limiteController.text = c.limiteCredito
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _observacoesController.text = c.observacoes;
      _ocupacaoController.text = c.ocupacao;
      _ativo = c.ativo;
      _status = 'Editando cliente: ${c.nomeRazao}';
    });
    _padronizarMascarasCamposCliente();
    _carregandoClienteNoFormulario = false;
    _debounceConsultaCnpj?.cancel();
    _debounceConsultaCep?.cancel();
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
    for (final endereco in _enderecosExtras) {
      endereco.cepController.value = _cepFormatter.formatEditUpdate(
        const TextEditingValue(),
        TextEditingValue(text: endereco.cepController.text),
      );
      endereco.ufController.value = UpperCaseTextFormatter().formatEditUpdate(
        const TextEditingValue(),
        TextEditingValue(text: endereco.ufController.text),
      );
    }
    _limiteController.value = _limiteCreditoFormatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(text: _limiteController.text),
    );
  }

  List<EnderecoCliente> _enderecosDoFormulario() {
    final enderecos = <EnderecoCliente>[
      EnderecoCliente(
        tipo: 'principal',
        padraoCarreto: _principalPadraoCarreto,
        cep: _somenteDigitos(_cepController.text),
        endereco: _enderecoController.text.trim(),
        numero: _numeroController.text.trim(),
        bairro: _bairroController.text.trim(),
        cidade: _cidadeController.text.trim(),
        uf: _ufController.text.trim().toUpperCase(),
        referencia: _referenciaController.text.trim(),
      ),
      ..._enderecosExtras.map((e) => e.toEndereco()),
    ];
    return enderecos.where((e) => e.temDados).toList();
  }

  void _definirUnicoPadraoCarreto({required bool principal, int? indiceExtra}) {
    setState(() {
      if (principal) {
        _principalPadraoCarreto = true;
        for (final e in _enderecosExtras) {
          e.padraoCarreto = false;
        }
      } else if (indiceExtra != null && indiceExtra >= 0) {
        _principalPadraoCarreto = false;
        for (var i = 0; i < _enderecosExtras.length; i++) {
          _enderecosExtras[i].padraoCarreto = i == indiceExtra;
        }
      }
    });
  }

  double _fiadoAbertoClienteAtual() {
    final id = _clienteEmEdicaoId;
    if (id == null) return 0;
    return widget.vendaRepository.saldoFiadoEmAbertoCliente(id);
  }

  Future<void> _confirmarExcluirCliente() async {
    final id = _clienteEmEdicaoId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir cliente'),
        content: const Text(
          'Confirma a exclusao deste cadastro? Esta acao nao pode ser desfeita.',
        ),
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
    if (ok != true || !mounted) return;
    if (widget.clienteRepository.remover(id)) {
      _limparFormulario();
      setState(() => _status = 'Cliente excluido.');
    }
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
          content: Text(
            'Cadastre um template manual em Configuracoes > Mensageria.',
          ),
        ),
      );
      return;
    }
    MensagemTemplate selecionado = templatesManuais.first;
    final destinoController = TextEditingController(
      text: cliente.whatsapp.trim().isNotEmpty
          ? cliente.whatsapp
          : cliente.telefone,
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

  List<Widget> _dadosPrincipaisChildren(bool formLargoTipoENome) {
    final dropdownTipo = DropdownButtonFormField<String>(
      isDense: true,
      isExpanded: true,
      initialValue: _tipoPessoa,
      decoration: const InputDecoration(
        labelText: 'Tipo de pessoa',
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(value: 'fisica', child: Text('Fisica')),
        DropdownMenuItem(value: 'juridica', child: Text('Juridica')),
      ],
      onChanged: (v) {
        if (v != null) {
          _debounceConsultaCnpj?.cancel();
          setState(() {
            _tipoPessoa = v;
            _documentoController.clear();
            if (_tipoPessoa == 'fisica') {
              _inscricaoController.clear();
            }
          });
        }
      },
    );

    final campoNomeRazao = TextField(
      controller: _nomeRazaoController,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Nome / Razao social',
        isDense: true,
      ),
    );

    final blocoDocumento = Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              SizedBox(
                width: _wDoc,
                child: TextField(
                  controller: _documentoController,
                  decoration: InputDecoration(
                    labelText: _tipoPessoa == 'fisica' ? 'CPF' : 'CNPJ',
                    isDense: true,
                    suffixIcon:
                        _tipoPessoa == 'juridica' && _consultaCnpjEmAndamento
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [_cpfCnpjFormatter],
                ),
              ),
              if (_tipoPessoa == 'juridica')
                SizedBox(
                  width: _wIe,
                  child: TextField(
                    controller: _inscricaoController,
                    decoration: const InputDecoration(
                      labelText: 'Inscricao Estadual',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
                      LengthLimitingTextInputFormatter(20),
                    ],
                  ),
                ),
            ],
          ),
          if (_tipoPessoa == 'juridica') ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: _estiloBotaoContornoCompacto,
              onPressed:
                  _consultaCnpjEmAndamento ? null : _buscarCnpjManualmente,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Buscar CNPJ'),
            ),
          ],
        ],
      ),
    );

    if (formLargoTipoENome) {
      return [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: _wTipoPessoa, child: dropdownTipo),
            const SizedBox(width: 10),
            Expanded(child: campoNomeRazao),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nomeFantasiaController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nome fantasia (opcional)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        blocoDocumento,
        ..._camposPessoaFisicaIdentificacao(),
      ];
    }

    return [
      Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: _wTipoPessoa, child: dropdownTipo),
      ),
      const SizedBox(height: 6),
      campoNomeRazao,
      const SizedBox(height: 6),
      TextField(
        controller: _nomeFantasiaController,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Nome fantasia (opcional)',
          isDense: true,
        ),
      ),
      const SizedBox(height: 6),
      blocoDocumento,
      ..._camposPessoaFisicaIdentificacao(),
    ];
  }

  Cliente? _clienteParaExtratoFiado() {
    final id = _clienteEmEdicaoId;
    if (id == null || id <= 0) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  double _limiteCreditoDigitado() =>
      double.tryParse(
        _limiteController.text.trim().replaceAll('.', '').replaceAll(',', '.'),
      ) ??
      0;

  Widget _buildResumoLimiteCredito(BuildContext context) {
    final id = _clienteEmEdicaoId;
    if (id == null) return const SizedBox.shrink();

    final limite = _limiteCreditoDigitado();
    final saldo = widget.vendaRepository.saldoFiadoEmAbertoCliente(id);
    final theme = Theme.of(context);
    final disponivel = limite > 0
        ? (limite - saldo).clamp(0.0, double.infinity).toDouble()
        : 0.0;

    String fmt(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fiado em aberto: ${fmt(saldo)}'
            '${limite > 0 ? ' · Limite: ${fmt(limite)} · Disponivel: ${fmt(disponivel)}' : ' · Sem limite cadastrado'}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (limite > 0 && saldo > limite)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Atencao: saldo acima do limite (vendas fiado finalizadas).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardComercialComLimiteDestaque() {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.payments_outlined,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Comercial',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: _fundoLimiteCredito,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _bordaLimiteCredito),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.attach_money,
                        size: 26,
                        color: _corLimiteDestaque,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Limite de credito',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _corLimiteDestaque,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Valor maximo que o cliente pode manter em aberto na loja.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _corLimiteDestaque.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_clienteEmEdicaoId != null) ...[
                    _buildResumoLimiteCredito(context),
                    if (_clienteParaExtratoFiado() != null)
                      ExtratoFiadoClienteCard(
                        vendaRepository: widget.vendaRepository,
                        cliente: _clienteParaExtratoFiado()!,
                        limiteCredito: _limiteCreditoDigitado(),
                      ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _limiteController,
                    decoration: InputDecoration(
                      labelText: 'Valor (R\$)',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.92),
                      prefixIcon: Icon(
                        Icons.paid_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_limiteCreditoFormatter],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _linhaCamposAdaptativa(
              larguraMinimaLinha: 720,
              flexes: const [2, 2, 1, 1],
              campos: [
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(_tabelaPrecoPadrao),
                  isExpanded: true,
                  initialValue: _tabelaPrecoPadrao,
                  decoration: const InputDecoration(
                    labelText: 'Tabela de preco padrao',
                    isDense: true,
                  ),
                  items: ClienteCadastro.tabelasPreco
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.$1,
                          child: Text(
                            e.$2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _tabelaPrecoPadrao = v);
                  },
                ),
                DropdownButtonFormField<int?>(
                  key: ValueKey<int?>(_vendedorResponsavelId),
                  isExpanded: true,
                  initialValue: _vendedorResponsavelId,
                  decoration: const InputDecoration(
                    labelText: 'Vendedor responsavel',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Nenhum'),
                    ),
                    ..._vendedoresAtivos.map(
                      (v) => DropdownMenuItem<int?>(
                        value: v.id,
                        child: Text(
                          v.apelido.trim().isNotEmpty
                              ? v.apelido
                              : v.nomeCompleto,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _vendedorResponsavelId = v),
                ),
                TextField(
                  controller: _prazoPagamentoController,
                  decoration: const InputDecoration(
                    labelText: 'Prazo (dias)',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(_categoriaComercial),
                  isExpanded: true,
                  initialValue: _categoriaComercial.isEmpty
                      ? ''
                      : _categoriaComercial,
                  decoration: const InputDecoration(
                    labelText: 'Categoria',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('-'),
                    ),
                    ...ClienteCadastro.categoriasComerciais.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _categoriaComercial = v ?? ''),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              value: _bloqueadoFiado,
              onChanged: (v) => setState(() => _bloqueadoFiado = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Bloquear fiado'),
              subtitle: const Text(
                'Impede vendas a prazo (fiado) no PDV e caixa.',
              ),
            ),
            if (_bloqueadoFiado) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _motivoBloqueioController,
                decoration: const InputDecoration(
                  labelText: 'Motivo do bloqueio',
                  isDense: true,
                ),
                maxLines: 2,
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _ocupacaoController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Ocupacao / profissao',
                isDense: true,
                prefixIcon: Icon(Icons.work_outline, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _observacoesController,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observacoes',
                isDense: true,
              ),
            ),
            SwitchListTile(
              dense: true,
              value: _ativo,
              onChanged: (v) => setState(() => _ativo = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Cliente ativo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraFerramentasCadastro() {
    final theme = Theme.of(context);
    final iconStyle = IconButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      minimumSize: const Size(36, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Primeiro cliente',
              style: iconStyle,
              onPressed: _irParaPrimeiroCliente,
              icon: const Icon(Icons.first_page),
            ),
            IconButton(
              tooltip: 'Cliente anterior',
              style: iconStyle,
              onPressed: _irParaClienteAnterior,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Proximo cliente',
              style: iconStyle,
              onPressed: _irParaProximoCliente,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: 'Ultimo cliente',
              style: iconStyle,
              onPressed: _irParaUltimoCliente,
              icon: const Icon(Icons.last_page),
            ),
            const VerticalDivider(width: 16),
            IconButton(
              tooltip: 'Pesquisar cliente',
              style: iconStyle,
              onPressed: _abrirPesquisaCliente,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPainelComAbas({
    required ThemeData theme,
    required bool emEdicao,
    required bool formWide,
    required List<Venda> compras,
    required double totalGasto,
    required double ticketMedio,
    required Venda? ultimaCompra,
    required int quantidadeItens,
    required List<MapEntry<String, int>> topProdutos,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          tabs: const [
            Tab(text: 'Identificacao'),
            Tab(text: 'Contato'),
            Tab(text: 'Comercial'),
            Tab(text: 'Enderecos'),
            Tab(text: 'Relacionamento'),
          ],
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _fundoPainelCadastro,
              border: Border.all(color: _bordaPainelCadastro),
            ),
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildScrollAba(
                  _buildAbaIdentificacao(theme, emEdicao, formWide),
                  _scrollAbaIdentificacao,
                ),
                _buildScrollAba(
                  _buildAbaContato(theme),
                  _scrollAbaContato,
                ),
                _buildScrollAba(
                  _buildCardComercialComLimiteDestaque(),
                  _scrollAbaComercial,
                ),
                _buildScrollAbaEndereco(theme),
                _buildScrollAbaRelacionamento(
                  theme: theme,
                  emEdicao: emEdicao,
                  compras: compras,
                  totalGasto: totalGasto,
                  ticketMedio: ticketMedio,
                  ultimaCompra: ultimaCompra,
                  quantidadeItens: quantidadeItens,
                  topProdutos: topProdutos,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScrollAba(Widget child, ScrollController controller) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        controller: controller,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 96),
        child: child,
      ),
    );
  }

  Widget _buildScrollAbaEndereco(ThemeData theme) {
    return Scrollbar(
      controller: _scrollAbaEndereco,
      thumbVisibility: true,
      trackVisibility: true,
      child: ListView(
        controller: _scrollAbaEndereco,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 96),
        children: [
          Card(
            color: theme.colorScheme.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Endereco',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildEnderecoForm(
                    titulo: 'Endereco principal / sede',
                    tipo: 'principal',
                    nomeObraController: null,
                    padraoCarreto: _principalPadraoCarreto,
                    onPadraoCarreto: () => _definirUnicoPadraoCarreto(
                      principal: true,
                    ),
                    cepController: _cepController,
                    enderecoController: _enderecoController,
                    numeroController: _numeroController,
                    bairroController: _bairroController,
                    cidadeController: _cidadeController,
                    ufController: _ufController,
                    referenciaController: _referenciaController,
                  ),
                  for (var i = 0; i < _enderecosExtras.length; i++) ...[
                    const SizedBox(height: 8),
                    _buildEnderecoForm(
                      titulo: _enderecosExtras[i].tituloExibicao(),
                      tipo: _enderecosExtras[i].tipo,
                      onTipoChanged: (v) =>
                          setState(() => _enderecosExtras[i].tipo = v),
                      nomeObraController:
                          _enderecosExtras[i].nomeObraController,
                      padraoCarreto: _enderecosExtras[i].padraoCarreto,
                      onPadraoCarreto: () => _definirUnicoPadraoCarreto(
                        principal: false,
                        indiceExtra: i,
                      ),
                      cepController: _enderecosExtras[i].cepController,
                      enderecoController:
                          _enderecosExtras[i].enderecoController,
                      numeroController: _enderecosExtras[i].numeroController,
                      bairroController: _enderecosExtras[i].bairroController,
                      cidadeController: _enderecosExtras[i].cidadeController,
                      ufController: _enderecosExtras[i].ufController,
                      referenciaController:
                          _enderecosExtras[i].referenciaController,
                      onRemover: () {
                        final removido = _enderecosExtras.removeAt(i);
                        removido.dispose();
                        setState(() {});
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      style: _estiloBotaoContornoCompacto,
                      onPressed: () {
                        setState(() {
                          _enderecosExtras.add(
                            _EnderecoFormControllers.vazio(tipo: 'entrega'),
                          );
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (!_scrollAbaEndereco.hasClients) return;
                          final pos = _scrollAbaEndereco.position;
                          pos.animateTo(
                            pos.maxScrollExtent,
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOut,
                          );
                        });
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Adicionar endereco'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbaIdentificacao(ThemeData theme, bool emEdicao, bool formWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionCard(
          context: context,
          title: 'Identificacao',
          icon: Icons.person_outline,
          children: [
            _linhaCamposAdaptativa(
              flexes: const [1, 2, 2],
              campos: [
                TextField(
                  controller: _codigoInternoController,
                  decoration: InputDecoration(
                    labelText: 'Codigo interno',
                    isDense: true,
                    hintText: emEdicao && _clienteEmEdicaoId != null
                        ? '#$_clienteEmEdicaoId'
                        : null,
                  ),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(_segmento),
                  isExpanded: true,
                  initialValue: _segmento.isEmpty ? '' : _segmento,
                  decoration: const InputDecoration(
                    labelText: 'Segmento',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Nao informado'),
                    ),
                    ...ClienteCadastro.segmentos.map(
                      (e) => DropdownMenuItem(
                        value: e.$1,
                        child: Text(
                          e.$2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _segmento = v ?? ''),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(_origemCadastro),
                  isExpanded: true,
                  initialValue:
                      _origemCadastro.isEmpty ? '' : _origemCadastro,
                  decoration: const InputDecoration(
                    labelText: 'Origem do cadastro',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Nao informado'),
                    ),
                    ...ClienteCadastro.origensCadastro.map(
                      (e) => DropdownMenuItem(
                        value: e.$1,
                        child: Text(
                          e.$2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _origemCadastro = v ?? ''),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._dadosPrincipaisChildren(formWide),
            if (_tipoPessoa == 'juridica') ...[
              const SizedBox(height: 8),
              _linhaCamposAdaptativa(
                larguraMinimaLinha: 480,
                flexes: const [1, 2],
                campos: [
                  TextField(
                    controller: _inscricaoMunicipalController,
                    decoration: const InputDecoration(
                      labelText: 'Inscricao municipal',
                      isDense: true,
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(_indicadorIe),
                    isExpanded: true,
                    initialValue: _indicadorIe.isEmpty ? '' : _indicadorIe,
                    decoration: const InputDecoration(
                      labelText: 'Indicador IE',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Nao informado'),
                      ),
                      ...ClienteCadastro.indicadoresIe.map(
                        (e) => DropdownMenuItem(
                          value: e.$1,
                          child: Text(
                            e.$2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _indicadorIe = v ?? ''),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildAbaContato(ThemeData theme) {
    return _buildSectionCard(
      context: context,
      title: 'Contato',
      icon: Icons.phone_outlined,
      children: [
        if (_tipoPessoa == 'juridica') ...[
          TextField(
            controller: _contatoPrincipalNomeController,
            decoration: const InputDecoration(
              labelText: 'Contato principal (nome)',
              isDense: true,
              prefixIcon: Icon(Icons.person_outline, size: 20),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contatoPrincipalCargoController,
            decoration: const InputDecoration(
              labelText: 'Cargo / funcao na obra',
              isDense: true,
              prefixIcon: Icon(Icons.engineering_outlined, size: 20),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _telefoneController,
          decoration: const InputDecoration(
            labelText: 'Telefone',
            isDense: true,
          ),
          keyboardType: TextInputType.phone,
          inputFormatters: [_telefoneFormatter],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _whatsappController,
          decoration: const InputDecoration(
            labelText: 'WhatsApp',
            isDense: true,
          ),
          keyboardType: TextInputType.phone,
          inputFormatters: [_telefoneFormatter],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'E-mail',
            isDense: true,
          ),
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
          inputFormatters: [_emailFormatter],
        ),
      ],
    );
  }

  /// Historico sem [ExpansionTile]: o corpo do tile usa [Expansible] com
  /// [ClipRect]/[Align.heightFactor], o que pode truncar listas longas dentro
  /// de scroll. Aqui um [ListView] com [ScrollController] ligado ao [Scrollbar].
  Widget _buildScrollAbaRelacionamento({
    required ThemeData theme,
    required bool emEdicao,
    required List<Venda> compras,
    required double totalGasto,
    required double ticketMedio,
    required Venda? ultimaCompra,
    required int quantidadeItens,
    required List<MapEntry<String, int>> topProdutos,
  }) {
    final tituloSecao = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Scrollbar(
      controller: _scrollAbaRelacionamento,
      thumbVisibility: true,
      trackVisibility: true,
      child: ListView(
        controller: _scrollAbaRelacionamento,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 48),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Historico de compras',
                          style: tituloSecao,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!emEdicao)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Salve o cliente para habilitar o historico de compras.',
                          ),
                        )
                      else ...[
                        DropdownButtonFormField<String>(
                          initialValue: _periodoHistorico,
                          decoration: const InputDecoration(
                            labelText: 'Periodo do historico',
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'todo',
                              child: Text('Todo o periodo'),
                            ),
                            DropdownMenuItem(
                              value: 'ultimos_30',
                              child: Text('Ultimos 30 dias'),
                            ),
                            DropdownMenuItem(
                              value: 'ultimos_90',
                              child: Text('Ultimos 90 dias'),
                            ),
                            DropdownMenuItem(
                              value: 'ano_atual',
                              child: Text('Ano atual'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _periodoHistorico = value);
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total ja gasto na loja: ${_formatarMoeda(totalGasto)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text('Ticket medio: ${_formatarMoeda(ticketMedio)}'),
                        Text('Total de itens comprados: $quantidadeItens'),
                        Text(
                          'Ultima compra: ${ultimaCompra == null ? 'Nao disponivel' : _dataHora.format(ultimaCompra.data.toLocal())}',
                        ),
                        Text('Compras registradas: ${compras.length}'),
                        if (topProdutos.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Top produtos',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          ...topProdutos
                              .take(3)
                              .map((e) => Text('${e.key} - ${e.value} un')),
                        ],
                        const SizedBox(height: 8),
                        if (compras.isEmpty)
                          const Text(
                            'Este cliente ainda nao tem compras finalizadas.',
                          )
                        else
                          ...compras.map((compra) {
                            final nota = compra.numeroOrcamento > 0
                                ? '${compra.numeroOrcamento}'
                                : 'ID ${compra.id}';
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 0,
                              ),
                              leading: const Icon(
                                Icons.receipt_long_outlined,
                                size: 20,
                              ),
                              title: Text('Nota/Orcamento: $nota'),
                              subtitle: Text(
                                _dataHora.format(compra.data.toLocal()),
                              ),
                              trailing: Text(
                                _formatarMoeda(compra.total),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mensagens enviadas',
                          style: tituloSecao,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: !emEdicao
                      ? const Text(
                          'Salve o cliente para habilitar logs de mensagens.',
                        )
                      : FutureBuilder<List<MensagemLog>>(
                          key: ValueKey<int?>(_clienteEmEdicaoId),
                          future: _mensageriaRepository.listarLogsPorCliente(
                            _clienteEmEdicaoId!,
                          ),
                          builder: (context, snapshot) {
                            final logs = snapshot.data ?? const <MensagemLog>[];
                            final clienteAtual = _clienteEmEdicaoAtual();
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: LinearProgressIndicator(),
                              );
                            }
                            if (clienteAtual == null) {
                              return const Text('Cliente nao encontrado.');
                            }
                            if (logs.isEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _enviarMensagemManualCliente(
                                          clienteAtual,
                                        ),
                                    icon: const Icon(
                                      Icons.send_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Enviar mensagem agora'),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Nenhum log de mensagem para este cliente.',
                                  ),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _enviarMensagemManualCliente(clienteAtual),
                                  icon: const Icon(
                                    Icons.send_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Enviar mensagem agora'),
                                ),
                                const SizedBox(height: 8),
                                ...logs.map((log) {
                                  final enviado = log.resultado == 'enviado';
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    leading: Icon(
                                      enviado
                                          ? Icons.check_circle_outline
                                          : Icons.error_outline,
                                      size: 20,
                                      color: enviado
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.error,
                                    ),
                                    title: Text(
                                      '${log.canal.toUpperCase()} - ${_rotuloStatusMensagem(log.statusEntrega)}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    subtitle: Text(
                                      '${_dataHora.format(log.criadoEm.toLocal())}\n${log.destino}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    isThreeLine: true,
                                    trailing: log.resultado == 'falhou'
                                        ? IconButton(
                                            tooltip: 'Ver erro',
                                            onPressed: () =>
                                                _verErroDetalhadoLogCliente(
                                                  log,
                                                ),
                                            icon: const Icon(
                                              Icons.error_outline,
                                              size: 20,
                                            ),
                                          )
                                        : null,
                                  );
                                }),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      (acc, compra) =>
          acc +
          compra.itens.fold<int>(0, (soma, item) => soma + item.quantidade),
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
    final limiteDigitado = _limiteCreditoDigitado();
    final fiadoAberto = emEdicao ? _fiadoAbertoClienteAtual() : 0.0;
    final creditoDisp = limiteDigitado > 0
        ? (limiteDigitado - fiadoAberto).clamp(0.0, double.infinity)
        : 0.0;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.f5): _CadastroClienteSalvarIntent(),
        SingleActivator(LogicalKeyboardKey.escape):
            _CadastroClienteCancelarIntent(),
      },
      child: Actions(
        actions: {
          _CadastroClienteSalvarIntent: CallbackAction(
            onInvoke: (_) {
              _salvarCliente();
              return null;
            },
          ),
          _CadastroClienteCancelarIntent: CallbackAction(
            onInvoke: (_) {
              _limparFormulario();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(title: const Text('Cadastro de Clientes')),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _maxLarguraFormulario,
                        ),
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final formWide = box.maxWidth >= 680;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ClienteCadastroHeader(
                                  emEdicao: emEdicao,
                                  clienteId: _clienteEmEdicaoId,
                                  nomeRazao: _nomeRazaoController.text,
                                  tipoPessoa: _tipoPessoa,
                                  documento: _documentoController.text,
                                  ativo: _ativo,
                                  segmento: _segmento,
                                  codigoInterno: _codigoInternoController
                                          .text
                                          .trim()
                                          .isNotEmpty
                                      ? _codigoInternoController.text.trim()
                                      : (emEdicao &&
                                              _clienteEmEdicaoId != null
                                          ? '#${_clienteEmEdicaoId}'
                                          : 'Novo'),
                                  totalGasto: emEdicao
                                      ? _formatarMoeda(totalGasto)
                                      : null,
                                  ultimaCompraTexto: emEdicao
                                      ? (ultimaCompra == null
                                          ? 'Sem compras'
                                          : _dataHora.format(
                                              ultimaCompra.data.toLocal(),
                                            ))
                                      : null,
                                  fiadoAberto: emEdicao && limiteDigitado > 0
                                      ? _formatarMoeda(fiadoAberto)
                                      : null,
                                  creditoDisponivel:
                                      emEdicao && limiteDigitado > 0
                                          ? _formatarMoeda(creditoDisp)
                                          : null,
                                  limiteCredito: limiteDigitado,
                                ),
                                const SizedBox(height: 6),
                                _buildBarraFerramentasCadastro(),
                                if (_status.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  _buildStatusBanner(context, _status),
                                ],
                                const SizedBox(height: 6),
                                Expanded(
                                  child: _buildPainelComAbas(
                                    theme: theme,
                                    emEdicao: emEdicao,
                                    formWide: formWide,
                                    compras: compras,
                                    totalGasto: totalGasto,
                                    ticketMedio: ticketMedio,
                                    ultimaCompra: ultimaCompra,
                                    quantidadeItens: quantidadeItens,
                                    topProdutos: topProdutos,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                ClienteCadastroRodape(
                  emEdicao: emEdicao,
                  onSalvar: _salvarCliente,
                  onNovo: _limparFormulario,
                  onLimpar: _limparFormulario,
                  podeExcluir: emEdicao && _clienteEmEdicaoId != null,
                  onExcluir: _confirmarExcluirCliente,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Empilha em coluna em telas estreitas; em telas largas usa [Row] com [Expanded].
  Widget _linhaCamposAdaptativa({
    required List<Widget> campos,
    double larguraMinimaLinha = 620,
    double espacamento = 10,
    List<double>? flexes,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        if (maxW < larguraMinimaLinha) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < campos.length; i++) ...[
                if (i > 0) SizedBox(height: espacamento),
                campos[i],
              ],
            ],
          );
        }
        final flexList = flexes ?? List<double>.filled(campos.length, 1);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < campos.length; i++) ...[
              if (i > 0) SizedBox(width: espacamento),
              Expanded(flex: flexList[i].round(), child: campos[i]),
            ],
          ],
        );
      },
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
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildEnderecoForm({
    required String titulo,
    required String tipo,
    TextEditingController? nomeObraController,
    ValueChanged<String>? onTipoChanged,
    bool padraoCarreto = false,
    VoidCallback? onPadraoCarreto,
    required TextEditingController cepController,
    required TextEditingController enderecoController,
    required TextEditingController numeroController,
    required TextEditingController bairroController,
    required TextEditingController cidadeController,
    required TextEditingController ufController,
    required TextEditingController referenciaController,
    VoidCallback? onRemover,
  }) {
    final alvoCep = _AlvoPreenchimentoCep(
      cep: cepController,
      endereco: enderecoController,
      numero: numeroController,
      bairro: bairroController,
      cidade: cidadeController,
      uf: ufController,
    );
    final cepConsultando = _consultaCepEmAndamento &&
        identical(_cepControllerEmConsulta, cepController);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cepCidadeUfUmaLinha = constraints.maxWidth >= 520;
        final campoCep = SizedBox(
          width: _wCep,
          child: TextField(
            controller: cepController,
            decoration: InputDecoration(
              labelText: 'CEP',
              isDense: true,
              suffixIcon: cepConsultando
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [_cepFormatter],
            onChanged: (_) => _agendarConsultaCep(alvoCep),
          ),
        );
        final campoCidade = TextField(
          controller: cidadeController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Cidade',
            isDense: true,
          ),
        );
        final campoUf = SizedBox(
          width: _wUf,
          child: TextField(
            controller: ufController,
            decoration: const InputDecoration(
              labelText: 'UF',
              isDense: true,
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
              LengthLimitingTextInputFormatter(2),
              UpperCaseTextFormatter(),
            ],
          ),
        );

        final linhaCepBuscar = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            campoCep,
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: _estiloBotaoContornoCompacto,
                  onPressed: cepConsultando
                      ? null
                      : () => _buscarCepManual(alvoCep),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Buscar CEP'),
                ),
              ),
            ),
          ],
        );

        final linhaEnderecoNumero = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: enderecoController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Endereco',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: _wNumero,
              child: TextField(
                controller: numeroController,
                decoration: const InputDecoration(
                  labelText: 'Nº',
                  isDense: true,
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(10)],
              ),
            ),
          ],
        );

        final campoBairro = TextField(
          controller: bairroController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Bairro',
            isDense: true,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (onRemover != null)
                  IconButton(
                    tooltip: 'Remover endereco',
                    onPressed: onRemover,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
              ],
            ),
            if (onTipoChanged != null || onPadraoCarreto != null) ...[
              const SizedBox(height: 6),
              _linhaCamposAdaptativa(
                larguraMinimaLinha: 520,
                campos: [
                  if (onTipoChanged != null)
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(tipo),
                      isExpanded: true,
                      initialValue: tipo,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        isDense: true,
                      ),
                      items: ClienteCadastro.tiposEndereco
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.$1,
                              child: Text(e.$2),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) onTipoChanged(v);
                      },
                    ),
                  if (nomeObraController != null &&
                      (tipo == 'obra' || tipo == 'entrega'))
                    TextField(
                      controller: nomeObraController,
                      decoration: const InputDecoration(
                        labelText: 'Nome da obra / referencia',
                        isDense: true,
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  if (onPadraoCarreto != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        label: const Text('Padrao para carreto (PDV)'),
                        selected: padraoCarreto,
                        onSelected: (_) => onPadraoCarreto(),
                      ),
                    ),
                ],
              ),
            ] else if (onPadraoCarreto != null) ...[
              const SizedBox(height: 4),
              FilterChip(
                label: const Text('Padrao para carreto (PDV)'),
                selected: padraoCarreto,
                onSelected: (_) => onPadraoCarreto(),
              ),
            ],
            const SizedBox(height: 6),
            linhaCepBuscar,
            const SizedBox(height: 6),
            linhaEnderecoNumero,
            const SizedBox(height: 6),
            campoBairro,
            const SizedBox(height: 6),
            if (cepCidadeUfUmaLinha)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: campoCidade),
                  const SizedBox(width: 8),
                  campoUf,
                ],
              )
            else ...[
              campoCidade,
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: campoUf,
              ),
            ],
            const SizedBox(height: 6),
            TextField(
              controller: referenciaController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Referencia',
                isDense: true,
              ),
            ),
          ],
        );
      },
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
          Icon(
            sucesso ? Icons.check_circle_outline : Icons.error_outline,
            color: fg,
          ),
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
    final masked = truncated.length <= 11
        ? _maskCpf(truncated)
        : _maskCnpj(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  String _maskCpf(String value) {
    if (value.length <= 3) return value;
    if (value.length <= 6) {
      return '${value.substring(0, 3)}.${value.substring(3)}';
    }
    if (value.length <= 9) {
      return '${value.substring(0, 3)}.${value.substring(3, 6)}.${value.substring(6)}';
    }
    return '${value.substring(0, 3)}.${value.substring(3, 6)}.${value.substring(6, 9)}-${value.substring(9)}';
  }

  String _maskCnpj(String value) {
    if (value.length <= 2) return value;
    if (value.length <= 5) {
      return '${value.substring(0, 2)}.${value.substring(2)}';
    }
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
    if (value.length <= 6) {
      return '(${value.substring(0, 2)}) ${value.substring(2)}';
    }
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

class _EnderecoFormControllers {
  _EnderecoFormControllers({
    required this.tipo,
    required this.nomeObraController,
    this.padraoCarreto = false,
    required this.cepController,
    required this.enderecoController,
    required this.numeroController,
    required this.bairroController,
    required this.cidadeController,
    required this.ufController,
    required this.referenciaController,
  });

  factory _EnderecoFormControllers.vazio({String tipo = 'entrega'}) {
    return _EnderecoFormControllers(
      tipo: ClienteCadastro.normalizarTipoEndereco(tipo),
      nomeObraController: TextEditingController(),
      cepController: TextEditingController(),
      enderecoController: TextEditingController(),
      numeroController: TextEditingController(),
      bairroController: TextEditingController(),
      cidadeController: TextEditingController(),
      ufController: TextEditingController(),
      referenciaController: TextEditingController(),
    );
  }

  factory _EnderecoFormControllers.fromEndereco(EnderecoCliente endereco) {
    return _EnderecoFormControllers(
      tipo: ClienteCadastro.normalizarTipoEndereco(endereco.tipo),
      nomeObraController: TextEditingController(text: endereco.nomeObra),
      padraoCarreto: endereco.padraoCarreto,
      cepController: TextEditingController(text: endereco.cep),
      enderecoController: TextEditingController(text: endereco.endereco),
      numeroController: TextEditingController(text: endereco.numero),
      bairroController: TextEditingController(text: endereco.bairro),
      cidadeController: TextEditingController(text: endereco.cidade),
      ufController: TextEditingController(text: endereco.uf),
      referenciaController: TextEditingController(text: endereco.referencia),
    );
  }

  String tipo;
  final TextEditingController nomeObraController;
  bool padraoCarreto;
  final TextEditingController cepController;
  final TextEditingController enderecoController;
  final TextEditingController numeroController;
  final TextEditingController bairroController;
  final TextEditingController cidadeController;
  final TextEditingController ufController;
  final TextEditingController referenciaController;

  String tituloExibicao() {
    return EnderecoCliente(
      tipo: tipo,
      nomeObra: nomeObraController.text,
    ).tituloExibicao();
  }

  EnderecoCliente toEndereco() {
    return EnderecoCliente(
      tipo: ClienteCadastro.normalizarTipoEndereco(tipo),
      nomeObra: nomeObraController.text.trim(),
      padraoCarreto: padraoCarreto,
      cep: cepController.text.replaceAll(RegExp(r'\D'), ''),
      endereco: enderecoController.text.trim(),
      numero: numeroController.text.trim(),
      bairro: bairroController.text.trim(),
      cidade: cidadeController.text.trim(),
      uf: ufController.text.trim().toUpperCase(),
      referencia: referenciaController.text.trim(),
    );
  }

  void dispose() {
    nomeObraController.dispose();
    cepController.dispose();
    enderecoController.dispose();
    numeroController.dispose();
    bairroController.dispose();
    cidadeController.dispose();
    ufController.dispose();
    referenciaController.dispose();
  }
}
