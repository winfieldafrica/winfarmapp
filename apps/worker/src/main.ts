import { baseEnv, loadConfig, port } from '@winfield/shared';
import { createHealthServer } from './health.js';

const config = loadConfig(baseEnv.extend({ WORKER_HEALTH_PORT: port(4200) }));
const server = createHealthServer();
server.listen(config.WORKER_HEALTH_PORT, '0.0.0.0', () => {
  console.log(`worker health on :${config.WORKER_HEALTH_PORT}`);
});

const shutdown = () => server.close(() => process.exit(0));
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
