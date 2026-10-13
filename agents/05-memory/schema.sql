CREATE TABLE IF NOT EXISTS episodes (
  id          bigserial PRIMARY KEY,
  agent       text NOT NULL,
  user_id     text NOT NULL,
  skill       text NOT NULL,
  observation text NOT NULL,
  action      text,
  reason      text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS episodes_agent_created
  ON episodes (agent, created_at DESC);
