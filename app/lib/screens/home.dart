// Lista de contactos a la izquierda.
// Pantalla ancha (Linux): lista y chat lado a lado, como WhatsApp Web.
// Pantalla estrecha (Android): lista, y al tocar un contacto se abre el chat encima.

import 'package:flutter/material.dart';

import '../chat_service.dart';
import 'chat.dart';

class HomeScreen extends StatelessWidget {
  final ChatService chat;
  const HomeScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => LayoutBuilder(builder: (context, medidas) {
        final ancha = medidas.maxWidth > 700;
        final lista = Scaffold(
          appBar: AppBar(title: Text(chat.conectado ? 'Chats de ${chat.yo}' : 'Reconectando...')),
          body: ListView(children: [for (final c in chat.contactos) _contacto(context, c, ancha)]),
        );

        if (!ancha) return lista;

        final abierto = chat.chatAbierto;
        return Row(children: [
          SizedBox(width: 320, child: lista),
          const VerticalDivider(width: 1),
          Expanded(
            child: abierto == null
                ? const Scaffold(body: Center(child: Text('Selecciona un chat')))
                : ChatScreen(key: ValueKey(abierto), chat: chat, otro: abierto),
          ),
        ]);
      }),
    );
  }

  Widget _contacto(BuildContext context, String usuario, bool ancha) {
    final mensajes = chat.chat(usuario);
    final pendientes = chat.noLeidos(usuario);

    String subtitulo = '';
    if (chat.escribiendo.containsKey(usuario)) {
      subtitulo = 'escribiendo...';
    } else if (mensajes.isNotEmpty) {
      subtitulo = mensajes.last.tipo == 'image' ? 'Imagen' : mensajes.last.contenido;
    }

    return ListTile(
      selected: chat.chatAbierto == usuario,
      leading: CircleAvatar(
        backgroundColor: chat.online.contains(usuario) ? Colors.green : Colors.grey,
        child: Text(usuario[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
      ),
      title: Text(usuario),
      subtitle: Text(subtitulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: pendientes > 0 ? Badge(label: Text('$pendientes'), backgroundColor: Colors.green) : null,
      onTap: () {
        chat.abrirChat(usuario);
        if (!ancha) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chat: chat, otro: usuario)))
              .then((_) => chat.cerrarChat());
        }
      },
    );
  }
}
