// Servidor WebSocket de "WhatsApp seguro".
// Solo reenvía mensajes entre usuarios. El contenido llega cifrado
// (campo "cipher") y el servidor no tiene ninguna clave para leerlo.

const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;

const clients = new Map(); // usuario -> socket conectado
const keys = new Map();    // usuario -> clave pública (base64)
const pending = new Map(); // usuario -> mensajes recibidos mientras estaba desconectado

// maxPayload: 10 MB para permitir imágenes
const wss = new WebSocketServer({ port: PORT, maxPayload: 10 * 1024 * 1024 });

// Envía un objeto como JSON a un socket
function send(socket, data) {
  socket.send(JSON.stringify(data));
}

// Envía a todos la lista de usuarios con su clave pública y si están conectados
function broadcastUsers() {
  const users = [];
  for (const [user, publicKey] of keys) {
    users.push({ user, publicKey, online: clients.has(user) });
  }
  for (const socket of clients.values()) {
    send(socket, { type: 'users', users });
  }
}

// Reenvía un mensaje a su destinatario, o lo guarda si está desconectado
function forward(data) {
  const socket = clients.get(data.to);
  if (socket) {
    send(socket, data);
  } else {
    if (!pending.has(data.to)) pending.set(data.to, []);
    pending.get(data.to).push(data);
  }
}

wss.on('connection', (socket) => {
  let me = null; // nombre del usuario de esta conexión
  socket.vivo = true;
  socket.on('pong', () => (socket.vivo = true)); // el cliente responde a nuestro ping

  socket.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      return; // ignoramos lo que no sea JSON
    }

    // Solo registramos tipo, origen y destino: nunca el contenido
    console.log(new Date().toISOString(), data.type, me || data.user, '->', data.to || '');

    if (data.type === 'login') {
      me = data.user;
      clients.set(me, socket);
      keys.set(me, data.publicKey);
      broadcastUsers();

      // Entregamos los mensajes que le llegaron estando desconectado
      for (const msg of pending.get(me) || []) send(socket, msg);
      pending.delete(me);
      return;
    }

    // msg, delivered, read y typing: se reenvían tal cual al destinatario
    if (me && data.to) {
      data.from = me; // el remitente lo pone el servidor, no el cliente
      forward(data);
    }
  });

  socket.on('close', () => {
    if (me && clients.get(me) === socket) {
      clients.delete(me);
      broadcastUsers();
    }
  });
});

// Latido cada 25 s: mandamos un ping a cada cliente.
// - Si no respondió al ping anterior, la conexión está muerta: la cerramos
//   (eso lanza 'close', que lo marca desconectado y sus mensajes van a "pending").
// - El tráfico del ping evita que el proxy HTTPS corte las conexiones inactivas (~50 s).
setInterval(() => {
  for (const socket of wss.clients) {
    if (!socket.vivo) {
      socket.terminate();
      continue;
    }
    socket.vivo = false;
    socket.ping();
  }
}, 25000);

console.log(`Servidor escuchando en ws://0.0.0.0:${PORT}`);
