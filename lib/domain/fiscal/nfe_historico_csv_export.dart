import 'package:intl/intl.dart';

import '../../data/nfe_saida_fiscal_store.dart';

/// Exporta historico NF-e para CSV (contabilidade / conferencia).
abstract final class NfeHistoricoCsvExport {
  NfeHistoricoCsvExport._();

  static final _dataHora = DateFormat('dd/MM/yyyy HH:mm');
  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');

  static String gerar(List<NfeSaidaFiscalRegistro> registros) {
    final buf = StringBuffer();
    buf.writeln(
      'Data;Status;Venda;Cliente;Numero NF-e;Serie;Chave;Referencia Focus;'
      'Valor;Protocolo;Mensagem SEFAZ',
    );
    for (final r in registros) {
      buf.writeln(
        [
          _dataHora.format(r.emitidaEm.toLocal()),
          r.rotuloStatus,
          r.numeroOrcamento > 0 ? r.numeroOrcamento : r.vendaId,
          _csv(r.clienteNome),
          _csv(r.numero),
          _csv(r.serie),
          _csv(r.chaveNfe),
          _csv(r.referenciaFocus),
          _moeda.format(r.valorTotal),
          _csv(r.protocolo),
          _csv(r.mensagemSefaz),
        ].join(';'),
      );
    }
    return buf.toString();
  }

  static String _csv(String v) {
    final t = v.replaceAll(';', ',').replaceAll('\n', ' ').trim();
    if (t.contains('"') || t.contains(';')) {
      return '"${t.replaceAll('"', '""')}"';
    }
    return t;
  }
}
