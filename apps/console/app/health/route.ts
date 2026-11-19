import { healthBody } from '@winfield/shared';

export const dynamic = 'force-dynamic';

export function GET(): Response {
  return Response.json(healthBody('console'));
}
