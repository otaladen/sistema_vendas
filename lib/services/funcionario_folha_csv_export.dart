import 'package:intl/intl.dart';

import '../domain/funcionario_cadastro_catalogo.dart';
import '../domain/funcionario_folha_resumo.dart';
import '../domain/lancamento_funcionario_catalogo.dart';
import '../model/fechamento_rh_funcionario.dart';
import '../model/funcionario.dart';
import '../model/lancamento_funcionario.dart';

final NumberFormat _moedaCsv = NumberFormat('#,##0.00', 'pt_BR');
final DateFormat _dataCsv = DateFormat('dd/MM/yyyy');
final DateFormat _mesCsv = DateFormat('yyyy-MM');

String _celula(String v) {
  if (v.contains(';') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

String _linha(List<String> cols) => cols.map(_celula).join(';');

/// CSV da folha da equipe no mes (contador / Excel).
String gerarCsvFolhaEquipeMes({
  required DateTime mesReferencia,
  required List<Funcionario> funcionarios,
  required List<FuncionarioMesResumo> resumos,
  required List<FechamentoRhFuncionario> fechamentos,
}) {
  final mes = _mesCsv.format(mesReferencia);
  final fechPorFunc = {
    for (final f in fechamentos) f.funcionarioId: f,
  };
  final resumoPorFunc = {for (final r in resumos) r.funcionarioId: r};

  final buf = StringBuffer()
    ..writeln(_linha([
      'Mes',
      'Codigo',
      'Nome',
      'Setor',
      'Funcao',
      'Salario base',
      'Desconto fixo',
      'Vales',
      'Descontos lancados',
      'Bonus',
      'Liquido',
      'Qtd vales',
      'Mes fechado',
      'Conta pagar ID',
    ]));

  for (final f in funcionarios) {
    if (!f.ativo) continue;
    final r = resumoPorFunc[f.id];
    if (r == null) continue;
    final fech = fechPorFunc[f.id];
    buf.writeln(_linha([
      mes,
      f.codigoInterno,
      f.nomeCompleto,
      FuncionarioCadastroCatalogo.rotuloSetor(f.setor),
      FuncionarioCadastroCatalogo.resumoSetorFuncao(
        setor: f.setor,
        funcao: f.funcao,
        funcaoOutro: f.funcaoOutro,
        cargoLegado: f.cargo,
      ),
      _moedaCsv.format(r.salarioBase),
      _moedaCsv.format(r.descontoFixo),
      _moedaCsv.format(r.totalVales),
      _moedaCsv.format(r.totalDescontosLancados),
      _moedaCsv.format(r.totalBonus),
      _moedaCsv.format(r.liquidoApagar),
      '${r.qtdVales}',
      fech != null ? 'SIM' : 'NAO',
      fech != null && fech.contaPagarId > 0 ? '${fech.contaPagarId}' : '',
    ]));
  }

  return buf.toString();
}

/// CSV dos lancamentos de um funcionario no ano.
String gerarCsvLancamentosAno({
  required Funcionario funcionario,
  required int ano,
  required List<LancamentoFuncionario> lancamentos,
}) {
  final buf = StringBuffer()
    ..writeln(_linha([
      'Ano',
      'Codigo funcionario',
      'Nome',
      'Data',
      'Tipo',
      'Valor',
      'Observacao',
      'Estornado',
    ]));

  for (final l in lancamentos) {
    if (l.data.year != ano) continue;
    buf.writeln(_linha([
      '$ano',
      funcionario.codigoInterno,
      funcionario.nomeCompleto,
      _dataCsv.format(l.data.toLocal()),
      LancamentoFuncionarioCatalogo.rotulo(l.tipo),
      LancamentoFuncionarioCatalogo.exigeValor(l.tipo)
          ? _moedaCsv.format(l.valor)
          : '',
      l.observacao,
      l.estornado ? 'SIM' : 'NAO',
    ]));
  }

  return buf.toString();
}

/// CSV do relatorio por setor.
String gerarCsvRelatorioSetor({
  required DateTime mesReferencia,
  required List<FolhaSetorLinha> linhas,
}) {
  final mes = _mesCsv.format(mesReferencia);
  final buf = StringBuffer()
    ..writeln(_linha([
      'Mes',
      'Setor',
      'Funcionarios',
      'Ativos',
      'Folha base',
      'Total vales',
      'Liquido estimado',
    ]));

  for (final l in linhas) {
    buf.writeln(_linha([
      mes,
      l.setorRotulo,
      '${l.qtdFuncionarios}',
      '${l.qtdAtivos}',
      _moedaCsv.format(l.folhaBase),
      _moedaCsv.format(l.totalVales),
      _moedaCsv.format(l.liquidoEstimado),
    ]));
  }

  return buf.toString();
}
