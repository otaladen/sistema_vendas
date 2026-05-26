import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_whatsapp_helper.dart';
import 'package:sistema_vendas/model/cliente.dart';

void main() {
  test('monta uri whatsapp com mensagem', () {
    final uri = NfeWhatsappHelper.uriWhatsapp(
      telefone: '71999998888',
      mensagem: 'NF-e teste',
    );
    expect(uri, isNotNull);
    expect(uri!.toString(), contains('wa.me/5571999998888'));
    expect(uri.toString(), contains('text='));
  });

  test('telefoneCliente prioriza whatsapp', () {
    final c = Cliente(
      nomeRazao: 'Loja',
      whatsapp: '(71) 98888-7777',
      telefone: '7133334444',
    );
    expect(NfeWhatsappHelper.telefoneCliente(c), '5571988887777');
  });
}
