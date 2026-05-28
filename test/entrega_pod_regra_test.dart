import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_pod_regra.dart';

void main() {
  test('deveSolicitarPod na primeira entrega', () {
    expect(
      EntregaPodRegra.deveSolicitarPod(
        novoStatus: 'entregue',
        statusAnterior: 'saiu_entrega',
        podRecebidoPorAtual: '',
      ),
      isTrue,
    );
  });

  test('deveSolicitarPod nao repete se ja tem POD', () {
    expect(
      EntregaPodRegra.deveSolicitarPod(
        novoStatus: 'entregue',
        statusAnterior: 'saiu_entrega',
        podRecebidoPorAtual: 'Maria',
      ),
      isFalse,
    );
  });

  test('deveSolicitarPod no complemento mesmo com POD anterior', () {
    expect(
      EntregaPodRegra.deveSolicitarPod(
        novoStatus: 'entregue',
        statusAnterior: 'entregue_complemento_pendente',
        podRecebidoPorAtual: 'Maria',
      ),
      isTrue,
    );
  });

  test('temReferenciaFoto aceita caminho local ou servidor', () {
    expect(
      EntregaPodRegra.temReferenciaFoto(
        podFotoPath: '',
        podFotoPathServidor: 'pod_entrega/venda_1.jpg',
      ),
      isTrue,
    );
  });
}
