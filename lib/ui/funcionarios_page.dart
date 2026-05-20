import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/funcionario_repository.dart';
import '../data/lancamento_funcionario_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../domain/funcionario_cadastro_catalogo.dart';
import '../domain/lancamento_funcionario_catalogo.dart';
import '../main.dart';
import '../model/funcionario.dart';
import '../model/lancamento_funcionario.dart';
import '../model/vendedor.dart';
import '../services/funcionario_extrato_pdf.dart';
import '../services/brasil_api_cep_service.dart';
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
  });

  final FuncionarioRepository funcionarioRepository;
  final VendedorRepository vendedorRepository;
  final VendaRepository vendaRepository;

  @override
  State<FuncionariosPage> createState() => _FuncionariosPageState();
}

class _FuncionariosPageState extends State<FuncionariosPage>
    with SingleTickerProviderStateMixin {
  static ButtonStyle get _estiloBotaoContornoCompacto => OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  static ButtonStyle get _estiloBotaoPrimarioCompacto => FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
  static const double _erpGap8 = 8;
  static const double _erpGap12 = 12;
  static const double _erpGap16 = 16;

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
  final _pesquisaController = TextEditingController();
  final _filtroListaController = TextEditingController();
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
  DateTime _dataNascimento = DateTime(2000, 1, 1);
  DateTime _dataAdmissao = DateTime.now();
  String _status = '';
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final NumberFormat _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat _mesAnoFormat = DateFormat('MMMM/yyyy', 'pt_BR');
  List<LancamentoFuncionario> _lancamentos = [];
  late DateTime _mesFiltroLancamentos =
      DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _preencherCodigoAutomaticoSeNovo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focarNomeSeNovo();
    });
  }

  void _focarNomeSeNovo() {
    if (_funcionarioEmEdicaoId != null) return;
    _nomeFocus.requestFocus();
  }

  @override
  void dispose() {
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
    _pesquisaController.dispose();
    _filtroListaController.dispose();
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
      _lancamentos = [];
      _mesFiltroLancamentos =
          DateTime(DateTime.now().year, DateTime.now().month, 1);
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

  String _resumoSetorFuncaoAtual() => FuncionarioCadastroCatalogo.resumoSetorFuncao(
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
      final leg = FuncionarioCadastroCatalogo.migrarCargoLegado(f.cargo, '', '');
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
          () => _status = 'Informe a data de demissao para funcionario inativo.',
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
        vendedorId = _sincronizarVendedorVinculo();
      } catch (e) {
        setState(
          () => _status = 'Nao foi possivel vincular vendedor no PDV: $e',
        );
        return;
      }
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
      contatoEmergenciaTelefone:
          somenteDigitos(_contatoEmergenciaTelefoneController.text),
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
      motivoDemissaoOutro:
          _ativo || _motivoDemissao != 'outro'
              ? ''
              : _motivoDemissaoOutroController.text.trim(),
      dataNascimento: _dataNascimento,
      dataAdmissao: _dataAdmissao,
      dataDemissao: _ativo ? null : _dataDemissao,
      vendedorId: vendedorId,
      criadoEm: existente?.criadoEm,
    );
    var id = widget.funcionarioRepository.salvar(funcionario);
    for (final l in _lancamentos.where((x) => x.id == 0).toList()) {
      widget.funcionarioRepository.lancamentos.salvar(l, id);
    }
    final atualizado = widget.funcionarioRepository.obterPorId(id);
    if (atualizado != null) {
      atualizado.adiantamentoAtual =
          widget.funcionarioRepository.lancamentos.totalValesAtivos(id);
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
      _status = 'Funcionario salvo com sucesso.';
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
      widget.funcionarioRepository.lancamentos.migrarLegadoSeNecessario(f);
      _mesFiltroLancamentos =
          DateTime(DateTime.now().year, DateTime.now().month, 1);
      _carregarLancamentos(f.id);
      _observacoesController.text = f.observacoes;
      _dataNascimento = f.dataNascimento.toLocal();
      _dataAdmissao = f.dataAdmissao.toLocal();
      _ativo = f.ativo;
      _status = 'Editando: ${f.nomeCompleto}';
    });
  }

  LancamentoFuncionarioRepository get _lancRepo =>
      widget.funcionarioRepository.lancamentos;

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

  double _liquidoReferencia() => _salarioValor() -
      _descontoValor() -
      _totalVales() -
      _totalDescontosLancados() +
      _totalBonus();

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
    final ultimoProximo = DateTime(proximoMes.year, proximoMes.month + 1, 0).day;
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
      _vendedorComissaoController.text =
          v.percentualComissao.toStringAsFixed(2).replaceAll('.', ',');
    }
    if (v.metaMensalValor > 0) {
      _vendedorMetaController.text =
          v.metaMensalValor.toStringAsFixed(2).replaceAll('.', ',');
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

  int _sincronizarVendedorVinculo() {
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
    return widget.vendedorRepository.salvar(v);
  }

  Widget _buildLinhaKpiFinanceiro({
    required String rotulo,
    required String valor,
    TextStyle? estiloValor,
    bool destaque = false,
  }) {
    final estilo = estiloValor ??
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
        ? widget.vendaRepository
            .contarVendasFinalizadasPorVendedor(_vendedorVinculadoId)
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
            'Cria ou atualiza o cadastro de vendedor com os mesmos dados de contato.',
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
                  _vendedorComissaoController.text = existente.percentualComissao
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
                  Row(
                    children: [
                      comissao,
                      const SizedBox(width: 10),
                      meta,
                    ],
                  ),
                ],
              );
            },
          ),
        ],
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
                          lastDate: DateTime.now().add(const Duration(days: 365)),
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
      _lancRepo.salvar(lanc, fid);
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

    _lancRepo.estornar(lanc.id);
    final fid = _funcionarioEmEdicaoId;
    if (fid != null) _carregarLancamentos(fid);
    if (!mounted) return;
    setState(() => _status = 'Lancamento estornado.');
  }

  Future<void> _exportarExtratoPdf() async {
    final fid = _funcionarioEmEdicaoId;
    if (fid == null || fid <= 0) {
      setState(() => _status = 'Salve o funcionario antes de gerar o extrato PDF.');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Extrato salvo em: $path')),
    );
  }

  Future<void> _confirmarRemocao(Funcionario f) async {
    final vendasPdv = f.vendedorId > 0
        ? widget.vendaRepository.contarVendasFinalizadasPorVendedor(f.vendedorId)
        : 0;
    if (vendasPdv > 0) {
      setState(
        () => _status =
            'Nao e possivel remover: vendedor vinculado tem $vendasPdv venda(s) no PDV. '
            'Desative o funcionario em vez de apagar.',
      );
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
                          labelText:
                              'Nome, codigo, setor, funcao, CPF, telefone...',
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
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        children: children,
      ),
    );
  }

  Widget _buildCorpoAbas(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Identificacao'),
              Tab(text: 'Documentos'),
              Tab(text: 'Financeiro'),
              Tab(text: 'Operacional'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _wrapAbaScroll(
                controller: _scrollAbaIdent,
                children: _conteudoAbaIdentificacao(context),
              ),
              _wrapAbaScroll(
                controller: _scrollAbaDocs,
                children: _conteudoAbaDocumentos(context),
              ),
              _wrapAbaScroll(
                controller: _scrollAbaFin,
                children: _conteudoAbaFinanceiro(context),
              ),
              _wrapAbaScroll(
                controller: _scrollAbaOp,
                children: _conteudoAbaOperacional(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _conteudoAbaIdentificacao(BuildContext context) {
    return [
      _buildSectionCard(
        context: context,
        title: 'RH — setor e funcao',
        icon: Icons.badge_outlined,
        children: _camposSetorFuncaoDatas(),
      ),
      if (!_ativo) ...[
        const SizedBox(height: 8),
        _buildSecaoDemissao(context),
      ],
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
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _setorSelecionado = v);
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
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _funcaoSelecionada = v;
                if (v != 'outro') _funcaoOutroController.clear();
              });
            },
          );
          if (empilhar) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                setor,
                const SizedBox(height: 6),
                funcao,
              ],
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
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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

          const limiarDuasColunas = 700.0;
          final largura = constraints.maxWidth;
          final usarDuasColunas =
              constraints.hasBoundedWidth && largura >= limiarDuasColunas;
          if (!usarDuasColunas) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                docCard,
                const SizedBox(height: 8),
                contCard,
              ],
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
              decoration: const InputDecoration(
                labelText: 'Nº',
                isDense: true,
              ),
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
              decoration: const InputDecoration(
                labelText: 'UF',
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _conteudoAbaFinanceiro(BuildContext context) {
    final theme = Theme.of(context);
    return [
      _buildSectionCard(
        context: context,
        title: 'Financeiro',
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: _estiloBotaoContornoCompacto,
                  onPressed: _selecionarMesFiltro,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(
                    'Mes: ${_mesAnoFormat.format(_mesFiltroLancamentos)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: _estiloBotaoContornoCompacto,
                  onPressed: _incluirLancamento,
                  icon: const Icon(Icons.add_card_outlined, size: 18),
                  label: const Text('Lancamento'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: _estiloBotaoContornoCompacto,
                onPressed: () => unawaited(_exportarExtratoPdf()),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
              ),
            ],
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
                final tipoRotulo =
                    LancamentoFuncionarioCatalogo.rotulo(lanc.tipo);
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
                          onPressed: () =>
                              unawaited(_estornarLancamento(lanc)),
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
    ];
  }

  List<Widget> _conteudoAbaOperacional(BuildContext context) {
    return [
      _buildSecaoVendedorPdv(context),
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

  Widget _buildCabecalhoFixo(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final codigo = _codigoController.text.trim();
    final rh = _resumoSetorFuncaoAtual();
    final diaPag = int.tryParse(_diaPagamentoController.text.trim()) ?? 5;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _erpGap16,
          _erpGap12,
          _erpGap16,
          _erpGap12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final empilhar = constraints.maxWidth < 720;
                final campoCodigo = SizedBox(
                  width: _wCodigo,
                  child: TextField(
                    controller: _codigoController,
                    decoration: const InputDecoration(
                      labelText: 'Codigo interno',
                      hintText: 'Ex.: 01',
                      isDense: true,
                    ),
                  ),
                );
                final campoNome = TextField(
                  focusNode: _nomeFocus,
                  controller: _nomeController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo',
                    isDense: true,
                  ),
                );
                if (empilhar) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      campoCodigo,
                      const SizedBox(height: _erpGap8),
                      campoNome,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    campoCodigo,
                    const SizedBox(width: _erpGap16),
                    Expanded(child: campoNome),
                  ],
                );
              },
            ),
            const SizedBox(height: _erpGap8),
            Wrap(
              spacing: _erpGap8,
              runSpacing: _erpGap8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    codigo.isEmpty ? 'Codigo ao salvar' : 'Cod. $codigo',
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_ativo ? 'Ativo' : 'Inativo'),
                  backgroundColor: _ativo
                      ? scheme.primaryContainer.withValues(alpha: 0.55)
                      : scheme.errorContainer.withValues(alpha: 0.4),
                ),
                if (rh.isNotEmpty)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(rh),
                  ),
                if (!_ativo && _dataDemissao != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      'Demissao ${_dateFormat.format(_dataDemissao!)}',
                    ),
                    backgroundColor:
                        scheme.errorContainer.withValues(alpha: 0.35),
                  ),
                if (_funcionarioEmEdicaoId != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Edicao #${_funcionarioEmEdicaoId!}'),
                  ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_rotuloTempoCasa()),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('Pag. dia $diaPag'),
                ),
                if (_tambemVendedorPdv)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      _vendedorVinculadoId > 0
                          ? 'PDV #$_vendedorVinculadoId'
                          : 'PDV (ao salvar)',
                    ),
                    backgroundColor:
                        scheme.tertiaryContainer.withValues(alpha: 0.5),
                  ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Funcionario ativo'),
              value: _ativo,
              onChanged: (v) => unawaited(_onAtivoChanged(v)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lista = widget.funcionarioRepository.pesquisar(_filtroListaController.text);
    final emEdicao = _funcionarioEmEdicaoId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro de funcionarios')),
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
                _salvar();
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              if (_status.isNotEmpty) ...[
                _buildStatusBanner(context, _status),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: _estiloBotaoContornoCompacto,
                      onPressed: _irPrimeiroFuncionario,
                      child: const Text('|< Primeiro'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      style: _estiloBotaoContornoCompacto,
                      onPressed: _irFuncionarioAnterior,
                      child: const Text('< Anterior'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      style: _estiloBotaoContornoCompacto,
                      onPressed: _irProximoFuncionario,
                      child: const Text('Proximo >'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      style: _estiloBotaoContornoCompacto,
                      onPressed: _irUltimoFuncionario,
                      child: const Text('Ultimo >|'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pesquisaController,
                      decoration: const InputDecoration(
                        labelText: 'Busca rapida (F3 abre lista)',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onSubmitted: (t) {
                        final r = widget.funcionarioRepository.pesquisar(t);
                        if (r.isNotEmpty) _editar(r.first);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: _estiloBotaoContornoCompacto,
                    onPressed: _abrirPesquisaFuncionario,
                    icon: const Icon(Icons.manage_search, size: 18),
                    label: const Text('Lista (F3)'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildCabecalhoFixo(context),
              Expanded(child: _buildCorpoAbas(context)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: _estiloBotaoPrimarioCompacto,
                      onPressed: _salvar,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(
                        emEdicao ? 'Atualizar (F5)' : 'Salvar (F5 · F10)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: _estiloBotaoContornoCompacto,
                    onPressed: _limparFormulario,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Novo (Esc)'),
                  ),
                  if (emEdicao) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: _estiloBotaoContornoCompacto,
                      onPressed: () {
                        final atualId = _funcionarioEmEdicaoId;
                        if (atualId == null) return;
                        final atual = widget.funcionarioRepository.obterPorId(atualId);
                        if (atual == null) return;
                        _confirmarRemocao(atual);
                      },
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
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
              const SizedBox(height: 12),
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
                                '${f.codigoInterno} · ${_resumoRhDe(f)}'
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
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                ),
              )
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

class _DemissaoFuncionarioDialogState extends State<_DemissaoFuncionarioDialog> {
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
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ),
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

