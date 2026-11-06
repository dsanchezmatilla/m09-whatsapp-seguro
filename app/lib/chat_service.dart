// Toda la lógica de la app: conexión con el servidor, claves, mensajes e historial.
// Las pantallas solo leen datos de aquí y llaman a sus métodos.
// Al ser un ChangeNotifier, cada notifyListeners() redibuja las pantallas.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'crypto.dart';

class Mensaje {
  final String id;
  final bool mio;
  final String tipo; // 'text' o 'image'
  final String contenido; // el texto, o la imagen en base64
  // Imagen decodificada una sola vez (la primera vez que se pinta) y reutilizada:
  // si se decodificase en cada redibujado, Flutter la recargaría y parpadearía.
  late final Uint8List bytes = base64Decode(contenido);
  final String hora;
  final int fecha; // milisegundos desde 1970: sirve para ordenar los chats
  String estado; // 'enviado', 'recibido' o 'leido'

  // Si no se indica la fecha, es la de ahora (mensaje nuevo)
  Mensaje(this.id, this.mio, this.tipo, this.contenido, this.hora, this.estado, [int? fecha])
      : fecha = fecha ?? DateTime.now().millisecondsSinceEpoch;

  Map toJson() =>
      {'id': id, 'mio': mio, 'tipo': tipo, 'contenido': contenido, 'hora': hora, 'estado': estado, 'fecha': fecha};

  // Los mensajes guardados antes de existir 'fecha' toman 0 (quedan al final)
  factory Mensaje.fromJson(Map j) =>
      Mensaje(j['id'], j['mio'], j['tipo'], j['contenido'], j['hora'], j['estado'], j['fecha'] ?? 0);
}

class ChatService extends ChangeNotifier {
  late String yo;
  late SimpleKeyPair claves;
  late String privada; // la clave privada en base64, tal como se guarda en el fichero
  late File fichero; // claves + historial de este usuario
  late String url; // servidor, para poder reconectar
  WebSocketChannel? canal;
  bool conectado = false;

  final publicas = <String, String>{}; // usuario -> clave pública
  final online = <String>{};
  final chats = <String, List<Mensaje>>{}; // usuario -> conversación
  final escribiendo = <String, Timer>{}; // usuarios que están escribiendo
  String? chatAbierto;
  DateTime _ultimoAviso = DateTime(2000);

  // Todos los contactos: los que ve el servidor y los que tienen historial
  // Ordenados como en WhatsApp: primero el chat con el mensaje más reciente;
  // los que no tienen mensajes, al final y por orden alfabético
  List<String> get contactos {
    final lista = {...publicas.keys, ...chats.keys}.toList();
    lista.sort((a, b) {
      final porFecha = _ultimaFecha(b).compareTo(_ultimaFecha(a));
      return porFecha != 0 ? porFecha : a.compareTo(b);
    });
    return lista;
  }

  int _ultimaFecha(String usuario) => chat(usuario).isEmpty ? 0 : chat(usuario).last.fecha;

  List<Mensaje> chat(String usuario) => chats.putIfAbsent(usuario, () => []);

  int noLeidos(String usuario) => chat(usuario).where((m) => !m.mio && m.estado != 'leido').length;

  Future<void> conectar(String nombre, String url) async {
    yo = nombre;
    this.url = url;
    final dir = await getApplicationSupportDirectory();
    fichero = File('${dir.path}/whatsapp_$nombre.json');

    if (fichero.existsSync()) {
      // Ya teníamos claves e historial
      final datos = jsonDecode(fichero.readAsStringSync());
      privada = datos['privada'];
      claves = await cargarClaves(privada);
      (datos['chats'] as Map).forEach((usuario, lista) {
        chats[usuario] = [for (final m in lista) Mensaje.fromJson(m)];
      });
    } else {
      // Primera vez: generamos el par de claves automáticamente
      claves = await generarClaves();
      privada = await clavePrivada(claves);
      _guardar();
    }

    await _abrirConexion(); // si falla, el error llega a la pantalla de login
  }

  Future<void> _abrirConexion() async {
    canal = WebSocketChannel.connect(Uri.parse(url));
    await canal!.ready;
    canal!.stream.listen(_recibir, onDone: _conexionPerdida, onError: (_) {});
    _enviar({'type': 'login', 'user': yo, 'publicKey': await clavePublica(claves)});
    conectado = true;
    notifyListeners();
  }

  // Se ha cortado la conexión (sin red, móvil dormido, proxy...): reintentamos cada 3 s
  void _conexionPerdida() {
    conectado = false;
    online.clear();
    notifyListeners();
    Timer(const Duration(seconds: 3), () async {
      try {
        await _abrirConexion();
      } catch (_) {
        _conexionPerdida();
      }
    });
  }

  // Escritura síncrona a propósito: así dos guardados seguidos nunca se mezclan
  // en el fichero (con la versión async podían solaparse y dejarlo corrupto).
  void _guardar() {
    final datos = {
      'privada': privada,
      'chats': chats.map((usuario, lista) => MapEntry(usuario, [for (final m in lista) m.toJson()])),
    };
    fichero.writeAsStringSync(jsonEncode(datos));
  }

  void _enviar(Map data) => canal!.sink.add(jsonEncode(data));

  String _hora() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // ---------- Enviar ----------

  Future<void> enviarTexto(String para, String texto) =>
      _enviarMensaje(para, 'text', utf8.encode(texto), texto);

  Future<void> enviarImagen(String para, List<int> bytes) =>
      _enviarMensaje(para, 'image', bytes, base64Encode(bytes));

  Future<void> _enviarMensaje(String para, String tipo, List<int> datos, String contenido) async {
    final id = '${yo}_${DateTime.now().microsecondsSinceEpoch}';
    final cifrado = await cifrar(datos, claves, publicas[para]!);
    _enviar({'type': 'msg', 'to': para, 'id': id, 'kind': tipo, ...cifrado});
    chat(para).add(Mensaje(id, true, tipo, contenido, _hora(), 'enviado'));
    _guardar();
    notifyListeners();
  }

  // Avisa de que estoy escribiendo (como mucho una vez cada 2 segundos)
  void avisarEscribiendo(String para) {
    if (DateTime.now().difference(_ultimoAviso).inSeconds < 2) return;
    _ultimoAviso = DateTime.now();
    _enviar({'type': 'typing', 'to': para});
  }

  void abrirChat(String usuario) {
    chatAbierto = usuario;
    marcarLeidos(usuario);
  }

  void cerrarChat() {
    chatAbierto = null;
    notifyListeners();
  }

  // Marca como leídos los mensajes recibidos y se lo dice al remitente
  void marcarLeidos(String usuario) {
    for (final m in chat(usuario)) {
      if (!m.mio && m.estado != 'leido') {
        m.estado = 'leido';
        _enviar({'type': 'read', 'to': usuario, 'id': m.id});
      }
    }
    _guardar();
    notifyListeners();
  }

  // ---------- Recibir ----------

  Future<void> _recibir(dynamic raw) async {
    final data = jsonDecode(raw);
    final de = data['from'];

    switch (data['type']) {
      case 'users':
        publicas.clear();
        online.clear();
        for (final u in data['users']) {
          if (u['user'] == yo) continue;
          publicas[u['user']] = u['publicKey'];
          if (u['online']) online.add(u['user']);
        }

      case 'msg':
        try {
          final bytes = await descifrar(data, claves, publicas[de]!);
          final contenido = data['kind'] == 'image' ? base64Encode(bytes) : utf8.decode(bytes);
          chat(de).add(Mensaje(data['id'], false, data['kind'], contenido, _hora(), 'recibido'));
          escribiendo.remove(de)?.cancel();
          _enviar({'type': 'delivered', 'to': de, 'id': data['id']});
          if (chatAbierto == de) marcarLeidos(de);
          _guardar();
        } catch (e) {
          debugPrint('No se ha podido descifrar el mensaje de $de: $e');
        }

      case 'delivered':
        _cambiarEstado(de, data['id'], 'recibido');

      case 'read':
        _cambiarEstado(de, data['id'], 'leido');

      case 'typing':
        // "escribiendo..." desaparece a los 3 segundos si no llega otro aviso
        escribiendo[de]?.cancel();
        escribiendo[de] = Timer(const Duration(seconds: 3), () {
          escribiendo.remove(de);
          notifyListeners();
        });
    }
    notifyListeners();
  }

  void _cambiarEstado(String usuario, String id, String estado) {
    for (final m in chat(usuario)) {
      // No retrocedemos: si ya está leído no vuelve a "recibido"
      if (m.id == id && m.estado != 'leido') m.estado = estado;
    }
    _guardar();
  }
}
