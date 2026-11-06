// Conversación con un usuario: burbujas, ticks de estado, "escribiendo..." y envío.

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../chat_service.dart';

class ChatScreen extends StatefulWidget {
  final ChatService chat;
  final String otro;
  const ChatScreen({super.key, required this.chat, required this.otro});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final texto = TextEditingController();

  ChatService get chat => widget.chat;

  // Sin clave pública no podemos cifrar (el otro aún no se ha conectado nunca)
  bool get puedoEnviar => chat.publicas.containsKey(widget.otro);

  void enviarTexto() {
    if (texto.text.trim().isEmpty || !puedoEnviar) return;
    chat.enviarTexto(widget.otro, texto.text.trim());
    texto.clear();
  }

  Future<void> enviarImagen() async {
    if (!puedoEnviar) return;
    final PlatformFile? fichero;
    try {
      fichero = await FilePicker.pickFile(type: FileType.image);
    } catch (e) {
      // En Linux el selector usa el portal de escritorio (xdg-desktop-portal)
      avisar('No se ha podido abrir el selector de imágenes');
      return;
    }
    if (fichero == null) return; // el usuario ha cancelado
    final bytes = await fichero.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      avisar('Imagen demasiado grande (máx. 5 MB)');
      return;
    }
    chat.enviarImagen(widget.otro, bytes);
  }

  void avisar(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final mensajes = chat.chat(widget.otro).reversed.toList();
        String estado = chat.online.contains(widget.otro) ? 'en línea' : 'desconectado';
        if (chat.escribiendo.containsKey(widget.otro)) estado = 'escribiendo...';

        return Scaffold(
          backgroundColor: const Color(0xFFECE5DD),
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.otro),
              Text(estado, style: const TextStyle(fontSize: 12)),
            ]),
          ),
          body: Column(children: [
            Expanded(
              child: ListView.builder(
                reverse: true, // los mensajes nuevos abajo
                itemCount: mensajes.length,
                itemBuilder: (_, i) => _burbuja(mensajes[i]),
              ),
            ),
            _barraEscritura(),
          ]),
        );
      },
    );
  }

  Widget _burbuja(Mensaje m) {
    return Align(
      alignment: m.mio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: m.mio ? const Color(0xFFDCF8C6) : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          m.tipo == 'image' ? Image.memory(base64Decode(m.contenido)) : Text(m.contenido),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(m.hora, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (m.mio) _tick(m.estado),
          ]),
        ]),
      ),
    );
  }

  // ✓ enviado · ✓✓ gris recibido · ✓✓ azul leído
  Widget _tick(String estado) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        estado == 'enviado' ? Icons.done : Icons.done_all,
        size: 16,
        color: estado == 'leido' ? Colors.blue : Colors.grey,
      ),
    );
  }

  Widget _barraEscritura() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(6),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.attach_file), onPressed: puedoEnviar ? enviarImagen : null),
        Expanded(
          child: TextField(
            controller: texto,
            enabled: puedoEnviar,
            decoration: InputDecoration(hintText: puedoEnviar ? 'Escribe un mensaje' : 'Usuario no disponible'),
            onChanged: (_) => chat.avisarEscribiendo(widget.otro),
            onSubmitted: (_) => enviarTexto(),
          ),
        ),
        IconButton(icon: const Icon(Icons.send), onPressed: puedoEnviar ? enviarTexto : null),
      ]),
    );
  }
}
