import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { baseEnv, loadConfig, port } from './config.js';

describe('loadConfig', () => {
  const schema = baseEnv.extend({ API_PORT: port(4000) });

  it('applies defaults', () => {
    expect(loadConfig(schema, {})).toEqual({ NODE_ENV: 'development', LOG_LEVEL: 'info', API_PORT: 4000 });
  });

  it('names the invalid variable without echoing its value', () => {
    const withSecret = schema.extend({ FIELD_ENCRYPTION_KEY: z.string().min(32) });
    const run = () => loadConfig(withSecret, { FIELD_ENCRYPTION_KEY: 'tooShortValue' });
    expect(run).toThrowError(/FIELD_ENCRYPTION_KEY/);
    expect(run).not.toThrowError(/tooShortValue/);
  });

  it('rejects an out-of-range port', () => {
    expect(() => loadConfig(schema, { API_PORT: '70000' })).toThrowError(/API_PORT/);
  });
});
