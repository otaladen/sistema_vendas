import 'package:flutter/material.dart';

import '../model/venda.dart';
import 'venda_documento_rotulo_helper.dart';

enum CaixaFiscalStatusTipo {
  pendenteOrcamento,
  emitida,
  aguardandoEmissao,
}

class CaixaFiscalStatusInfo {
  const CaixaFiscalStatusInfo({
    required this.tipo,
    required this.rotulo,
    this.destaqueAlerta = false,
    this.icone,
  });

  final CaixaFiscalStatusTipo tipo;
  final String rotulo;
  /// Em [emitida] ou [aguardandoEmissao]: false = ok, true = pendencia fiscal/estoque.
  final bool destaqueAlerta;
  final IconData? icone;
}

class CaixaFiscalStatusHelper {
  CaixaFiscalStatusHelper._();

  static CaixaFiscalStatusInfo deVenda(Venda v, {required bool orcamentoPendente}) {
    if (v.nfceEmitida) {
      final partes = <String>[];
      final nfce = VendaDocumentoRotuloHelper.rotuloNfce(v);
      if (nfce != null) partes.add(nfce);
      if (v.estoqueBaixadoCupom) {
        partes.add('Estoque OK');
      }
      final rotulo = partes.isEmpty
          ? 'NFC-e emitida'
          : partes.join(' · ');
      return CaixaFiscalStatusInfo(
        tipo: CaixaFiscalStatusTipo.emitida,
        rotulo: rotulo,
        destaqueAlerta: !v.estoqueBaixadoCupom,
        icone: v.estoqueBaixadoCupom
            ? Icons.verified_outlined
            : Icons.warning_amber_outlined,
      );
    }
    if (orcamentoPendente) {
      return const CaixaFiscalStatusInfo(
        tipo: CaixaFiscalStatusTipo.pendenteOrcamento,
        rotulo: 'Fiscal na finalizacao',
        icone: Icons.receipt_outlined,
      );
    }
    return CaixaFiscalStatusInfo(
      tipo: CaixaFiscalStatusTipo.aguardandoEmissao,
      rotulo: v.estoqueBaixadoCupom
          ? 'Estoque OK · aguardando NFC-e'
          : 'Sem NFC-e',
      destaqueAlerta: !v.estoqueBaixadoCupom,
      icone: v.estoqueBaixadoCupom
          ? Icons.inventory_2_outlined
          : Icons.warning_amber_outlined,
    );
  }
}
