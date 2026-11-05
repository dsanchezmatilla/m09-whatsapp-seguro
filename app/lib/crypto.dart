// Cifrado de extremo a extremo.
//
// Cada usuario tiene un par de claves X25519 (privada + pública).
// Para hablar con otro usuario se calcula una clave secreta compartida:
//
//     secreto = X25519(mi clave privada, clave pública del otro)
//
// El otro obtiene exactamente el mismo secreto con
// X25519(su clave privada, mi clave pública). Ese secreto se usa como clave
// AES-256-GCM para cifrar texto e imágenes. El servidor solo conoce las claves
// públicas, así que no puede calcular el secreto ni leer los mensajes.

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

final _x25519 = X25519();
final _aes = AesGcm.with256bits();

// Genera un par de claves nuevo (la primera vez que se usa la app)
Future<SimpleKeyPair> generarClaves() => _x25519.newKeyPair();

// Reconstruye el par de claves a partir de la clave privada guardada
Future<SimpleKeyPair> cargarClaves(String privadaBase64) =>
    _x25519.newKeyPairFromSeed(base64Decode(privadaBase64));

Future<String> clavePrivada(SimpleKeyPair claves) async =>
    base64Encode(await claves.extractPrivateKeyBytes());

Future<String> clavePublica(SimpleKeyPair claves) async =>
    base64Encode((await claves.extractPublicKey()).bytes);

// Secreto compartido entre mi clave privada y la clave pública del otro
Future<SecretKey> _secreto(SimpleKeyPair mias, String publicaOtro) {
  final publica = SimplePublicKey(base64Decode(publicaOtro), type: KeyPairType.x25519);
  return _x25519.sharedSecretKey(keyPair: mias, remotePublicKey: publica);
}

// Cifra bytes. Devuelve los tres campos que viajan por el servidor.
Future<Map<String, String>> cifrar(List<int> datos, SimpleKeyPair mias, String publicaOtro) async {
  final clave = await _secreto(mias, publicaOtro);
  final caja = await _aes.encrypt(datos, secretKey: clave); // nonce aleatorio
  return {
    'nonce': base64Encode(caja.nonce),
    'cipher': base64Encode(caja.cipherText),
    'mac': base64Encode(caja.mac.bytes),
  };
}

// Descifra un mensaje recibido. Falla si alguien ha modificado el contenido (MAC).
Future<List<int>> descifrar(Map data, SimpleKeyPair mias, String publicaOtro) async {
  final clave = await _secreto(mias, publicaOtro);
  final caja = SecretBox(
    base64Decode(data['cipher']),
    nonce: base64Decode(data['nonce']),
    mac: Mac(base64Decode(data['mac'])),
  );
  return _aes.decrypt(caja, secretKey: clave);
}
