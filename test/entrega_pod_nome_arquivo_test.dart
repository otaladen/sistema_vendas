import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_pod_nome_arquivo.dart';

void main() {
  test('valido aceita padrao venda_id_data_hora', () {
    expect(
      EntregaPodNomeArquivo.valido('venda_42_20260522_153045.jpg'),
      isTrue,
    );
  });

  test('valido rejeita path traversal e nomes invalidos', () {
    expect(EntregaPodNomeArquivo.valido('../venda_1.jpg'), isFalse);
    expect(EntregaPodNomeArquivo.valido('foto.jpg'), isFalse);
    expect(EntregaPodNomeArquivo.valido(''), isFalse);
  });

  test('extrairNomeArquivo de caminho relativo servidor', () {
    expect(
      EntregaPodNomeArquivo.extrairNomeArquivo(
        r'pod_entrega\venda_10_20260101_120000.jpg',
      ),
      'venda_10_20260101_120000.jpg',
    );
    expect(
      EntregaPodNomeArquivo.extrairNomeArquivo('pod_entrega/invalido.png'),
      isNull,
    );
  });
}
