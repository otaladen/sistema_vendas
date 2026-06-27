import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pdv_busca_inteligente.dart';

void main() {
  group('PdvBuscaInteligenteHelper', () {
    test('permite auto com codigo de barras mesmo termo curto', () {
      expect(
        PdvBuscaInteligenteHelper.permiteAutoEnquantoDigita(
          '789',
          matchCodigoBarras: true,
        ),
        isTrue,
      );
    });

    test('bloqueia auto enquanto digita termo muito curto', () {
      expect(
        PdvBuscaInteligenteHelper.permiteAutoEnquantoDigita(
          'ar',
          matchCodigoBarras: false,
        ),
        isFalse,
      );
    });

    test('permite auto enquanto digita termo com 3+ letras', () {
      expect(
        PdvBuscaInteligenteHelper.permiteAutoEnquantoDigita(
          'areia',
          matchCodigoBarras: false,
        ),
        isTrue,
      );
    });

    test('bloqueia auto com curingas', () {
      expect(
        PdvBuscaInteligenteHelper.permiteAutoEnquantoDigita(
          'tub%25',
          matchCodigoBarras: false,
        ),
        isFalse,
      );
    });
  });
}
