import { baseEnv, loadConfig, port } from '@winfield/shared';
import { createApp } from './app.js';

const config = loadConfig(baseEnv.extend({ INGEST_PORT: port(4100) }));
const app = createApp();
await app.listen({ port: config.INGEST_PORT, host: '0.0.0.0' });
console.log(`ingest listening on :${config.INGEST_PORT}`);
