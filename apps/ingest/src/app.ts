import Fastify, { type FastifyInstance } from 'fastify';
import { healthBody } from '@winfield/shared';

/** Device ingestion service (separate from the API to isolate device traffic). Ingest routes arrive in M11. */
export function createApp(): FastifyInstance {
  const app = Fastify({ bodyLimit: 262_144, logger: false });
  app.get('/health', async () => healthBody('ingest'));
  return app;
}
