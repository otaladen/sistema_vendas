import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pdv_busca_inteligente.dart';

void main() {
  group('PdvBuscaInteligenteHelper.permiteAutoSemEnter', () {
    test('digitacao manual nunca adiciona sozinha', () {
      expect(
        PdvBuscaInteligenteHelper.permiteAutoSemEnter(
          'areia',
          entradaViaLeitor: false,
        ),
        isFalse,
      );
    });

    test('leitor adiciona sem Enter', () {
      expect(
        PdvBuscaInteligenteHelper.permiteAutoSemEnter(
          '7891234567890',
          entradaViaLeitor: true,
        ),
        isTrue,
      );
    });

    test('bloqueia auto com curingas', () {
      expect(
        PdvBuscaInteligenteHelper.permiteAutoSemEnter(
          'tub%25',
          entradaViaLeitor: true,
        ),
        isFalse,
      );
    });
  });

  group('DetectorEntradaLeitorCodigo', () {
    late DateTime agora;
    late DetectorEntradaLeitorCodigo detector;

    setUp(() {
      agora = DateTime(2026, 9, 26, 10);
      detector = DetectorEntradaLeitorCodigo(relogio: () => agora);
    });

    void digitar(String texto, Duration intervalo) {
      var atual = '';
      for (final ch in texto.split('')) {
        agora = agora.add(intervalo);
        atual += ch;
        detector.registrarTexto(atual);
      }
    }

    test('caracteres com menos de 30ms entre si = leitor', () {
      digitar('7891234567890', const Duration(milliseconds: 8));
      expect(detector.pareceLeitor('7891234567890'), isTrue);
    });

    test('digitacao humana nao e leitor, mesmo sendo EAN', () {
      digitar('7891234567890', const Duration(milliseconds: 140));
      expect(detector.pareceLeitor('7891234567890'), isFalse);
    });

    test('3 letras digitadas nao disparam', () {
      digitar('cim', const Duration(milliseconds: 90));
      expect(detector.pareceLeitor('cim'), isFalse);
    });

    test('pausa no meio invalida a sequencia rapida', () {
      digitar('789123', const Duration(milliseconds: 8));
      agora = agora.add(const Duration(milliseconds: 400));
      detector.registrarTexto('7891234');
      expect(detector.pareceLeitor('7891234'), isFalse);
    });

    test('quantidade digitada antes e codigo lido depois', () {
      digitar('3 ', const Duration(milliseconds: 200));
      agora = agora.add(const Duration(milliseconds: 500));
      var atual = '3 ';
      for (final ch in '7891234567890'.split('')) {
        atual += ch;
        detector.registrarTexto(atual);
        agora = agora.add(const Duration(milliseconds: 6));
      }
      expect(detector.pareceLeitor('7891234567890'), isTrue);
    });

    test('apagar texto reinicia contagem', () {
      digitar('7891234567890', const Duration(milliseconds: 8));
      agora = agora.add(const Duration(milliseconds: 8));
      detector.registrarTexto('');
      expect(detector.pareceLeitor('7891234567890'), isFalse);
    });
  });
}
