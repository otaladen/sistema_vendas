import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/mensagem_interna_repository.dart';
import 'package:sistema_vendas/domain/autorizacao_pdv_chat.dart';
import 'package:sistema_vendas/domain/chat_interno_exclusao.dart';
import 'package:sistema_vendas/domain/chat_interno_lista_ui.dart';
import 'package:sistema_vendas/model/mensagem_interna.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';

UsuarioSistema _usuario({
  required String login,
  String perfil = 'vendedor',
  bool admin = false,
}) {
  return UsuarioSistema(
    id: login,
    nome: login,
    login: login,
    senha: 'hash',
    perfil: perfil,
    admin: admin,
  );
}

MensagemInterna _msg({
  required int id,
  required String vendedor,
  Duration idade = Duration.zero,
  bool auth = false,
}) {
  return MensagemInterna(
    id: id,
    vendedor: vendedor,
    texto: auth ? 'Auth' : 'Oi',
    dataHora: DateTime.now().toUtc().subtract(idade),
    tipo: auth ? kMensagemInternaTipoAutorizacaoPdv : kMensagemInternaTipoTexto,
    payload: auth ? {'solicitacaoId': 's-$id'} : const {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('autorizacao PDV nunca pode ser apagada', () {
    final operador = _usuario(login: 'joao');
    final auth = _msg(id: 1, vendedor: 'joao', auth: true);
    expect(
      ChatInternoExclusaoPolitica.podeApagar(
        operador: operador,
        nomeOperadorLogado: 'joao',
        loginOperador: 'joao',
        mensagem: auth,
      ),
      isFalse,
    );
    expect(
      ChatInternoExclusaoPolitica.podeApagar(
        operador: _usuario(login: 'admin', admin: true),
        nomeOperadorLogado: 'admin',
        loginOperador: 'admin',
        mensagem: auth,
      ),
      isFalse,
    );
  });

  test('operador apaga propria mensagem dentro de 30 minutos', () {
    final operador = _usuario(login: 'maria');
    final recente = _msg(
      id: 2,
      vendedor: 'maria',
      idade: const Duration(minutes: 10),
    );
    expect(
      ChatInternoExclusaoPolitica.podeApagar(
        operador: operador,
        nomeOperadorLogado: 'maria',
        loginOperador: 'maria',
        mensagem: recente,
      ),
      isTrue,
    );
    final antiga = _msg(
      id: 3,
      vendedor: 'maria',
      idade: const Duration(minutes: 45),
    );
    expect(
      ChatInternoExclusaoPolitica.podeApagar(
        operador: operador,
        nomeOperadorLogado: 'maria',
        loginOperador: 'maria',
        mensagem: antiga,
      ),
      isFalse,
    );
  });

  test('gerente apaga mensagem de outro operador', () {
    final gerente = _usuario(login: 'g1', perfil: 'gerente');
    final msg = _msg(
      id: 4,
      vendedor: 'outro',
      idade: const Duration(hours: 5),
    );
    expect(
      ChatInternoExclusaoPolitica.podeApagar(
        operador: gerente,
        nomeOperadorLogado: 'Gerente',
        loginOperador: 'g1',
        mensagem: msg,
      ),
      isTrue,
    );
  });

  test('limpar mural remove normais e mantem autorizacao', () async {
    final dir = await Directory.systemTemp.createTemp('chat_exc_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    final repo = MensagemInternaRepository(storeDirectoryPath: dir.path);
    await repo.enviar(vendedor: 'A', texto: 'normal 1');
    await repo.enviar(
      vendedor: 'B',
      texto: 'auth',
      tipo: kMensagemInternaTipoAutorizacaoPdv,
      payload: {'solicitacaoId': 'x-1'},
    );
    await repo.enviar(vendedor: 'A', texto: 'normal 2');

    final removidos = await repo.limparMuralNormais();
    expect(removidos.length, 2);

    final historico = await repo.listarHistorico();
    expect(historico.length, 1);
    expect(historico.single.ehAutorizacaoPdv, isTrue);
  });

  test('repositorio recusa apagar mensagem protegida', () async {
    final dir = await Directory.systemTemp.createTemp('chat_exc_srv_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    final repo = MensagemInternaRepository(storeDirectoryPath: dir.path);
    final auth = await repo.enviar(
      vendedor: 'Sistema',
      texto: 'auth',
      tipo: kMensagemInternaTipoAutorizacaoPdv,
      payload: {'solicitacaoId': 'prot-1'},
    );
    await expectLater(
      repo.apagarPorId(auth.id),
      throwsA(isA<StateError>()),
    );
    final historico = await repo.listarHistorico();
    expect(historico.any((m) => m.id == auth.id), isTrue);
  });

  test('lista UI insere separadores Hoje e Ontem', () {
    final agora = DateTime.now().toUtc();
    final ontem = agora.subtract(const Duration(days: 1));
    final itens = ChatInternoListaUi.montar([
      MensagemInterna(
        id: 1,
        vendedor: 'A',
        texto: '1',
        dataHora: ontem,
      ),
      MensagemInterna(
        id: 2,
        vendedor: 'A',
        texto: '2',
        dataHora: agora,
      ),
    ]);
    expect(itens.length, 4);
    expect(itens[0], isA<ChatInternoSeparadorData>());
    expect((itens[0] as ChatInternoSeparadorData).rotulo, 'Ontem');
    expect((itens[2] as ChatInternoSeparadorData).rotulo, 'Hoje');
  });
}
