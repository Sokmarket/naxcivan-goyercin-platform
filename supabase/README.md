# Supabase — V3 Foundation

This folder contains version-controlled database migrations and a minimal CLI `config.toml`.

## First migration

`migrations/20261110000000_v3_foundation.sql`

The migration is designed for a clean Supabase project. Review it before applying. Do not run it blindly against an existing database: first capture the remote schema and reconcile existing objects.

## CLI

After installing the official Supabase CLI and linking the intended project:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase migration list --remote
supabase db push --dry-run --remote
```

Only after reviewing the dry-run target and migration list should you apply:

```bash
supabase db push --remote
```

Do not use `db reset --remote` on production. It is destructive.

Supabase CLI v3 targets local by default for database commands; use `--remote` explicitly when the intended target is hosted.
