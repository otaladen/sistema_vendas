import 'package:flutter/material.dart';

import '../../domain/caixa_fiscal_status.dart';
import '../theme/app_semantic_helper.dart';

extension CaixaFiscalStatusInfoTheme on CaixaFiscalStatusInfo {
  Color cor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    switch (tipo) {
      case CaixaFiscalStatusTipo.pendenteOrcamento:
        return scheme.onSurfaceVariant;
      case CaixaFiscalStatusTipo.emitida:
      case CaixaFiscalStatusTipo.aguardandoEmissao:
        return destaqueAlerta ? semantic.warningFg : semantic.successFg;
    }
  }
}

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
    final cor = info.cor(context);
    return Chip(
      avatar: info.icone != null
          ? Icon(info.icone, size: dense ? 14 : 16, color: cor)
          : null,
      label: Text(
        info.rotulo,
        style: TextStyle(
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: cor,
        ),
      ),
      visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
      padding: dense ? EdgeInsets.zero : null,
      side: BorderSide(color: cor.withValues(alpha: 0.5)),
      backgroundColor: cor.withValues(alpha: 0.08),
    );
  }
}
