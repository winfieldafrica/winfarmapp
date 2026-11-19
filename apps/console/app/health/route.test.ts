import { describe, expect, it } from 'vitest';
import { GET } from './route';

describe('console /health', () => {
  it('returns ok', async () => {
    const res = GET();
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: 'ok', service: 'console' });
  });
});
