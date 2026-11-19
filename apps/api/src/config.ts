import { baseEnv, loadConfig, port } from '@winfield/shared';

export const apiEnv = baseEnv.extend({ API_PORT: port(4000) });
export type ApiConfig = ReturnType<typeof loadApiConfig>;
export const loadApiConfig = (env: NodeJS.ProcessEnv = process.env) => loadConfig(apiEnv, env);
