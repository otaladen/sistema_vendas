import 'package:flutter/foundation.dart';

import '../../domain/lancamento_funcionario_catalogo.dart';
import '../../model/funcionario.dart';
import '../../model/lancamento_funcionario.dart';
import '../../model/motorista.dart';
import '../sync/sync_entity_codec_extras.dart';
import 'lan_api_client.dart';
import 'lan_api_event_hub.dart';

class FuncionarioApiRepository extends ChangeNotifier {
  FuncionarioApiRepository(this._client);

  final LanApiClient _client;
  List<Funcionario> _lista = [];
  List<LancamentoFuncionario> _lancamentos = [];

  bool get _offline => LanApiEventHub.instance.deveBloquearOperacoes;

  void _exigirServidorOnline() {
    if (_offline) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  Future<void> hidratar() async {
    _exigirServidorOnline();
    final raw = await _client.listarFuncionarios();
    _lista = raw
        .map(SyncEntityCodecExtras.funcionarioDeMap)
        .toList(growable: false);

    // Servidor antigo exige funcionarioId; novo aceita lista geral.
    final acumulado = <LancamentoFuncionario>[];
    try {
      final lan = await _client.listarLancamentosRh();
      acumulado.addAll(
        lan.map(SyncEntityCodecExtras.lancamentoFuncionarioDeMap),
      );
    } on LanApiException {
      for (final f in _lista) {
        if (f.id <= 0) continue;
        try {
          final lan = await _client.listarLancamentosRh(funcionarioId: f.id);
          acumulado.addAll(
            lan.map(SyncEntityCodecExtras.lancamentoFuncionarioDeMap),
          );
        } on LanApiException {
          // Ignora funcionario isolado.
        }
      }
    } catch (_) {
      // RH opcional no boot do terminal.
    }
    _lancamentos = List.unmodifiable(acumulado);
    notifyListeners();
  }

  List<Funcionario> listarTodos() => List.unmodifiable(_lista);

  Funcionario? obterPorId(int id) {
    for (final f in _lista) {
      if (f.id == id) return f;
    }
    return null;
  }

  Funcionario? obterPorUsuarioSistemaId(String usuarioId) {
    final id = usuarioId.trim();
    if (id.isEmpty) return null;
    for (final f in _lista) {
      if (f.usuarioSistemaId.trim() == id) return f;
    }
    return null;
  }

  String proximoCodigoInterno() {
    var maior = 0;
    for (final f in _lista) {
      final digits = f.codigoInterno.replaceAll(RegExp(r'\D'), '');
      final numero = int.tryParse(digits);
      if (numero != null && numero > maior) {
        maior = numero;
      }
    }
    return (maior + 1).toString();
  }

  List<Funcionario> pesquisar(String termo) {
    if (_offline) return const [];
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) return listarTodos();
    final digitos = termo.replaceAll(RegExp(r'\D'), '');
    return _lista.where((f) {
      if (f.nomeCompleto.toLowerCase().contains(t) ||
          f.codigoInterno.toLowerCase().contains(t) ||
          f.cargo.toLowerCase().contains(t) ||
          f.setor.toLowerCase().contains(t) ||
          f.funcao.toLowerCase().contains(t) ||
          f.cpf.toLowerCase().contains(t) ||
          f.telefone.contains(t) ||
          f.whatsapp.contains(t)) {
        return true;
      }
      if (digitos.isEmpty) return false;
      final nums = [
        f.cpf,
        f.telefone,
        f.whatsapp,
        f.pis,
      ].map((s) => s.replaceAll(RegExp(r'\D'), ''));
      return nums.any((n) => n.contains(digitos));
    }).toList();
  }

  bool existeCpfParaOutro({
    required String cpfSomenteDigitos,
    required int ignorarId,
  }) {
    final cpf = cpfSomenteDigitos.replaceAll(RegExp(r'\D'), '');
    if (cpf.length != 11) return false;
    for (final f in _lista) {
      if (f.id == ignorarId) continue;
      final outro = f.cpf.replaceAll(RegExp(r'\D'), '');
      if (outro == cpf) return true;
    }
    return false;
  }

  bool existeCodigoParaOutro({
    required String codigoNormalizado,
    required int ignorarId,
  }) {
    final c = codigoNormalizado.trim().toLowerCase();
    if (c.isEmpty) return false;
    for (final f in _lista) {
      if (f.id != ignorarId && f.codigoInterno.trim().toLowerCase() == c) {
        return true;
      }
    }
    return false;
  }

  bool existeMotoristaParaOutro({
    required int motoristaId,
    required int ignorarId,
  }) {
    if (motoristaId <= 0) return false;
    for (final f in _lista) {
      if (f.id != ignorarId && f.motoristaId == motoristaId) return true;
    }
    return false;
  }

  bool existeUsuarioParaOutro({
    required String usuarioId,
    required int ignorarId,
  }) {
    final id = usuarioId.trim();
    if (id.isEmpty) return false;
    for (final f in _lista) {
      if (f.id != ignorarId && f.usuarioSistemaId == id) return true;
    }
    return false;
  }

  Future<int> salvarRemoto(Funcionario f) async {
    _exigirServidorOnline();
    final id = await _client.salvarFuncionario({
      'funcionario': SyncEntityCodecExtras.funcionarioParaMap(f),
    });
    await hidratar();
    return id;
  }

  int salvar(Funcionario f) {
    throw StateError('Use salvarRemoto() no terminal leve.');
  }

  bool remover(int id) {
    throw StateError(
      'Terminal leve: use removerRemoto (async) no cadastro de funcionarios.',
    );
  }

  Future<bool> removerRemoto(int id) async {
    _exigirServidorOnline();
    final ok = await _client.removerFuncionario(id);
    if (ok) {
      _lista = _lista.where((f) => f.id != id).toList(growable: false);
      notifyListeners();
    }
    return ok;
  }

  int contarFuncionariosComFotoPath(
    String path, {
    int? excluirFuncionarioId,
  }) =>
      0;

  String get funcionarioImagesDirPath => '';

  Never get objectBox => throw StateError(
        'Terminal leve: sem ObjectBox local em funcionarios.',
      );

  Never get fechamentos => throw StateError(
        'Fechamento RH avancado so no PC servidor (terminal leve).',
      );

  LancamentosApiFacade get lancamentos => LancamentosApiFacade(this);
}

/// Facade duck-typed como [LancamentoFuncionarioRepository] para a UI.
class LancamentosApiFacade {
  LancamentosApiFacade(this._parent);
  final FuncionarioApiRepository _parent;

  List<LancamentoFuncionario> listarPorFuncionario(
    int funcionarioId, {
    DateTime? mesReferencia,
  }) {
    var lista = _parent._lancamentos
        .where((l) => l.funcionario.targetId == funcionarioId)
        .toList();
    if (mesReferencia != null) {
      final inicio = DateTime(mesReferencia.year, mesReferencia.month, 1);
      final fim = DateTime(
        mesReferencia.year,
        mesReferencia.month + 1,
        0,
        23,
        59,
        59,
      );
      lista = lista
          .where(
            (l) => !l.data.isBefore(inicio) && !l.data.isAfter(fim),
          )
          .toList();
    }
    lista.sort((a, b) => b.data.compareTo(a.data));
    return lista;
  }

  List<LancamentoFuncionario> listarPorFuncionarioAno(
    int funcionarioId,
    int ano,
  ) {
    return _parent._lancamentos
        .where(
          (l) =>
              l.funcionario.targetId == funcionarioId && l.data.year == ano,
        )
        .toList()
      ..sort((a, b) => b.data.compareTo(a.data));
  }

  void migrarLegadoSeNecessario(Funcionario f) {}

  double totalValesAtivos(int funcionarioId, {DateTime? mesReferencia}) {
    return listarPorFuncionario(funcionarioId, mesReferencia: mesReferencia)
        .where(
          (l) =>
              !l.estornado && l.tipo == LancamentoFuncionarioCatalogo.vale,
        )
        .fold<double>(0, (s, l) => s + l.valor);
  }

  double totalDescontosLancados(int funcionarioId, {DateTime? mesReferencia}) {
    return listarPorFuncionario(funcionarioId, mesReferencia: mesReferencia)
        .where(
          (l) =>
              !l.estornado &&
              l.tipo == LancamentoFuncionarioCatalogo.desconto,
        )
        .fold<double>(0, (s, l) => s + l.valor);
  }

  double totalBonus(int funcionarioId, {DateTime? mesReferencia}) {
    return listarPorFuncionario(funcionarioId, mesReferencia: mesReferencia)
        .where(
          (l) =>
              !l.estornado && l.tipo == LancamentoFuncionarioCatalogo.bonus,
        )
        .fold<double>(0, (s, l) => s + l.valor);
  }

  Future<int> salvarRemoto(LancamentoFuncionario l, [int? funcionarioId]) async {
    _parent._exigirServidorOnline();
    final fid = (funcionarioId != null && funcionarioId > 0)
        ? funcionarioId
        : l.funcionario.targetId;
    if (fid <= 0) {
      throw StateError('funcionarioId obrigatorio para salvar lancamento RH.');
    }
    l.funcionario.targetId = fid;
    final id = await _parent._client.salvarLancamentoRh({
      'funcionarioId': fid,
      'lancamento': SyncEntityCodecExtras.lancamentoFuncionarioParaMap(l),
    });
    await _parent.hidratar();
    return id;
  }

  int salvar(LancamentoFuncionario l, int funcionarioId) {
    throw StateError('Use salvarRemoto() no terminal leve.');
  }

  void estornar(int id) {
    throw StateError(
      'Terminal leve: use estornarRemoto (async) no cadastro de funcionarios.',
    );
  }

  Future<void> estornarRemoto(int id) async {
    _parent._exigirServidorOnline();
    await _parent._client.estornarLancamentoRh(id);
    await _parent.hidratar();
  }
}

class MotoristaApiRepository extends ChangeNotifier {
  MotoristaApiRepository(this._client);

  final LanApiClient _client;
  List<Motorista> _lista = [];

  bool get _offline => LanApiEventHub.instance.deveBloquearOperacoes;

  void _exigirServidorOnline() {
    if (_offline) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  Future<void> hidratar() async {
    _exigirServidorOnline();
    final raw = await _client.listarMotoristas();
    _lista = raw
        .map(SyncEntityCodecExtras.motoristaDeMap)
        .toList(growable: false);
    notifyListeners();
  }

  List<Motorista> listarTodos() => List.unmodifiable(_lista);
  List<Motorista> listarAtivos() =>
      _lista.where((m) => m.ativo).toList(growable: false);

  List<Motorista> pesquisar(String termo) {
    if (_offline) return const [];
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) return listarTodos();
    final digitos = termo.replaceAll(RegExp(r'\D'), '');
    return _lista.where((m) {
      if (m.nome.toLowerCase().contains(t) ||
          m.telefone.toLowerCase().contains(t) ||
          m.codigoInterno.toLowerCase().contains(t) ||
          m.cpf.toLowerCase().contains(t) ||
          m.cnhNumero.toLowerCase().contains(t) ||
          m.cnhCategoria.toLowerCase().contains(t)) {
        return true;
      }
      if (digitos.isEmpty) return false;
      final nums = [
        m.telefone,
        m.cpf,
        m.cnhNumero,
      ].map((s) => s.replaceAll(RegExp(r'\D'), ''));
      return nums.any((n) => n.contains(digitos));
    }).toList(growable: false);
  }

  Motorista? obterPorId(int id) {
    for (final m in _lista) {
      if (m.id == id) return m;
    }
    return null;
  }

  String proximoCodigoInterno() {
    var maior = 0;
    for (final m in _lista) {
      final digits = m.codigoInterno.replaceAll(RegExp(r'\D'), '');
      final n = int.tryParse(digits);
      if (n != null && n > maior) maior = n;
    }
    return (maior + 1).toString();
  }

  bool existeNomeParaOutro({
    required String nomeNormalizado,
    required int ignorarId,
  }) {
    final n = nomeNormalizado.trim().toLowerCase();
    if (n.isEmpty) return false;
    for (final m in _lista) {
      if (m.id != ignorarId && m.nome.trim().toLowerCase() == n) {
        return true;
      }
    }
    return false;
  }

  bool existeCodigoParaOutro({
    required String codigoNormalizado,
    required int ignorarId,
  }) {
    final c = codigoNormalizado.trim().toLowerCase();
    if (c.isEmpty) return false;
    for (final m in _lista) {
      if (m.id != ignorarId && m.codigoInterno.trim().toLowerCase() == c) {
        return true;
      }
    }
    return false;
  }

  bool existeCpfParaOutro({
    required String cpfSomenteDigitos,
    required int ignorarId,
  }) {
    final cpf = cpfSomenteDigitos.replaceAll(RegExp(r'\D'), '');
    if (cpf.length != 11) return false;
    for (final m in _lista) {
      if (m.id == ignorarId) continue;
      if (m.cpf.replaceAll(RegExp(r'\D'), '') == cpf) return true;
    }
    return false;
  }

  bool existeCnhParaOutro({
    required String cnhSomenteDigitos,
    required int ignorarId,
  }) {
    final cnh = cnhSomenteDigitos.replaceAll(RegExp(r'\D'), '');
    if (cnh.isEmpty) return false;
    for (final m in _lista) {
      if (m.id == ignorarId) continue;
      if (m.cnhNumero.replaceAll(RegExp(r'\D'), '') == cnh) return true;
    }
    return false;
  }

  Future<int> salvarRemoto(Motorista m) async {
    _exigirServidorOnline();
    final id = await _client.salvarMotorista({
      'motorista': SyncEntityCodecExtras.motoristaParaMap(m),
    });
    await hidratar();
    return id;
  }

  int salvar(Motorista m) {
    throw StateError('Use salvarRemoto() no terminal leve.');
  }

  bool remover(int id) {
    throw StateError(
      'Terminal leve: use removerRemoto (async) no cadastro de motoristas.',
    );
  }

  Future<bool> removerRemoto(int id) async {
    _exigirServidorOnline();
    final ok = await _client.removerMotorista(id);
    if (ok) {
      _lista = _lista.where((m) => m.id != id).toList(growable: false);
      notifyListeners();
    }
    return ok;
  }
}
