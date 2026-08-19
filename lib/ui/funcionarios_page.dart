import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/conta_pagar_repository.dart';
import '../data/api/funcionario_api_repository.dart';
import '../data/api/vendedor_api_repository.dart';
import '../domain/funcionario_cadastro_catalogo.dart';
import '../domain/funcionario_folha_resumo.dart';
import '../domain/funcionario_folha_service.dart';
import '../domain/lancamento_funcionario_catalogo.dart';
import '../domain/perfil_usuario_preset.dart';
import '../model/funcionario.dart';
import '../model/lancamento_funcionario.dart';
import '../model/motorista.dart';
import '../model/vendedor.dart';
import '../model/usuario_sistema.dart';
import '../services/funcionario_extrato_pdf.dart';
import '../services/funcionario_folha_csv_export.dart';
import '../services/funcionario_imagem_service.dart';
import 'widgets/lan_api_feedback.dart';
import '../services/brasil_api_cep_service.dart';
import 'funcionarios/funcionario_layout.dart';
import 'funcionarios/widgets/funcionario_atalhos_bar.dart';
import 'funcionarios/widgets/funcionario_folha_painel.dart';
import 'funcionarios/widgets/funcionario_foto_panel.dart';
import 'funcionarios/widgets/funcionario_resumo_header.dart';
import 'layout/app_layout.dart';
import 'theme/app_semantic_helper.dart';
import 'widgets/conta_sessao_app_bar_actions.dart';
import 'widgets/funcionario/funcionario_cadastro_rodape.dart';
import 'widgets/mascaras_cadastro_input.dart';

class _FuncionarioSalvarIntent extends Intent {
  const _FuncionarioSalvarIntent();
}

class _FuncionarioNovoIntent extends Intent {
  const _FuncionarioNovoIntent();
}

class _FuncionarioPesquisarIntent extends Intent {
  const _FuncionarioPesquisarIntent();
}

class FuncionariosPage extends StatefulWidget {
  const FuncionariosPage({
    super.key,
    required this.funcionarioRepository,
    required this.vendedorRepository,
    required this.vendaRepository,
    required this.motoristaRepository,
    required this.usuarioRepository,
    this.usuarioLogado,
    this.onLogout,
  });

  final dynamic funcionarioRepository;
  final dynamic vendedorRepository;
  final dynamic vendaRepository;
  final dynamic motoristaRepository;
  final dynamic usuarioRepository;
  final UsuarioSistema? usuarioLogado;
  final VoidCallback? onLogout;

  @override
  State<FuncionariosPage> createState() => _FuncionariosPageState();
}

class _FuncionariosPageState extends State<FuncionariosPage>
    with SingleTickerProviderStateMixin {
  bool get _terminalRh =>
      widget.funcionarioRepository is FuncionarioApiRepository;

  FuncionarioFolhaService? _folhaService;
  late final FuncionarioImagemService _imagemService = _criarImagemService();

  String _fotoPathAtual = '';
  String? _fotoOrigemLocalPath;
  bool _fotoFoiRemovida = false;

  FuncionarioImagemService _criarImagemService() {
    if (_terminalRh) {
      return FuncionarioImagemService(imagesDirectoryPath: '');
    }
    return FuncionarioImagemService(
      imagesDirectoryPath:
          widget.funcionarioRepository.funcionarioImagesDirPath as String,
    );
  }

  void _avisoFolhaSoServidor() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Fechamento de folha / RH avancado so no PC servidor.',
        ),
      ),
    );
  }

  static ButtonStyle get _estiloBotaoContornoCompacto =>
      OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  static const double _wCodigo = 132;
  static const double _wData = 232;
  static const double _wCpf = 200;
  static const double _wRg = 168;
  static const double _wPis = 220;
  static const double _wFone = 184;
  static const double _wCep = 120;
  static const double _wNumero = 88;
  static const double _wUf = 72;
  static const double _wMoeda = 176;
  static const double _wDiaPag = 132;
  static const double _wPct = 120;
  static const double _wCnh = 200;
  static const EdgeInsets _padCampoCadastro =
      EdgeInsets.symmetric(horizontal: 10, vertical: 10);
  static const BoxConstraints _iconCampoCadastro = BoxConstraints(
    minWidth: 28,
    minHeight: 28,
    maxWidth: 32,
    maxHeight: 32,
  );
  static const Color _pageBg = Color(0xFFF8FAFC);

  final _cpfFormatter = CpfInputFormatter();
  final _cepFormatter = CepInputFormatter();
  final _telefoneFormatter = TelefoneInputFormatter();

  final _codigoController = TextEditingController();
  final _nomeController = TextEditingController();
  final _funcaoOutroController = TextEditingController();
  final _motivoDemissaoOutroController = TextEditingController();
  final _contatoEmergenciaNomeController = TextEditingController();
  final _contatoEmergenciaTelefoneController = TextEditingController();
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
  final _diaPagamentoController = TextEditingController(text: '5');
  final _vendedorApelidoController = TextEditingController();
  final _vendedorComissaoController = TextEditingController();
  final _vendedorMetaController = TextEditingController();
  final _observacoesController = TextEditingController();
  final _cnhNumeroController = TextEditingController();
  final _epiObservacoesController = TextEditingController();
  final _scrollAbaIdent = ScrollController();
  final _scrollAbaDocs = ScrollController();
  final _scrollAbaFin = ScrollController();
  final _scrollAbaOp = ScrollController();
  late TabController _tabController;
  final _nomeFocus = FocusNode(debugLabel: 'funcionarioNome');
  final _cepFocus = FocusNode(debugLabel: 'funcionarioCep');

  Timer? _debounceConsultaCep;
  bool _consultaCepEmAndamento = false;

  int? _funcionarioEmEdicaoId;
  bool _ativo = true;
  String _setorSelecionado = 'balcao';
  String _funcaoSelecionada = 'vendedor';
  String _motivoDemissao = '';
  DateTime? _dataDemissao;
  bool _tambemVendedorPdv = false;
  int _vendedorVinculadoId = 0;
  bool _tambemMotoristaEntrega = false;
  int _motoristaVinculadoId = 0;
  bool _temUsuarioSistema = false;
  String _usuarioVinculadoId = '';
  List<UsuarioSistema> _usuariosCache = [];
  String _tipoVinculo = 'clt';
  String _cnhCategoria = '';
  DateTime? _cnhValidade;
  DateTime? _asoData;
  DateTime? _asoValidade;
  String _tamanhoUniforme = '';
  bool _podeOperarEmpilhadeira = false;
  bool _podeOperarTranspalete = false;
  DateTime _dataNascimento = DateTime(2000, 1, 1);
  DateTime _dataAdmissao = DateTime.now();
  String _status = '';
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _mesAnoFormat = DateFormat('MMMM/yyyy', 'pt_BR');
  List<LancamentoFuncionario> _lancamentos = [];
  late DateTime _mesFiltroLancamentos = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  @override
  void initState() {
    super.initState();
    if (!_terminalRh) {
      _folhaService = FuncionarioFolhaService(
        funcionarioRepository: widget.funcionarioRepository,
        fechamentoRepository: widget.funcionarioRepository.fechamentos,
        contaPagarRepository: ContaPagarRepository(
          widget.funcionarioRepository.objectBox,
        ),
      );
    } else {
      final repo = widget.funcionarioRepository;
      if (repo is FuncionarioApiRepository) {
        repo.addListener(_onFuncionarioApiChanged);
        unawaited(_hidratarTerminal());
      }
    }
    _tabController = TabController(length: 4, vsync: this);
    _nomeController.addListener(_onCamposResumoChanged);
    unawaited(_carregarUsuariosCache());
    _preencherCodigoAutomaticoSeNovo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focarNomeSeNovo();
    });
  }

  void _onFuncionarioApiChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _hidratarTerminal() async {
    final repo = widget.funcionarioRepository;
    if (repo is! FuncionarioApiRepository) return;
    try {
      await repo.hidratar();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackAviso(context, e, prefixo: 'Funcionarios');
    }
  }

  void _focarNomeSeNovo() {
    if (_funcionarioEmEdicaoId != null) return;
    _nomeFocus.requestFocus();
  }

  void _onCamposResumoChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _carregarUsuariosCache() async {
    final lista = await widget.usuarioRepository.listarTodos();
    if (!mounted) return;
    setState(() => _usuariosCache = lista);
  }

  @override
  void dispose() {
    final repo = widget.funcionarioRepository;
    if (repo is FuncionarioApiRepository) {
      repo.removeListener(_onFuncionarioApiChanged);
    }
    _nomeController.removeListener(_onCamposResumoChanged);
    _tabController.dispose();
    _scrollAbaIdent.dispose();
    _scrollAbaDocs.dispose();
    _scrollAbaFin.dispose();
    _scrollAbaOp.dispose();
    _debounceConsultaCep?.cancel();
    _nomeFocus.dispose();
    _cepFocus.dispose();
    _codigoController.dispose();
    _nomeController.dispose();
    _funcaoOutroController.dispose();
    _motivoDemissaoOutroController.dispose();
    _contatoEmergenciaNomeController.dispose();
    _contatoEmergenciaTelefoneController.dispose();
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
    _diaPagamentoController.dispose();
    _vendedorApelidoController.dispose();
    _vendedorComissaoController.dispose();
    _vendedorMetaController.dispose();
    _observacoesController.dispose();
    _cnhNumeroController.dispose();
    _epiObservacoesController.dispose();
    super.dispose();
  }

  void _preencherCodigoAutomaticoSeNovo() {
    if (_funcionarioEmEdicaoId != null) return;
    if (_codigoController.text.trim().isNotEmpty) return;
    _codigoController.text = widget.funcionarioRepository
        .proximoCodigoInterno();
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

  Future<void> _selecionarCnhValidade() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate:
          _cnhValidade ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365 * 15)),
    );
    if (escolhida == null) return;
    setState(() => _cnhValidade = escolhida);
  }

  Future<void> _selecionarAsoData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _asoData ?? _dataAdmissao,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (escolhida == null) return;
    setState(() => _asoData = escolhida);
  }

  Future<void> _selecionarAsoValidade() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate:
          _asoValidade ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (escolhida == null) return;
    setState(() => _asoValidade = escolhida);
  }

  bool _documentoVencido(DateTime? data) {
    if (data == null) return false;
    final hoje = DateTime.now();
    final ref = DateTime(hoje.year, hoje.month, hoje.day);
    final limite = DateTime(data.year, data.month, data.day);
    return limite.isBefore(ref);
  }

  bool get _cnhVencida => _documentoVencido(_cnhValidade);

  bool get _asoVencido => _documentoVencido(_asoValidade);

  PerfilUsuarioPreset _perfilSugeridoUsuario() {
    if (_setorSelecionado == 'motorista' ||
        _funcaoSelecionada == 'motorista' ||
        _funcaoSelecionada == 'ajudante') {
      return PerfilUsuarioPreset.motorista;
    }
    if (_setorSelecionado == 'caixa' || _funcaoSelecionada == 'caixa') {
      return PerfilUsuarioPreset.caixa;
    }
    if (_setorSelecionado == 'expedicao' ||
        _funcaoSelecionada == 'conferente' ||
        _funcaoSelecionada == 'estoquista') {
      return PerfilUsuarioPreset.separador;
    }
    if (_setorSelecionado == 'compras' || _funcaoSelecionada == 'comprador') {
      return PerfilUsuarioPreset.comprador;
    }
    if (_funcaoSelecionada == 'gerente') {
      return PerfilUsuarioPreset.gerente;
    }
    return PerfilUsuarioPreset.vendedor;
  }

  String _sugerirLoginFromNome() {
    final partes = _nomeController.text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '';
    if (partes.length == 1) return partes.first;
    return '${partes.first}.${partes.last}';
  }

  void _sugerirVinculosOperacionaisPorSetor() {
    if (_setorSelecionado == 'motorista' ||
        _funcaoSelecionada == 'motorista' ||
        _funcaoSelecionada == 'ajudante') {
      _tambemMotoristaEntrega = true;
    }
    if (_setorSelecionado == 'balcao' ||
        _setorSelecionado == 'caixa' ||
        _funcaoSelecionada == 'vendedor' ||
        _funcaoSelecionada == 'caixa') {
      // Nao forca usuario — apenas motorista quando aplicavel.
    }
  }

  void _limparFormulario() {
    setState(() {
      _codigoController.clear();
      _nomeController.clear();
      _funcaoOutroController.clear();
      _motivoDemissaoOutroController.clear();
      _contatoEmergenciaNomeController.clear();
      _contatoEmergenciaTelefoneController.clear();
      _setorSelecionado = 'balcao';
      _funcaoSelecionada = 'vendedor';
      _motivoDemissao = '';
      _dataDemissao = null;
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
      _diaPagamentoController.text = '5';
      _vendedorApelidoController.clear();
      _vendedorComissaoController.clear();
      _vendedorMetaController.clear();
      _tambemVendedorPdv = false;
      _vendedorVinculadoId = 0;
      _tambemMotoristaEntrega = false;
      _motoristaVinculadoId = 0;
      _temUsuarioSistema = false;
      _usuarioVinculadoId = '';
      _tipoVinculo = 'clt';
      _cnhNumeroController.clear();
      _cnhCategoria = '';
      _cnhValidade = null;
      _asoData = null;
      _asoValidade = null;
      _tamanhoUniforme = '';
      _epiObservacoesController.clear();
      _podeOperarEmpilhadeira = false;
      _podeOperarTranspalete = false;
      _fotoPathAtual = '';
      _fotoOrigemLocalPath = null;
      _fotoFoiRemovida = false;
      _lancamentos = [];
      _mesFiltroLancamentos = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      );
      _observacoesController.clear();
      _dataNascimento = DateTime(2000, 1, 1);
      _dataAdmissao = DateTime.now();
      _ativo = true;
      _funcionarioEmEdicaoId = null;
      _status = '';
      _preencherCodigoAutomaticoSeNovo();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focarNomeSeNovo();
    });
  }

  void _agendarConsultaCep() {
    _debounceConsultaCep?.cancel();
    final digitos = somenteDigitos(_cepController.text);
    if (digitos.length != 8) return;
    _debounceConsultaCep = Timer(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      unawaited(_executarConsultaCep());
    });
  }

  Future<void> _executarConsultaCep() async {
    final digitos = somenteDigitos(_cepController.text);
    if (digitos.length != 8) return;
    if (_consultaCepEmAndamento) return;
    setState(() => _consultaCepEmAndamento = true);
    try {
      final dados = await BrasilApiCepService.consultar(digitos);
      if (!mounted) return;
      if (somenteDigitos(_cepController.text) != digitos) return;
      if (dados == null) {
        setState(() => _status = 'CEP nao encontrado na BrasilAPI.');
        return;
      }
      setState(() {
        _enderecoController.text = dados.logradouro;
        _bairroController.text = dados.bairro;
        _cidadeController.text = dados.cidade;
        _ufController.text = dados.uf;
        _cepController.text = dados.cep;
        _status = 'Endereco preenchido pelo CEP.';
      });
      aplicarMascaraCep(_cepController, _cepFormatter);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Falha ao consultar CEP: $e');
    } finally {
      if (mounted) setState(() => _consultaCepEmAndamento = false);
    }
  }

  String _rotuloTempoCasa() {
    final adm = DateTime(
      _dataAdmissao.year,
      _dataAdmissao.month,
      _dataAdmissao.day,
    );
    final hoje = DateTime.now();
    final dias = hoje.difference(adm).inDays;
    if (dias < 30) return 'Admissao recente';
    final meses = dias ~/ 30;
    if (meses < 12) return '$meses mes(es)';
    final anos = meses ~/ 12;
    return '$anos ano(s)';
  }

  double _parseBr(String text) {
    final n = text.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(n) ?? 0;
  }

  String _resumoSetorFuncaoAtual() =>
      FuncionarioCadastroCatalogo.resumoSetorFuncao(
        setor: _setorSelecionado,
        funcao: _funcaoSelecionada,
        funcaoOutro: _funcaoOutroController.text,
      );

  static String _resumoRhDe(Funcionario f) =>
      FuncionarioCadastroCatalogo.resumoSetorFuncao(
        setor: f.setor,
        funcao: f.funcao,
        funcaoOutro: f.funcaoOutro,
        cargoLegado: f.cargo,
      );

  void _carregarRhFromFuncionario(Funcionario f) {
    var setor = f.setor;
    var funcao = f.funcao;
    var funcaoOutro = f.funcaoOutro;
    if (setor.isEmpty && funcao.isEmpty) {
      final leg = FuncionarioCadastroCatalogo.migrarCargoLegado(
        f.cargo,
        '',
        '',
      );
      setor = leg.setor;
      funcao = leg.funcao;
      funcaoOutro = leg.funcaoOutro;
    }
    _setorSelecionado = FuncionarioCadastroCatalogo.idsSetores.contains(setor)
        ? setor
        : 'outro';
    _funcaoSelecionada = FuncionarioCadastroCatalogo.idsFuncoes.contains(funcao)
        ? funcao
        : 'outro';
    _funcaoOutroController.text = _funcaoSelecionada == 'outro'
        ? (funcaoOutro.isNotEmpty ? funcaoOutro : f.cargo)
        : '';
    _motivoDemissao = f.motivoDemissao;
    _motivoDemissaoOutroController.text = f.motivoDemissaoOutro;
    _dataDemissao = f.dataDemissao?.toLocal();
    _contatoEmergenciaNomeController.text = f.contatoEmergenciaNome;
    _contatoEmergenciaTelefoneController.text = f.contatoEmergenciaTelefone;
    if (f.contatoEmergenciaTelefone.isNotEmpty) {
      aplicarMascaraTelefone(
        _contatoEmergenciaTelefoneController,
        _telefoneFormatter,
      );
    }
  }

  Future<void> _onAtivoChanged(bool novoAtivo) async {
    if (novoAtivo) {
      setState(() {
        _ativo = true;
        _dataDemissao = null;
        _motivoDemissao = '';
        _motivoDemissaoOutroController.clear();
      });
      return;
    }
    final r = await _mostrarDialogDemissao(
      dataInicial: _dataDemissao ?? DateTime.now(),
      motivoInicial: _motivoDemissao,
      motivoOutroInicial: _motivoDemissaoOutroController.text,
    );
    if (r == null || !mounted) return;
    setState(() {
      _ativo = false;
      _dataDemissao = r.data;
      _motivoDemissao = r.motivo;
      _motivoDemissaoOutroController.text = r.motivoOutro;
    });
  }

  Future<_DemissaoDialogResult?> _mostrarDialogDemissao({
    required DateTime dataInicial,
    required String motivoInicial,
    required String motivoOutroInicial,
  }) {
    return showDialog<_DemissaoDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DemissaoFuncionarioDialog(
        dataInicial: dataInicial,
        motivoInicial: motivoInicial,
        motivoOutroInicial: motivoOutroInicial,
        dateFormat: _dateFormat,
      ),
    );
  }

  Future<void> _selecionarDataDemissao() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataDemissao ?? DateTime.now(),
      firstDate: DateTime(1950, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (escolhida == null) return;
    setState(() => _dataDemissao = escolhida);
  }

  Future<void> _salvar() async {
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

    final cpf = somenteDigitos(_cpfController.text);
    if (!cpfValidoOuVazio(cpf)) {
      setState(() => _status = 'CPF invalido. Confira os digitos.');
      return;
    }
    if (cpf.isNotEmpty &&
        widget.funcionarioRepository.existeCpfParaOutro(
          cpfSomenteDigitos: cpf,
          ignorarId: idAtual,
        )) {
      setState(() => _status = 'Ja existe outro funcionario com este CPF.');
      return;
    }

    if (!FuncionarioCadastroCatalogo.idsSetores.contains(_setorSelecionado)) {
      setState(() => _status = 'Selecione o setor do funcionario.');
      return;
    }
    final funcaoOutro = _funcaoSelecionada == 'outro'
        ? _funcaoOutroController.text.trim()
        : '';
    if (_funcaoSelecionada == 'outro' && funcaoOutro.isEmpty) {
      setState(() => _status = 'Informe a funcao quando selecionar Outro.');
      return;
    }
    if (!_ativo) {
      if (_dataDemissao == null) {
        setState(
          () =>
              _status = 'Informe a data de demissao para funcionario inativo.',
        );
        return;
      }
      if (_motivoDemissao.isEmpty) {
        setState(() => _status = 'Informe o motivo da demissao.');
        return;
      }
      if (_motivoDemissao == 'outro' &&
          _motivoDemissaoOutroController.text.trim().isEmpty) {
        setState(() => _status = 'Descreva o motivo da demissao (Outro).');
        return;
      }
    }

    final dia = int.tryParse(_diaPagamentoController.text.trim()) ?? 5;
    if (dia < 1 || dia > 31) {
      setState(() => _status = 'Dia de pagamento deve ser entre 1 e 31.');
      return;
    }

    final existente = _funcionarioEmEdicaoId == null
        ? null
        : widget.funcionarioRepository.obterPorId(_funcionarioEmEdicaoId!);

    int vendedorId = 0;
    if (_tambemVendedorPdv) {
      try {
        vendedorId = await _sincronizarVendedorVinculo();
      } catch (e) {
        setState(
          () => _status = 'Nao foi possivel vincular vendedor no PDV: $e',
        );
        return;
      }
    }

    int motoristaId = 0;
    if (_tambemMotoristaEntrega) {
      try {
        motoristaId = await _sincronizarMotoristaVinculo();
        _motoristaVinculadoId = motoristaId;
      } catch (e) {
        setState(() => _status = 'Nao foi possivel vincular motorista: $e');
        return;
      }
    }

    var usuarioSistemaId = '';
    if (_temUsuarioSistema) {
      if (_usuarioVinculadoId.trim().isEmpty) {
        setState(
          () => _status =
              'Selecione um usuario existente ou crie um login rapido.',
        );
        return;
      }
      if (widget.funcionarioRepository.existeUsuarioParaOutro(
        usuarioId: _usuarioVinculadoId,
        ignorarId: idAtual,
      )) {
        setState(
          () => _status = 'Este login ja esta vinculado a outro funcionario.',
        );
        return;
      }
      try {
        usuarioSistemaId = await _sincronizarUsuarioVinculo(
          vendedorIdParaUsuario: vendedorId,
          vendedorIdAnteriorFuncionario: existente?.vendedorId ?? 0,
        );
      } catch (e) {
        setState(
          () => _status = 'Nao foi possivel vincular usuario do sistema: $e',
        );
        return;
      }
    } else {
      // Desmarcou login: se tambem nao e vendedor, limpa usuario.vendedorId
      // com seguranca (nao apaga o cadastro de vendedor).
      final uidAnterior = existente?.usuarioSistemaId.trim() ?? '';
      final vidAnterior = existente?.vendedorId ?? 0;
      if (!_tambemVendedorPdv && uidAnterior.isNotEmpty && vidAnterior > 0) {
        try {
          await _limparVendedorIdDoUsuarioSeSeguro(
            usuarioId: uidAnterior,
            vendedorIdEsperado: vidAnterior,
          );
        } catch (e) {
          setState(
            () => _status =
                'Nao foi possivel limpar vinculo usuario/vendedor: $e',
          );
          return;
        }
      }
    }

    if (motoristaId > 0 &&
        widget.funcionarioRepository.existeMotoristaParaOutro(
          motoristaId: motoristaId,
          ignorarId: idAtual,
        )) {
      setState(
        () => _status = 'Este motorista ja esta vinculado a outro funcionario.',
      );
      return;
    }

    final fotoPathExistente = existente?.fotoPath ?? '';
    var fotoPathFinal = fotoPathExistente;
    var avisoFotoTerminal = false;
    if (_terminalRh &&
        ((_fotoOrigemLocalPath != null &&
                _fotoOrigemLocalPath!.trim().isNotEmpty) ||
            _fotoFoiRemovida)) {
      avisoFotoTerminal = true;
    } else if (_fotoOrigemLocalPath != null &&
        _fotoOrigemLocalPath!.trim().isNotEmpty) {
      final processada = await _imagemService.processarESalvar(
        sourceImagePath: _fotoOrigemLocalPath!,
        funcionarioIdentifier: codigo,
      );
      if (processada == null) {
        setState(
          () => _status = 'Nao foi possivel processar a foto selecionada.',
        );
        return;
      }
      if (fotoPathExistente.trim().isNotEmpty &&
          fotoPathExistente != processada) {
        await _imagemService.removerSeOrfao(
          fotoPathExistente,
          contarReferencias: (path) =>
              widget.funcionarioRepository.contarFuncionariosComFotoPath(
                path,
                excluirFuncionarioId: existente?.id,
              ),
        );
      }
      fotoPathFinal = processada;
    } else if (_fotoFoiRemovida && fotoPathExistente.trim().isNotEmpty) {
      await _imagemService.removerSeOrfao(
        fotoPathExistente,
        contarReferencias: (path) =>
            widget.funcionarioRepository.contarFuncionariosComFotoPath(
              path,
              excluirFuncionarioId: existente?.id,
            ),
      );
      fotoPathFinal = '';
    }

    final funcionario = Funcionario(
      id: existente?.id ?? 0,
      codigoInterno: codigo,
      nomeCompleto: nome,
      cargo: _resumoSetorFuncaoAtual(),
      setor: _setorSelecionado,
      funcao: _funcaoSelecionada,
      funcaoOutro: funcaoOutro,
      cpf: cpf,
      rg: _rgController.text.trim(),
      pis: _pisController.text.trim(),
      telefone: somenteDigitos(_telefoneController.text),
      whatsapp: somenteDigitos(_whatsappController.text),
      email: _emailController.text.trim(),
      contatoEmergenciaNome: _contatoEmergenciaNomeController.text.trim(),
      contatoEmergenciaTelefone: somenteDigitos(
        _contatoEmergenciaTelefoneController.text,
      ),
      endereco: _enderecoController.text.trim(),
      numero: _numeroController.text.trim(),
      bairro: _bairroController.text.trim(),
      cidade: _cidadeController.text.trim(),
      uf: _ufController.text.trim().toUpperCase(),
      cep: somenteDigitos(_cepController.text),
      observacoes: _observacoesController.text.trim(),
      salario: _parseBr(_salarioController.text),
      descontoAtual: _parseBr(_descontoController.text),
      adiantamentoAtual: _totalVales(),
      historicoFinanceiro: '',
      valesJson: '[]',
      diaPagamento: dia,
      ativo: _ativo,
      motivoDemissao: _ativo ? '' : _motivoDemissao,
      motivoDemissaoOutro: _ativo || _motivoDemissao != 'outro'
          ? ''
          : _motivoDemissaoOutroController.text.trim(),
      dataNascimento: _dataNascimento,
      dataAdmissao: _dataAdmissao,
      dataDemissao: _ativo ? null : _dataDemissao,
      vendedorId: vendedorId,
      motoristaId: motoristaId,
      usuarioSistemaId: usuarioSistemaId,
      tipoVinculo: _tipoVinculo,
      cnhNumero: _cnhNumeroController.text.trim(),
      cnhCategoria: _cnhCategoria,
      cnhValidade: _cnhValidade,
      asoData: _asoData,
      asoValidade: _asoValidade,
      tamanhoUniforme: _tamanhoUniforme,
      epiObservacoes: _epiObservacoesController.text.trim(),
      podeOperarEmpilhadeira: _podeOperarEmpilhadeira,
      podeOperarTranspalete: _podeOperarTranspalete,
      fotoPath: fotoPathFinal,
      criadoEm: existente?.criadoEm,
    );
    try {
      var id = widget.funcionarioRepository is FuncionarioApiRepository
          ? await widget.funcionarioRepository.salvarRemoto(funcionario)
          : widget.funcionarioRepository.salvar(funcionario);

      final pendentes = _lancamentos.where((x) => x.id == 0).toList();
      if (widget.funcionarioRepository is FuncionarioApiRepository) {
        for (final l in pendentes) {
          await widget.funcionarioRepository.lancamentos.salvarRemoto(l, id);
        }
        _carregarLancamentos(id);
        if (!mounted) return;
        setState(() {
          _funcionarioEmEdicaoId = id;
          _codigoController.text = codigo;
          _vendedorVinculadoId = vendedorId;
          _motoristaVinculadoId = motoristaId;
          _usuarioVinculadoId = usuarioSistemaId;
          _fotoOrigemLocalPath = null;
          _fotoFoiRemovida = false;
          _status = avisoFotoTerminal
              ? 'Funcionario salvo. Foto nao sincroniza no terminal leve '
                  '(use o PC servidor para alterar a foto).'
              : 'Funcionario salvo com sucesso.';
        });
        unawaited(_carregarUsuariosCache());
        return;
      }
      for (final l in pendentes) {
        widget.funcionarioRepository.lancamentos.salvar(l, id);
      }
      final atualizado = widget.funcionarioRepository.obterPorId(id);
      if (atualizado != null) {
        atualizado.adiantamentoAtual = widget.funcionarioRepository.lancamentos
            .totalValesAtivos(id);
        atualizado.valesJson = '[]';
        atualizado.historicoFinanceiro = '';
        id = widget.funcionarioRepository.salvar(atualizado);
      }
      _carregarLancamentos(id);
      if (!mounted) return;
      setState(() {
        _funcionarioEmEdicaoId = id;
        _codigoController.text = codigo;
        _vendedorVinculadoId = vendedorId;
        _motoristaVinculadoId = motoristaId;
        _usuarioVinculadoId = usuarioSistemaId;
        _fotoPathAtual = fotoPathFinal;
        _fotoOrigemLocalPath = null;
        _fotoFoiRemovida = false;
        _status = 'Funcionario salvo com sucesso.';
      });
      unawaited(_carregarUsuariosCache());
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel salvar');
      setState(() => _status = LanApiFeedback.mensagem(e));
    }
  }

  String? _fotoPreviewPath() {
    final origem = _fotoOrigemLocalPath?.trim();
    if (origem != null && origem.isNotEmpty) return origem;
    return _imagemService.resolverArquivoExistente(_fotoPathAtual);
  }

  Future<void> _aplicarFotoOrigem(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    if (_terminalRh) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Foto no terminal leve: o cadastro salva, mas a imagem so '
            'grava no PC servidor. Use o servidor para alterar a foto.',
          ),
        ),
      );
    }
    setState(() {
      _fotoOrigemLocalPath = path;
      _fotoFoiRemovida = false;
      _status = _terminalRh
          ? 'Foto selecionada (nao sera sincronizada neste terminal).'
          : 'Foto selecionada. Salve para gravar no cadastro.';
    });
  }

  Future<void> _tirarFotoFuncionario() async {
    final path = await _imagemService.capturarFotoCamera();
    await _aplicarFotoOrigem(path);
  }

  Future<void> _escolherFotoFuncionario() async {
    final path = FuncionarioImagemService.cameraDisponivel
        ? await _imagemService.selecionarDaGaleria()
        : await _imagemService.selecionarArquivoLocal();
    await _aplicarFotoOrigem(path);
  }

  void _removerFotoFuncionario() {
    setState(() {
      _fotoOrigemLocalPath = null;
      if (_fotoPathAtual.trim().isNotEmpty) {
        _fotoFoiRemovida = true;
      }
      _fotoPathAtual = '';
      _status = 'Foto removida. Salve para confirmar.';
    });
  }

  void _editar(Funcionario f) {
    setState(() {
      _funcionarioEmEdicaoId = f.id;
      _codigoController.text = f.codigoInterno;
      _nomeController.text = f.nomeCompleto;
      _carregarRhFromFuncionario(f);
      _cpfController.text = f.cpf;
      aplicarMascaraCpf(_cpfController, _cpfFormatter);
      _rgController.text = f.rg;
      _pisController.text = f.pis;
      _telefoneController.text = f.telefone;
      aplicarMascaraTelefone(_telefoneController, _telefoneFormatter);
      _whatsappController.text = f.whatsapp;
      aplicarMascaraTelefone(_whatsappController, _telefoneFormatter);
      _emailController.text = f.email;
      _cepController.text = f.cep;
      aplicarMascaraCep(_cepController, _cepFormatter);
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
      _diaPagamentoController.text = f.diaPagamento.toString();
      _carregarVendedorFromFuncionario(f);
      _carregarMotoristaFromFuncionario(f);
      _carregarUsuarioFromFuncionario(f);
      widget.funcionarioRepository.lancamentos.migrarLegadoSeNecessario(f);
      _mesFiltroLancamentos = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      );
      _carregarLancamentos(f.id);
      _observacoesController.text = f.observacoes;
      _tipoVinculo =
          FuncionarioCadastroCatalogo.idsTiposVinculo.contains(f.tipoVinculo)
          ? f.tipoVinculo
          : 'clt';
      _cnhNumeroController.text = f.cnhNumero;
      _cnhCategoria =
          FuncionarioCadastroCatalogo.idsCategoriasCnh.contains(f.cnhCategoria)
          ? f.cnhCategoria
          : '';
      _cnhValidade = f.cnhValidade?.toLocal();
      _asoData = f.asoData?.toLocal();
      _asoValidade = f.asoValidade?.toLocal();
      _tamanhoUniforme =
          FuncionarioCadastroCatalogo.idsTamanhosUniforme.contains(
            f.tamanhoUniforme,
          )
          ? f.tamanhoUniforme
          : '';
      _epiObservacoesController.text = f.epiObservacoes;
      _podeOperarEmpilhadeira = f.podeOperarEmpilhadeira;
      _podeOperarTranspalete = f.podeOperarTranspalete;
      _fotoPathAtual = f.fotoPath;
      _fotoOrigemLocalPath = null;
      _fotoFoiRemovida = false;
      _dataNascimento = f.dataNascimento.toLocal();
      _dataAdmissao = f.dataAdmissao.toLocal();
      _ativo = f.ativo;
      _status = 'Editando: ${f.nomeCompleto}';
    });
  }

  dynamic get _lancRepo => widget.funcionarioRepository.lancamentos;

  void _carregarLancamentos(int funcionarioId) {
    if (funcionarioId <= 0) {
      _lancamentos = _lancamentos.where((l) => l.id == 0).toList();
      return;
    }
    final doBanco = _lancRepo.listarPorFuncionario(
      funcionarioId,
      mesReferencia: _mesFiltroLancamentos,
    );
    final pendentes = _lancamentos.where((l) => l.id == 0).toList();
    _lancamentos = [...pendentes, ...doBanco];
  }

  Iterable<LancamentoFuncionario> get _lancamentosAtivos =>
      _lancamentos.where((l) => !l.estornado);

  double _totalVales() => _lancamentosAtivos
      .where((l) => l.tipo == LancamentoFuncionarioCatalogo.vale)
      .fold<double>(0, (acc, l) => acc + l.valor);

  double _totalDescontosLancados() => _lancamentosAtivos
      .where((l) => l.tipo == LancamentoFuncionarioCatalogo.desconto)
      .fold<double>(0, (acc, l) => acc + l.valor);

  double _totalBonus() => _lancamentosAtivos
      .where((l) => l.tipo == LancamentoFuncionarioCatalogo.bonus)
      .fold<double>(0, (acc, l) => acc + l.valor);

  double _salarioValor() => _parseBr(_salarioController.text);

  double _descontoValor() => _parseBr(_descontoController.text);

  double _liquidoReferencia() =>
      _salarioValor() -
      _descontoValor() -
      _totalVales() -
      _totalDescontosLancados() +
      _totalBonus();

  bool _mesEstaFechado() {
    final fid = _funcionarioEmEdicaoId;
    if (fid == null || fid <= 0) return false;
    return _folhaService?.mesEstaFechado(fid, _mesFiltroLancamentos) ?? false;
  }

  FuncionarioMesResumo? _resumoMesAtual() {
    final fid = _funcionarioEmEdicaoId;
    if (fid == null || fid <= 0) return null;
    final folha = _folhaService;
    if (folha != null) {
      final f = widget.funcionarioRepository.obterPorId(fid);
      if (f == null) return null;
      return folha.calcularMes(
        funcionario: f,
        mesReferencia: _mesFiltroLancamentos,
        salarioBaseOverride: _salarioValor(),
        descontoFixoOverride: _descontoValor(),
      );
    }
    // Terminal leve: resumo local (sem fechamento / Contas a Pagar).
    final vales = _totalVales();
    final descontos = _totalDescontosLancados();
    final bonus = _totalBonus();
    final salario = _salarioValor();
    final descontoFixo = _descontoValor();
    return FuncionarioMesResumo(
      funcionarioId: fid,
      mesReferencia: _mesFiltroLancamentos,
      salarioBase: salario,
      descontoFixo: descontoFixo,
      totalVales: vales,
      totalDescontosLancados: descontos,
      totalBonus: bonus,
      qtdVales: _lancamentosAtivos
          .where((l) => l.tipo == LancamentoFuncionarioCatalogo.vale)
          .length,
      liquidoApagar: salario - descontoFixo - vales - descontos + bonus,
      fechado: false,
    );
  }

  List<FuncionarioFolhaAlerta> _alertasEquipeMes() =>
      _folhaService?.alertasEquipe(_mesFiltroLancamentos) ?? const [];

  List<FolhaMesHistoricoItem> _historico12Meses() {
    final folha = _folhaService;
    if (folha == null) return const [];
    final fid = _funcionarioEmEdicaoId;
    if (fid == null || fid <= 0) return const [];
    final f = widget.funcionarioRepository.obterPorId(fid);
    if (f == null) return const [];
    return folha.historicoUltimosMeses(
      funcionario: f,
      salarioBaseOverride: _salarioValor(),
      descontoFixoOverride: _descontoValor(),
    );
  }

  Future<void> _salvarArquivoCsv({
    required String tituloDialogo,
    required String nomeArquivo,
    required String conteudo,
  }) async {
    final bytes = Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(conteudo),
    ]);
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: tituloDialogo,
      fileName: nomeArquivo,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: bytes,
    );
    if (selectedPath == null || !mounted) return;
    final path = selectedPath.toLowerCase().endsWith('.csv')
        ? selectedPath
        : '$selectedPath.csv';
    await File(path).writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Arquivo salvo em: $path')));
  }

  Future<void> _fecharMesRh() async {
    if (_folhaService == null) {
      _avisoFolhaSoServidor();
      return;
    }
    final fid = _funcionarioEmEdicaoId;
    if (fid == null || fid <= 0) {
      setState(() => _status = 'Salve o funcionario antes de fechar o mes.');
      return;
    }
    if (_mesEstaFechado()) {
      setState(() => _status = 'Mes ja esta fechado.');
      return;
    }
    final f = widget.funcionarioRepository.obterPorId(fid);
    if (f == null) return;
    final resumo = _resumoMesAtual();
    if (resumo == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fechar mes RH'),
        content: Text(
          'Fechar ${_mesAnoFormat.format(_mesFiltroLancamentos)} para '
          '${f.nomeCompleto}?\n\n'
          'Liquido estimado: ${_formatMoeda(resumo.liquidoApagar)}\n'
          'Vales: ${_formatMoeda(resumo.totalVales)}\n\n'
          'Sera gerado titulo em Contas a Pagar (se liquido > 0) e '
          'lancamentos do mes ficarao bloqueados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Fechar mes'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final fechamento = await _folhaService!.fecharMes(
        funcionario: f,
        mesReferencia: _mesFiltroLancamentos,
        usuarioLogin: widget.usuarioLogado?.login ?? 'sistema',
        salarioBaseOverride: _salarioValor(),
        descontoFixoOverride: _descontoValor(),
      );
      setState(() {
        _status = fechamento.contaPagarId > 0
            ? 'Mes fechado. Titulo AP #${fechamento.contaPagarId} gerado.'
            : 'Mes fechado (sem titulo AP — liquido zero ou negativo).';
      });
    } catch (e) {
      setState(() => _status = 'Falha ao fechar mes: $e');
    }
  }

  Future<void> _reabrirMesRh() async {
    if (_folhaService == null) {
      _avisoFolhaSoServidor();
      return;
    }
    final fid = _funcionarioEmEdicaoId;
    if (fid == null || fid <= 0) return;
    if (!_mesEstaFechado()) {
      setState(() => _status = 'Mes nao esta fechado.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reabrir mes RH'),
        content: const Text(
          'Reabrir o mes permite novos lancamentos. '
          'Se existir titulo pendente em Contas a Pagar, ele sera removido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _folhaService!.reabrirMes(
        funcionarioId: fid,
        mesReferencia: _mesFiltroLancamentos,
      );
      setState(() => _status = 'Mes reaberto para lancamentos.');
    } catch (e) {
      setState(() => _status = 'Falha ao reabrir mes: $e');
    }
  }

  Future<void> _exportarFolhaEquipeCsv() async {
    final folha = _folhaService;
    if (folha == null) {
      _avisoFolhaSoServidor();
      return;
    }
    final mes = _mesFiltroLancamentos;
    final funcionarios = widget.funcionarioRepository.listarTodos();
    final resumos = folha.resumoEquipeMes(mes);
    final fechamentos = widget.funcionarioRepository.fechamentos.listarPorMes(
      mes,
    );
    final csv = gerarCsvFolhaEquipeMes(
      mesReferencia: mes,
      funcionarios: funcionarios,
      resumos: resumos,
      fechamentos: fechamentos,
    );
    final slug = DateFormat('yyyyMM').format(mes);
    await _salvarArquivoCsv(
      tituloDialogo: 'Exportar folha da equipe',
      nomeArquivo: 'folha_equipe_$slug.csv',
      conteudo: csv,
    );
  }

  Future<void> _exportarLancamentosAnoCsv() async {
    final fid = _funcionarioEmEdicaoId;
    if (fid == null || fid <= 0) {
      setState(() => _status = 'Selecione um funcionario salvo para exportar.');
      return;
    }
    final f = widget.funcionarioRepository.obterPorId(fid);
    if (f == null) return;
    final ano = _mesFiltroLancamentos.year;
    final lancamentos = _lancRepo.listarPorFuncionarioAno(fid, ano);
    final csv = gerarCsvLancamentosAno(
      funcionario: f,
      ano: ano,
      lancamentos: lancamentos,
    );
    await _salvarArquivoCsv(
      tituloDialogo: 'Exportar lancamentos do ano',
      nomeArquivo: 'lancamentos_${f.codigoInterno}_$ano.csv',
      conteudo: csv,
    );
  }

  Future<void> _mostrarRelatorioFolhaSetor() async {
    final folha = _folhaService;
    if (folha == null) {
      _avisoFolhaSoServidor();
      return;
    }
    final mes = _mesFiltroLancamentos;
    final linhas = folha.relatorioPorSetor(mes);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Folha por setor — ${_mesAnoFormat.format(mes)}'),
          content: SizedBox(
            width: 560,
            child: linhas.isEmpty
                ? const Text('Nenhum funcionario cadastrado.')
                : SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Setor')),
                        DataColumn(label: Text('Ativos')),
                        DataColumn(label: Text('Folha')),
                        DataColumn(label: Text('Vales')),
                        DataColumn(label: Text('Liquido')),
                      ],
                      rows: linhas
                          .map(
                            (l) => DataRow(
                              cells: [
                                DataCell(Text(l.setorRotulo)),
                                DataCell(Text('${l.qtdAtivos}')),
                                DataCell(Text(_formatMoeda(l.folhaBase))),
                                DataCell(Text(_formatMoeda(l.totalVales))),
                                DataCell(Text(_formatMoeda(l.liquidoEstimado))),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final csv = gerarCsvRelatorioSetor(
                  mesReferencia: mes,
                  linhas: linhas,
                );
                await _salvarArquivoCsv(
                  tituloDialogo: 'Exportar folha por setor',
                  nomeArquivo:
                      'folha_setor_${DateFormat('yyyyMM').format(mes)}.csv',
                  conteudo: csv,
                );
              },
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('CSV'),
            ),
          ],
        );
      },
    );
  }

  int _diaPagamentoAtual() {
    final d = int.tryParse(_diaPagamentoController.text.trim()) ?? 5;
    return d.clamp(1, 31);
  }

  DateTime _dataProximoPagamento() {
    final dia = _diaPagamentoAtual();
    final hoje = DateTime.now();
    final ultimoMesAtual = DateTime(hoje.year, hoje.month + 1, 0).day;
    final diaMesAtual = dia > ultimoMesAtual ? ultimoMesAtual : dia;
    var candidata = DateTime(hoje.year, hoje.month, diaMesAtual);
    final hojeData = DateTime(hoje.year, hoje.month, hoje.day);
    if (!candidata.isBefore(hojeData)) return candidata;

    final proximoMes = DateTime(hoje.year, hoje.month + 1, 1);
    final ultimoProximo = DateTime(
      proximoMes.year,
      proximoMes.month + 1,
      0,
    ).day;
    final diaProximo = dia > ultimoProximo ? ultimoProximo : dia;
    return DateTime(proximoMes.year, proximoMes.month, diaProximo);
  }

  String _formatMoeda(double v) => _moeda.format(v);

  void _carregarVendedorFromFuncionario(Funcionario f) {
    _vendedorVinculadoId = f.vendedorId;
    _tambemVendedorPdv = f.vendedorId > 0;
    _vendedorApelidoController.clear();
    _vendedorComissaoController.clear();
    _vendedorMetaController.clear();
    if (f.vendedorId <= 0) return;
    final v = widget.vendedorRepository.obterPorId(f.vendedorId);
    if (v == null) return;
    _vendedorApelidoController.text = v.apelido;
    if (v.percentualComissao > 0) {
      _vendedorComissaoController.text = v.percentualComissao
          .toStringAsFixed(2)
          .replaceAll('.', ',');
    }
    if (v.metaMensalValor > 0) {
      _vendedorMetaController.text = v.metaMensalValor
          .toStringAsFixed(2)
          .replaceAll('.', ',');
    }
  }

  Vendedor? _localizarVendedorPorCodigoFuncionario() {
    final cod = _codigoController.text.trim().toLowerCase();
    if (cod.isEmpty) return null;
    for (final v in widget.vendedorRepository.listarTodos()) {
      final c = v.codigoInterno.trim().toLowerCase();
      if (c == cod || c == 'v$cod') return v;
    }
    return null;
  }

  Future<int> _sincronizarVendedorVinculo() async {
    final nome = _nomeController.text.trim();
    if (nome.isEmpty) {
      throw StateError('Informe o nome antes de vincular ao PDV.');
    }

    Vendedor? v;
    if (_vendedorVinculadoId > 0) {
      v = widget.vendedorRepository.obterPorId(_vendedorVinculadoId);
    }
    v ??= _localizarVendedorPorCodigoFuncionario();

    final codigoFunc = _codigoController.text.trim();
    final codigoVendedor = codigoFunc.isEmpty
        ? widget.vendedorRepository.proximoCodigoInternoSequencial().toString()
        : (codigoFunc.toUpperCase().startsWith('V')
              ? codigoFunc
              : 'V$codigoFunc');

    v ??= Vendedor(
      codigoInterno: codigoVendedor,
      nomeCompleto: nome,
      ativo: _ativo,
    );

    v.codigoInterno = codigoVendedor;
    v.nomeCompleto = nome;
    v.apelido = _vendedorApelidoController.text.trim();
    v.telefone = somenteDigitos(_telefoneController.text);
    v.whatsapp = somenteDigitos(_whatsappController.text);
    v.email = _emailController.text.trim();
    v.percentualComissao = _parseBr(_vendedorComissaoController.text);
    v.metaMensalValor = _parseBr(_vendedorMetaController.text);
    v.ativo = _ativo;
    if (widget.vendedorRepository is VendedorApiRepository) {
      return await widget.vendedorRepository.salvarRemoto(v);
    }
    return widget.vendedorRepository.salvar(v);
  }

  Motorista? _localizarMotoristaPorNomeFuncionario() {
    final nome = _nomeController.text.trim().toLowerCase();
    if (nome.isEmpty) return null;
    for (final m in widget.motoristaRepository.listarTodos()) {
      if (m.nome.trim().toLowerCase() == nome) return m;
    }
    return null;
  }

  Future<int> _sincronizarMotoristaVinculo() async {
    final nome = _nomeController.text.trim();
    if (nome.isEmpty) {
      throw StateError('Informe o nome antes de vincular motorista.');
    }

    Motorista? m;
    if (_motoristaVinculadoId > 0) {
      m = widget.motoristaRepository.obterPorId(_motoristaVinculadoId);
    }
    m ??= _localizarMotoristaPorNomeFuncionario();

    final tel = somenteDigitos(_whatsappController.text).isNotEmpty
        ? somenteDigitos(_whatsappController.text)
        : somenteDigitos(_telefoneController.text);

    m ??= Motorista(nome: nome, telefone: tel, ativo: _ativo);

    if (widget.motoristaRepository.existeNomeParaOutro(
      nomeNormalizado: nome,
      ignorarId: m.id,
    )) {
      throw StateError('Ja existe outro motorista com este nome.');
    }

    m.nome = nome;
    m.telefone = tel;
    m.ativo = _ativo;
    final repo = widget.motoristaRepository;
    if (repo is MotoristaApiRepository) {
      return await repo.salvarRemoto(m);
    }
    return repo.salvar(m) as int;
  }

  void _carregarMotoristaFromFuncionario(Funcionario f) {
    _motoristaVinculadoId = f.motoristaId;
    _tambemMotoristaEntrega = f.motoristaId > 0;
  }

  Future<void> _limparVendedorIdDoUsuarioSeSeguro({
    required String usuarioId,
    required int vendedorIdEsperado,
  }) async {
    if (usuarioId.trim().isEmpty || vendedorIdEsperado <= 0) return;
    final anterior = await widget.usuarioRepository.obterPorId(usuarioId);
    if (anterior == null) return;
    if (anterior.vendedorId != vendedorIdEsperado) return;
    await widget.usuarioRepository.salvar(
      anterior.copyWith(vendedorId: 0),
      alteradoPor: widget.usuarioLogado,
      anterior: anterior,
      resumoExtra: 'Vinculo vendedor removido via funcionarios',
    );
  }

  Future<String> _sincronizarUsuarioVinculo({
    required int vendedorIdParaUsuario,
    required int vendedorIdAnteriorFuncionario,
  }) async {
    final id = _usuarioVinculadoId.trim();
    if (id.isEmpty) return '';

    final anterior = await widget.usuarioRepository.obterPorId(id);
    if (anterior == null) {
      throw StateError('Usuario vinculado nao encontrado.');
    }

    var atualizado = anterior.copyWith(
      nome: _nomeController.text.trim().isEmpty
          ? anterior.nome
          : _nomeController.text.trim(),
      ativo: _ativo,
    );

    // Fecha o triangulo RH ↔ login ↔ PDV: grava usuario.vendedorId.
    if (_tambemVendedorPdv && vendedorIdParaUsuario > 0) {
      atualizado = atualizado.copyWith(vendedorId: vendedorIdParaUsuario);
    } else if (!_tambemVendedorPdv) {
      final vidLimpar = vendedorIdAnteriorFuncionario > 0
          ? vendedorIdAnteriorFuncionario
          : _vendedorVinculadoId;
      if (vidLimpar > 0 && anterior.vendedorId == vidLimpar) {
        atualizado = atualizado.copyWith(vendedorId: 0);
      }
    }

    if (_tambemMotoristaEntrega) {
      final mot = _motoristaVinculadoId > 0
          ? widget.motoristaRepository.obterPorId(_motoristaVinculadoId)
          : null;
      if (mot != null) {
        atualizado = atualizado.copyWith(
          podeModoMotorista: true,
          motoristaEntregaNome: mot.nome,
        );
      }
    }

    await widget.usuarioRepository.salvar(
      atualizado,
      alteradoPor: widget.usuarioLogado,
      anterior: anterior,
      resumoExtra: 'Vinculo via cadastro de funcionarios',
    );
    return id;
  }

  void _carregarUsuarioFromFuncionario(Funcionario f) {
    _usuarioVinculadoId = f.usuarioSistemaId;
    _temUsuarioSistema = f.usuarioSistemaId.trim().isNotEmpty;
  }

  UsuarioSistema? _usuarioVinculadoAtual() {
    final id = _usuarioVinculadoId.trim();
    if (id.isEmpty) return null;
    for (final u in _usuariosCache) {
      if (u.id == id) return u;
    }
    return null;
  }

  Future<void> _criarLoginRapido() async {
    final nome = _nomeController.text.trim();
    if (nome.isEmpty) {
      setState(() => _status = 'Informe o nome antes de criar o login.');
      return;
    }

    final loginController = TextEditingController(
      text: _sugerirLoginFromNome(),
    );
    final senhaController = TextEditingController();
    var perfil = _perfilSugeridoUsuario();

    final criado = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Criar login rapido'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: loginController,
                      decoration: const InputDecoration(
                        labelText: 'Login',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: senhaController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Senha inicial',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<PerfilUsuarioPreset>(
                      initialValue: perfil,
                      decoration: const InputDecoration(
                        labelText: 'Perfil sugerido',
                        isDense: true,
                      ),
                      items: PerfilUsuarioPreset.values
                          .where((p) => p != PerfilUsuarioPreset.dono)
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.rotulo),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => perfil = v);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Criar'),
                ),
              ],
            );
          },
        );
      },
    );

    final login = loginController.text.trim();
    final senha = senhaController.text;
    loginController.dispose();
    senhaController.dispose();
    if (criado != true || !mounted) return;

    if (login.isEmpty || senha.isEmpty) {
      setState(() => _status = 'Informe login e senha para criar usuario.');
      return;
    }
    if (await widget.usuarioRepository.loginJaExiste(login)) {
      setState(() => _status = 'Ja existe usuario com este login.');
      return;
    }

    var vendedorId = 0;
    if (_tambemVendedorPdv) {
      try {
        vendedorId = await _sincronizarVendedorVinculo();
      } catch (e) {
        setState(
          () => _status = 'Nao foi possivel vincular vendedor no PDV: $e',
        );
        return;
      }
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    var base = UsuarioSistema(
      id: id,
      nome: nome,
      login: login,
      senha: '',
      ativo: _ativo,
      perfil: perfil.id,
      vendedorId: vendedorId > 0 ? vendedorId : 0,
    );
    var usuario = PerfilUsuarioPresetAplicador.aplicar(base, perfil);
    if (vendedorId > 0) {
      usuario = usuario.copyWith(vendedorId: vendedorId);
    }
    if (_tambemMotoristaEntrega && _motoristaVinculadoId > 0) {
      final mot = widget.motoristaRepository.obterPorId(_motoristaVinculadoId);
      if (mot != null) {
        usuario = usuario.copyWith(
          podeModoMotorista: true,
          motoristaEntregaNome: mot.nome,
        );
      }
    }

    try {
      await widget.usuarioRepository.salvar(
        usuario,
        alteradoPor: widget.usuarioLogado,
        senhaPlainNova: senha,
        resumoExtra: 'Criado a partir do cadastro de funcionarios',
      );
    } catch (e) {
      setState(() => _status = 'Falha ao criar login: $e');
      return;
    }

    await _carregarUsuariosCache();
    if (!mounted) return;
    setState(() {
      _temUsuarioSistema = true;
      _usuarioVinculadoId = id;
      _vendedorVinculadoId = vendedorId;
      _tambemVendedorPdv = _tambemVendedorPdv || vendedorId > 0;
      _status = vendedorId > 0
          ? 'Login criado e vinculado ao funcionario e ao vendedor do PDV.'
          : 'Login criado e vinculado ao funcionario.';
    });
  }

  Widget _buildLinhaKpiFinanceiro({
    required String rotulo,
    required String valor,
    TextStyle? estiloValor,
    bool destaque = false,
  }) {
    final estilo =
        estiloValor ??
        (destaque
            ? const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)
            : const TextStyle(fontWeight: FontWeight.w600));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(rotulo)),
          Text(valor, style: estilo),
        ],
      ),
    );
  }

  Widget _buildPainelKpiFinanceiro(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nVales = _lancamentosAtivos
        .where((l) => l.tipo == LancamentoFuncionarioCatalogo.vale)
        .length;
    final liquido = _liquidoReferencia();
    final liquidoNegativo = liquido < 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Resumo do mes (estimativa)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          _buildLinhaKpiFinanceiro(
            rotulo: 'Salario base',
            valor: _formatMoeda(_salarioValor()),
          ),
          _buildLinhaKpiFinanceiro(
            rotulo: '(−) Descontos',
            valor: _formatMoeda(_descontoValor()),
          ),
          _buildLinhaKpiFinanceiro(
            rotulo: '(−) Vales',
            valor:
                '${_formatMoeda(_totalVales())}  [$nVales ${nVales == 1 ? 'vale' : 'vales'}]',
          ),
          if (_totalDescontosLancados() > 0)
            _buildLinhaKpiFinanceiro(
              rotulo: '(−) Descontos lancados',
              valor: _formatMoeda(_totalDescontosLancados()),
            ),
          if (_totalBonus() > 0)
            _buildLinhaKpiFinanceiro(
              rotulo: '(+) Bonus',
              valor: _formatMoeda(_totalBonus()),
            ),
          const Divider(height: 14),
          _buildLinhaKpiFinanceiro(
            rotulo: '(=) Liquido referencia',
            valor: _formatMoeda(liquido),
            destaque: true,
            estiloValor: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: liquidoNegativo ? scheme.error : scheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Periodo dos lancamentos: ${_mesAnoFormat.format(_mesFiltroLancamentos)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Proximo pagamento: ${_dateFormat.format(_dataProximoPagamento())} '
            '(dia ${_diaPagamentoAtual()})',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoVendedorPdv(BuildContext context) {
    final theme = Theme.of(context);
    final vendasVinculadas = _vendedorVinculadoId > 0
        ? widget.vendaRepository.contarVendasFinalizadasPorVendedor(
            _vendedorVinculadoId,
          )
        : 0;

    return _buildSectionCard(
      context: context,
      title: 'Vendas no PDV',
      icon: Icons.point_of_sale_outlined,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Tambem e vendedor no sistema (PDV / orcamentos)'),
          subtitle: const Text(
            'Quem aparece nas vendas e comissoes. Nao cria senha — '
            'o desbloqueio do PDV usa login do sistema ou PIN do vendedor.',
          ),
          value: _tambemVendedorPdv,
          onChanged: (v) => setState(() {
            _tambemVendedorPdv = v;
            if (!v) return;
            if (_vendedorVinculadoId <= 0) {
              final existente = _localizarVendedorPorCodigoFuncionario();
              if (existente != null) {
                _vendedorVinculadoId = existente.id;
                _vendedorApelidoController.text = existente.apelido;
                if (existente.percentualComissao > 0) {
                  _vendedorComissaoController.text = existente
                      .percentualComissao
                      .toStringAsFixed(2)
                      .replaceAll('.', ',');
                }
                if (existente.metaMensalValor > 0) {
                  _vendedorMetaController.text = existente.metaMensalValor
                      .toStringAsFixed(2)
                      .replaceAll('.', ',');
                }
              }
            }
          }),
        ),
        if (_tambemVendedorPdv) ...[
          if (_vendedorVinculadoId > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Vendedor #$_vendedorVinculadoId'
                '${vendasVinculadas > 0 ? ' · $vendasVinculadas venda(s) no PDV' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final empilhar = constraints.maxWidth < 520;
              final apelido = TextField(
                controller: _vendedorApelidoController,
                decoration: const InputDecoration(
                  labelText: 'Apelido no cupom (opcional)',
                  isDense: true,
                ),
              );
              final comissao = SizedBox(
                width: _wPct,
                child: TextField(
                  controller: _vendedorComissaoController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Comissao %',
                    isDense: true,
                  ),
                ),
              );
              final meta = SizedBox(
                width: _wMoeda,
                child: TextField(
                  controller: _vendedorMetaController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Meta mensal (R\$)',
                    isDense: true,
                  ),
                ),
              );
              if (empilhar) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    apelido,
                    const SizedBox(height: 6),
                    comissao,
                    const SizedBox(height: 6),
                    meta,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  apelido,
                  const SizedBox(height: 6),
                  Row(children: [comissao, const SizedBox(width: 10), meta]),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSecaoMotoristaEntregas(BuildContext context) {
    final theme = Theme.of(context);
    return _buildSectionCard(
      context: context,
      title: 'Motorista de entregas',
      icon: Icons.local_shipping_outlined,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Cadastrado como motorista (romaneio / entregas)'),
          subtitle: const Text(
            'Cria ou atualiza o cadastro de motoristas usado na expedicao.',
          ),
          value: _tambemMotoristaEntrega,
          onChanged: (v) => setState(() {
            _tambemMotoristaEntrega = v;
            if (!v) return;
            if (_motoristaVinculadoId <= 0) {
              final existente = _localizarMotoristaPorNomeFuncionario();
              if (existente != null) {
                _motoristaVinculadoId = existente.id;
              }
            }
          }),
        ),
        if (_tambemMotoristaEntrega) ...[
          if (_motoristaVinculadoId > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Motorista #$_motoristaVinculadoId'
                '${_cnhVencida ? ' · CNH vencida' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _cnhVencida
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_cnhNumeroController.text.trim().isEmpty)
            Text(
              'Preencha CNH na aba Documentos para motoristas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildSecaoUsuarioSistema(BuildContext context) {
    final theme = Theme.of(context);
    final vinculado = _usuarioVinculadoAtual();
    final usuariosAtivos = _usuariosCache.where((u) => u.ativo).toList();

    return _buildSectionCard(
      context: context,
      title: 'Login no ERP',
      icon: Icons.manage_accounts_outlined,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Possui usuario no sistema'),
          subtitle: const Text(
            'Login e permissoes (PDV, caixa, etc.). A senha de acesso fica so aqui — '
            'funcionario nao tem senha propria.',
          ),
          value: _temUsuarioSistema,
          onChanged: (v) => setState(() {
            _temUsuarioSistema = v;
            if (!v) _usuarioVinculadoId = '';
          }),
        ),
        if (_temUsuarioSistema) ...[
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _usuarioVinculadoId.isEmpty
                      ? null
                      : _usuarioVinculadoId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Usuario vinculado',
                    isDense: true,
                  ),
                  items: usuariosAtivos
                      .map(
                        (u) => DropdownMenuItem(
                          value: u.id,
                          child: Text('${u.nome} (${u.login})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _usuarioVinculadoId = v ?? ''),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: _estiloBotaoContornoCompacto,
                onPressed: () => unawaited(_criarLoginRapido()),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Criar login'),
              ),
            ],
          ),
          if (vinculado != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(perfilUsuarioFromId(vinculado.perfil).rotulo),
                ),
                if (vinculado.podeModoMotorista)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Modo motorista'),
                  ),
                if (vinculado.podeAcessarPdv)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('PDV'),
                  ),
                if (vinculado.podeAcessarCaixa)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Caixa'),
                  ),
              ],
            ),
          ] else if (_usuarioVinculadoId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Usuario nao encontrado na lista. Recarregue ou selecione outro.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildCampoCategoriaCnh() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue:
          FuncionarioCadastroCatalogo.idsCategoriasCnh.contains(_cnhCategoria)
          ? _cnhCategoria
          : '',
      decoration: const InputDecoration(labelText: 'Categoria', isDense: true),
      items: FuncionarioCadastroCatalogo.categoriasCnh.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      selectedItemBuilder: (context) {
        return FuncionarioCadastroCatalogo.categoriasCnh.entries
            .map(
              (e) => Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  e.key.isEmpty ? 'N/A' : e.key,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList();
      },
      onChanged: (v) => setState(() => _cnhCategoria = v ?? ''),
    );
  }

  Widget _buildSecaoCnh(BuildContext context) {
    final theme = Theme.of(context);
    return _buildSectionCard(
      context: context,
      title: 'CNH (motoristas / entregas)',
      icon: Icons.directions_car_outlined,
      children: [
        if (_cnhVencida)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'CNH vencida em ${_dateFormat.format(_cnhValidade!)}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final empilhar = constraints.maxWidth < 560;
            final numero = TextField(
              controller: _cnhNumeroController,
              decoration: const InputDecoration(
                labelText: 'Numero CNH',
                isDense: true,
              ),
            );
            final categoria = _buildCampoCategoriaCnh();
            final validade = OutlinedButton.icon(
              style: _estiloBotaoContornoCompacto,
              onPressed: () => unawaited(_selecionarCnhValidade()),
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(
                _cnhValidade == null
                    ? 'Validade CNH'
                    : 'Val.: ${_dateFormat.format(_cnhValidade!)}',
                overflow: TextOverflow.ellipsis,
              ),
            );
            final limparValidade = _cnhValidade == null
                ? null
                : TextButton(
                    onPressed: () => setState(() => _cnhValidade = null),
                    child: const Text('Limpar validade'),
                  );

            if (empilhar) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  numero,
                  const SizedBox(height: 8),
                  categoria,
                  const SizedBox(height: 8),
                  validade,
                  ?limparValidade,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: _wCnh, child: numero),
                    const SizedBox(width: 10),
                    Expanded(child: categoria),
                    const SizedBox(width: 10),
                    SizedBox(width: _wData, child: validade),
                  ],
                ),
                if (limparValidade != null)
                  Align(alignment: Alignment.centerLeft, child: limparValidade),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSecaoSst(BuildContext context) {
    final theme = Theme.of(context);
    return _buildSectionCard(
      context: context,
      title: 'SST — saude e seguranca',
      icon: Icons.health_and_safety_outlined,
      children: [
        if (_asoVencido)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'ASO vencido em ${_dateFormat.format(_asoValidade!)}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: _wData,
              child: OutlinedButton.icon(
                style: _estiloBotaoContornoCompacto,
                onPressed: () => unawaited(_selecionarAsoData()),
                icon: const Icon(Icons.medical_services_outlined, size: 18),
                label: Text(
                  _asoData == null
                      ? 'Exame / ASO'
                      : 'ASO: ${_dateFormat.format(_asoData!)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: _wData,
              child: OutlinedButton.icon(
                style: _estiloBotaoContornoCompacto,
                onPressed: () => unawaited(_selecionarAsoValidade()),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(
                  _asoValidade == null
                      ? 'Validade ASO'
                      : 'Val.: ${_dateFormat.format(_asoValidade!)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            initialValue:
                FuncionarioCadastroCatalogo.idsTamanhosUniforme.contains(
                  _tamanhoUniforme,
                )
                ? _tamanhoUniforme
                : '',
            decoration: const InputDecoration(
              labelText: 'Uniforme / bota',
              isDense: true,
            ),
            items: FuncionarioCadastroCatalogo.tamanhosUniforme.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) => setState(() => _tamanhoUniforme = v ?? ''),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _epiObservacoesController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'EPIs e observacoes de seguranca',
            hintText: 'Capacete, luva, oculos, colete...',
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Autorizado a operar empilhadeira'),
          value: _podeOperarEmpilhadeira,
          onChanged: (v) => setState(() => _podeOperarEmpilhadeira = v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Autorizado a operar transpalete'),
          value: _podeOperarTranspalete,
          onChanged: (v) => setState(() => _podeOperarTranspalete = v),
        ),
      ],
    );
  }

  Future<void> _selecionarMesFiltro() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _mesFiltroLancamentos,
      firstDate: DateTime(2010, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Mes de referencia dos lancamentos',
    );
    if (escolhida == null) return;
    setState(() {
      _mesFiltroLancamentos = DateTime(escolhida.year, escolhida.month, 1);
      final fid = _funcionarioEmEdicaoId;
      if (fid != null && fid > 0) {
        _carregarLancamentos(fid);
      }
    });
  }

  Future<void> _incluirLancamento() async {
    if (_mesEstaFechado()) {
      setState(
        () =>
            _status = 'Mes fechado. Reabra o mes RH para incluir lancamentos.',
      );
      return;
    }
    final valorController = TextEditingController();
    final obsController = TextEditingController();
    var tipo = LancamentoFuncionarioCatalogo.vale;
    DateTime data = DateTime.now();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Novo lancamento'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: tipo,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        isDense: true,
                      ),
                      items: LancamentoFuncionarioCatalogo.tipos.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => tipo = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final escolhida = await showDatePicker(
                          context: context,
                          initialDate: data,
                          firstDate: DateTime(2000, 1, 1),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (escolhida == null) return;
                        setDialogState(() => data = escolhida);
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text('Data: ${_dateFormat.format(data)}'),
                    ),
                    if (LancamentoFuncionarioCatalogo.exigeValor(tipo)) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: valorController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: tipo == LancamentoFuncionarioCatalogo.bonus
                              ? 'Valor do credito (R\$)'
                              : 'Valor (R\$)',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: obsController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Observacao',
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

    final valor = LancamentoFuncionarioCatalogo.exigeValor(tipo)
        ? _parseBr(valorController.text)
        : 0.0;
    if (LancamentoFuncionarioCatalogo.exigeValor(tipo) && valor <= 0) {
      setState(() => _status = 'Informe um valor maior que zero.');
      return;
    }

    final lanc = LancamentoFuncionario(
      tipo: tipo,
      valor: valor,
      observacao: obsController.text.trim(),
      data: data,
    );

    final fid = _funcionarioEmEdicaoId;
    if (fid != null && fid > 0) {
      if (_terminalRh) {
        await _lancRepo.salvarRemoto(lanc, fid);
      } else {
        _lancRepo.salvar(lanc, fid);
      }
      _carregarLancamentos(fid);
      if (!mounted) return;
      setState(() => _status = 'Lancamento gravado.');
      return;
    }

    setState(() {
      _lancamentos.insert(0, lanc);
      _status = 'Lancamento incluido. Salve o funcionario para gravar.';
    });
  }

  Future<void> _estornarLancamento(LancamentoFuncionario lanc) async {
    if (_mesEstaFechado()) {
      setState(
        () =>
            _status = 'Mes fechado. Reabra o mes RH para estornar lancamentos.',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estornar lancamento'),
        content: Text(
          'Estornar ${LancamentoFuncionarioCatalogo.rotulo(lanc.tipo)} '
          'de ${_dateFormat.format(lanc.data)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Estornar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    if (lanc.id == 0) {
      setState(() {
        _lancamentos.remove(lanc);
        _status = 'Lancamento removido.';
      });
      return;
    }

    try {
      if (_terminalRh) {
        await _lancRepo.estornarRemoto(lanc.id);
      } else {
        _lancRepo.estornar(lanc.id);
      }
      final fid = _funcionarioEmEdicaoId;
      if (fid != null) _carregarLancamentos(fid);
      if (!mounted) return;
      setState(() => _status = 'Lancamento estornado.');
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Estorno');
      setState(() => _status = LanApiFeedback.mensagem(e));
    }
  }

  Future<void> _exportarExtratoPdf() async {
    final fid = _funcionarioEmEdicaoId;
    if (fid == null || fid <= 0) {
      setState(
        () => _status = 'Salve o funcionario antes de gerar o extrato PDF.',
      );
      return;
    }
    final f = widget.funcionarioRepository.obterPorId(fid);
    if (f == null) return;

    final lancamentos = _lancRepo.listarPorFuncionario(
      fid,
      mesReferencia: _mesFiltroLancamentos,
    );

    Uint8List bytes;
    try {
      bytes = await gerarExtratoFuncionarioPdf(
        funcionario: f,
        lancamentos: lancamentos,
        salarioBase: _salarioValor(),
        descontoFixo: _descontoValor(),
        mesReferencia: _mesFiltroLancamentos,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Erro ao gerar PDF: $e');
      return;
    }

    final mesSlug = DateFormat('yyyyMM').format(_mesFiltroLancamentos);
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar extrato do funcionario',
      fileName:
          'extrato_${f.codigoInterno}_${mesSlug}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
    if (selectedPath == null || !mounted) return;
    final path = selectedPath.toLowerCase().endsWith('.pdf')
        ? selectedPath
        : '$selectedPath.pdf';
    await File(path).writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Extrato salvo em: $path')));
  }

  Future<void> _confirmarRemocao(Funcionario f) async {
    var vendasPdv = 0;
    try {
      if (f.vendedorId > 0) {
        vendasPdv = widget.vendaRepository.contarVendasFinalizadasPorVendedor(
              f.vendedorId,
            )
            as int;
      }
    } catch (_) {
      vendasPdv = 0;
    }
    if (vendasPdv > 0) {
      setState(
        () => _status =
            'Nao e possivel remover: vendedor vinculado tem $vendasPdv venda(s) no PDV. '
            'Desative o funcionario em vez de apagar.',
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
        title: const Text('Remover funcionario'),
        content: Text(
          f.vendedorId > 0
              ? 'Remover "${f.nomeCompleto}"? O cadastro de vendedor #${f.vendedorId} '
                    'permanece no sistema (sem vendas vinculadas).'
              : 'Remover "${f.nomeCompleto}" da lista?',
        ),
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
    final repo = widget.funcionarioRepository;
    try {
      if (repo is FuncionarioApiRepository) {
        final removido = await repo.removerRemoto(f.id);
        if (!removido) {
          if (!mounted) return;
          LanApiFeedback.snackAviso(
            context,
            'Nao foi possivel remover o funcionario.',
          );
          return;
        }
      } else {
        repo.remover(f.id);
      }
      if (!mounted) return;
      if (_funcionarioEmEdicaoId == f.id) {
        _limparFormulario();
      }
      setState(() => _status = 'Remocao concluida com sucesso.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Funcionario removido com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel remover');
      setState(() => _status = LanApiFeedback.mensagem(e));
    }
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
                          labelText:
                              'Nome, codigo, setor, funcao, CPF, telefone...',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            resultados = widget.funcionarioRepository.pesquisar(
                              value,
                            );
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
                                child: Text('Nenhum funcionario encontrado.'),
                              )
                            : ListView.builder(
                                controller: resultadosScrollController,
                                shrinkWrap: true,
                                itemCount: resultados.length,
                                itemBuilder: (context, index) {
                                  final f = resultados[index];
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
                                      if (indiceSelecionado == index) return;
                                      setDialogState(
                                        () => indiceSelecionado = index,
                                      );
                                    },
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
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
                                          'Codigo: ${f.codigoInterno} | ${_resumoRhDe(f)}'
                                          '${f.ativo ? '' : ' | inativo'}',
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

  Widget _wrapAbaScroll({
    required ScrollController controller,
    required List<Widget> children,
  }) {
    return RawScrollbar(
      controller: controller,
      thumbVisibility: true,
      trackVisibility: true,
      thickness: 10,
      radius: const Radius.circular(8),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        children: children,
      ),
    );
  }

  ThemeData _temaCadastro(ThemeData theme) {
    final scheme = theme.colorScheme;
    return theme.copyWith(
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: _pageBg,
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
        titleSmall: theme.textTheme.titleSmall?.copyWith(fontSize: 12.5),
        labelLarge: theme.textTheme.labelLarge?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCorpoAbas(BuildContext context, {bool compactUi = false}) {
    final denseTheme = _temaCadastro(Theme.of(context));
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
                Tab(height: 36, text: 'Dados'),
                Tab(height: 36, text: 'Documentos'),
                Tab(height: 36, text: 'Remuneracao'),
                Tab(height: 36, text: 'Acessos'),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: _pageBg,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _wrapAbaScroll(
                    controller: _scrollAbaIdent,
                    children: _conteudoAbaDados(context),
                  ),
                  _wrapAbaScroll(
                    controller: _scrollAbaDocs,
                    children: _conteudoAbaDocumentos(context),
                  ),
                  _wrapAbaScroll(
                    controller: _scrollAbaFin,
                    children: _conteudoAbaRemuneracao(context),
                  ),
                  _wrapAbaScroll(
                    controller: _scrollAbaOp,
                    children: _conteudoAbaAcessos(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _conteudoAbaDados(BuildContext context) {
    return [
      _buildSectionCard(
        context: context,
        title: 'Identificacao',
        icon: Icons.badge_outlined,
        children: [
          FuncionarioFotoPanel(
            previewPath: _fotoPreviewPath(),
            compact: context.isFuncionarioCompactDesktop,
            onTirarFoto: () => unawaited(_tirarFotoFuncionario()),
            onEscolherArquivo: () => unawaited(_escolherFotoFuncionario()),
            onRemover: _removerFotoFuncionario,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: context.isFuncionarioCompactDesktop ? 112 : _wCodigo,
                  child: TextField(
                    controller: _codigoController,
                    decoration: const InputDecoration(
                      labelText: 'Codigo interno',
                      hintText: 'Ex.: 01',
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    focusNode: _nomeFocus,
                    controller: _nomeController,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nome completo',
                      isDense: true,
                    ),
                  ),
                ),
                FilterChip(
                  label: Text(_ativo ? 'Ativo no sistema' : 'Inativo'),
                  selected: _ativo,
                  onSelected: (v) => unawaited(_onAtivoChanged(v)),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _buildSectionCard(
        context: context,
        title: 'RH — setor e funcao',
        icon: Icons.work_outline,
        children: _camposSetorFuncaoDatas(),
      ),
      if (!_ativo) ...[const SizedBox(height: 8), _buildSecaoDemissao(context)],
    ];
  }

  List<Widget> _camposSetorFuncaoDatas() {
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          final empilhar = constraints.maxWidth < 560;
          final setor = DropdownButtonFormField<String>(
            initialValue: _setorSelecionado,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Setor',
              isDense: true,
            ),
            items: FuncionarioCadastroCatalogo.setores.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _setorSelecionado = v;
                _sugerirVinculosOperacionaisPorSetor();
              });
            },
          );
          final funcao = DropdownButtonFormField<String>(
            initialValue: _funcaoSelecionada,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Funcao',
              isDense: true,
            ),
            items: FuncionarioCadastroCatalogo.funcoes.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _funcaoSelecionada = v;
                if (v != 'outro') _funcaoOutroController.clear();
                _sugerirVinculosOperacionaisPorSetor();
              });
            },
          );
          if (empilhar) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [setor, const SizedBox(height: 6), funcao],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: setor),
              const SizedBox(width: 10),
              Expanded(child: funcao),
            ],
          );
        },
      ),
      if (_funcaoSelecionada == 'outro') ...[
        const SizedBox(height: 6),
        TextField(
          controller: _funcaoOutroController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Descreva a funcao',
            isDense: true,
          ),
        ),
      ],
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue:
            FuncionarioCadastroCatalogo.idsTiposVinculo.contains(_tipoVinculo)
            ? _tipoVinculo
            : 'clt',
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Tipo de vinculo',
          isDense: true,
        ),
        items: FuncionarioCadastroCatalogo.tiposVinculo.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() => _tipoVinculo = v);
        },
      ),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: _wData,
              child: OutlinedButton.icon(
                style: _estiloBotaoContornoCompacto,
                onPressed: _selecionarDataNascimento,
                icon: const Icon(Icons.cake_outlined, size: 18),
                label: Text(
                  'Nasc.: ${_dateFormat.format(_dataNascimento)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: _wData,
              child: OutlinedButton.icon(
                style: _estiloBotaoContornoCompacto,
                onPressed: _selecionarDataAdmissao,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(
                  'Admissao: ${_dateFormat.format(_dataAdmissao)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _conteudoAbaDocumentos(BuildContext context) {
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          final docCard = _buildSectionCard(
            context: context,
            title: 'Documentacao',
            icon: Icons.assignment_ind_outlined,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: _wCpf,
                      child: TextField(
                        controller: _cpfController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [_cpfFormatter],
                        decoration: const InputDecoration(
                          labelText: 'CPF',
                          hintText: '000.000.000-00',
                          isDense: true,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _wRg,
                      child: TextField(
                        controller: _rgController,
                        decoration: const InputDecoration(
                          labelText: 'RG',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: _wPis,
                  child: TextField(
                    controller: _pisController,
                    decoration: const InputDecoration(
                      labelText: 'PIS',
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
          );
          final contCard = _buildSectionCard(
            context: context,
            title: 'Contato',
            icon: Icons.phone_outlined,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: _wFone,
                      child: TextField(
                        controller: _telefoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_telefoneFormatter],
                        decoration: const InputDecoration(
                          labelText: 'Telefone',
                          hintText: '(00) 00000-0000',
                          isDense: true,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _wFone,
                      child: TextField(
                        controller: _whatsappController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_telefoneFormatter],
                        decoration: const InputDecoration(
                          labelText: 'WhatsApp',
                          hintText: '(00) 00000-0000',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Contato de emergencia',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _contatoEmergenciaNomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome do contato',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: _wFone,
                  child: TextField(
                    controller: _contatoEmergenciaTelefoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [_telefoneFormatter],
                    decoration: const InputDecoration(
                      labelText: 'Telefone emergencia',
                      hintText: '(00) 00000-0000',
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
          );

          final largura = constraints.maxWidth;
          final usarDuasColunas =
              constraints.hasBoundedWidth &&
              FuncionarioLayout.documentosDuasColunas(largura);
          if (!usarDuasColunas) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [docCard, const SizedBox(height: 8), contCard],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: docCard),
              const SizedBox(width: 10),
              Expanded(child: contCard),
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      _buildSecaoCnh(context),
      const SizedBox(height: 8),
      _buildSecaoSst(context),
      const SizedBox(height: 8),
      _buildSectionCard(
        context: context,
        title: 'Endereco',
        icon: Icons.location_on_outlined,
        children: _camposEndereco(),
      ),
    ];
  }

  List<Widget> _camposEndereco() {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _wCep,
            child: TextField(
              controller: _cepController,
              focusNode: _cepFocus,
              keyboardType: TextInputType.number,
              inputFormatters: [_cepFormatter],
              onChanged: (_) => _agendarConsultaCep(),
              decoration: InputDecoration(
                labelText: 'CEP',
                hintText: '00000-000',
                isDense: true,
                suffixIcon: _consultaCepEmAndamento
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Buscar CEP na BrasilAPI',
                        onPressed: () => unawaited(_executarConsultaCep()),
                        icon: const Icon(Icons.search, size: 20),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _enderecoController,
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
              controller: _numeroController,
              decoration: const InputDecoration(labelText: 'Nº', isDense: true),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _bairroController,
              decoration: const InputDecoration(
                labelText: 'Bairro',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _cidadeController,
              decoration: const InputDecoration(
                labelText: 'Cidade',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: _wUf,
            child: TextField(
              controller: _ufController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: const InputDecoration(labelText: 'UF', isDense: true),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _conteudoAbaRemuneracao(BuildContext context) {
    final theme = Theme.of(context);
    final compactUi = context.isFuncionarioCompactDesktop;
    final resumoMes = _resumoMesAtual();
    final mesFechado = _mesEstaFechado();
    final fechamento = _folhaService != null && _funcionarioEmEdicaoId != null
        ? _folhaService!.fechamentoDe(
            _funcionarioEmEdicaoId!,
            _mesFiltroLancamentos,
          )
        : null;

    return [
      if (_terminalRh)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.info_outline),
              title: Text(
                'Terminal leve: cadastro, vales/descontos/bonus e estorno '
                'funcionam. Fechamento de mes / Contas a Pagar so no PC servidor.',
              ),
            ),
          ),
        ),
      _buildSectionCard(
        context: context,
        title: 'Salario e beneficios',
        icon: Icons.payments_outlined,
        children: [
          _buildPainelKpiFinanceiro(context),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: _wMoeda,
                  child: TextField(
                    controller: _salarioController,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Salario (R\$)',
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: _wDiaPag,
                  child: TextField(
                    controller: _diaPagamentoController,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Dia pag.',
                      helperText: '1-31',
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: _wMoeda,
                  child: TextField(
                    controller: _descontoController,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Desconto fixo (R\$)',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _buildSectionCard(
        context: context,
        title: 'Lancamentos do mes',
        icon: Icons.receipt_long_outlined,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final acoesWrap = FuncionarioLayout.acoesEmWrap(
                constraints.maxWidth,
              );
              final mesBtn = OutlinedButton.icon(
                style: _estiloBotaoContornoCompacto,
                onPressed: _selecionarMesFiltro,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: Text(
                  'Mes: ${_mesAnoFormat.format(_mesFiltroLancamentos)}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
              final lancBtn = OutlinedButton.icon(
                style: _estiloBotaoContornoCompacto,
                onPressed: mesFechado ? null : _incluirLancamento,
                icon: const Icon(Icons.add_card_outlined, size: 18),
                label: const Text('Lancamento'),
              );
              final pdfBtn = OutlinedButton.icon(
                style: _estiloBotaoContornoCompacto,
                onPressed: () => unawaited(_exportarExtratoPdf()),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
              );
              if (acoesWrap) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [mesBtn, lancBtn, pdfBtn],
                );
              }
              return Row(
                children: [
                  Expanded(child: mesBtn),
                  const SizedBox(width: 8),
                  Expanded(child: lancBtn),
                  const SizedBox(width: 8),
                  pdfBtn,
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          if (_lancamentos.isEmpty)
            const Text('Nenhum lancamento neste mes.')
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lancamentos.length,
              itemBuilder: (context, index) {
                final lanc = _lancamentos[index];
                final tipoRotulo = LancamentoFuncionarioCatalogo.rotulo(
                  lanc.tipo,
                );
                final valorTxt =
                    lanc.tipo == LancamentoFuncionarioCatalogo.observacao
                    ? ''
                    : ' · ${_formatMoeda(lanc.valor)}';
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    '${_dateFormat.format(lanc.data.toLocal())} · $tipoRotulo$valorTxt'
                    '${lanc.estornado ? ' [estornado]' : ''}'
                    '${lanc.id == 0 ? ' (pendente)' : ''}',
                    style: lanc.estornado
                        ? theme.textTheme.bodyMedium?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: theme.colorScheme.outline,
                          )
                        : null,
                  ),
                  subtitle: Text(
                    lanc.observacao.isEmpty
                        ? 'Sem observacao'
                        : lanc.observacao,
                  ),
                  trailing: lanc.estornado
                      ? null
                      : IconButton(
                          tooltip: 'Estornar',
                          onPressed: () => unawaited(_estornarLancamento(lanc)),
                          icon: Icon(
                            Icons.undo_outlined,
                            color: theme.colorScheme.error,
                          ),
                        ),
                );
              },
            ),
        ],
      ),
      const SizedBox(height: 8),
      Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
        child: ExpansionTile(
          initiallyExpanded: false,
          maintainState: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          leading: Icon(
            Icons.account_balance_outlined,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          title: Text(
            'Folha da equipe / fechamento',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'Fechar mes, exportacoes e historico',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            FuncionarioFolhaPainel(
              mesReferencia: _mesFiltroLancamentos,
              resumoMes: resumoMes,
              mesFechado: mesFechado,
              contaPagarId:
                  fechamento?.contaPagarId ?? resumoMes?.contaPagarId ?? 0,
              alertasEquipe: _alertasEquipeMes(),
              historico12Meses: _historico12Meses(),
              onFecharMes: () => unawaited(_fecharMesRh()),
              onReabrirMes: () => unawaited(_reabrirMesRh()),
              onExportarFolhaEquipe: () => unawaited(_exportarFolhaEquipeCsv()),
              onExportarLancamentosAno: () =>
                  unawaited(_exportarLancamentosAnoCsv()),
              onRelatorioSetor: () => unawaited(_mostrarRelatorioFolhaSetor()),
              compact: compactUi,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _conteudoAbaAcessos(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Funcionario e a ficha de RH (folha e documentos). '
                  'Se tambem vende ou entra no sistema, use os vinculos abaixo. '
                  'A senha de acesso e so do usuario; PIN do PDV e opcional no cadastro de Vendedores.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      _buildSecaoVendedorPdv(context),
      const SizedBox(height: 8),
      _buildSecaoMotoristaEntregas(context),
      const SizedBox(height: 8),
      _buildSecaoUsuarioSistema(context),
      const SizedBox(height: 8),
      _buildSectionCard(
        context: context,
        title: 'Observacoes RH',
        icon: Icons.notes_outlined,
        children: [
          TextField(
            controller: _observacoesController,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Observacoes gerais',
              isDense: true,
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildResumoHeader(BuildContext context, {required bool compactUi}) {
    return FuncionarioResumoHeader(
      nome: _nomeController.text,
      codigo: _codigoController.text,
      resumoRh: _resumoSetorFuncaoAtual(),
      tempoCasa: _rotuloTempoCasa(),
      liquidoFormatado: _formatMoeda(_liquidoReferencia()),
      proximoPagamentoFormatado: _dateFormat.format(_dataProximoPagamento()),
      ativo: _ativo,
      emEdicaoId: _funcionarioEmEdicaoId,
      tambemVendedorPdv: _tambemVendedorPdv,
      vendedorVinculadoId: _vendedorVinculadoId,
      tambemMotoristaEntrega: _tambemMotoristaEntrega,
      motoristaVinculadoId: _motoristaVinculadoId,
      temUsuarioSistema: _temUsuarioSistema,
      usuarioLogin: _usuarioVinculadoAtual()?.login,
      cnhVencida: _cnhVencida,
      asoVencido: _asoVencido,
      dataDemissaoFormatada: _dataDemissao != null
          ? _dateFormat.format(_dataDemissao!)
          : null,
      fotoPath: _fotoPreviewPath(),
      compact: compactUi,
    );
  }

  Widget _buildPainelDetalhe(BuildContext context, {required bool compact}) {
    final emEdicao = _funcionarioEmEdicaoId != null;
    final compactUi = compact || context.isFuncionarioCompactDesktop;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FuncionarioAtalhosBar(
                  compact: compactUi,
                  mostrarNavegacao: true,
                  onPrimeiro: _irPrimeiroFuncionario,
                  onAnterior: _irFuncionarioAnterior,
                  onProximo: _irProximoFuncionario,
                  onUltimo: _irUltimoFuncionario,
                  onPesquisar: () => unawaited(_abrirPesquisaFuncionario()),
                ),
                const SizedBox(height: 4),
                _buildResumoHeader(context, compactUi: compactUi),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _buildStatusBanner(context, _status),
                ],
                const SizedBox(height: 2),
                Expanded(
                  child: _buildCorpoAbas(context, compactUi: compactUi),
                ),
              ],
            ),
          ),
        ),
        FuncionarioCadastroRodape(
          emEdicao: emEdicao,
          onSalvar: () => unawaited(_salvar()),
          onNovo: _limparFormulario,
          podeExcluir: emEdicao,
          onExcluir: () {
            final atualId = _funcionarioEmEdicaoId;
            if (atualId == null) return;
            final atual = widget.funcionarioRepository.obterPorId(atualId);
            if (atual == null) return;
            _confirmarRemocao(atual);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessaoActions =
        widget.usuarioLogado != null && widget.onLogout != null
        ? ContaSessaoAppBarActions(
            login: widget.usuarioLogado!.login,
            onLogout: widget.onLogout!,
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastro de Funcionarios'),
        actions: [
          IconButton(
            tooltip: 'Pesquisar funcionario (F3)',
            onPressed: () => unawaited(_abrirPesquisaFuncionario()),
            icon: const Icon(Icons.search),
          ),
          ?sessaoActions,
        ],
      ),
      body: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.f5): _FuncionarioSalvarIntent(),
          SingleActivator(LogicalKeyboardKey.f10): _FuncionarioSalvarIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _FuncionarioNovoIntent(),
          SingleActivator(LogicalKeyboardKey.f3): _FuncionarioPesquisarIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _FuncionarioSalvarIntent: CallbackAction<_FuncionarioSalvarIntent>(
              onInvoke: (_) {
                unawaited(_salvar());
                return null;
              },
            ),
            _FuncionarioNovoIntent: CallbackAction<_FuncionarioNovoIntent>(
              onInvoke: (_) {
                _limparFormulario();
                return null;
              },
            ),
            _FuncionarioPesquisarIntent:
                CallbackAction<_FuncionarioPesquisarIntent>(
                  onInvoke: (_) {
                    unawaited(_abrirPesquisaFuncionario());
                    return null;
                  },
                ),
          },
          child: _buildPainelDetalhe(
            context,
            compact: !context.isDesktopLayout,
          ),
        ),
      ),
    );
  }

  Widget _buildSecaoDemissao(BuildContext context) {
    final motivoRotulo = _motivoDemissao.isEmpty
        ? 'Selecione'
        : FuncionarioCadastroCatalogo.rotuloMotivoDemissao(
            _motivoDemissao,
            outroTexto: _motivoDemissaoOutroController.text,
          );

    return _buildSectionCard(
      context: context,
      title: 'Desligamento',
      icon: Icons.person_off_outlined,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: _wData,
                child: OutlinedButton.icon(
                  style: _estiloBotaoContornoCompacto,
                  onPressed: _selecionarDataDemissao,
                  icon: const Icon(Icons.event_busy_outlined, size: 18),
                  label: Text(
                    _dataDemissao == null
                        ? 'Data demissao *'
                        : 'Demissao: ${_dateFormat.format(_dataDemissao!)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              OutlinedButton.icon(
                style: _estiloBotaoContornoCompacto,
                onPressed: () async {
                  final r = await _mostrarDialogDemissao(
                    dataInicial: _dataDemissao ?? DateTime.now(),
                    motivoInicial: _motivoDemissao,
                    motivoOutroInicial: _motivoDemissaoOutroController.text,
                  );
                  if (r == null || !mounted) return;
                  setState(() {
                    _dataDemissao = r.data;
                    _motivoDemissao = r.motivo;
                    _motivoDemissaoOutroController.text = r.motivoOutro;
                  });
                },
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: Text('Motivo: $motivoRotulo'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _motivoDemissao.isEmpty ? null : _motivoDemissao,
          decoration: const InputDecoration(
            labelText: 'Motivo da demissao *',
            isDense: true,
          ),
          items: FuncionarioCadastroCatalogo.motivosDemissao.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _motivoDemissao = v;
              if (v != 'outro') _motivoDemissaoOutroController.clear();
            });
          },
        ),
        if (_motivoDemissao == 'outro') ...[
          const SizedBox(height: 6),
          TextField(
            controller: _motivoDemissaoOutroController,
            decoration: const InputDecoration(
              labelText: 'Descreva o motivo',
              isDense: true,
            ),
          ),
        ],
      ],
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
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.1,
                    ),
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
    final semantic = context.semanticColors;
    final m = message.toLowerCase();
    final sucesso = m.contains('sucesso') ||
        m.contains('salvo') ||
        m.contains('preenchido') ||
        m.contains('gravado') ||
        m.contains('removido') ||
        m.contains('reaberto') ||
        m.contains('fechado') ||
        m.contains('concluida') ||
        m.contains('concluída');
    final erro = m.contains('falha') ||
        m.contains('erro') ||
        m.contains('invalido') ||
        m.contains('inválido') ||
        m.contains('ja existe') ||
        m.contains('já existe') ||
        m.contains('informe') ||
        m.contains('selecione') ||
        m.contains('nao foi') ||
        m.contains('não foi') ||
        m.contains('nao e') ||
        m.contains('não e') ||
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

class _DemissaoDialogResult {
  const _DemissaoDialogResult({
    required this.data,
    required this.motivo,
    required this.motivoOutro,
  });

  final DateTime data;
  final String motivo;
  final String motivoOutro;
}

class _DemissaoFuncionarioDialog extends StatefulWidget {
  const _DemissaoFuncionarioDialog({
    required this.dataInicial,
    required this.motivoInicial,
    required this.motivoOutroInicial,
    required this.dateFormat,
  });

  final DateTime dataInicial;
  final String motivoInicial;
  final String motivoOutroInicial;
  final DateFormat dateFormat;

  @override
  State<_DemissaoFuncionarioDialog> createState() =>
      _DemissaoFuncionarioDialogState();
}

class _DemissaoFuncionarioDialogState
    extends State<_DemissaoFuncionarioDialog> {
  late DateTime _data;
  late String _motivo;
  late final TextEditingController _outroController;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _data = widget.dataInicial;
    _motivo = widget.motivoInicial.isEmpty ? 'pedido' : widget.motivoInicial;
    _outroController = TextEditingController(text: widget.motivoOutroInicial);
  }

  @override
  void dispose() {
    _outroController.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(1950, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (escolhida == null) return;
    setState(() => _data = escolhida);
  }

  void _confirmar() {
    if (_motivo == 'outro' && _outroController.text.trim().isEmpty) {
      setState(() => _erro = 'Descreva o motivo quando selecionar Outro.');
      return;
    }
    Navigator.pop(
      context,
      _DemissaoDialogResult(
        data: _data,
        motivo: _motivo,
        motivoOutro: _motivo == 'outro' ? _outroController.text.trim() : '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar demissao'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ao inativar o funcionario, informe a data e o motivo do desligamento.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _escolherData,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('Data: ${widget.dateFormat.format(_data)}'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _motivo,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                isDense: true,
              ),
              items: FuncionarioCadastroCatalogo.motivosDemissao.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _motivo = v;
                  _erro = null;
                  if (v != 'outro') _outroController.clear();
                });
              },
            ),
            if (_motivo == 'outro') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _outroController,
                decoration: const InputDecoration(
                  labelText: 'Descreva o motivo',
                  isDense: true,
                ),
              ),
            ],
            if (_erro != null) ...[
              const SizedBox(height: 8),
              Text(
                _erro!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Confirmar inativacao'),
        ),
      ],
    );
  }
}
