import { describe, expect, it } from 'vitest';
import { createApp } from './app.js';

describe('ingest /health', () => {
  it('returns ok', async () => {
    const app = createApp();
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok', service: 'ingest' });
    await app.close();
  });
});
