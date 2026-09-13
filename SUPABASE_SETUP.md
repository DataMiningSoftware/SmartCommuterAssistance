# Supabase Setup — Social / Competition / Education Features

The friends, party, race, and education features require the following to be
done once against your live Supabase project. These are manual (need your
service key), so they are not automated here.

## 1. Apply migrations (in order)

Run the migrations in the Supabase SQL Editor (Dashboard → SQL Editor), or
run `python scripts/apply_migrations.py` with `DATABASE_URL` set.

In order:

1. `supabase/migration_profiles.sql`
2. `supabase/storage_avatars.sql`
3. `supabase/migration_social.sql`
4. `supabase/migration_competition.sql`
5. `supabase/migration_education.sql`
6. `supabase/rls_policies.sql`
7. `supabase/rls_social_policies.sql`

## 2. Enable Realtime

Dashboard → **Database → Replication** → enable Realtime for these tables:

- `parties`
- `party_members`
- `races`
- `race_participants`
- `race_checkpoints`

(The migrations already add them to the `supabase_realtime` publication; the
dashboard toggle makes the tables actually stream.)

## 3. Enable email confirmation (optional)

Dashboard → **Authentication → Providers → Email** → toggle **Confirm email**.

- ON  → signups get a verification email before they can log in (the app shows
  "check your email").
- OFF → signups log in immediately.

## 4. Verify tables

Confirm `route_connections` and `train_stops_kl` are populated (the app falls
back to the bundled CSV if `route_connections` is empty).

## 5. Storage bucket (avatars)

`supabase/storage_avatars.sql` creates the `avatars` bucket. Verify it appears
under Dashboard → **Storage**.
