import 'package:flutter/material.dart';

import '../../data/motorista_repository.dart';
import '../../model/venda.dart';
import 'logistica_entregas.dart';
import 'selecionar_motorista_dialog.dart';

/// Dialogo para escolher motorista ao agrupar pedidos na mesma viagem.
Future<String?> showAgruparViagemMotoristaDialog(
  BuildContext context,
  MotoristaRepository motoristaRepository, {
  String? motoristaSugerido,
  List<Venda> vendasSelecionadas = const [],
}) {
  final clientesDistintos = agrupamentoTemClientesDistintos(vendasSelecionadas);
  final resumoPedidos = vendasSelecionadas.isEmpty
      ? null
      : vendasSelecionadas
          .map((v) => '#${v.numeroOrcamento}')
          .join(', ');

  final buffer = StringBuffer();
  if (clientesDistintos) {
    buffer.writeln(
      'Atencao: clientes diferentes na mesma viagem do caminhao. '
      'Cada nota continua com cobranca e entrega separadas.',
    );
    buffer.writeln();
  }
  if (resumoPedidos != null) {
    buffer.writeln('Pedidos: $resumoPedidos.');
    buffer.writeln();
  }
  buffer.writeln(
    'Mesma viagem = mesmo carregamento e mesma rota. '
    'Depois de agrupar, use as setas em "Rota — ordem das paradas" '
    'para definir qual nota entrega primeiro.',
  );
  buffer.writeln();
  buffer.write(
    'Informe o motorista — na loja, cada motorista usa sempre o mesmo caminhao.',
  );

  return showSelecionarMotoristaDialog(
    context,
    motoristaRepository,
    titulo: 'Agrupar viagem (mesmo carro)',
    motoristaSugerido: motoristaSugerido,
    rotuloConfirmar: 'Confirmar agrupamento',
    textoAuxiliar: buffer.toString(),
  );
}
