import '../../data/nfe_saida_fiscal_store.dart';

/// Status exibido no filtro do historico NF-e.
enum NfeHistoricoStatusFiltro {
  todos,
  autorizada,
  processando,
  rejeitada,
  cancelada,
}

extension NfeHistoricoStatusFiltroExt on NfeHistoricoStatusFiltro {
  String get codigo {
    switch (this) {
      case NfeHistoricoStatusFiltro.todos:
        return 'todos';
      case NfeHistoricoStatusFiltro.autorizada:
        return 'autorizada';
      case NfeHistoricoStatusFiltro.processando:
        return 'processando';
      case NfeHistoricoStatusFiltro.rejeitada:
        return 'rejeitada';
      case NfeHistoricoStatusFiltro.cancelada:
        return 'cancelada';
    }
  }

  String get rotulo {
    switch (this) {
      case NfeHistoricoStatusFiltro.todos:
        return 'Todos';
      case NfeHistoricoStatusFiltro.autorizada:
        return 'Autorizadas';
      case NfeHistoricoStatusFiltro.processando:
        return 'Processando';
      case NfeHistoricoStatusFiltro.rejeitada:
        return 'Rejeitadas';
      case NfeHistoricoStatusFiltro.cancelada:
        return 'Canceladas';
    }
  }

  static NfeHistoricoStatusFiltro fromCodigo(String? v) {
    switch ((v ?? '').trim().toLowerCase()) {
      case 'autorizada':
        return NfeHistoricoStatusFiltro.autorizada;
      case 'processando':
        return NfeHistoricoStatusFiltro.processando;
      case 'rejeitada':
        return NfeHistoricoStatusFiltro.rejeitada;
      case 'cancelada':
        return NfeHistoricoStatusFiltro.cancelada;
      default:
        return NfeHistoricoStatusFiltro.todos;
    }
  }
}

/// Filtros da aba historico NF-e.
class NfeHistoricoFiltro {
  const NfeHistoricoFiltro({
    this.textoBusca = '',
    this.status = NfeHistoricoStatusFiltro.todos,
    this.dataInicio,
    this.dataFim,
  });

  final String textoBusca;
  final NfeHistoricoStatusFiltro status;
  final DateTime? dataInicio;
  final DateTime? dataFim;
}

abstract final class NfeHistoricoFiltroUtil {
  NfeHistoricoFiltroUtil._();

  static List<NfeSaidaFiscalRegistro> aplicar(
    List<NfeSaidaFiscalRegistro> origem,
    NfeHistoricoFiltro filtro,
  ) {
    final texto = filtro.textoBusca.trim().toLowerCase();
    final digitos = filtro.textoBusca.replaceAll(RegExp(r'\D'), '');

    return origem.where((r) {
      if (!_bateStatus(r, filtro.status)) return false;
      if (!_batePeriodo(r, filtro.dataInicio, filtro.dataFim)) return false;
      if (texto.isEmpty && digitos.length < 2) return true;
      if (r.clienteNome.toLowerCase().contains(texto)) return true;
      if (r.referenciaFocus.toLowerCase().contains(texto)) return true;
      if (r.chaveNfe.toLowerCase().contains(texto)) return true;
      if ('${r.numeroOrcamento}'.contains(texto)) return true;
      if ('${r.vendaId}'.contains(texto)) return true;
      if (digitos.length >= 2) {
        if (r.chaveNfe.replaceAll(RegExp(r'\D'), '').contains(digitos)) {
          return true;
        }
        if (r.numero.replaceAll(RegExp(r'\D'), '').contains(digitos)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  static bool _bateStatus(
    NfeSaidaFiscalRegistro r,
    NfeHistoricoStatusFiltro status,
  ) {
    switch (status) {
      case NfeHistoricoStatusFiltro.todos:
        return true;
      case NfeHistoricoStatusFiltro.autorizada:
        return r.autorizada;
      case NfeHistoricoStatusFiltro.processando:
        return r.processando;
      case NfeHistoricoStatusFiltro.rejeitada:
        return r.rejeitada;
      case NfeHistoricoStatusFiltro.cancelada:
        return r.cancelada;
    }
  }

  static bool _batePeriodo(
    NfeSaidaFiscalRegistro r,
    DateTime? inicio,
    DateTime? fim,
  ) {
    if (inicio == null && fim == null) return true;
    final d = r.emitidaEm.toLocal();
    if (inicio != null) {
      final i = DateTime(inicio.year, inicio.month, inicio.day);
      if (d.isBefore(i)) return false;
    }
    if (fim != null) {
      final f = DateTime(fim.year, fim.month, fim.day, 23, 59, 59);
      if (d.isAfter(f)) return false;
    }
    return true;
  }
}
