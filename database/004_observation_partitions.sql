-- 004_observation_partitions.sql — monthly partitions for sensor data.
-- Run once at install, then schedule `SELECT app.ensure_observation_partitions(3);` monthly (the worker does this).
-- Retention: detach/drop old partitions (DDL, so it does not conflict with the append-only row triggers).

SET search_path = app, public;

CREATE OR REPLACE FUNCTION app.ensure_observation_partitions(months_ahead int DEFAULT 3)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE m date; part text;
BEGIN
  FOR i IN -1 .. months_ahead LOOP
    m    := (date_trunc('month', now()) + make_interval(months => i))::date;
    part := format('observations_%s', to_char(m, 'YYYY_MM'));
    IF to_regclass('app.' || part) IS NULL THEN
      EXECUTE format('CREATE TABLE app.%I PARTITION OF app.observations FOR VALUES FROM (%L) TO (%L)',
                     part, m, (m + interval '1 month')::date);
      EXECUTE format('CREATE INDEX ON app.%I (farm_id, block_id, metric, observed_at DESC)', part);
      EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY', part);   -- defence in depth: no direct partition access
    END IF;
  END LOOP;
END $$;

SELECT app.ensure_observation_partitions(3);
