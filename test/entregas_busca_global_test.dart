import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_busca_texto.dart';
import 'package:sistema_vendas/domain/entrega_filtro_util.dart';
import 'package:sistema_vendas/domain/filtro_listagem_entregas.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  final diaAntigo = DateTime(2024, 3, 10);
  final hoje = DateTime.now();
  final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);
  final fimHoje = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59, 999);

  Venda entregaAntiga({
    required int id,
    int numeroControle = 0,
    String endereco = 'Centro | Rua A',
  }) {
    return Venda(
      id: id,
      status: 'finalizada',
      statusEntrega: 'pendente',
      tipoEntrega: 'entrega_loja',
      dataEntregaMarcada: diaAntigo,
      numeroControle: numeroControle,
      enderecoEntrega: endereco,
    );
  }

  test('busca global ignora filtro de data marcada (hoje)', () {
    final vAntiga = entregaAntiga(id: 900, numeroControle: 812);
    final vHoje = Venda(
      id: 901,
      status: 'finalizada',
      statusEntrega: 'pendente',
      tipoEntrega: 'entrega_loja',
      dataEntregaMarcada: hoje,
      numeroControle: 813,
    );

    final filtroDia = FiltroListagemEntregas(
      statusEntrega: 'todos',
      dataMarcadaInicio: inicioHoje,
      dataMarcadaFim: fimHoje,
      incluirEntregasConcluidas: false,
    );
    expect(
      EntregaFiltroUtil.aplicarEmMemoria([vAntiga, vHoje], filtroDia),
      hasLength(1),
    );

    final filtroBusca = FiltroListagemEntregas(
      statusEntrega: 'todos',
      bairroTermo: '812',
      dataMarcadaInicio: inicioHoje,
      dataMarcadaFim: fimHoje,
      incluirEntregasConcluidas: true,
    );
    expect(EntregaFiltroUtil.buscaGlobalAtiva(filtroBusca), isTrue);

    final encontradas =
        EntregaFiltroUtil.aplicarEmMemoria([vAntiga, vHoje], filtroBusca);
    expect(encontradas.map((v) => v.id), [900]);
  });

  test('busca por texto sem acento encontra entrega antiga fora do dia', () {
    final v = entregaAntiga(
      id: 555,
      endereco: 'José da Silva | Jardim | Rua B',
    );
    final filtro = FiltroListagemEntregas(
      bairroTermo: 'jose da silva',
      dataMarcadaInicio: inicioHoje,
      dataMarcadaFim: fimHoje,
      incluirEntregasConcluidas: true,
    );

    final r = EntregaFiltroUtil.aplicarEmMemoria([v], filtro);
    expect(r, hasLength(1));
    expect(r.first.id, 555);
  });

  test('busca numerica aceita prefixo de controle', () {
    final v = entregaAntiga(id: 647, numeroControle: 712);
    expect(
      EntregaFiltroUtil.aplicarEmMemoria(
        [v],
        FiltroListagemEntregas(bairroTermo: '71', incluirEntregasConcluidas: true),
      ),
      hasLength(1),
    );
  });

  test('EntregaBuscaTexto normaliza acentos para contains', () {
    expect(
      EntregaBuscaTexto.contem('São José', EntregaBuscaTexto.normalizar('sao')),
      isTrue,
    );
  });
}
