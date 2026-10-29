# DataEngineeringStuff

## ShutterPaid — Supabase backend

`supabase/` holds the Supabase project for ShutterPaid. Photographers manage clients and photo galleries, then invoice clients and take payment.

- `supabase/migrations/` — schema: `profiles`, `clients`, `galleries`, `photos`, `invoices`, `payments`, with row level security (each photographer sees only their own rows) and a private `photos` storage bucket (objects stored under `<user id>/...`).
- `.github/workflows/supabase-deploy.yml` — on push to `main` (or a manual run), it links the hosted project and runs `supabase db push`.

### One-time setup

1. Create a project named **ShutterPaid** at https://supabase.com/dashboard.
2. Add these repository secrets (Settings → Secrets and variables → Actions):
   - `SUPABASE_ACCESS_TOKEN`: a personal access token from https://supabase.com/dashboard/account/tokens
   - `SUPABASE_PROJECT_ID`: the project ref (the `xxxx` in `xxxx.supabase.co`)
   - `SUPABASE_DB_PASSWORD`: the database password chosen at project creation
3. Merge to `main` or run the workflow manually.

### Local development

```bash
npx supabase start      # needs Docker
npx supabase db reset   # re-applies migrations + seed.sql
```
