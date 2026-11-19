import { Controller, Get } from '@nestjs/common';
import { healthBody, type HealthBody } from '@winfield/shared';

/** Liveness only. Readiness (database, Redis) is added when those connections exist (M1). */
@Controller()
export class HealthController {
  @Get('health')
  health(): HealthBody {
    return healthBody('api');
  }
}
