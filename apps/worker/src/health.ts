import { createServer, type Server } from 'node:http';
import { healthBody } from '@winfield/shared';

/**
 * The worker has no public API; this tiny server exists so the host can health-check it (setup guide 6.4).
 * In M6 it will also report the scheduler heartbeat age and fail when the scheduler stalls.
 */
export function createHealthServer(): Server {
  return createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(healthBody('worker')));
      return;
    }
    res.writeHead(404).end();
  });
}
