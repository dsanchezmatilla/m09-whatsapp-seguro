# WhatsApp seguro (M09)

Chat estilo WhatsApp con **cifrado de extremo a extremo**.

- `app/` → cliente Flutter (Linux y Android).
- `server/` → servidor Node.js con WebSockets. Solo reenvía mensajes cifrados: no puede leerlos.

## Funcionamiento

1. Al entrar por primera vez, la app genera un par de claves **X25519** y lo guarda en el dispositivo.
2. Al conectarse, envía su **clave pública** al servidor, que la reparte al resto de usuarios.
3. Para enviar un mensaje (texto o imagen) se calcula un secreto compartido
   `X25519(mi privada, pública del otro)` y se cifra con **AES-256-GCM**.
4. El servidor recibe `{to, nonce, cipher, mac}` y lo reenvía al destinatario.
5. El destinatario calcula el mismo secreto con `X25519(su privada, mi pública)` y descifra.

### Protocolo (JSON por WebSocket)

| type | Campos | Para qué |
|---|---|---|
| `login` | `user`, `publicKey` | Registrarse en el servidor |
| `users` | `users: [{user, publicKey, online}]` | Lista de usuarios (la envía el servidor) |
| `msg` | `to`, `id`, `kind`, `nonce`, `cipher`, `mac` | Mensaje cifrado |
| `delivered` | `to`, `id` | El mensaje ha llegado (✓✓ gris) |
| `read` | `to`, `id` | El mensaje se ha leído (✓✓ azul) |
| `typing` | `to` | El usuario está escribiendo |

El servidor añade el campo `from` a todo lo que reenvía.

## Ejecutar el servidor

```bash
cd server
npm install
npm start            # puerto 8080 (cambiar con PORT=xxxx)
```

### Despliegue en Proxmox

```bash
git clone <url-de-este-repo>
cd m09-whatsapp-seguro/server
npm install --omit=dev
# editar User, WorkingDirectory y ruta de node en whatsapp.service
sudo cp whatsapp.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now whatsapp
journalctl -u whatsapp -f      # ver logs
```

Para actualizar: `git pull && sudo systemctl restart whatsapp`.

En el Proxmox el servicio escucha en el puerto 80, que el instituto publica hacia fuera por HTTPS.
Por eso desde fuera la app se conecta con `wss://` (WebSocket cifrado con TLS).

## Ejecutar la app

```bash
cd app
flutter pub get
flutter run -d linux        # o con un Android conectado: flutter run
```

En el emulador de Android el PC es `ws://10.0.2.2:8080`.

Pruebas del cifrado (Ana cifra → Pepe descifra, un tercero no puede):

```bash
flutter test
```

## Compilar

```bash
flutter build linux --release   # build/linux/x64/release/bundle/
flutter build apk --release     # build/app/outputs/flutter-apk/app-release.apk
```
