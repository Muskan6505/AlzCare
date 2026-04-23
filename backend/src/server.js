// backend-nodejs/src/server.js
// AlzCare Node.js Backend v2 — entry point.
//
// Starts in order:
//   1. MongoDB Atlas (Mongoose)
//   2. Express HTTP server
//   3. Socket.io hub (always-on patient/caregiver rooms)
//   4. Persistent Nagger (node-cron, every minute)
//
// Run:
//   npm run dev    (nodemon — development)
//   npm start      (production)

import 'dotenv/config';
import http from 'http';

import app                  from './app.js';
import { connectDB }        from '../config/database.js';
import { initSocketHub }    from './sockets/socketHub.js';
import { startReminderEngine } from './services/reminderEngine.js';
import logger               from '../config/logger.js';

const PORT = parseInt(process.env.PORT || '4000', 10);

async function bootstrap() {
  // 1. Database
  await connectDB();

  // 2. HTTP server (Express sits inside)
  const httpServer = http.createServer(app);

  // 3. Socket.io — attaches to the same port, no separate WS server needed
  initSocketHub(httpServer);

  // 4. Persistent Nagger cron
  startReminderEngine();

  // 5. Listen
  httpServer.listen(PORT, '0.0.0.0', () => {
    logger.info(`🚀  AlzCare Node.js backend v2 on http://0.0.0.0:${PORT}`);
    logger.info(`🔌  Socket.io on ws://0.0.0.0:${PORT}  (path: /socket.io)`);
  });

  // Graceful shutdown
  const shutdown = (signal) => {
    logger.info(`${signal} received — shutting down …`);
    httpServer.close(() => { logger.info('Server closed.'); process.exit(0); });
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT',  () => shutdown('SIGINT'));
}

bootstrap().catch((err) => {
  logger.error(`Bootstrap failed: ${err.message}`);
  process.exit(1);
});
