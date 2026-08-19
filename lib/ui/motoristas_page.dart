import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/api/funcionario_api_repository.dart';
import '../domain/funcionario_cadastro_catalogo.dart';
import '../model/funcionario.dart';
import '../model/motorista.dart';
import 'layout/app_layout.dart';
import 'theme/app_semantic_helper.dart';
import 'widgets/consulta_lista_vazia.dart';
import 'widgets/lan_api_feedback.dart';
import 'widgets/mascaras_cadastro_input.dart';
import 'widgets/motorista/motorista_cadastro_header.dart';
import 'widgets/motorista/motorista_cadastro_rodape.dart';

class MotoristasPage extends StatefulWidget {
  const MotoristasPage({
    super.key,
    required this.motoristaRepository,
    this.funcionarioRepository,
  });

  final dynamic motoristaRepository;
  /// Usado para bloquear exclusao quando o motorista esta vinculado a RH.
  final dynamic funcionarioRepository;

  @override
  State<MotoristasPage> createState() => _MotoristasPageState();
}

class _MotoristasPageState extends State<MotoristasPage> {
  static const _padCampo = EdgeInsets.symmetric(horizontal: 10, vertical: 10);
  static const _iconCampo = BoxConstraints(
    minWidth: 28,
    minHeight: 28,
    maxWidth: 32,
    maxHeight: 32,
  );

  final _formKey = GlobalKey<FormState>();
  final _codigoController = TextEditingController();
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _cpfController = TextEditingController();
  final _cnhNumeroController = TextEditingController();
  final _pesquisaController = TextEditingController();
  final _scrollFormulario = ScrollController();
  final _cpfFormatter = CpfInputFormatter();
  final _telefoneFormatter = TelefoneInputFormatter();
  final _dataFmt = DateFormat('dd/MM/yyyy');

  int? _motoristaEmEdicaoId;
  DateTime? _criadoEmEdicao;
  String _cnhCategoria = '';
  DateTime? _cnhValidade;
  bool _ativo = true;
  bool _carregandoLista = false;
  String _status = '';

  bool get _terminalLeve =>
      widget.motoristaRepository is MotoristaApiRepository;

  @override
  void initState() {
    super.initState();
    final repo = widget.motoristaRepository;
    if (repo is MotoristaApiRepository) {
      repo.addListener(_onMotoristaApiChanged);
      unawaited(_hidratarTerminal());
    }
    _preencherCodigoSeNovo();
  }

  void _onMotoristaApiChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _hidratarTerminal() async {
    final repo = widget.motoristaRepository;
    if (repo is! MotoristaApiRepository) return;
    setState(() => _carregandoLista = true);
    try {
      await repo.hidratar();
      final funcRepo = widget.funcionarioRepository;
      if (funcRepo is FuncionarioApiRepository) {
        try {
          await funcRepo.hidratar();
        } catch (_) {
          // Vinculo RH e informativo; API do servidor ainda bloqueia exclusao.
        }
      }
      if (!mounted) return;
      setState(() {
        _carregandoLista = false;
        if (_motoristaEmEdicaoId == null) {
          _codigoController.text = repo.proximoCodigoInterno();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoLista = false);
      LanApiFeedback.snackAviso(context, e, prefixo: 'Motoristas');
    }
  }

  @override
  void dispose() {
    final repo = widget.motoristaRepository;
    if (repo is MotoristaApiRepository) {
      repo.removeListener(_onMotoristaApiChanged);
    }
    _codigoController.dispose();
    _nomeController.dispose();
    _telefoneController.dispose();
    _cpfController.dispose();
    _cnhNumeroController.dispose();
    _pesquisaController.dispose();
    _scrollFormulario.dispose();
    super.dispose();
  }

  void _preencherCodigoSeNovo() {
    if (_motoristaEmEdicaoId != null) return;
    _codigoController.text =
        '${widget.motoristaRepository.proximoCodigoInterno()}';
  }

  void _limparFormulario() {
    _formKey.currentState?.reset();
    setState(() {
      _motoristaEmEdicaoId = null;
      _criadoEmEdicao = null;
      _codigoController.clear();
      _nomeController.clear();
      _telefoneController.clear();
      _cpfController.clear();
      _cnhNumeroController.clear();
      _cnhCategoria = '';
      _cnhValidade = null;
      _ativo = true;
      _status = '';
    });
    _preencherCodigoSeNovo();
  }

  void _editar(Motorista m) {
    setState(() {
      _motoristaEmEdicaoId = m.id;
      _criadoEmEdicao = m.criadoEm;
      _codigoController.text = m.codigoInterno;
      _nomeController.text = m.nome;
      _telefoneController.text = m.telefone;
      _cpfController.text = m.cpf;
      _cnhNumeroController.text = m.cnhNumero;
      _cnhCategoria =
          FuncionarioCadastroCatalogo.idsCategoriasCnh.contains(m.cnhCategoria)
              ? m.cnhCategoria
              : '';
      _cnhValidade = m.cnhValidade;
      _ativo = m.ativo;
      _status = 'Editando: ${m.nome}';
    });
  }

  Future<void> _selecionarCnhValidade() async {
    final agora = DateTime.now();
    final inicial = _cnhValidade ?? agora.add(const Duration(days: 365));
    final escolhida = await showDatePicker(
      context: context,
      initialDate: inicial.isBefore(agora) ? agora : inicial,
      firstDate: DateTime(agora.year - 1),
      lastDate: DateTime(agora.year + 20),
    );
    if (escolhida != null && mounted) {
      setState(() => _cnhValidade = escolhida);
    }
  }

  Funcionario? _funcionarioVinculado(int motoristaId) {
    final repo = widget.funcionarioRepository;
    if (repo == null || motoristaId <= 0) return null;
    try {
      final lista = repo.listarTodos();
      if (lista is! Iterable) return null;
      for (final f in lista) {
        if (f is Funcionario && f.motoristaId == motoristaId) return f;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final nome = _nomeController.text.trim();
    final idAtual = _motoristaEmEdicaoId ?? 0;
    var codigo = _codigoController.text.trim();
    if (codigo.isEmpty) {
      codigo = '${widget.motoristaRepository.proximoCodigoInterno()}';
      _codigoController.text = codigo;
    }

    final repo = widget.motoristaRepository;
    if (repo.existeNomeParaOutro(nomeNormalizado: nome, ignorarId: idAtual)) {
      setState(() => _status = 'Ja existe um motorista com este nome.');
      return;
    }
    if (repo.existeCodigoParaOutro(
      codigoNormalizado: codigo,
      ignorarId: idAtual,
    )) {
      setState(() => _status = 'Ja existe um motorista com este codigo.');
      return;
    }
    final cpf = somenteDigitos(_cpfController.text);
    if (!cpfValidoOuVazio(cpf)) {
      setState(() => _status = 'CPF invalido.');
      return;
    }
    if (cpf.isNotEmpty &&
        repo.existeCpfParaOutro(cpfSomenteDigitos: cpf, ignorarId: idAtual)) {
      setState(() => _status = 'Ja existe um motorista com este CPF.');
      return;
    }
    final cnh = somenteDigitos(_cnhNumeroController.text);
    if (cnh.isNotEmpty &&
        repo.existeCnhParaOutro(cnhSomenteDigitos: cnh, ignorarId: idAtual)) {
      setState(() => _status = 'Ja existe um motorista com esta CNH.');
      return;
    }

    final atual = idAtual > 0 ? repo.obterPorId(idAtual) as Motorista? : null;
    final motorista = Motorista(
      id: atual?.id ?? 0,
      codigoInterno: codigo,
      nome: nome,
      telefone: somenteDigitos(_telefoneController.text),
      cpf: cpf,
      cnhNumero: cnh,
      cnhCategoria: _cnhCategoria,
      cnhValidade: _cnhValidade,
      ativo: _ativo,
      criadoEm: atual?.criadoEm ?? _criadoEmEdicao,
    );

    try {
      final id = repo is MotoristaApiRepository
          ? await repo.salvarRemoto(motorista)
          : repo.salvar(motorista) as int;
      if (!mounted) return;
      final salvo = repo.obterPorId(id) as Motorista?;
      setState(() {
        _motoristaEmEdicaoId = id;
        _criadoEmEdicao = salvo?.criadoEm ?? motorista.criadoEm;
        _status = 'Motorista salvo com sucesso.';
      });
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel salvar');
      setState(() => _status = LanApiFeedback.mensagem(e));
    }
  }

  Future<void> _remover(Motorista m) async {
    final vinculado = _funcionarioVinculado(m.id);
    if (vinculado != null) {
      setState(
        () => _status =
            'Nao e possivel remover: motorista vinculado ao funcionario '
            '"${vinculado.nomeCompleto}". Desvincule em Cadastros > Funcionarios '
            'ou desative o motorista.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_status)),
        );
      }
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover motorista'),
        content: Text('Deseja remover "${m.nome}"?'),
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
    final repo = widget.motoristaRepository;
    try {
      if (repo is MotoristaApiRepository) {
        final removido = await repo.removerRemoto(m.id);
        if (!removido) {
          if (!mounted) return;
          LanApiFeedback.snackAviso(
            context,
            'Nao foi possivel remover o motorista.',
          );
          return;
        }
      } else {
        repo.remover(m.id);
      }
      if (!mounted) return;
      if (_motoristaEmEdicaoId == m.id) _limparFormulario();
      setState(() => _status = 'Motorista removido com sucesso.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Motorista removido com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel remover');
      setState(() => _status = LanApiFeedback.mensagem(e));
    }
  }

  bool _cnhVencida(Motorista m) {
    final v = m.cnhValidade;
    if (v == null) return false;
    final hoje = DateTime.now();
    final dia = DateTime(hoje.year, hoje.month, hoje.day);
    final val = DateTime(v.year, v.month, v.day);
    return val.isBefore(dia);
  }

  List<Motorista> _motoristasOrdenados() {
    final lista = widget.motoristaRepository.listarTodos() as List<Motorista>;
    final copia = List<Motorista>.from(lista);
    copia.sort((a, b) {
      final ca = a.codigoInterno.compareTo(b.codigoInterno);
      if (ca != 0) return ca;
      return a.id.compareTo(b.id);
    });
    return copia;
  }

  int _indiceMotoristaAtual(List<Motorista> lista) {
    if (_motoristaEmEdicaoId == null) return -1;
    return lista.indexWhere((m) => m.id == _motoristaEmEdicaoId);
  }

  void _abrirMotoristaPorIndice(int indice) {
    final lista = _motoristasOrdenados();
    if (lista.isEmpty) {
      setState(
        () => _status = 'Nao ha motoristas cadastrados para navegar.',
      );
      return;
    }
    _editar(lista[indice.clamp(0, lista.length - 1)]);
  }

  void _irParaPrimeiro() => _abrirMotoristaPorIndice(0);

  void _irParaUltimo() {
    final lista = _motoristasOrdenados();
    if (lista.isEmpty) {
      setState(
        () => _status = 'Nao ha motoristas cadastrados para navegar.',
      );
      return;
    }
    _abrirMotoristaPorIndice(lista.length - 1);
  }

  void _irParaAnterior() {
    final lista = _motoristasOrdenados();
    if (lista.isEmpty) {
      setState(
        () => _status = 'Nao ha motoristas cadastrados para navegar.',
      );
      return;
    }
    final atual = _indiceMotoristaAtual(lista);
    _abrirMotoristaPorIndice(atual <= 0 ? 0 : atual - 1);
  }

  void _irParaProximo() {
    final lista = _motoristasOrdenados();
    if (lista.isEmpty) {
      setState(
        () => _status = 'Nao ha motoristas cadastrados para navegar.',
      );
      return;
    }
    final atual = _indiceMotoristaAtual(lista);
    if (atual < 0 || atual >= lista.length - 1) {
      _abrirMotoristaPorIndice(lista.length - 1);
      return;
    }
    _abrirMotoristaPorIndice(atual + 1);
  }

  Future<void> _excluirAtual() async {
    final id = _motoristaEmEdicaoId;
    if (id == null) return;
    final m = widget.motoristaRepository.obterPorId(id) as Motorista?;
    if (m == null) return;
    await _remover(m);
  }

  Future<void> _abrirPesquisa() async {
    final ctrl = TextEditingController(text: _pesquisaController.text);
    final escolhido = await showDialog<Motorista>(
      context: context,
      builder: (ctx) {
        var resultados = widget.motoristaRepository.pesquisar(ctrl.text)
            as List<Motorista>;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Pesquisar motorista'),
              content: SizedBox(
                width: 520,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nome, CPF, CNH, telefone...',
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) {
                        setLocal(() {
                          resultados = widget.motoristaRepository.pesquisar(v)
                              as List<Motorista>;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: resultados.isEmpty
                          ? const Center(child: Text('Nenhum motorista.'))
                          : ListView.builder(
                              itemCount: resultados.length,
                              itemBuilder: (_, i) {
                                final m = resultados[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    m.codigoInterno.isEmpty
                                        ? m.nome
                                        : '${m.codigoInterno} · ${m.nome}',
                                  ),
                                  subtitle: Text(
                                    [
                                      if (m.cpf.isNotEmpty) 'CPF ${m.cpf}',
                                      if (m.cnhNumero.isNotEmpty)
                                        'CNH ${m.cnhNumero}',
                                      if (!m.ativo) 'inativo',
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                  ),
                                  onTap: () => Navigator.pop(ctx, m),
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
    if (escolhido != null && mounted) _editar(escolhido);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emEdicao = _motoristaEmEdicaoId != null;
    final listados = widget.motoristaRepository.pesquisar(
      _pesquisaController.text,
    ) as List<Motorista>;
    final catSelecionada =
        FuncionarioCadastroCatalogo.idsCategoriasCnh.contains(_cnhCategoria)
            ? _cnhCategoria
            : null;
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
        SingleActivator(LogicalKeyboardKey.escape): _LimparIntent(),
      },
      child: Actions(
        actions: {
          _SalvarIntent: CallbackAction(onInvoke: (_) {
            unawaited(_salvar());
            return null;
          }),
          _LimparIntent: CallbackAction(onInvoke: (_) {
            _limparFormulario();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Cadastro de Motoristas'),
              actions: [
                if (_terminalLeve)
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
                        : const Icon(Icons.refresh_outlined),
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
                        MotoristaCadastroHeader(
                          emEdicao: emEdicao,
                          motoristaId: _motoristaEmEdicaoId,
                          nome: _nomeController.text,
                          codigoInterno: _codigoController.text,
                          cpf: _cpfController.text,
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
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (_terminalLeve) ...[
                                          Material(
                                            color: scheme.secondaryContainer
                                                .withValues(alpha: 0.45),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: const ListTile(
                                              dense: true,
                                              leading: Icon(Icons.info_outline),
                                              title: Text(
                                                'Terminal leve: cadastro sincroniza com o PC servidor. '
                                                'Preferivel desativar em vez de apagar se houver entregas no nome.',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                        _buildSectionCard(
                                          title: 'Identificacao',
                                          icon: Icons.badge_outlined,
                                          children: [
                                            _linhaCampos(
                                              larguraMinimaLinha: 560,
                                              flexes: const [1, 3],
                                              campos: [
                                                TextFormField(
                                                  controller:
                                                      _codigoController,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText: 'Codigo',
                                                    isDense: true,
                                                  ),
                                                ),
                                                TextFormField(
                                                  controller: _nomeController,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText: 'Nome',
                                                    isDense: true,
                                                  ),
                                                  textCapitalization:
                                                      TextCapitalization
                                                          .words,
                                                  validator: (v) {
                                                    if (v == null ||
                                                        v.trim().isEmpty) {
                                                      return 'Informe o nome do motorista.';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            _linhaCampos(
                                              larguraMinimaLinha: 560,
                                              flexes: const [1, 1],
                                              campos: [
                                                TextFormField(
                                                  controller:
                                                      _telefoneController,
                                                  inputFormatters: [
                                                    _telefoneFormatter,
                                                  ],
                                                  keyboardType:
                                                      TextInputType.phone,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText: 'Telefone',
                                                    isDense: true,
                                                  ),
                                                ),
                                                TextFormField(
                                                  controller: _cpfController,
                                                  inputFormatters: [
                                                    _cpfFormatter,
                                                  ],
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText: 'CPF',
                                                    isDense: true,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        _buildSectionCard(
                                          title: 'CNH',
                                          icon: Icons.credit_card_outlined,
                                          children: [
                                            _linhaCampos(
                                              larguraMinimaLinha: 560,
                                              flexes: const [1, 1],
                                              campos: [
                                                TextFormField(
                                                  controller:
                                                      _cnhNumeroController,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText: 'CNH (numero)',
                                                    isDense: true,
                                                  ),
                                                ),
                                                DropdownButtonFormField<
                                                    String>(
                                                  // ignore: deprecated_member_use
                                                  value: catSelecionada,
                                                  isDense: true,
                                                  isExpanded: true,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText:
                                                        'Categoria CNH',
                                                    isDense: true,
                                                  ),
                                                  items: [
                                                    const DropdownMenuItem(
                                                      value: null,
                                                      child: Text(
                                                        'Nao informada',
                                                      ),
                                                    ),
                                                    ...FuncionarioCadastroCatalogo
                                                        .categoriasCnh.entries
                                                        .map(
                                                      (e) =>
                                                          DropdownMenuItem(
                                                        value: e.key,
                                                        child: Text(e.value),
                                                      ),
                                                    ),
                                                  ],
                                                  onChanged: (v) => setState(
                                                    () => _cnhCategoria =
                                                        v ?? '',
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            InkWell(
                                              onTap: _selecionarCnhValidade,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: InputDecorator(
                                                decoration:
                                                    const InputDecoration(
                                                  labelText:
                                                      'Validade da CNH',
                                                  isDense: true,
                                                  suffixIcon: Icon(
                                                    Icons
                                                        .calendar_today_outlined,
                                                    size: 18,
                                                  ),
                                                ),
                                                child: Text(
                                                  _cnhValidade == null
                                                      ? 'Nao informada'
                                                      : _dataFmt.format(
                                                          _cnhValidade!,
                                                        ),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        _buildSectionCard(
                                          title: 'Status',
                                          icon: Icons.toggle_on_outlined,
                                          children: [
                                            _buildMiniCardStatus(theme),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        _buildSectionCard(
                                          title:
                                              'Cadastros (${listados.length})',
                                          icon: Icons.list_alt_outlined,
                                          children: [
                                            TextField(
                                              controller:
                                                  _pesquisaController,
                                              onChanged: (_) =>
                                                  setState(() {}),
                                              decoration:
                                                  const InputDecoration(
                                                labelText:
                                                    'Pesquisar (nome, CPF, CNH, telefone...)',
                                                isDense: true,
                                                prefixIcon: Icon(
                                                  Icons.search,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (_carregandoLista)
                                              const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: 16,
                                                ),
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              )
                                            else if (listados.isEmpty)
                                              const ConsultaListaVazia(
                                                mensagem:
                                                    'Nenhum motorista cadastrado.',
                                                dica:
                                                    'Preencha o formulario acima e salve.',
                                                icone: Icons
                                                    .local_shipping_outlined,
                                              )
                                            else
                                              ...listados.map((m) {
                                                final vencida =
                                                    _cnhVencida(m);
                                                final vinculo =
                                                    _funcionarioVinculado(
                                                  m.id,
                                                );
                                                return ListTile(
                                                  dense: true,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  title: Text(
                                                    m.codigoInterno.isEmpty
                                                        ? m.nome
                                                        : '${m.codigoInterno} · ${m.nome}',
                                                    style: const TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  subtitle: Text(
                                                    [
                                                      if (m.telefone
                                                          .isNotEmpty)
                                                        m.telefone,
                                                      if (m.cpf.isNotEmpty)
                                                        'CPF ${m.cpf}',
                                                      if (m.cnhNumero
                                                          .isNotEmpty)
                                                        'CNH ${m.cnhNumero}'
                                                            '${m.cnhCategoria.isEmpty ? '' : ' (${m.cnhCategoria})'}',
                                                      if (m.cnhValidade !=
                                                          null)
                                                        vencida
                                                            ? 'CNH vencida ${_dataFmt.format(m.cnhValidade!)}'
                                                            : 'val. ${_dataFmt.format(m.cnhValidade!)}',
                                                      if (vinculo != null)
                                                        'RH: ${vinculo.nomeCompleto}',
                                                      if (!m.ativo)
                                                        'inativo',
                                                    ]
                                                        .where(
                                                          (s) =>
                                                              s.isNotEmpty,
                                                        )
                                                        .join(' · ')
                                                        .ifEmpty(
                                                          'Sem dados',
                                                        ),
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  isThreeLine: true,
                                                  onTap: () => _editar(m),
                                                  trailing: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (vencida)
                                                        Icon(
                                                          Icons
                                                              .warning_amber_outlined,
                                                          color: scheme
                                                              .error,
                                                          size: 20,
                                                        ),
                                                      IconButton(
                                                        tooltip: 'Editar',
                                                        onPressed: () =>
                                                            _editar(m),
                                                        icon: const Icon(
                                                          Icons
                                                              .edit_outlined,
                                                          size: 20,
                                                        ),
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Remover',
                                                        onPressed: () =>
                                                            unawaited(
                                                          _remover(m),
                                                        ),
                                                        icon: Icon(
                                                          Icons
                                                              .delete_outline,
                                                          size: 20,
                                                          color: scheme
                                                              .error,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                          ],
                                        ),
                                      ],
                                    ),
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
                MotoristaCadastroRodape(
                  emEdicao: emEdicao,
                  onSalvar: () => unawaited(_salvar()),
                  onNovo: _limparFormulario,
                  podeExcluir: emEdicao,
                  onExcluir: () => unawaited(_excluirAtual()),
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
      onPressed: () => unawaited(_abrirPesquisa()),
      icon: const Icon(Icons.search, size: 20),
      label: const Text('Pesquisar motorista'),
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
                'Motorista ativo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: const Text(
                'Desligue em ferias ou desligamento da logistica.',
                style: TextStyle(fontSize: 11),
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
        m.contains('removido');
    final erro = m.contains('falha') ||
        m.contains('erro') ||
        m.contains('invalido') ||
        m.contains('inválido') ||
        m.contains('ja existe') ||
        m.contains('já existe') ||
        m.contains('nao e possivel') ||
        m.contains('não e possivel') ||
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
            ok ? Icons.check_circle_outline : Icons.info_outline,
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

class _LimparIntent extends Intent {
  const _LimparIntent();
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
