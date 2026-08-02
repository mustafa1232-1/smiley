import { createServer } from 'node:http';
import { Server } from 'socket.io';

import { createApp } from './app.js';
import { config } from './config.js';

const app = createApp();
const server = createServer(app);
const io = new Server(server, {
  cors: { origin: config.corsOrigin === '*' ? true : config.corsOrigin }
});

io.use((socket, next) => {
  const token = socket.handshake.auth.token;
  if (!token) return next(new Error('unauthorized'));
  next();
});

io.on('connection', (socket) => {
  socket.emit('connected', { socketId: socket.id });
});

server.listen(config.port, () => {
  console.log(`Smiley API listening on port ${config.port}`);
});
