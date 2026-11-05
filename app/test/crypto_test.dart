// Comprueba el cifrado de extremo a extremo sin servidor ni interfaz.
// Ejecutar con: flutter test

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_seguro/crypto.dart';

void main() {
  test('Pepe descifra lo que Ana le cifra', () async {
    final ana = await generarClaves();
    final pepe = await generarClaves();

    final cifrado = await cifrar(utf8.encode('Hola'), ana, await clavePublica(pepe));
    final descifrado = await descifrar(cifrado, pepe, await clavePublica(ana));

    expect(utf8.decode(descifrado), 'Hola');
    expect(cifrado['cipher'], isNot(contains('Hola')));
  });

  test('Un tercero (o el servidor) no puede descifrarlo', () async {
    final ana = await generarClaves();
    final pepe = await generarClaves();
    final espia = await generarClaves();

    final cifrado = await cifrar(utf8.encode('Secreto'), ana, await clavePublica(pepe));
    final publicaAna = await clavePublica(ana);

    expect(descifrar(cifrado, espia, publicaAna), throwsA(anything));
  });

  test('La clave privada guardada se recupera igual', () async {
    final claves = await generarClaves();
    final recuperadas = await cargarClaves(await clavePrivada(claves));
    expect(await clavePublica(recuperadas), await clavePublica(claves));
  });
}
