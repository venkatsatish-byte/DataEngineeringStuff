-- ShutterPaid initial schema
-- Photographers (auth users) manage clients, deliver photo galleries, and invoice/collect payment.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.gallery_status as enum ('draft', 'published', 'archived');
create type public.invoice_status as enum ('draft', 'sent', 'paid', 'void');
create type public.payment_status as enum ('pending', 'succeeded', 'failed', 'refunded');

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  display_name       text,
  business_name      text,
  stripe_account_id  text unique,
  default_currency   char(3) not null default 'USD',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table public.clients (
  id               uuid primary key default gen_random_uuid(),
  photographer_id  uuid not null references public.profiles (id) on delete cascade,
  name             text not null,
  email            text,
  phone            text,
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index clients_photographer_id_idx on public.clients (photographer_id);

create table public.galleries (
  id               uuid primary key default gen_random_uuid(),
  photographer_id  uuid not null references public.profiles (id) on delete cascade,
  client_id        uuid references public.clients (id) on delete set null,
  title            text not null,
  slug             text not null unique,
  status           public.gallery_status not null default 'draft',
  price_cents      integer not null default 0 check (price_cents >= 0),
  currency         char(3) not null default 'USD',
  expires_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index galleries_photographer_id_idx on public.galleries (photographer_id);
create index galleries_client_id_idx on public.galleries (client_id);

create table public.photos (
  id               uuid primary key default gen_random_uuid(),
  gallery_id       uuid not null references public.galleries (id) on delete cascade,
  photographer_id  uuid not null references public.profiles (id) on delete cascade,
  storage_path     text not null unique,
  filename         text not null,
  width            integer,
  height           integer,
  position         integer not null default 0,
  created_at       timestamptz not null default now()
);
create index photos_gallery_id_idx on public.photos (gallery_id, position);

create table public.invoices (
  id               uuid primary key default gen_random_uuid(),
  photographer_id  uuid not null references public.profiles (id) on delete cascade,
  client_id        uuid not null references public.clients (id) on delete restrict,
  gallery_id       uuid references public.galleries (id) on delete set null,
  number           text not null,
  amount_cents     integer not null check (amount_cents >= 0),
  currency         char(3) not null default 'USD',
  status           public.invoice_status not null default 'draft',
  due_date         date,
  paid_at          timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (photographer_id, number)
);
create index invoices_photographer_id_idx on public.invoices (photographer_id);
create index invoices_client_id_idx on public.invoices (client_id);

create table public.payments (
  id                   uuid primary key default gen_random_uuid(),
  invoice_id           uuid not null references public.invoices (id) on delete cascade,
  photographer_id      uuid not null references public.profiles (id) on delete cascade,
  amount_cents         integer not null check (amount_cents > 0),
  currency             char(3) not null default 'USD',
  provider             text not null default 'stripe',
  provider_payment_id  text unique,
  status               public.payment_status not null default 'pending',
  created_at           timestamptz not null default now()
);
create index payments_invoice_id_idx on public.payments (invoice_id);

-- updated_at triggers
create trigger profiles_set_updated_at  before update on public.profiles  for each row execute function public.set_updated_at();
create trigger clients_set_updated_at   before update on public.clients   for each row execute function public.set_updated_at();
create trigger galleries_set_updated_at before update on public.galleries for each row execute function public.set_updated_at();
create trigger invoices_set_updated_at  before update on public.invoices  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Create a profile row for every new auth user
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', new.email));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row level security: photographers only see and change their own rows
-- ---------------------------------------------------------------------------
alter table public.profiles  enable row level security;
alter table public.clients   enable row level security;
alter table public.galleries enable row level security;
alter table public.photos    enable row level security;
alter table public.invoices  enable row level security;
alter table public.payments  enable row level security;

create policy "Own profile: select" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy "Own profile: update" on public.profiles
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy "Own clients" on public.clients
  for all to authenticated
  using ((select auth.uid()) = photographer_id)
  with check ((select auth.uid()) = photographer_id);

create policy "Own galleries" on public.galleries
  for all to authenticated
  using ((select auth.uid()) = photographer_id)
  with check ((select auth.uid()) = photographer_id);

create policy "Own photos" on public.photos
  for all to authenticated
  using ((select auth.uid()) = photographer_id)
  with check (
    (select auth.uid()) = photographer_id
    and exists (
      select 1 from public.galleries g
      where g.id = gallery_id and g.photographer_id = (select auth.uid())
    )
  );

create policy "Own invoices" on public.invoices
  for all to authenticated
  using ((select auth.uid()) = photographer_id)
  with check ((select auth.uid()) = photographer_id);

-- Payments are written by the server (service role, e.g. a Stripe webhook); owners can only read them.
create policy "Own payments: select" on public.payments
  for select to authenticated using ((select auth.uid()) = photographer_id);

-- ---------------------------------------------------------------------------
-- Storage: private "photos" bucket, objects stored under "<user id>/..."
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

create policy "Photos: owner read" on storage.objects
  for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Photos: owner insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Photos: owner update" on storage.objects
  for update to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Photos: owner delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
