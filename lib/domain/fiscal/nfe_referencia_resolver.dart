import '../../data/nfe_saida_fiscal_store.dart';
import '../../model/venda.dart';

/// Gera referencia Focus para NF-e 55 (retry vs nova sequencia).
abstract final class NfeReferenciaResolver {
  NfeReferenciaResolver._();

  static String base(int vendaId) => 'venda_${vendaId}_nfe';

  static int extrairSequencia(String referencia) {
    final ref = referencia.trim();
    final m = RegExp(r'_nfe_(\d+)$').firstMatch(ref);
    if (m != null) return int.tryParse(m.group(1) ?? '') ?? 2;
    if (ref.endsWith('_nfe')) return 1;
    return 0;
  }

  static String comSequencia(int vendaId, int sequencia) {
    if (sequencia <= 1) return base(vendaId);
    return '${base(vendaId)}_$sequencia';
  }

  /// Referencia para proxima tentativa de emissao.
  static String proximaParaEmissao({
    required Venda venda,
    NfeSaidaFiscalRegistro? ultimaLocal,
    List<NfeSaidaFiscalRegistro> historicoVenda = const [],
  }) {
    final id = venda.id;
    if (id <= 0) {
      return 'venda_tmp_${DateTime.now().millisecondsSinceEpoch}_nfe';
    }

    final refs = <String>{};
    for (final r in historicoVenda) {
      if (r.referenciaFocus.trim().isNotEmpty) refs.add(r.referenciaFocus.trim());
    }
    if (venda.nfeReferenciaFocus.trim().isNotEmpty) {
      refs.add(venda.nfeReferenciaFocus.trim());
    }

    var maxSeq = 0;
    for (final ref in refs) {
      final s = extrairSequencia(ref);
      if (s > maxSeq) maxSeq = s;
    }

    final ultima = ultimaLocal ??
        (historicoVenda.isNotEmpty ? historicoVenda.first : null);

    if (ultima != null) {
      if (ultima.rejeitada || ultima.processando) {
        return ultima.referenciaFocus.isNotEmpty
            ? ultima.referenciaFocus
            : comSequencia(id, maxSeq > 0 ? maxSeq : 1);
      }
      if (ultima.autorizada || ultima.cancelada) {
        return comSequencia(id, maxSeq + 1);
      }
    }

    if (venda.nfe55Autorizada || venda.nfe55Cancelada) {
      return comSequencia(id, maxSeq + 1);
    }

    if (venda.nfe55Rejeitada || venda.nfe55Processando) {
      final ref = venda.nfeReferenciaFocus.trim();
      if (ref.isNotEmpty) return ref;
    }

    return comSequencia(id, maxSeq > 0 ? maxSeq : 1);
  }
}
