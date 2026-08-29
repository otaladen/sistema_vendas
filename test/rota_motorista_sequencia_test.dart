import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/entrega_baixa_motorista_visao.dart';
import 'package:sistema_vendas/domain/entregas/rota_motorista_sequencia.dart';
import 'package:sistema_vendas/model/venda.dart';

EntregaBaixaLinhaVisao _linha(
  int id, {
  EntregaBaixaUiStatus sync = EntregaBaixaUiStatus.ativa,
  String endereco = 'Rua A, 100',
}) {
  return EntregaBaixaLinhaVisao(
    venda: Venda(
      id: id,
      numeroOrcamento: id,
      statusEntrega: 'saiu_entrega',
      enderecoEntrega: endereco,
    ),
    sync: sync,
  );
}

void main() {
  test('numera as paradas na ordem recebida', () {
    final paradas = RotaMotorista.montar([_linha(1), _linha(2), _linha(3)]);

    expect(paradas.map((p) => p.posicao), [1, 2, 3]);
    expect(paradas.every((p) => p.total == 3), isTrue);
    expect(paradas.first.rotulo, 'Parada 1 de 3');
    expect(paradas.last.rotulo, 'Parada 3 de 3');
  });

  test('so a primeira pendente e a proxima', () {
    final paradas = RotaMotorista.montar([_linha(1), _linha(2)]);

    expect(paradas.first.proxima, isTrue);
    expect(paradas.first.destacarProxima, isTrue);
    expect(paradas.last.proxima, isFalse);
  });

  test('entrega ja baixada sai da contagem e renumera o resto', () {
    final paradas = RotaMotorista.montar([
      _linha(1, sync: EntregaBaixaUiStatus.sincronizada),
      _linha(2, sync: EntregaBaixaUiStatus.aguardandoSync),
      _linha(3),
      _linha(4),
    ]);

    expect(paradas[0].pendente, isFalse);
    expect(paradas[0].rotulo, isEmpty);
    expect(paradas[1].pendente, isFalse);
    expect(paradas[2].rotulo, 'Parada 1 de 2');
    expect(paradas[2].proxima, isTrue);
    expect(paradas[3].rotulo, 'Parada 2 de 2');
    expect(RotaMotorista.totalPendentes(paradas), 2);
  });

  test('baixa recusada continua sendo parada: material segue no carro', () {
    final paradas = RotaMotorista.montar([
      _linha(1, sync: EntregaBaixaUiStatus.recusada),
      _linha(2),
    ]);

    expect(paradas.first.pendente, isTrue);
    expect(paradas.first.rotulo, 'Parada 1 de 2');
  });

  test('com uma parada so nao numera nem destaca', () {
    final paradas = RotaMotorista.montar([
      _linha(1, sync: EntregaBaixaUiStatus.sincronizada),
      _linha(2),
    ]);

    expect(paradas[1].pendente, isTrue);
    expect(paradas[1].mostrarSequencia, isFalse);
    expect(paradas[1].rotulo, isEmpty);
    expect(paradas[1].destacarProxima, isFalse);
  });

  test('mapa leva so as pendentes com endereco, na ordem', () {
    final paradas = RotaMotorista.montar([
      _linha(1, sync: EntregaBaixaUiStatus.sincronizada),
      _linha(2, endereco: '   '),
      _linha(3, endereco: 'Rua B, 200'),
      _linha(4, endereco: 'Rua C, 300'),
    ]);

    final vendas = RotaMotorista.vendasParaMapa(paradas);
    expect(vendas.map((v) => v.id), [3, 4]);
  });

  test('rota vazia nao quebra', () {
    final paradas = RotaMotorista.montar(const []);

    expect(paradas, isEmpty);
    expect(RotaMotorista.totalPendentes(paradas), 0);
    expect(RotaMotorista.vendasParaMapa(paradas), isEmpty);
  });
}
