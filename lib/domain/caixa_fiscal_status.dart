import 'package:flutter/material.dart';

import '../model/venda.dart';

enum CaixaFiscalStatusTipo {
  pendenteOrcamento,
  emitida,
  aguardandoEmissao,
}

class CaixaFiscalStatusInfo {
  const CaixaFiscalStatusInfo({
    required this.tipo,
    required this.rotulo,
    required this.cor,
    this.icone,
  });

  final CaixaFiscalStatusTipo tipo;
  final String rotulo;
  final Color cor;
  final IconData? icone;
}

class CaixaFiscalStatusHelper {
  CaixaFiscalStatusHelper._();

  static CaixaFiscalStatusInfo deVenda(Venda v, {required bool orcamentoPendente}) {
    if (v.nfceEmitida) {
      final num = v.nfceNumero.trim();
      final rotulo = num.isNotEmpty ? 'NFC-e $num' : 'NFC-e emitida';
      return CaixaFiscalStatusInfo(
        tipo: CaixaFiscalStatusTipo.emitida,
        rotulo: rotulo,
        cor: Colors.green.shade700,
        icone: Icons.verified_outlined,
      );
    }
    if (orcamentoPendente) {
      return const CaixaFiscalStatusInfo(
        tipo: CaixaFiscalStatusTipo.pendenteOrcamento,
        rotulo: 'Fiscal na finalizacao',
        cor: Color(0xFF546E7A),
        icone: Icons.receipt_outlined,
      );
    }
    return CaixaFiscalStatusInfo(
      tipo: CaixaFiscalStatusTipo.aguardandoEmissao,
      rotulo: 'Sem NFC-e',
      cor: Colors.orange.shade800,
      icone: Icons.warning_amber_outlined,
    );
  }
}
