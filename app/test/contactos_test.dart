// Comprueba el orden de la lista de chats (el más reciente primero).
// Ejecutar con: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_seguro/chat_service.dart';

void main() {
  test('Los chats se ordenan por el último mensaje, como en WhatsApp', () {
    final chat = ChatService();
    chat.chats['ana'] = [Mensaje('1', true, 'text', 'hola', '10:00', 'leido', 1000)];
    chat.chats['pepe'] = [Mensaje('2', false, 'text', 'ey', '11:00', 'leido', 2000)];
    chat.publicas['zoe'] = 'clave'; // conectada, pero sin mensajes
    chat.publicas['bea'] = 'clave';

    // pepe (más reciente), ana, y los que no tienen mensajes por orden alfabético
    expect(chat.contactos, ['pepe', 'ana', 'bea', 'zoe']);
  });
}
