import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/main_menu_destino.dart';
import 'package:sistema_vendas/domain/main_menu_sub_destino.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';

UsuarioSistema _admin() => const UsuarioSistema(
      id: '1',
      login: 'admin',
      nome: 'Admin',
      senha: 'x',
      admin: true,
    );

void main() {
  test('subitens de vendas respeitam permissoes', () {
    final subs = MainMenuSubDestinoHelper.subitensDe(
      MainMenuDestino.vendas,
      _admin(),
    );
    expect(subs, contains(MainMenuSubDestino.vendasOrcamentos));
    expect(subs, contains(MainMenuSubDestino.vendasListagem));
    expect(subs, contains(MainMenuSubDestino.vendasRelatorios));
  });

  test('subitens de cadastros incluem produtos e usuarios para admin', () {
    final subs = MainMenuSubDestinoHelper.subitensDe(
      MainMenuDestino.cadastros,
      _admin(),
    );
    expect(subs.first, MainMenuSubDestino.cadastrosProdutos);
    expect(subs, contains(MainMenuSubDestino.cadastrosUsuarios));
  });

  test('primeiro permitido de vendas e orcamentos', () {
    expect(
      MainMenuSubDestinoHelper.primeiroPermitido(
        MainMenuDestino.vendas,
        _admin(),
      ),
      MainMenuSubDestino.vendasOrcamentos,
    );
  });

  test('subitens fiscais comecam em importar nfe', () {
    final subs = MainMenuSubDestinoHelper.subitensDe(
      MainMenuDestino.notasFiscais,
      _admin(),
    );
    expect(subs.first, MainMenuSubDestino.fiscalImportarNfe);
    expect(subs, contains(MainMenuSubDestino.fiscalPendencias));
  });

  test('subitens financeiros incluem tesouraria e fiados', () {
    final subs = MainMenuSubDestinoHelper.subitensDe(
      MainMenuDestino.financeiro,
      _admin(),
    );
    expect(subs.first, MainMenuSubDestino.financeiroTesouraria);
    expect(subs, contains(MainMenuSubDestino.financeiroRelatorioFiados));
  });

  test('modulos com submenu incluem fiscal e financeiro', () {
    expect(
      MainMenuSubDestinoHelper.moduloTemSubmenu(MainMenuDestino.notasFiscais),
      isTrue,
    );
    expect(
      MainMenuSubDestinoHelper.moduloTemSubmenu(MainMenuDestino.financeiro),
      isTrue,
    );
  });
}
