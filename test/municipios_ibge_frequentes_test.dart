import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/municipios_ibge_frequentes.dart';

void main() {
  test('reconhece codigos dos municipios frequentes', () {
    expect(
      MunicipiosIbgeFrequentes.porCodigo('2927408')?.rotulo,
      contains('Salvador'),
    );
    expect(
      MunicipiosIbgeFrequentes.selecaoParaCodigo('2919207'),
      '2919207',
    );
    expect(
      MunicipiosIbgeFrequentes.selecaoParaCodigo('1234567'),
      MunicipiosIbgeFrequentes.valorManual,
    );
  });

  test('sugere IBGE pelo nome da cidade', () {
    expect(
      MunicipiosIbgeFrequentes.sugerirPorNomeCidade('Lauro de Freitas')?.codigo,
      '2919207',
    );
    expect(
      MunicipiosIbgeFrequentes.sugerirPorNomeCidade('Camaçari')?.codigo,
      '2905701',
    );
  });
}
