import { z } from 'zod';

/**
 * Reads and validates environment variables for a service.
 * Secret names follow setup guide Part 6.3 exactly; extra non-secret names are listed in
 * .env.example and docs/assumptions.md. Values are never logged.
 */
export function loadConfig<S extends z.ZodType>(schema: S, env: NodeJS.ProcessEnv = process.env): z.infer<S> {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const names = parsed.error.issues.map((i) => i.path.join('.')).join(', ');
    throw new Error(`Invalid or missing configuration: ${names}`);
  }
  return parsed.data;
}

export const port = (fallback: number) => z.coerce.number().int().min(1).max(65535).default(fallback);

export const baseEnv = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
});
