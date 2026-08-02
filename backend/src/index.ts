import { createServer } from 'node:http';

import { createApp } from './app.js';
import { config } from './config.js';
import { configureRealtime } from './realtime/server.js';

const app = createApp();
const server = createServer(app);

configureRealtime(server);

server.listen(config.port, '0.0.0.0', () => {
  console.log(`Smiley API listening on 0.0.0.0:${config.port}`);
});
