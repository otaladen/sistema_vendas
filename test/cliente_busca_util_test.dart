import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/cliente_busca_util.dart';
import 'package:sistema_vendas/model/cliente.dart';

void main() {
  test('clienteCorrespondeTermoBusca por nome parcial', () {
    final c = Cliente(nomeRazao: 'Antonio de Jesus');
    expect(clienteCorrespondeTermoBusca(c, 'antonio'), isTrue);
    expect(clienteCorrespondeTermoBusca(c, 'jesus'), isTrue);
    expect(clienteCorrespondeTermoBusca(c, 'xyz'), isFalse);
  });

  test('filtrarClientesPorTermo respeita ativo e limite', () {
    final lista = [
      Cliente(nomeRazao: 'Ana', ativo: true),
      Cliente(nomeRazao: 'Ana Inativa', ativo: false),
      Cliente(nomeRazao: 'Alan', ativo: true),
    ];
    final r = filtrarClientesPorTermo(
      lista,
      'an',
      somenteAtivos: true,
      limit: 1,
    );
    expect(r.length, 1);
    expect(r.first.nomeRazao, 'Alan');
  });
}
