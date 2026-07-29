-- Track live workers and make run updates observable to status polling.
ALTER TABLE public.weekly_generation_runs
  ADD COLUMN IF NOT EXISTS heartbeat_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

UPDATE public.weekly_generation_runs
SET updated_at = now()
WHERE updated_at IS NULL;

ALTER TABLE public.weekly_generation_runs
  ALTER COLUMN updated_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET NOT NULL;

-- Index for heartbeat lookups on running runs.
CREATE INDEX IF NOT EXISTS idx_weekly_generation_runs_heartbeat
  ON public.weekly_generation_runs (heartbeat_at)
  WHERE status = 'running';

-- Portable updated_at trigger: the trigger itself is idempotent, and the
-- function body replaces the previous definition if it already exists.
CREATE OR REPLACE FUNCTION public.weekly_generation_runs_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_weekly_generation_runs_set_updated_at
  ON public.weekly_generation_runs;

CREATE TRIGGER trg_weekly_generation_runs_set_updated_at
  BEFORE UPDATE ON public.weekly_generation_runs
  FOR EACH ROW
  EXECUTE FUNCTION public.weekly_generation_runs_set_updated_at();
