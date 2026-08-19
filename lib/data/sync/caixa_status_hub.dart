import 'package:flutter/foundation.dart';

import '../../model/caixa_sessao.dart';
import '../caixa_sessao_repository.dart';

/// Status de caixa da **loja** (alguma sessao aberta), compartilhado entre
/// tela Caixa e KPI do Menu principal no mesmo processo.
class CaixaStatusHub extends ChangeNotifier {
  CaixaStatusHub._();
  static final CaixaStatusHub instance = CaixaStatusHub._();

  bool _lojaAberta = false;
  String _operador = '';
  String _terminalId = '';
  bool _hidratado = false;

  bool get lojaAberta => _lojaAberta;
  String get operador => _operador;
  String get terminalId => _terminalId;
  bool get hidratado => _hidratado;

  void publicar({
    required bool aberto,
    String operador = '',
    String terminalId = '',
  }) {
    final op = operador.trim();
    final tid = terminalId.trim();
    if (_hidratado &&
        _lojaAberta == aberto &&
        _operador == op &&
        _terminalId == tid) {
      return;
    }
    _lojaAberta = aberto;
    _operador = op;
    _terminalId = tid;
    _hidratado = true;
    notifyListeners();
  }

  void publicarDasSessoes(Map<String, CaixaSessao> sessoes) {
    CaixaSessao? aberta;
    for (final s in sessoes.values) {
      if (s.aberto) {
        aberta = s;
        break;
      }
    }
    publicar(
      aberto: aberta != null,
      operador: aberta?.operador ?? '',
      terminalId: aberta?.terminalId ?? '',
    );
  }

  Future<void> sincronizarDoRepositorio() async {
    try {
      final todas = await CaixaSessaoRepository().listarTodasSessoes();
      publicarDasSessoes(todas);
    } catch (_) {
      // Mantem ultimo status conhecido.
    }
  }
}
