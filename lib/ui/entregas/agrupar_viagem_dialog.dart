import 'package:flutter/material.dart';

import '../../data/motorista_repository.dart';
import 'selecionar_motorista_dialog.dart';

/// Dialogo para escolher motorista ao agrupar pedidos na mesma viagem.
Future<String?> showAgruparViagemMotoristaDialog(
  BuildContext context,
  MotoristaRepository motoristaRepository, {
  String? motoristaSugerido,
}) {
  return showSelecionarMotoristaDialog(
    context,
    motoristaRepository,
    titulo: 'Agrupar viagem (mesmo carro)',
    motoristaSugerido: motoristaSugerido,
    rotuloConfirmar: 'Confirmar agrupamento',
    textoAuxiliar:
        'Cada confirmacao = uma viagem (ex.: 1a saida do dia). '
        'Informe o motorista — na loja, cada motorista usa sempre o mesmo caminhao.',
  );
}
