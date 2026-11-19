export type ServiceName = 'api' | 'worker' | 'ingest' | 'console';

export interface HealthBody {
  status: 'ok';
  service: ServiceName;
}

export function healthBody(service: ServiceName): HealthBody {
  return { status: 'ok', service };
}
