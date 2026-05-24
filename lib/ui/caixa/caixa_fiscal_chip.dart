import 'package:flutter/material.dart';

import '../../domain/caixa_fiscal_status.dart';

class CaixaFiscalChip extends StatelessWidget {
  const CaixaFiscalChip({
    super.key,
    required this.info,
    this.dense = false,
  });

  final CaixaFiscalStatusInfo info;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: info.icone != null
          ? Icon(info.icone, size: dense ? 14 : 16, color: info.cor)
          : null,
      label: Text(
        info.rotulo,
        style: TextStyle(
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: info.cor,
        ),
      ),
      visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
      padding: dense ? EdgeInsets.zero : null,
      side: BorderSide(color: info.cor.withValues(alpha: 0.5)),
      backgroundColor: info.cor.withValues(alpha: 0.08),
    );
  }
}
