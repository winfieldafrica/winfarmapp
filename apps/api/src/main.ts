import { createApp } from './app.js';
import { loadApiConfig } from './config.js';

const config = loadApiConfig();
const app = await createApp();
await app.listen({ port: config.API_PORT, host: '0.0.0.0' });
console.log(`api listening on :${config.API_PORT}`);
