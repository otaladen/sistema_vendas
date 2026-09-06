import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../domain/cliente_cadastro.dart';
import '../data/api/cliente_api_repository.dart';
import '../data/api/venda_api_repository.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/vendedor.dart';
import '../services/brasil_api_cep_service.dart';
import 'widgets/cliente_endereco_ibge_selector.dart';
import '../services/brasil_api_cnpj_service.dart';
import '../model/venda.dart';
import 'layout/app_layout.dart';
import 'theme/app_semantic_helper.dart';
import 'widgets/cliente/cliente_cadastro_header.dart';
import 'widgets/cliente/cliente_cadastro_rodape.dart';
import 'widgets/extrato_fiado_cliente_card.dart';
import 'widgets/lan_api_feedback.dart';
import 'widgets/mascaras_cadastro_input.dart';

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

  final dynamic clienteRepository;
  final dynamic vendaRepository;
  final dynamic vendedorRepository;
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
    this.codigoIbge,
  });

  final TextEditingController cep;
  final TextEditingController endereco;
  final TextEditingController numero;
  final TextEditingController bairro;
  final TextEditingController cidade;
  final TextEditingController uf;
  final TextEditingController? codigoIbge;
}

class _ClientesPageState extends State<ClientesPage>
    with SingleTickerProviderStateMixin {
  static ButtonStyle get _estiloBotaoContornoCompacto => OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  static const double _wDoc = 228;
  static const double _wIe = 200;
  static const double _wCep = 120;
  static const double _wNumero = 88;
  static const double _wUf = 72;
  /// Padding unico dos campos do cadastro (mesma altura do dropdown Tipo).
  static const EdgeInsets _padCampoCadastro =
      EdgeInsets.symmetric(horizontal: 10, vertical: 10);
  static const BoxConstraints _iconCampoCadastro = BoxConstraints(
    minWidth: 28,
    minHeight: 28,
    maxWidth: 32,
    maxHeight: 32,
  );

  final _nomeRazaoController = TextEditingController();
  final _nomeRazaoFocus = FocusNode(debugLabel: 'clienteNomeRazao');
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
  final _codigoIbgeController = TextEditingController();
  final _referenciaController = TextEditingController();
  final _limiteController = TextEditingController();
  final _observacoesController = TextEditingController();
  final _rgController = TextEditingController();
  final _nascimentoController = TextEditingController();
  final _ocupacaoController = TextEditingController();
  final _codigoInternoController = TextEditingController();
  final _inscricaoMunicipalController = TextEditingController();
  final _contatoPrincipalNomeController = TextEditingController();
  final _contatoPrincipalCargoController = TextEditingController();
  final _motivoBloqueioController = TextEditingController();
  final _prazoPagamentoController = TextEditingController();
  String _sexoCliente = '';
  final List<_EnderecoFormControllers> _enderecosExtras = [];
  bool _principalPadraoCarreto = true;

  int? _clienteEmEdicaoId;
  /// Saldo de fiado (cache); no Terminal Leve e atualizado via API.
  double _saldoFiadoCache = 0;
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
  String? _erroDocumento;
  late final _cpfCnpjFormatter = _CpfCnpjInputFormatter();
  late final _telefoneFormatter = _TelefoneInputFormatter();
  late final _cepFormatter = _CepInputFormatter();
  late final _emailFormatter = _EmailInputFormatter();
  late final _limiteCreditoFormatter = _MoedaInputFormatter();
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat _dataNascimentoFmt = DateFormat('dd/MM/yyyy');
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  String _periodoHistorico = 'todo';
  List<Venda> _comprasClienteCache = [];
  bool _carregandoCompras = false;

  Timer? _debounceConsultaCnpj;
  Timer? _debounceConsultaCep;
  bool _carregandoClienteNoFormulario = false;
  bool _consultaCnpjEmAndamento = false;
  bool _consultaCepEmAndamento = false;
  TextEditingController? _cepControllerEmConsulta;
  final ScrollController _scrollFormulario = ScrollController();
  final ScrollController _scrollRelacionamento = ScrollController();
  late final TabController _tabController;

  void _onClienteApiChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _documentoController.addListener(_onDocumentoChanged);
    final repo = widget.clienteRepository;
    if (repo is ClienteApiRepository) {
      repo.addListener(_onClienteApiChanged);
      unawaited(_hidratarClientesTerminal());
    }
    _vendedoresAtivos =
        widget.vendedorRepository?.listarAtivos() ?? const [];
    final idInicial = widget.clienteIdInicial;
    if (idInicial != null && idInicial > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_abrirClienteIdInicial(idInicial));
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focarCampoNome();
      });
    }
  }

  void _focarCampoNome() {
    if (!mounted) return;
    if (_nomeRazaoFocus.canRequestFocus) {
      _nomeRazaoFocus.requestFocus();
    }
  }

  Future<void> _hidratarClientesTerminal() async {
    final repo = widget.clienteRepository;
    if (repo is! ClienteApiRepository) return;
    try {
      await repo.hidratar();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackAviso(context, e, prefixo: 'Clientes');
    }
  }

  Future<void> _abrirClienteIdInicial(int id) async {
    final repo = widget.clienteRepository;
    Cliente? c;
    if (repo is ClienteApiRepository) {
      c = await repo.obterPorIdRemoto(id) ?? repo.obterPorId(id);
    } else {
      c = repo.obterPorId(id) as Cliente?;
    }
    if (c != null && mounted) _editarCliente(c);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounceConsultaCnpj?.cancel();
    _debounceConsultaCep?.cancel();
    final repo = widget.clienteRepository;
    if (repo is ClienteApiRepository) {
      repo.removeListener(_onClienteApiChanged);
    }
    _documentoController.removeListener(_onDocumentoChanged);
    _nomeRazaoFocus.dispose();
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
    _codigoIbgeController.dispose();
    _referenciaController.dispose();
    _limiteController.dispose();
    _observacoesController.dispose();
    _rgController.dispose();
    _nascimentoController.dispose();
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
    _scrollFormulario.dispose();
    _scrollRelacionamento.dispose();
    super.dispose();
  }

  Future<void> _abrirPesquisaCliente() async {
    final pesquisaController = TextEditingController();
    final resultadosScrollController = ScrollController();
    final pesquisaFocusNode = FocusNode();
    List<Cliente> resultados = List<Cliente>.from(
      widget.clienteRepository.listarTodos() as List,
    );
    int indiceSelecionado = resultados.isEmpty ? -1 : 0;
    Timer? debounceApi;

    List<Cliente> filtrarLocal(String value) {
      final termo = value.trim().toLowerCase();
      final termoNumerico = _somenteDigitos(value);
      final base = List<Cliente>.from(
        widget.clienteRepository.listarTodos() as List,
      );
      if (termo.isEmpty && termoNumerico.isEmpty) return base;
      return base.where((cliente) {
        final campos = [
          cliente.nomeRazao,
          cliente.nomeFantasia,
          cliente.documento,
          cliente.telefone,
          cliente.whatsapp,
          cliente.email,
          cliente.cidade,
        ].map((e) => e.toLowerCase());
        if (campos.any((campo) => campo.contains(termo))) return true;
        if (termoNumerico.isEmpty) return false;
        final camposNumericos = [
          cliente.documento,
          cliente.telefone,
          cliente.whatsapp,
          cliente.cep,
        ].map((s) => _somenteDigitos('$s'));
        return camposNumericos.any(
          (campoNumerico) => campoNumerico.contains(termoNumerico),
        );
      }).toList();
    }

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
                content: AdaptiveDialogPane(
                  desktopWidth: 760,
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
                          setDialogState(() {
                            resultados = filtrarLocal(value);
                            indiceSelecionado = resultados.isEmpty ? -1 : 0;
                          });
                          final repo = widget.clienteRepository;
                          if (repo is ClienteApiRepository) {
                            debounceApi?.cancel();
                            debounceApi = Timer(
                              const Duration(milliseconds: 320),
                              () async {
                                final termo = value.trim();
                                if (termo.isEmpty) return;
                                try {
                                  final remotos =
                                      await repo.pesquisarRemoto(termo);
                                  if (!context.mounted) return;
                                  setDialogState(() {
                                    resultados = remotos;
                                    indiceSelecionado =
                                        resultados.isEmpty ? -1 : 0;
                                  });
                                } catch (_) {}
                              },
                            );
                          }
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
                          minHeight: context.isCompactLayout ? 120 : 220,
                          maxHeight: adaptiveDialogListMaxHeight(context),
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

    debounceApi?.cancel();
    pesquisaController.dispose();
    resultadosScrollController.dispose();
    pesquisaFocusNode.dispose();

    if (clienteSelecionado != null) {
      await _editarClienteComRefresh(clienteSelecionado);
    }
  }

  Future<void> _editarClienteComRefresh(Cliente c) async {
    final repo = widget.clienteRepository;
    if (repo is ClienteApiRepository && c.id > 0) {
      final fresco = await repo.obterPorIdRemoto(c.id);
      if (fresco != null && mounted) {
        _editarCliente(fresco);
        return;
      }
    }
    _editarCliente(c);
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
      _codigoIbgeController.clear();
      _referenciaController.clear();
      _enderecosExtras.clear();
      _limiteController.clear();
      _observacoesController.clear();
      _rgController.clear();
      _nascimentoController.clear();
      _ocupacaoController.clear();
      _codigoInternoController.clear();
      _inscricaoMunicipalController.clear();
      _contatoPrincipalNomeController.clear();
      _contatoPrincipalCargoController.clear();
      _motivoBloqueioController.clear();
      _prazoPagamentoController.clear();
      _sexoCliente = '';
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
      _saldoFiadoCache = 0;
      _comprasClienteCache = [];
      _carregandoCompras = false;
      _status = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focarCampoNome();
    });
  }

  Future<void> _salvarCliente() async {
    final nomeRazao = _nomeRazaoController.text.trim();
    if (nomeRazao.isEmpty) {
      setState(() {
        _status = 'Nome/Razao social e obrigatorio.';
      });
      return;
    }
    final doc = _documentoController.text.trim();
    if (!documentoCpfCnpjValidoOuVazio(doc, tipoPessoa: _tipoPessoa)) {
      setState(() {
        _erroDocumento = _tipoPessoa == 'fisica'
            ? 'CPF invalido.'
            : 'CNPJ invalido.';
        _status = _erroDocumento!;
      });
      return;
    }
    setState(() => _erroDocumento = null);
    DateTime? dataNascimento;
    if (_tipoPessoa == 'fisica') {
      final nascDigitos = _somenteDigitos(_nascimentoController.text);
      if (nascDigitos.isNotEmpty) {
        dataNascimento = parseDataDdMmYyyy(_nascimentoController.text);
        if (dataNascimento == null) {
          setState(() {
            _status = 'Nascimento invalido. Use 00/00/0000.';
          });
          return;
        }
      }
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
      dataNascimento: dataNascimento == null
          ? null
          : DateTime.utc(
              dataNascimento.year,
              dataNascimento.month,
              dataNascimento.day,
            ),
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
    final repo = widget.clienteRepository;
    try {
      final int clienteId;
      if (repo is ClienteApiRepository) {
        clienteId = await repo.salvarRemoto(cliente);
      } else {
        clienteId = repo.salvar(cliente) as int;
      }
      final clienteSalvo = widget.clienteRepository.obterPorId(clienteId);
      if (!mounted) return;
      if (widget.retornarClienteAoSalvar && clienteSalvo != null) {
        Navigator.pop(context, clienteSalvo);
        return;
      }
      _limparFormulario();
      setState(() {
        _status = 'Cliente salvo com sucesso.';
      });
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel salvar');
      setState(() => _status = LanApiFeedback.mensagem(e));
    }
  }

  String _somenteDigitos(String valor) {
    return valor.replaceAll(RegExp(r'\D'), '');
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
      final dados = await BrasilApiCepService.consultarComIbge(digitos) ??
          await BrasilApiCepService.consultar(digitos);
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
      final ibge = dados.codigoIbge.replaceAll(RegExp(r'\D'), '');
      setState(() {
        alvo.endereco.text = dados.logradouro;
        alvo.bairro.text = dados.bairro;
        alvo.cidade.text = dados.cidade;
        alvo.uf.text = dados.uf;
        alvo.cep.text = dados.cep;
        if (alvo.codigoIbge != null && ibge.length == 7) {
          alvo.codigoIbge!.text = ibge;
        }
      });
      if (ibge.length != 7 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'CEP encontrado, mas sem codigo IBGE na BrasilAPI. '
              'Preencha o IBGE do municipio manualmente (7 digitos) para NF-e.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
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
      _nascimentoController.text = c.dataNascimento == null
          ? ''
          : _dataNascimentoFmt.format(
              DateTime(
                c.dataNascimento!.toUtc().year,
                c.dataNascimento!.toUtc().month,
                c.dataNascimento!.toUtc().day,
              ),
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
      _codigoIbgeController.text = principal.codigoIbge;
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
      _saldoFiadoCache = widget.vendaRepository is VendaApiRepository
          ? (widget.vendaRepository as VendaApiRepository)
              .saldoFiadoEmAbertoCliente(c.id)
          : (widget.vendaRepository.saldoFiadoEmAbertoCliente(c.id) as num)
              .toDouble();
    });
    _padronizarMascarasCamposCliente();
    _carregandoClienteNoFormulario = false;
    _debounceConsultaCnpj?.cancel();
    _debounceConsultaCep?.cancel();
    unawaited(_atualizarSaldoFiadoRemoto(c.id));
    unawaited(_carregarComprasCliente(c.id));
  }

  Future<void> _atualizarSaldoFiadoRemoto(int clienteId) async {
    if (clienteId <= 0) return;
    try {
      final double saldo;
      if (widget.vendaRepository is VendaApiRepository) {
        saldo = await (widget.vendaRepository as VendaApiRepository)
            .saldoFiadoEmAbertoClienteRemoto(
          clienteId,
          onResumoCredito: ({
            double? limiteCredito,
            bool? bloqueadoFiado,
            String? motivoBloqueio,
          }) {
            final cliRepo = widget.clienteRepository;
            if (cliRepo is ClienteApiRepository) {
              cliRepo.aplicarResumoCredito(
                clienteId: clienteId,
                limiteCredito: limiteCredito,
                bloqueadoFiado: bloqueadoFiado,
                motivoBloqueio: motivoBloqueio,
              );
            }
            if (!mounted || _clienteEmEdicaoId != clienteId) return;
            setState(() {
              if (bloqueadoFiado != null) _bloqueadoFiado = bloqueadoFiado;
              if (motivoBloqueio != null && motivoBloqueio.isNotEmpty) {
                _motivoBloqueioController.text = motivoBloqueio;
              }
              if (limiteCredito != null && limiteCredito > 0) {
                _limiteController.text = limiteCredito
                    .toStringAsFixed(2)
                    .replaceAll('.', ',');
              }
            });
          },
        );
      } else {
        saldo = (widget.vendaRepository.saldoFiadoEmAbertoCliente(clienteId)
                as num)
            .toDouble();
      }
      if (!mounted || _clienteEmEdicaoId != clienteId) return;
      setState(() => _saldoFiadoCache = saldo);
    } catch (_) {
      // Mantem cache anterior; extrato/limite usam o valor disponivel.
    }
  }

  List<Cliente> _clientesOrdenadosPorCadastro() {
    final clientes = List<Cliente>.from(
      widget.clienteRepository.listarTodos() as List,
    );
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
        codigoIbge: _somenteDigitos(_codigoIbgeController.text),
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
    return _saldoFiadoCache;
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
    final repo = widget.clienteRepository;
    try {
      final bool removido;
      if (repo is ClienteApiRepository) {
        removido = await repo.removerRemoto(id);
      } else {
        removido = repo.remover(id) as bool;
      }
      if (!mounted) return;
      if (!removido) {
        LanApiFeedback.snackAviso(
          context,
          'Nao foi possivel excluir o cliente.',
        );
        return;
      }
      _limparFormulario();
      setState(() => _status = 'Cliente excluido.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente excluido com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel excluir');
      setState(() => _status = LanApiFeedback.mensagem(e));
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
    if (_comprasClienteCache.isNotEmpty) {
      final limites = _limitesPeriodoHistorico();
      final inicioUtc = limites.$1?.toUtc();
      final fimUtc = limites.$2?.toUtc();
      return _comprasClienteCache.where((venda) {
        final d = venda.data.toUtc();
        if (inicioUtc != null && d.isBefore(inicioUtc)) return false;
        if (fimUtc != null && d.isAfter(fimUtc)) return false;
        return true;
      }).toList();
    }
    final limites = _limitesPeriodoHistorico();
    try {
      return List<Venda>.from(
        widget.vendaRepository.listarComprasFinalizadasPorCliente(
          clienteId,
          inicio: limites.$1,
          fim: limites.$2,
        ) as List,
      );
    } catch (_) {
      return const [];
    }
  }

  List<ItemVenda> _itensDaCompraSafe(Venda compra) {
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      return repo.itensDaVendaSafe(compra);
    }
    try {
      final via = repo.listarItensPorVenda(compra.id);
      if (via is List && via.isNotEmpty) {
        return List<ItemVenda>.from(via);
      }
    } catch (_) {}
    try {
      return List<ItemVenda>.from(compra.itens);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _carregarComprasCliente(int clienteId) async {
    if (clienteId <= 0) {
      _comprasClienteCache = [];
      return;
    }
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      setState(() => _carregandoCompras = true);
      try {
        final limites = _limitesPeriodoHistorico();
        final lista = await repo.listarComprasFinalizadasPorClienteRemoto(
          clienteId,
          inicio: limites.$1,
          fim: limites.$2,
          limit: 300,
        );
        if (!mounted || _clienteEmEdicaoId != clienteId) return;
        setState(() {
          _comprasClienteCache = lista;
          _carregandoCompras = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _carregandoCompras = false);
        LanApiFeedback.snackAviso(context, e, prefixo: 'Historico');
      }
      return;
    }
    try {
      final limites = _limitesPeriodoHistorico();
      final lista = List<Venda>.from(
        repo.listarComprasFinalizadasPorCliente(
          clienteId,
          inicio: limites.$1,
          fim: limites.$2,
        ) as List,
      );
      if (!mounted || _clienteEmEdicaoId != clienteId) return;
      setState(() => _comprasClienteCache = lista);
    } catch (_) {}
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  List<Widget> _dadosPrincipaisChildren(bool emEdicao) {
    final dropdownStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        );
    final dropdownTipo = DropdownButtonFormField<String>(
      isDense: true,
      isExpanded: true,
      initialValue: _tipoPessoa,
      style: dropdownStyle,
      decoration: const InputDecoration(
        labelText: 'Tipo de pessoa',
        isDense: true,
      ),
      items: [
        DropdownMenuItem(
          value: 'fisica',
          child: Text('Física', style: dropdownStyle),
        ),
        DropdownMenuItem(
          value: 'juridica',
          child: Text('Jurídica', style: dropdownStyle),
        ),
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

    final campoCodigoInterno = TextField(
      controller: _codigoInternoController,
      decoration: InputDecoration(
        labelText: 'Código interno',
        isDense: true,
        hintText: emEdicao && _clienteEmEdicaoId != null
            ? '#$_clienteEmEdicaoId'
            : null,
      ),
    );

    final campoNomeRazao = TextField(
      controller: _nomeRazaoController,
      focusNode: _nomeRazaoFocus,
      autofocus: _clienteEmEdicaoId == null,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Nome / Razão social',
        isDense: true,
      ),
    );

    final campoRg = TextField(
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
    );
    final campoNascimento = TextField(
      controller: _nascimentoController,
      keyboardType: TextInputType.number,
      inputFormatters: [DataDdMmYyyyInputFormatter()],
      decoration: const InputDecoration(
        labelText: 'Nascimento',
        hintText: '00/00/0000',
        isDense: true,
      ),
    );
    final campoSexo = DropdownButtonFormField<String>(
      key: ValueKey<String>(_sexoCliente),
      initialValue: _sexoCliente,
      isDense: true,
      isExpanded: true,
      style: dropdownStyle,
      decoration: const InputDecoration(
        labelText: 'Sexo',
        isDense: true,
      ),
      items: [
        DropdownMenuItem(
          value: '',
          child: Text('Não informado', overflow: TextOverflow.ellipsis, style: dropdownStyle),
        ),
        DropdownMenuItem(
          value: 'M',
          child: Text('Masculino', overflow: TextOverflow.ellipsis, style: dropdownStyle),
        ),
        DropdownMenuItem(
          value: 'F',
          child: Text('Feminino', overflow: TextOverflow.ellipsis, style: dropdownStyle),
        ),
        DropdownMenuItem(
          value: 'O',
          child: Text('Outro', overflow: TextOverflow.ellipsis, style: dropdownStyle),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _sexoCliente = v);
      },
    );

    final campoFantasia = TextField(
      controller: _nomeFantasiaController,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: _tipoPessoa == 'fisica' ? 'Apelido' : 'Nome fantasia',
        isDense: true,
      ),
    );

    final campoCpf = TextField(
      controller: _documentoController,
      decoration: InputDecoration(
        labelText: 'CPF',
        isDense: true,
        errorText: _erroDocumento,
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [_cpfCnpjFormatter],
      onChanged: (_) {
        if (_erroDocumento != null) {
          setState(() => _erroDocumento = null);
        }
      },
    );

    if (_tipoPessoa == 'fisica') {
      // Duas linhas para evitar overflow (Sexo/Nascimento) em monitores comuns.
      return [
        _linhaCamposAdaptativa(
          larguraMinimaLinha: 720,
          espacamento: 6,
          flexes: const [1, 1, 3, 2],
          campos: [
            campoCodigoInterno,
            dropdownTipo,
            campoNomeRazao,
            campoFantasia,
          ],
        ),
        const SizedBox(height: 6),
        _linhaCamposAdaptativa(
          larguraMinimaLinha: 560,
          espacamento: 6,
          flexes: const [2, 1, 2, 2],
          campos: [
            campoCpf,
            campoRg,
            campoNascimento,
            campoSexo,
          ],
        ),
      ];
    }

    // Pessoa juridica: identidade + documento/IE/CNPJ.
    return [
      _linhaCamposAdaptativa(
        larguraMinimaLinha: 720,
        espacamento: 4,
        flexes: const [1, 1, 3, 2],
        campos: [
          campoCodigoInterno,
          dropdownTipo,
          campoNomeRazao,
          campoFantasia,
        ],
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: _wDoc,
            child: TextField(
              controller: _documentoController,
              decoration: InputDecoration(
                labelText: 'CNPJ',
                isDense: true,
                contentPadding: _padCampoCadastro,
                errorText: _erroDocumento,
                suffixIconConstraints: _iconCampoCadastro,
                suffixIcon: _consultaCnpjEmAndamento
                    ? const Padding(
                        padding: EdgeInsets.all(6),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [_cpfCnpjFormatter],
              onChanged: (_) {
                if (_erroDocumento != null) {
                  setState(() => _erroDocumento = null);
                }
              },
            ),
          ),
          SizedBox(
            width: _wIe,
            child: TextField(
              controller: _inscricaoController,
              decoration: const InputDecoration(
                labelText: 'Inscrição Estadual',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
                LengthLimitingTextInputFormatter(20),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: _estiloBotaoContornoCompacto,
            onPressed:
                _consultaCnpjEmAndamento ? null : _buscarCnpjManualmente,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Buscar CNPJ'),
          ),
        ],
      ),
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
    final saldo = _saldoFiadoCache;
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
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;
    final campoStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: scheme.onSurface,
    );

    return _buildSectionCard(
      context: context,
      title: 'Comercial',
      icon: Icons.payments_outlined,
      children: [
        if (_clienteEmEdicaoId != null) ...[
          _buildResumoLimiteCredito(context),
          const SizedBox(height: 8),
        ],
        // Linha 1: Limite (4) | Tabela (4) | Vendedor (4)
        _linhaCamposAdaptativa(
          larguraMinimaLinha: 640,
          espacamento: 8,
          flexes: const [4, 4, 4],
          campos: [
            TextField(
              controller: _limiteController,
              style: campoStyle,
              decoration: InputDecoration(
                labelText: 'Limite de crédito (R\$)',
                isDense: true,
                filled: true,
                fillColor: semantic.successBg,
                contentPadding: _padCampoCadastro,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [_limiteCreditoFormatter],
            ),
            DropdownButtonFormField<String>(
              key: ValueKey<String>(_tabelaPrecoPadrao),
              isExpanded: true,
              isDense: true,
              initialValue: _tabelaPrecoPadrao,
              style: campoStyle,
              decoration: const InputDecoration(
                labelText: 'Tabela de preço',
                isDense: true,
              ),
              items: ClienteCadastro.tabelasPreco
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.$1,
                      child: Text(
                        e.$2,
                        overflow: TextOverflow.ellipsis,
                        style: campoStyle,
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
              isDense: true,
              initialValue: _vendedorResponsavelId,
              style: campoStyle,
              decoration: const InputDecoration(
                labelText: 'Vendedor',
                isDense: true,
              ),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Nenhum', style: campoStyle),
                ),
                ..._vendedoresAtivos.map(
                  (v) => DropdownMenuItem<int?>(
                    value: v.id,
                    child: Text(
                      v.apelido.trim().isNotEmpty
                          ? v.apelido
                          : v.nomeCompleto,
                      overflow: TextOverflow.ellipsis,
                      style: campoStyle,
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _vendedorResponsavelId = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Linha 2: Prazo (3) | Categoria (3) | Ocupação (6)
        _linhaCamposAdaptativa(
          larguraMinimaLinha: 560,
          espacamento: 8,
          flexes: const [3, 3, 6],
          campos: [
            TextField(
              controller: _prazoPagamentoController,
              style: campoStyle,
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
              isDense: true,
              initialValue:
                  _categoriaComercial.isEmpty ? '' : _categoriaComercial,
              style: campoStyle,
              decoration: const InputDecoration(
                labelText: 'Categoria',
                isDense: true,
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text('-', style: campoStyle),
                ),
                ...ClienteCadastro.categoriasComerciais.map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, style: campoStyle),
                  ),
                ),
              ],
              onChanged: (v) =>
                  setState(() => _categoriaComercial = v ?? ''),
            ),
            TextField(
              controller: _ocupacaoController,
              style: campoStyle,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Ocupação / profissão',
                isDense: true,
                contentPadding: _padCampoCadastro,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _observacoesController,
          style: campoStyle,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Observações',
            isDense: true,
            contentPadding: _padCampoCadastro,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        _buildMiniCardStatusCliente(theme),
        if (_bloqueadoFiado) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _motivoBloqueioController,
            style: campoStyle,
            decoration: const InputDecoration(
              labelText: 'Motivo do bloqueio',
              isDense: true,
              contentPadding: _padCampoCadastro,
            ),
            maxLines: 1,
          ),
        ],
        if (_clienteEmEdicaoId != null &&
            _clienteParaExtratoFiado() != null) ...[
          const SizedBox(height: 8),
          ExtratoFiadoClienteCard(
            vendaRepository: widget.vendaRepository,
            cliente: _clienteParaExtratoFiado()!,
            limiteCredito: _limiteCreditoDigitado(),
          ),
        ],
      ],
    );
  }

  Widget _buildMiniCardStatusCliente(ThemeData theme) {
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            LayoutBuilder(
              builder: (context, constraints) {
                final ladoALado = constraints.maxWidth >= 420;
                final tiles = [
                  SwitchListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    value: _bloqueadoFiado,
                    onChanged: (v) => setState(() => _bloqueadoFiado = v),
                    title: const Text(
                      'Bloquear fiado',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    value: _ativo,
                    onChanged: (v) => setState(() => _ativo = v),
                    title: const Text(
                      'Cliente ativo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ];
                if (!ladoALado) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: tiles,
                  );
                }
                return Row(
                  children: [
                    Expanded(child: tiles[0]),
                    const SizedBox(width: 12),
                    Expanded(child: tiles[1]),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraFerramentasCadastro() {
    final pesquisaBtn = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onPressed: _abrirPesquisaCliente,
      icon: const Icon(Icons.search, size: 20),
      label: const Text('Pesquisar cliente'),
    );
    final nav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Primeiro',
          onPressed: _irParaPrimeiroCliente,
          icon: const Icon(Icons.first_page_outlined),
        ),
        IconButton(
          tooltip: 'Anterior',
          onPressed: _irParaClienteAnterior,
          icon: const Icon(Icons.navigate_before_outlined),
        ),
        IconButton(
          tooltip: 'Próximo',
          onPressed: _irParaProximoCliente,
          icon: const Icon(Icons.navigate_next_outlined),
        ),
        IconButton(
          tooltip: 'Último',
          onPressed: _irParaUltimoCliente,
          icon: const Icon(Icons.last_page_outlined),
        ),
      ],
    );
    if (context.isCompactLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pesquisaBtn,
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [nav],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: pesquisaBtn),
        nav,
      ],
    );
  }

  Widget _buildFormularioUnico({
    required ThemeData theme,
    required bool emEdicao,
    required bool formWide,
  }) {
    const pageBg = Color(0xFFF8FAFC);
    const fieldTextStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.25,
    );
    final scheme = theme.colorScheme;
    final denseTheme = theme.copyWith(
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: pageBg,
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: _padCampoCadastro,
        prefixIconConstraints: _iconCampoCadastro,
        suffixIconConstraints: _iconCampoCadastro,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
        hintStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      textTheme: theme.textTheme.copyWith(
        bodyLarge: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
        titleMedium: theme.textTheme.titleMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        titleSmall: theme.textTheme.titleSmall?.copyWith(fontSize: 12.5),
        labelLarge: theme.textTheme.labelLarge?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        labelMedium: theme.textTheme.labelMedium?.copyWith(fontSize: 11),
        labelSmall: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: fieldTextStyle,
      ),
    );

    Widget cadastroScroll({required Widget child}) {
      return Scrollbar(
        controller: _scrollFormulario,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollFormulario,
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: child,
        ),
      );
    }

    return Theme(
      data: denseTheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              tabs: const [
                Tab(height: 36, text: 'Cadastro'),
                Tab(height: 36, text: 'Relacionamento'),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: pageBg,
              child: TabBarView(
                controller: _tabController,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return cadastroScroll(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildAbaIdentificacao(denseTheme, emEdicao),
                            const SizedBox(height: 10),
                            _buildAbaContato(denseTheme),
                            const SizedBox(height: 10),
                            _buildSecaoEnderecos(denseTheme),
                            const SizedBox(height: 10),
                            _buildCardComercialComLimiteDestaque(),
                          ],
                        ),
                      );
                    },
                  ),
                  _buildAbaRelacionamento(
                    theme: denseTheme,
                    emEdicao: emEdicao,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoEnderecos(ThemeData theme) {
    return _buildSectionCard(
      context: context,
      title: 'Endereço',
      icon: Icons.location_on_outlined,
      children: [
        _buildEnderecoForm(
          titulo: 'Endereço principal / sede',
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
          codigoIbgeController: _codigoIbgeController,
          referenciaController: _referenciaController,
        ),
        for (var i = 0; i < _enderecosExtras.length; i++) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _buildEnderecoForm(
            titulo: _enderecosExtras[i].tituloExibicao(),
            tipo: _enderecosExtras[i].tipo,
            onTipoChanged: (v) =>
                setState(() => _enderecosExtras[i].tipo = v),
            nomeObraController: _enderecosExtras[i].nomeObraController,
            padraoCarreto: _enderecosExtras[i].padraoCarreto,
            onPadraoCarreto: () => _definirUnicoPadraoCarreto(
              principal: false,
              indiceExtra: i,
            ),
            cepController: _enderecosExtras[i].cepController,
            enderecoController: _enderecosExtras[i].enderecoController,
            numeroController: _enderecosExtras[i].numeroController,
            bairroController: _enderecosExtras[i].bairroController,
            cidadeController: _enderecosExtras[i].cidadeController,
            ufController: _enderecosExtras[i].ufController,
            codigoIbgeController: _enderecosExtras[i].codigoIbgeController,
            referenciaController: _enderecosExtras[i].referenciaController,
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
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.4),
              ),
            ),
            onPressed: () {
              setState(() {
                _enderecosExtras.add(
                  _EnderecoFormControllers.vazio(tipo: 'entrega'),
                );
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (!_scrollFormulario.hasClients) return;
                final pos = _scrollFormulario.position;
                pos.animateTo(
                  pos.maxScrollExtent,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                );
              });
            },
            icon: const Icon(Icons.add_location_alt_outlined, size: 16),
            label: const Text('Adicionar endereço'),
          ),
        ),
      ],
    );
  }

  Widget _buildAbaIdentificacao(ThemeData theme, bool emEdicao) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionCard(
          context: context,
          title: 'Identificação',
          icon: Icons.person_outline,
          children: [
            ..._dadosPrincipaisChildren(emEdicao),
            if (_tipoPessoa == 'juridica') ...[
              const SizedBox(height: 8),
              _linhaCamposAdaptativa(
                larguraMinimaLinha: 480,
                flexes: const [1, 2],
                campos: [
                  TextField(
                    controller: _inscricaoMunicipalController,
                    decoration: const InputDecoration(
                      labelText: 'Inscrição municipal',
                      isDense: true,
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(_indicadorIe),
                    isExpanded: true,
                    isDense: true,
                    initialValue: _indicadorIe.isEmpty ? '' : _indicadorIe,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Indicador IE',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Não informado'),
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
              contentPadding: _padCampoCadastro,
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _contatoPrincipalCargoController,
            decoration: const InputDecoration(
              labelText: 'Cargo / funcao na obra',
              isDense: true,
              contentPadding: _padCampoCadastro,
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 4),
        ],
        _linhaCamposAdaptativa(
          larguraMinimaLinha: 560,
          espacamento: 6,
          flexes: const [1, 1, 1],
          campos: [
            TextField(
              controller: _telefoneController,
              decoration: const InputDecoration(
                labelText: 'Telefone',
                isDense: true,
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [_telefoneFormatter],
            ),
            TextField(
              controller: _whatsappController,
              decoration: const InputDecoration(
                labelText: 'WhatsApp',
                isDense: true,
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [_telefoneFormatter],
            ),
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
        ),
      ],
    );
  }

  Widget _buildAbaRelacionamento({
    required ThemeData theme,
    required bool emEdicao,
  }) {
    final compras = _comprasDoClienteAtual();
    final totalGasto = compras.fold<double>(0, (acc, v) => acc + v.total);
    final ticketMedio = compras.isEmpty ? 0.0 : totalGasto / compras.length;
    final ultimaCompra = compras.isEmpty ? null : compras.first;
    final quantidadeItens = compras.fold<int>(
      0,
      (acc, compra) =>
          acc +
          _itensDaCompraSafe(compra).fold<int>(
            0,
            (soma, item) => soma + item.quantidade,
          ),
    );
    final topMap = <String, int>{};
    for (final compra in compras) {
      for (final item in _itensDaCompraSafe(compra)) {
        final nome = item.nomeProduto.trim();
        if (nome.isEmpty) continue;
        topMap[nome] = (topMap[nome] ?? 0) + item.quantidade;
      }
    }
    final topProdutos = topMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scrollbar(
      controller: _scrollRelacionamento,
      thumbVisibility: true,
      trackVisibility: true,
      child: ListView(
        controller: _scrollRelacionamento,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        children: [
          _buildConteudoHistoricoCompras(
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
    );
  }

  /// Historico de compras (Column no scroll do formulario).
  Widget _buildConteudoHistoricoCompras({
    required ThemeData theme,
    required bool emEdicao,
    required List<Venda> compras,
    required double totalGasto,
    required double ticketMedio,
    required Venda? ultimaCompra,
    required int quantidadeItens,
    required List<MapEntry<String, int>> topProdutos,
    VoidCallback? onAtualizarUi,
  }) {
    final tituloSecao = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        if (_carregandoCompras)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
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
                            onAtualizarUi?.call();
                            final id = _clienteEmEdicaoId;
                            if (id != null) {
                              unawaited(_carregarComprasCliente(id).then((_) {
                                onAtualizarUi?.call();
                              }));
                            }
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emEdicao = _clienteEmEdicaoId != null;
    final compras = _comprasDoClienteAtual();
    final totalGasto = compras.fold<double>(0, (acc, v) => acc + v.total);
    final ultimaCompra = compras.isEmpty ? null : compras.first;
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
          child: Scaffold(
            appBar: AppBar(title: const Text('Cadastro de Clientes')),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final formWide = box.maxWidth >= 720;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildBarraFerramentasCadastro(),
                            const SizedBox(height: 4),
                            ClienteCadastroHeader(
                              emEdicao: emEdicao,
                              clienteId: _clienteEmEdicaoId,
                              nomeRazao: _nomeRazaoController.text,
                              tipoPessoa: _tipoPessoa,
                              documento: _documentoController.text,
                              ativo: _ativo,
                              codigoInterno: _codigoInternoController.text
                                      .trim()
                                      .isNotEmpty
                                  ? _codigoInternoController.text.trim()
                                  : (emEdicao && _clienteEmEdicaoId != null
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
                            if (_status.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              _buildStatusBanner(context, _status),
                            ],
                            const SizedBox(height: 2),
                            Expanded(
                              child: _buildFormularioUnico(
                                theme: theme,
                                emEdicao: emEdicao,
                                formWide: formWide,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                ClienteCadastroRodape(
                  emEdicao: emEdicao,
                  onSalvar: _salvarCliente,
                  onNovo: _limparFormulario,
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
    double espacamento = 4,
    List<double>? flexes,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        if (!maxW.isFinite || maxW < larguraMinimaLinha) {
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
              Expanded(
                flex: flexList[i].round().clamp(1, 100),
                child: campos[i],
              ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.1,
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
    required TextEditingController codigoIbgeController,
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
      codigoIbge: codigoIbgeController,
    );
    final cepConsultando = _consultaCepEmAndamento &&
        identical(_cepControllerEmConsulta, cepController);

    return LayoutBuilder(
      builder: (context, constraints) {
        final campoCep = SizedBox(
          width: _wCep,
          child: TextField(
            controller: cepController,
            decoration: InputDecoration(
              labelText: 'CEP',
              isDense: true,
              contentPadding: _padCampoCadastro,
              suffixIconConstraints: _iconCampoCadastro,
              suffixIcon: cepConsultando
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: SizedBox(
                        width: 14,
                        height: 14,
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
                  labelText: 'Endereço',
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
                    tooltip: 'Remover endereço',
                    onPressed: onRemover,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
              ],
            ),
            if (onTipoChanged != null || onPadraoCarreto != null) ...[
              const SizedBox(height: 4),
              _linhaCamposAdaptativa(
                larguraMinimaLinha: 520,
                campos: [
                  if (onTipoChanged != null)
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(tipo),
                      isExpanded: true,
                      isDense: true,
                      initialValue: tipo,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
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
                        labelText: 'Nome da obra / referência',
                        isDense: true,
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  if (onPadraoCarreto != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        label: const Text('Padrão para carreto (PDV)'),
                        selected: padraoCarreto,
                        onSelected: (_) => onPadraoCarreto(),
                      ),
                    ),
                ],
              ),
            ] else if (onPadraoCarreto != null) ...[
              const SizedBox(height: 4),
              FilterChip(
                label: const Text('Padrão para carreto (PDV)'),
                selected: padraoCarreto,
                onSelected: (_) => onPadraoCarreto(),
              ),
            ],
            const SizedBox(height: 4),
            linhaCepBuscar,
            const SizedBox(height: 4),
            linhaEnderecoNumero,
            const SizedBox(height: 4),
            _linhaCamposAdaptativa(
              larguraMinimaLinha: 640,
              espacamento: 4,
              flexes: const [2, 2, 1, 3],
              campos: [
                campoBairro,
                campoCidade,
                campoUf,
                ClienteEnderecoIbgeSelector(
                  codigoIbgeController: codigoIbgeController,
                  cidadeController: cidadeController,
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: referenciaController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Referência',
                isDense: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusBanner(BuildContext context, String message) {
    final semantic = context.semanticColors;
    final sucesso = message.toLowerCase().contains('sucesso');
    final bg = sucesso ? semantic.successBg : semantic.errorBg;
    final border = sucesso ? semantic.successBorder : semantic.errorBorder;
    final fg = sucesso ? semantic.successFg : semantic.errorFg;
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
    required this.codigoIbgeController,
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
      codigoIbgeController: TextEditingController(),
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
      codigoIbgeController: TextEditingController(text: endereco.codigoIbge),
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
  final TextEditingController codigoIbgeController;
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
      codigoIbge: codigoIbgeController.text.replaceAll(RegExp(r'\D'), ''),
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
    codigoIbgeController.dispose();
    referenciaController.dispose();
  }
}
