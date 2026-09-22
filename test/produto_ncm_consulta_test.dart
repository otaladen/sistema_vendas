import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/produto_ncm_consulta.dart';

void main() {
  group('ProdutoNcmConsultaState', () {
    test('limpar ao trocar produto remove descricao anterior', () {
      final estado = ProdutoNcmConsultaState();
      final token = estado.iniciarConsulta();
      estado.aplicarResultadoOficial(
        token,
        '33051000',
        digitosConsultados: '33051000',
        descricaoOficial: 'Xampus',
        codigoFormatado: '3305.10.00',
      );
      estado.finalizarConsulta(token);

      expect(estado.infoExibicao, contains('Xampus'));

      estado.limpar();

      expect(estado.infoExibicao, isEmpty);
      expect(estado.consultando, isFalse);
    });

    test('alterar NCM invalida descricao e permite nova consulta', () {
      final estado = ProdutoNcmConsultaState();
      final token = estado.iniciarConsulta();
      estado.aplicarResultadoOficial(
        token,
        '33051000',
        digitosConsultados: '33051000',
        descricaoOficial: 'Xampus',
        codigoFormatado: '3305.10.00',
      );
      estado.finalizarConsulta(token);

      estado.aoEditarCampo('3305.20.00');

      expect(estado.infoExibicao, isEmpty);
      expect(estado.deveConsultarAutomaticamente('33052000'), isTrue);
    });

    test('consulta antiga nao sobrescreve NCM ja alterado', () {
      final estado = ProdutoNcmConsultaState();
      final tokenAntigo = estado.iniciarConsulta();

      estado.aoEditarCampo('12345678');
      final tokenNovo = estado.iniciarConsulta();

      estado.aplicarResultadoOficial(
        tokenAntigo,
        '12345678',
        digitosConsultados: '33051000',
        descricaoOficial: 'Obsoleto',
        codigoFormatado: '3305.10.00',
      );

      expect(estado.infoExibicao, isEmpty);

      estado.aplicarResultadoOficial(
        tokenNovo,
        '12345678',
        digitosConsultados: '12345678',
        descricaoOficial: 'Descricao correta',
        codigoFormatado: '1234.56.78',
      );

      expect(estado.infoExibicao, contains('Descricao correta'));
    });

    test('texto informativo oficial formata descricao', () {
      expect(
        ProdutoNcmConsultaState.textoInfoValido(
          descricaoOficial: 'Tintas',
          codigoFormatado: '3208.10.00',
        ),
        'NCM valido: Tintas',
      );
    });
  });
}
