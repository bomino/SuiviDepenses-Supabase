-- Adds client-supplied idempotency token for offline INSERT replay.
-- Apply AFTER 20260430000005_project_budgets.sql.
-- Idempotent.

alter table public.expenses
    add column if not exists client_id uuid;

create unique index if not exists expenses_client_id_uidx
    on public.expenses(client_id) where client_id is not null;
