import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { NestFastifyApplication } from '@nestjs/platform-fastify';
import { createApp } from './app.js';

describe('api /health', () => {
  let app: NestFastifyApplication;
  beforeAll(async () => {
    app = await createApp();
  });
  afterAll(async () => {
    await app.close();
  });

  it('returns ok', async () => {
    const res = await app.getHttpAdapter().getInstance().inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok', service: 'api' });
  });

  it('denies unknown routes', async () => {
    const res = await app.getHttpAdapter().getInstance().inject({ method: 'GET', url: '/v1/farms' });
    expect(res.statusCode).toBe(404);
  });
});
