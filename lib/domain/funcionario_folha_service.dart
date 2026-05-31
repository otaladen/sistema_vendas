import '../data/conta_pagar_repository.dart';
import '../data/fechamento_rh_repository.dart';
import '../data/funcionario_repository.dart';
import '../data/models/conta_pagar.dart';
import '../model/fechamento_rh_funcionario.dart';
import '../model/funcionario.dart';
import 'funcionario_cadastro_catalogo.dart';
import 'funcionario_folha_resumo.dart';
import 'lancamento_funcionario_catalogo.dart';

class FuncionarioFolhaService {
  FuncionarioFolhaService({
    required FuncionarioRepository funcionarioRepository,
    required FechamentoRhRepository fechamentoRepository,
    required ContaPagarRepository contaPagarRepository,
  })  : _funcionarios = funcionarioRepository,
        _fechamentos = fechamentoRepository,
        _contasPagar = contaPagarRepository;

  final FuncionarioRepository _funcionarios;
  final FechamentoRhRepository _fechamentos;
  final ContaPagarRepository _contasPagar;

  DateTime _mes(DateTime d) => FechamentoRhRepository.normalizarMes(d);

  FuncionarioMesResumo calcularMes({
    required Funcionario funcionario,
    required DateTime mesReferencia,
    double? salarioBaseOverride,
    double? descontoFixoOverride,
  }) {
    final mes = _mes(mesReferencia);
    final lancRepo = _funcionarios.lancamentos;
    final salario = salarioBaseOverride ?? funcionario.salario;
    final descontoFixo = descontoFixoOverride ?? funcionario.descontoAtual;
    final vales = lancRepo.totalValesAtivos(funcionario.id, mesReferencia: mes);
    final descontos =
        lancRepo.totalDescontosLancados(funcionario.id, mesReferencia: mes);
    final bonus = lancRepo.totalBonus(funcionario.id, mesReferencia: mes);
    final qtdVales = lancRepo
        .listarPorFuncionario(funcionario.id, mesReferencia: mes)
        .where(
          (l) =>
              !l.estornado && l.tipo == LancamentoFuncionarioCatalogo.vale,
        )
        .length;
    final liquido = salario - descontoFixo - vales - descontos + bonus;
    final fechamento = _fechamentos.obter(funcionario.id, mes);

    return FuncionarioMesResumo(
      funcionarioId: funcionario.id,
      mesReferencia: mes,
      salarioBase: salario,
      descontoFixo: descontoFixo,
      totalVales: vales,
      totalDescontosLancados: descontos,
      totalBonus: bonus,
      qtdVales: qtdVales,
      liquidoApagar: liquido,
      fechado: fechamento != null,
      contaPagarId: fechamento?.contaPagarId ?? 0,
    );
  }

  bool mesEstaFechado(int funcionarioId, DateTime mesReferencia) =>
      _fechamentos.obter(funcionarioId, mesReferencia) != null;

  FechamentoRhFuncionario? fechamentoDe(int funcionarioId, DateTime mesReferencia) =>
      _fechamentos.obter(funcionarioId, mesReferencia);

  DateTime vencimentoFolha(Funcionario funcionario, DateTime mesReferencia) {
    final mes = _mes(mesReferencia);
    final dia = funcionario.diaPagamento.clamp(1, 31);
    final proximoMes = DateTime(mes.year, mes.month + 1, 1);
    final ultimoDia = DateTime(proximoMes.year, proximoMes.month + 1, 0).day;
    final diaEfetivo = dia > ultimoDia ? ultimoDia : dia;
    return DateTime(proximoMes.year, proximoMes.month, diaEfetivo);
  }

  Future<FechamentoRhFuncionario> fecharMes({
    required Funcionario funcionario,
    required DateTime mesReferencia,
    required String usuarioLogin,
    double? salarioBaseOverride,
    double? descontoFixoOverride,
    bool gerarContaPagar = true,
  }) async {
    final mes = _mes(mesReferencia);
    if (_fechamentos.obter(funcionario.id, mes) != null) {
      throw StateError('Mes ja fechado para este funcionario.');
    }

    final resumo = calcularMes(
      funcionario: funcionario,
      mesReferencia: mes,
      salarioBaseOverride: salarioBaseOverride,
      descontoFixoOverride: descontoFixoOverride,
    );

    var contaPagarId = 0;
    if (gerarContaPagar && resumo.liquidoApagar > 0.01) {
      final mesSlug =
          '${mes.year.toString().padLeft(4, '0')}-${mes.month.toString().padLeft(2, '0')}';
      final conta = await _contasPagar.criarManual(
        nomeFornecedor: 'Folha de pagamento — RH',
        valor: resumo.liquidoApagar,
        vencimento: vencimentoFolha(funcionario, mes),
        numeroParcela: 'FOLHA/${funcionario.codigoInterno}',
        observacaoNota:
            'RH ${funcionario.nomeCompleto} · $mesSlug · liq. folha',
      );
      contaPagarId = conta.id;
    }

    final fechamento = FechamentoRhFuncionario(
      funcionarioId: funcionario.id,
      mesReferencia: mes,
      salarioBase: resumo.salarioBase,
      descontoFixo: resumo.descontoFixo,
      totalVales: resumo.totalVales,
      totalDescontosLancados: resumo.totalDescontosLancados,
      totalBonus: resumo.totalBonus,
      liquidoApagar: resumo.liquidoApagar,
      qtdVales: resumo.qtdVales,
      contaPagarId: contaPagarId,
      fechadoPorLogin: usuarioLogin.trim(),
    );
    fechamento.id = _fechamentos.salvar(fechamento);
    return fechamento;
  }

  Future<void> reabrirMes({
    required int funcionarioId,
    required DateTime mesReferencia,
    bool cancelarContaPagarPendente = true,
  }) async {
    final mes = _mes(mesReferencia);
    final fechamento = _fechamentos.obter(funcionarioId, mes);
    if (fechamento == null) {
      throw StateError('Mes nao esta fechado.');
    }

    if (cancelarContaPagarPendente && fechamento.contaPagarId > 0) {
      final contas = _contasPagar.listar();
      ContaPagar? conta;
      for (final c in contas) {
        if (c.id == fechamento.contaPagarId) {
          conta = c;
          break;
        }
      }
      if (conta != null && conta.status == ContaPagarStatus.pendente) {
        _contasPagar.remover(conta.id);
      } else if (conta != null && conta.status != ContaPagarStatus.pendente) {
        throw StateError(
          'Titulo no financeiro ja foi baixado. Ajuste manualmente antes de reabrir.',
        );
      }
    }

    _fechamentos.remover(fechamento.id);
  }

  List<FuncionarioFolhaAlerta> alertasEquipe(DateTime mesReferencia) {
    final mes = _mes(mesReferencia);
    final alertas = <FuncionarioFolhaAlerta>[];

    for (final f in _funcionarios.listarTodos()) {
      if (!f.ativo) continue;
      final resumo = calcularMes(funcionario: f, mesReferencia: mes);
      if (resumo.fechado) continue;

      if (resumo.salarioBase > 0 &&
          resumo.pctValesSalario >= FuncionarioFolhaPolitica.pctAlertaValesSalario) {
        final pct = (resumo.pctValesSalario * 100).round();
        alertas.add(
          FuncionarioFolhaAlerta(
            tipo: FuncionarioFolhaAlertaTipo.valesAltoPercentual,
            funcionarioId: f.id,
            nome: f.nomeCompleto,
            codigo: f.codigoInterno,
            mensagem: 'Vales $pct% do salario (R\$ ${resumo.totalVales.toStringAsFixed(2)})',
          ),
        );
      }

      if (resumo.qtdVales >= FuncionarioFolhaPolitica.qtdAlertaValesMes) {
        alertas.add(
          FuncionarioFolhaAlerta(
            tipo: FuncionarioFolhaAlertaTipo.muitosValesNoMes,
            funcionarioId: f.id,
            nome: f.nomeCompleto,
            codigo: f.codigoInterno,
            mensagem: '${resumo.qtdVales} vale(s) no mes',
          ),
        );
      }
    }

    return alertas;
  }

  List<FolhaSetorLinha> relatorioPorSetor(DateTime mesReferencia) {
    final mes = _mes(mesReferencia);
    final map = <String, FolhaSetorLinha>{};

    for (final f in _funcionarios.listarTodos()) {
      final setorId = f.setor.trim().isEmpty ? 'outro' : f.setor;
      final resumo = calcularMes(funcionario: f, mesReferencia: mes);
      final atual = map[setorId];
      map[setorId] = FolhaSetorLinha(
        setorId: setorId,
        setorRotulo: FuncionarioCadastroCatalogo.rotuloSetor(setorId),
        qtdFuncionarios: (atual?.qtdFuncionarios ?? 0) + 1,
        qtdAtivos: (atual?.qtdAtivos ?? 0) + (f.ativo ? 1 : 0),
        folhaBase: (atual?.folhaBase ?? 0) + (f.ativo ? resumo.salarioBase : 0),
        totalVales: (atual?.totalVales ?? 0) + resumo.totalVales,
        liquidoEstimado:
            (atual?.liquidoEstimado ?? 0) + (f.ativo ? resumo.liquidoApagar : 0),
      );
    }

    final lista = map.values.toList()
      ..sort((a, b) => a.setorRotulo.compareTo(b.setorRotulo));
    return lista;
  }

  List<FolhaMesHistoricoItem> historicoUltimosMeses({
    required Funcionario funcionario,
    int quantidade = 12,
    double? salarioBaseOverride,
    double? descontoFixoOverride,
  }) {
    final hoje = _mes(DateTime.now());
    final itens = <FolhaMesHistoricoItem>[];
    for (var i = 0; i < quantidade; i++) {
      final mes = DateTime(hoje.year, hoje.month - i, 1);
      final resumo = calcularMes(
        funcionario: funcionario,
        mesReferencia: mes,
        salarioBaseOverride: salarioBaseOverride,
        descontoFixoOverride: descontoFixoOverride,
      );
      itens.add(
        FolhaMesHistoricoItem(
          mesReferencia: mes,
          liquidoApagar: resumo.liquidoApagar,
          fechado: resumo.fechado,
          totalVales: resumo.totalVales,
        ),
      );
    }
    return itens;
  }

  List<FuncionarioMesResumo> resumoEquipeMes(DateTime mesReferencia) {
    final mes = _mes(mesReferencia);
    return _funcionarios
        .listarTodos()
        .where((f) => f.ativo)
        .map((f) => calcularMes(funcionario: f, mesReferencia: mes))
        .toList()
      ..sort((a, b) => a.funcionarioId.compareTo(b.funcionarioId));
  }
}
