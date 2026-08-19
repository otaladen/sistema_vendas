import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api/fornecedor_api_repository.dart';
import '../data/api/lan_api_client.dart';
import '../data/fornecedor_repository.dart';
import '../model/fornecedor_nfe.dart';
import '../services/brasil_api_cnpj_service.dart';
import 'layout/app_layout.dart';
import 'theme/app_semantic_helper.dart';
import 'widgets/fornecedor/fornecedor_cadastro_header.dart';
import 'widgets/fornecedor/fornecedor_cadastro_rodape.dart';
import 'widgets/lan_api_feedback.dart';

/// Cadastro de fornecedores (hibrido: manual + auto via NF-e / contas a pagar).
///
/// Aceita [FornecedorRepository] (PC1) ou [FornecedorApiRepository] (terminal).
class FornecedoresPage extends StatefulWidget {
  const FornecedoresPage({
    super.key,
    required this.fornecedorRepository,
  });

  final dynamic fornecedorRepository;

  @override
  State<FornecedoresPage> createState() => _FornecedoresPageState();
}

class _FornecedoresPageState extends State<FornecedoresPage> {
  static const _padCampo = EdgeInsets.symmetric(horizontal: 10, vertical: 10);
  static const _iconCampo = BoxConstraints(
    minWidth: 28,
    minHeight: 28,
    maxWidth: 32,
    maxHeight: 32,
  );

  final _cnpjController = TextEditingController();
  final _razaoController = TextEditingController();
  final _fantasiaController = TextEditingController();
  final _ieController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _cepController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _numeroController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _ufController = TextEditingController();
  final _obsController = TextEditingController();
  final _scrollFormulario = ScrollController();

  int? _emEdicaoId;
  bool _ativo = true;
  bool _consultaCnpj = false;
  String _status = '';
  String? _erroCnpj;

  List<FornecedorNfe> _lista = [];
  bool _carregandoLista = false;

  bool get _viaApi => widget.fornecedorRepository is FornecedorApiRepository;

  @override
  void initState() {
    super.initState();
    final repo = widget.fornecedorRepository;
    if (repo is FornecedorApiRepository) {
      repo.addListener(_onApiChanged);
      unawaited(_hidratarTerminal());
    } else {
      _recarregarLista();
    }
  }

  void _onApiChanged() {
    if (!mounted) return;
    setState(() {
      _lista = (widget.fornecedorRepository as FornecedorApiRepository)
          .listarTodos();
    });
  }

  Future<void> _hidratarTerminal() async {
    final repo = widget.fornecedorRepository;
    if (repo is! FornecedorApiRepository) return;
    setState(() => _carregandoLista = true);
    try {
      await repo.hidratar();
      if (mounted) {
        setState(() {
          _lista = repo.listarTodos();
          _carregandoLista = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoLista = false);
      LanApiFeedback.snackAviso(context, e, prefixo: 'Fornecedores');
    }
  }

  @override
  void dispose() {
    final repo = widget.fornecedorRepository;
    if (repo is FornecedorApiRepository) {
      repo.removeListener(_onApiChanged);
    }
    _cnpjController.dispose();
    _razaoController.dispose();
    _fantasiaController.dispose();
    _ieController.dispose();
    _telefoneController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _cepController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _ufController.dispose();
    _obsController.dispose();
    _scrollFormulario.dispose();
    super.dispose();
  }

  void _recarregarLista() {
    setState(() {
      _lista = widget.fornecedorRepository.listarTodos() as List<FornecedorNfe>;
    });
  }

  void _limpar() {
    setState(() {
      _emEdicaoId = null;
      _ativo = true;
      _erroCnpj = null;
      _status = '';
      _cnpjController.clear();
      _razaoController.clear();
      _fantasiaController.clear();
      _ieController.clear();
      _telefoneController.clear();
      _whatsappController.clear();
      _emailController.clear();
      _cepController.clear();
      _enderecoController.clear();
      _numeroController.clear();
      _bairroController.clear();
      _cidadeController.clear();
      _ufController.clear();
      _obsController.clear();
    });
  }

  void _carregar(FornecedorNfe f) {
    setState(() {
      _emEdicaoId = f.id;
      _ativo = f.ativo;
      _erroCnpj = null;
      _status = '';
      _cnpjController.text = f.ehManualSemDocumento ? '' : f.cnpj;
      _razaoController.text = f.razaoSocial;
      _fantasiaController.text = f.nomeFantasia;
      _ieController.text = f.inscricaoEstadual;
      _telefoneController.text = f.telefone;
      _whatsappController.text = f.whatsapp;
      _emailController.text = f.email;
      _cepController.text = f.cep;
      _enderecoController.text = f.endereco;
      _numeroController.text = f.numero;
      _bairroController.text = f.bairro;
      _cidadeController.text = f.cidade;
      _ufController.text = f.uf;
      _obsController.text = f.observacoes;
    });
  }

  Future<void> _abrirPesquisa() async {
    final ctrl = TextEditingController();
    final escolhido = await showDialog<FornecedorNfe>(
      context: context,
      builder: (ctx) {
        var resultados =
            widget.fornecedorRepository.listarTodos() as List<FornecedorNfe>;
        var buscando = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> filtrar(String v) async {
              final repo = widget.fornecedorRepository;
              if (repo is FornecedorApiRepository) {
                setLocal(() => buscando = true);
                try {
                  final rem = await repo.pesquisarRemoto(v);
                  if (ctx.mounted) {
                    setLocal(() {
                      resultados = rem;
                      buscando = false;
                    });
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    setLocal(() {
                      resultados = repo.pesquisar(v);
                      buscando = false;
                    });
                    LanApiFeedback.snackAviso(ctx, e, prefixo: 'Pesquisa');
                  }
                }
              } else {
                setLocal(() {
                  resultados = repo.pesquisar(v) as List<FornecedorNfe>;
                });
              }
            }

            return AlertDialog(
              title: const Text('Pesquisar fornecedor'),
              content: SizedBox(
                width: 520,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'CNPJ, razao ou fantasia',
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => unawaited(filtrar(v)),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: buscando
                          ? const Center(child: CircularProgressIndicator())
                          : resultados.isEmpty
                              ? const Center(child: Text('Nenhum fornecedor.'))
                              : ListView.builder(
                                  itemCount: resultados.length,
                                  itemBuilder: (_, i) {
                                    final f = resultados[i];
                                    return ListTile(
                                      dense: true,
                                      title: Text(f.nomeExibicao),
                                      subtitle: Text(
                                        f.ehManualSemDocumento
                                            ? 'Sem CNPJ (manual)'
                                            : 'CNPJ/CPF: ${f.cnpj}',
                                      ),
                                      onTap: () => Navigator.pop(ctx, f),
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
    ctrl.dispose();
    if (escolhido != null && mounted) _carregar(escolhido);
  }

  Future<void> _buscarCnpj() async {
    final dig = FornecedorRepository.somenteDigitos(_cnpjController.text);
    if (dig.length != 14) {
      setState(() => _erroCnpj = 'Informe CNPJ com 14 digitos.');
      return;
    }
    setState(() {
      _consultaCnpj = true;
      _erroCnpj = null;
    });
    try {
      final dados = await BrasilApiCnpjService.consultar(dig);
      if (!mounted) return;
      if (dados == null) {
        setState(() => _status = 'CNPJ nao encontrado na BrasilAPI.');
        return;
      }
      setState(() {
        if (dados.razaoSocial.isNotEmpty) {
          _razaoController.text = dados.razaoSocial;
        }
        if (dados.nomeFantasia.isNotEmpty) {
          _fantasiaController.text = dados.nomeFantasia;
        }
        if (dados.cep.isNotEmpty) _cepController.text = dados.cep;
        if (dados.logradouro.isNotEmpty) {
          _enderecoController.text = dados.logradouro;
        }
        if (dados.numero.isNotEmpty) _numeroController.text = dados.numero;
        if (dados.bairro.isNotEmpty) _bairroController.text = dados.bairro;
        if (dados.municipio.isNotEmpty) _cidadeController.text = dados.municipio;
        if (dados.uf.isNotEmpty) _ufController.text = dados.uf;
        _status = 'Dados preenchidos pela consulta de CNPJ.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Falha ao consultar CNPJ: $e');
    } finally {
      if (mounted) setState(() => _consultaCnpj = false);
    }
  }

  Future<void> _salvar() async {
    final dig = FornecedorRepository.somenteDigitos(_cnpjController.text);
    try {
      final f = FornecedorNfe(
        id: _emEdicaoId ?? 0,
        cnpj: dig,
        razaoSocial: _razaoController.text.trim(),
        nomeFantasia: _fantasiaController.text.trim(),
        inscricaoEstadual: _ieController.text.trim(),
        telefone: _telefoneController.text.trim(),
        whatsapp: _whatsappController.text.trim(),
        email: _emailController.text.trim(),
        cep: FornecedorRepository.somenteDigitos(_cepController.text),
        endereco: _enderecoController.text.trim(),
        numero: _numeroController.text.trim(),
        bairro: _bairroController.text.trim(),
        cidade: _cidadeController.text.trim(),
        uf: _ufController.text.trim().toUpperCase(),
        observacoes: _obsController.text.trim(),
        ativo: _ativo,
      );
      final repo = widget.fornecedorRepository;
      final int id;
      if (repo is FornecedorApiRepository) {
        id = await repo.salvarRemoto(f);
      } else {
        id = repo.salvar(f) as int;
      }
      if (!mounted) return;
      setState(() {
        _emEdicaoId = id;
        _status = 'Fornecedor salvo com sucesso.';
        _erroCnpj = null;
      });
      if (!_viaApi) _recarregarLista();
    } on LanApiException catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel salvar');
      setState(() => _status = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.toString().replaceFirst('ArgumentError: ', '');
        if (e.toString().contains('CNPJ')) _erroCnpj = _status;
      });
    }
  }

  Future<void> _excluir() async {
    final id = _emEdicaoId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir fornecedor?'),
        content: const Text(
          'Vinculos de NF-e e contas a pagar podem ficar sem referencia. '
          'Prefira inativar quando houver historico.',
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
    try {
      final repo = widget.fornecedorRepository;
      if (repo is FornecedorApiRepository) {
        await repo.removerRemoto(id);
      } else {
        repo.remover(id);
      }
      if (!mounted) return;
      _limpar();
      if (!_viaApi) _recarregarLista();
      setState(() => _status = 'Fornecedor excluido.');
    } on LanApiException catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel excluir');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '$e');
    }
  }

  List<FornecedorNfe> _fornecedoresOrdenados() {
    final lista = List<FornecedorNfe>.from(_lista);
    lista.sort((a, b) => a.id.compareTo(b.id));
    return lista;
  }

  int _indiceFornecedorAtual(List<FornecedorNfe> lista) {
    if (_emEdicaoId == null) return -1;
    return lista.indexWhere((f) => f.id == _emEdicaoId);
  }

  void _abrirFornecedorPorIndice(int indice) {
    final lista = _fornecedoresOrdenados();
    if (lista.isEmpty) {
      setState(() => _status = 'Nao ha fornecedores cadastrados para navegar.');
      return;
    }
    final indiceValido = indice.clamp(0, lista.length - 1);
    _carregar(lista[indiceValido]);
  }

  void _irParaPrimeiro() => _abrirFornecedorPorIndice(0);

  void _irParaUltimo() {
    final lista = _fornecedoresOrdenados();
    if (lista.isEmpty) {
      setState(() => _status = 'Nao ha fornecedores cadastrados para navegar.');
      return;
    }
    _abrirFornecedorPorIndice(lista.length - 1);
  }

  void _irParaAnterior() {
    final lista = _fornecedoresOrdenados();
    if (lista.isEmpty) {
      setState(() => _status = 'Nao ha fornecedores cadastrados para navegar.');
      return;
    }
    final indiceAtual = _indiceFornecedorAtual(lista);
    if (indiceAtual <= 0) {
      _abrirFornecedorPorIndice(0);
      return;
    }
    _abrirFornecedorPorIndice(indiceAtual - 1);
  }

  void _irParaProximo() {
    final lista = _fornecedoresOrdenados();
    if (lista.isEmpty) {
      setState(() => _status = 'Nao ha fornecedores cadastrados para navegar.');
      return;
    }
    final indiceAtual = _indiceFornecedorAtual(lista);
    if (indiceAtual < 0 || indiceAtual >= lista.length - 1) {
      _abrirFornecedorPorIndice(lista.length - 1);
      return;
    }
    _abrirFornecedorPorIndice(indiceAtual + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emEdicao = _emEdicaoId != null;
    const pageBg = Color(0xFFF8FAFC);
    final scheme = theme.colorScheme;
    final denseTheme = theme.copyWith(
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: pageBg,
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: _padCampo,
        prefixIconConstraints: _iconCampo,
        suffixIconConstraints: _iconCampo,
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
        titleSmall: theme.textTheme.titleSmall?.copyWith(fontSize: 12.5),
        labelLarge: theme.textTheme.labelLarge?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.f5): _SalvarIntent(),
        SingleActivator(LogicalKeyboardKey.f8): _CnpjIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _LimparIntent(),
      },
      child: Actions(
        actions: {
          _SalvarIntent: CallbackAction(onInvoke: (_) {
            unawaited(_salvar());
            return null;
          }),
          _CnpjIntent: CallbackAction(onInvoke: (_) {
            unawaited(_buscarCnpj());
            return null;
          }),
          _LimparIntent: CallbackAction(onInvoke: (_) {
            _limpar();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Cadastro de Fornecedores'),
              actions: [
                if (_viaApi)
                  IconButton(
                    tooltip: 'Atualizar do servidor',
                    onPressed: _carregandoLista
                        ? null
                        : () => unawaited(_hidratarTerminal()),
                    icon: _carregandoLista
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
              ],
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildBarraFerramentas(),
                        const SizedBox(height: 4),
                        FornecedorCadastroHeader(
                          emEdicao: emEdicao,
                          fornecedorId: _emEdicaoId,
                          razaoSocial: _razaoController.text,
                          documento: _cnpjController.text,
                          ativo: _ativo,
                        ),
                        if (_status.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          _buildStatusBanner(context, _status),
                        ],
                        const SizedBox(height: 2),
                        Expanded(
                          child: Theme(
                            data: denseTheme,
                            child: ColoredBox(
                              color: pageBg,
                              child: RawScrollbar(
                                controller: _scrollFormulario,
                                thumbVisibility: true,
                                trackVisibility: true,
                                thickness: 10,
                                radius: const Radius.circular(8),
                                child: SingleChildScrollView(
                                  controller: _scrollFormulario,
                                  primary: false,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 8, 8, 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildSectionCard(
                                        title: 'Identificacao',
                                        icon: Icons.business_outlined,
                                        children: [
                                          _linhaCampos(
                                            larguraMinimaLinha: 720,
                                            flexes: const [2, 1, 3],
                                            campos: [
                                              TextField(
                                                controller: _cnpjController,
                                                decoration: InputDecoration(
                                                  labelText: 'CNPJ / CPF',
                                                  isDense: true,
                                                  errorText: _erroCnpj,
                                                  suffixIcon: _consultaCnpj
                                                      ? const Padding(
                                                          padding:
                                                              EdgeInsets.all(
                                                            10,
                                                          ),
                                                          child: SizedBox(
                                                            width: 16,
                                                            height: 16,
                                                            child:
                                                                CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                                keyboardType:
                                                    TextInputType.number,
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .digitsOnly,
                                                  LengthLimitingTextInputFormatter(
                                                    14,
                                                  ),
                                                ],
                                              ),
                                              Align(
                                                alignment:
                                                    Alignment.centerLeft,
                                                child: OutlinedButton.icon(
                                                  onPressed: _consultaCnpj
                                                      ? null
                                                      : _buscarCnpj,
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.search,
                                                    size: 18,
                                                  ),
                                                  label:
                                                      const Text('F8 CNPJ'),
                                                ),
                                              ),
                                              TextField(
                                                controller: _razaoController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'Razao social',
                                                  isDense: true,
                                                ),
                                                textCapitalization:
                                                    TextCapitalization.words,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          _linhaCampos(
                                            larguraMinimaLinha: 560,
                                            flexes: const [2, 2],
                                            campos: [
                                              TextField(
                                                controller:
                                                    _fantasiaController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'Nome fantasia',
                                                  isDense: true,
                                                ),
                                                textCapitalization:
                                                    TextCapitalization.words,
                                              ),
                                              TextField(
                                                controller: _ieController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText:
                                                      'Inscricao estadual',
                                                  isDense: true,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      _buildSectionCard(
                                        title: 'Contato',
                                        icon: Icons.phone_outlined,
                                        children: [
                                          _linhaCampos(
                                            larguraMinimaLinha: 560,
                                            flexes: const [1, 1, 2],
                                            campos: [
                                              TextField(
                                                controller:
                                                    _telefoneController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'Telefone',
                                                  isDense: true,
                                                ),
                                                keyboardType:
                                                    TextInputType.phone,
                                              ),
                                              TextField(
                                                controller:
                                                    _whatsappController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'WhatsApp',
                                                  isDense: true,
                                                ),
                                                keyboardType:
                                                    TextInputType.phone,
                                              ),
                                              TextField(
                                                controller: _emailController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'E-mail',
                                                  isDense: true,
                                                ),
                                                keyboardType: TextInputType
                                                    .emailAddress,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      _buildSectionCard(
                                        title: 'Endereco',
                                        icon: Icons.location_on_outlined,
                                        children: [
                                          _linhaCampos(
                                            larguraMinimaLinha: 560,
                                            flexes: const [1, 3, 1],
                                            campos: [
                                              TextField(
                                                controller: _cepController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'CEP',
                                                  isDense: true,
                                                ),
                                                keyboardType:
                                                    TextInputType.number,
                                              ),
                                              TextField(
                                                controller:
                                                    _enderecoController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'Endereco',
                                                  isDense: true,
                                                ),
                                                textCapitalization:
                                                    TextCapitalization.words,
                                              ),
                                              TextField(
                                                controller:
                                                    _numeroController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'Nº',
                                                  isDense: true,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          _linhaCampos(
                                            larguraMinimaLinha: 480,
                                            flexes: const [2, 2, 1],
                                            campos: [
                                              TextField(
                                                controller:
                                                    _bairroController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'Bairro',
                                                  isDense: true,
                                                ),
                                                textCapitalization:
                                                    TextCapitalization.words,
                                              ),
                                              TextField(
                                                controller:
                                                    _cidadeController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'Cidade',
                                                  isDense: true,
                                                ),
                                                textCapitalization:
                                                    TextCapitalization.words,
                                              ),
                                              TextField(
                                                controller: _ufController,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'UF',
                                                  isDense: true,
                                                ),
                                                textCapitalization:
                                                    TextCapitalization
                                                        .characters,
                                                inputFormatters: [
                                                  LengthLimitingTextInputFormatter(
                                                    2,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      _buildSectionCard(
                                        title: 'Complemento',
                                        icon: Icons.notes_outlined,
                                        children: [
                                          TextField(
                                            controller: _obsController,
                                            decoration:
                                                const InputDecoration(
                                              labelText: 'Observacoes',
                                              isDense: true,
                                            ),
                                            maxLines: 2,
                                          ),
                                          const SizedBox(height: 8),
                                          _buildMiniCardStatus(theme),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      _buildSectionCard(
                                        title:
                                            'Ultimos cadastros (${_lista.length})',
                                        icon: Icons.history_outlined,
                                        children: [
                                          if (_lista.isEmpty)
                                            Text(
                                              'Nenhum fornecedor cadastrado ainda.',
                                              style: theme
                                                  .textTheme.bodySmall
                                                  ?.copyWith(
                                                color: scheme
                                                    .onSurfaceVariant,
                                              ),
                                            )
                                          else
                                            ..._lista.take(12).map(
                                              (f) => ListTile(
                                                dense: true,
                                                contentPadding:
                                                    EdgeInsets.zero,
                                                title: Text(
                                                  f.nomeExibicao,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  f.ehManualSemDocumento
                                                      ? 'Manual / sem CNPJ'
                                                      : f.cnpj,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                trailing: f.ativo
                                                    ? null
                                                    : Text(
                                                        'Inativo',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: scheme
                                                              .error,
                                                        ),
                                                      ),
                                                onTap: () => _carregar(f),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                FornecedorCadastroRodape(
                  emEdicao: emEdicao,
                  onSalvar: () => unawaited(_salvar()),
                  onNovo: _limpar,
                  podeExcluir: emEdicao,
                  onExcluir: () => unawaited(_excluir()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBarraFerramentas() {
    final pesquisaBtn = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onPressed: _abrirPesquisa,
      icon: const Icon(Icons.search, size: 20),
      label: const Text('Pesquisar fornecedor'),
    );
    final nav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Primeiro',
          onPressed: _irParaPrimeiro,
          icon: const Icon(Icons.first_page_outlined),
        ),
        IconButton(
          tooltip: 'Anterior',
          onPressed: _irParaAnterior,
          icon: const Icon(Icons.navigate_before_outlined),
        ),
        IconButton(
          tooltip: 'Proximo',
          onPressed: _irParaProximo,
          icon: const Icon(Icons.navigate_next_outlined),
        ),
        IconButton(
          tooltip: 'Ultimo',
          onPressed: _irParaUltimo,
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

  Widget _buildMiniCardStatus(ThemeData theme) {
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
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              value: _ativo,
              onChanged: (v) => setState(() => _ativo = v),
              title: const Text(
                'Fornecedor ativo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
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

  Widget _linhaCampos({
    required List<Widget> campos,
    double larguraMinimaLinha = 620,
    double espacamento = 6,
    List<int>? flexes,
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
        final flexList = flexes ?? List<int>.filled(campos.length, 1);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < campos.length; i++) ...[
              if (i > 0) SizedBox(width: espacamento),
              Expanded(flex: flexList[i], child: campos[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStatusBanner(BuildContext context, String message) {
    final semantic = context.semanticColors;
    final m = message.toLowerCase();
    final sucesso = m.contains('sucesso') ||
        m.contains('salvo') ||
        m.contains('excluido') ||
        m.contains('excluído') ||
        m.contains('preenchidos');
    final erro = m.contains('falha') ||
        m.contains('erro') ||
        m.contains('obrigat') ||
        m.contains('nao encontrado') ||
        m.contains('não encontrado') ||
        m.contains('nao ha') ||
        m.contains('não ha');
    final ok = sucesso && !erro;
    final bg = ok ? semantic.successBg : semantic.errorBg;
    final border = ok ? semantic.successBorder : semantic.errorBorder;
    final fg = ok ? semantic.successFg : semantic.errorFg;
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
            ok ? Icons.check_circle_outline : Icons.error_outline,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _SalvarIntent extends Intent {
  const _SalvarIntent();
}

class _CnpjIntent extends Intent {
  const _CnpjIntent();
}

class _LimparIntent extends Intent {
  const _LimparIntent();
}
