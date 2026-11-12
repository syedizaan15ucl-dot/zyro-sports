-- ZYRO store: one-time database setup for Supabase.
-- Paste this whole file into Supabase > SQL Editor > New query > Run.
-- Change the email below if the administrator account uses another email.

create table if not exists public.admins (email text primary key);
insert into public.admins (email) values ('khawajaizaanahmad@gmail.com') on conflict do nothing;
alter table public.admins enable row level security;   -- no policies: nobody can read this table directly

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
grant execute on function public.is_admin() to anon, authenticated;

create table if not exists public.products (id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.clubs    (id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.settings (key text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.entries (
  id text primary key,
  type text not null check (type in ('order', 'contact', 'design')),
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled')),
  at timestamptz not null default now(),
  data jsonb not null default '{}'::jsonb
);
create index if not exists entries_at_idx on public.entries (at desc);

alter table public.products enable row level security;
alter table public.clubs enable row level security;
alter table public.settings enable row level security;
alter table public.entries enable row level security;

-- Everyone can read the shop catalogue. Only the administrator can change it.
drop policy if exists "products read" on public.products;   create policy "products read" on public.products for select using (true);
drop policy if exists "clubs read" on public.clubs;         create policy "clubs read" on public.clubs for select using (true);
drop policy if exists "settings read" on public.settings;   create policy "settings read" on public.settings for select using (true);
drop policy if exists "products admin" on public.products;  create policy "products admin" on public.products for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "clubs admin" on public.clubs;        create policy "clubs admin" on public.clubs for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "settings admin" on public.settings;  create policy "settings admin" on public.settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Orders and messages: customers can NOT read or write this table directly. Only the administrator can.
drop policy if exists "entries admin" on public.entries;    create policy "entries admin" on public.entries for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Customers place orders only through this function. It prices the order from the products table,
-- so a customer cannot send their own prices.
create or replace function public.place_order(p_customer jsonb, p_items jsonb, p_hp text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  who text := left(trim(coalesce(p_customer ->> 'who', '')), 80);
  phone text := left(trim(coalesce(p_customer ->> 'phone', '')), 30);
  addr text := left(trim(coalesce(p_customer ->> 'address', '')), 300);
  it jsonb; pr jsonb; qty int; sz text; price int;
  subtotal int := 0; lines jsonb := '[]'::jsonb; threshold int; ship text; ref text;
begin
  if coalesce(p_hp, '') <> '' then return jsonb_build_object('ref', 'ZY-OK', 'total', 0, 'shipping', 'to be confirmed'); end if;
  if length(who) < 2 then raise exception 'Please enter your full name.'; end if;
  if length(regexp_replace(phone, '\D', '', 'g')) < 7 then raise exception 'Please enter a valid phone number.'; end if;
  if length(addr) < 6 then raise exception 'Please enter your delivery address.'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Your cart is empty.'; end if;
  if jsonb_array_length(p_items) > 30 then raise exception 'Too many items in one order.'; end if;
  if (select count(*) from entries where at > now() - interval '1 minute') > 40 then raise exception 'We are receiving many orders right now. Please try again in a minute.'; end if;

  for it in select * from jsonb_array_elements(p_items) loop
    select data into pr from products where id = it ->> 'id';
    if pr is null or coalesce(pr ->> 'active', 'true') = 'false' then raise exception 'An item in your cart is no longer available. Please refresh the page.'; end if;
    if coalesce(pr ->> 'stock', 'true') = 'false' then raise exception '% is sold out.', coalesce(pr ->> 'name', 'An item'); end if;
    qty := greatest(1, least(12, coalesce(nullif(regexp_replace(coalesce(it ->> 'qty', ''), '\D', '', 'g'), '')::int, 1)));
    sz := left(coalesce(it ->> 'size', ''), 20);
    if jsonb_typeof(pr -> 'sizes') = 'array' and jsonb_array_length(pr -> 'sizes') > 0 and sz <> '' and not (pr -> 'sizes') ? sz then
      raise exception 'Invalid size for %.', coalesce(pr ->> 'name', 'an item');
    end if;
    price := coalesce(nullif(regexp_replace(coalesce(pr ->> 'price', ''), '[^0-9]', '', 'g'), '')::int, 0);
    subtotal := subtotal + price * qty;
    lines := lines || jsonb_build_object('id', it ->> 'id', 'qty', qty, 'size', sz, 'price', price,
      'name', trim(coalesce(pr ->> 'team', '') || ' ' || coalesce(pr ->> 'name', '')));
  end loop;

  threshold := coalesce((select nullif(regexp_replace(coalesce(data ->> 'freeShip', ''), '[^0-9]', '', 'g'), '')::int from settings where key = 'site'), 6300);
  if threshold <= 0 then threshold := 6300; end if;
  ship := case when subtotal > threshold then 'free' else 'to be confirmed' end;
  ref := 'ZY-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into entries (id, type, status, data)
  values (ref, 'order', 'pending', jsonb_build_object(
    'customer', jsonb_build_object('who', who, 'phone', phone, 'address', addr),
    'items', lines, 'total', subtotal, 'shipping', ship));
  return jsonb_build_object('ref', ref, 'total', subtotal, 'shipping', ship);
end $$;

-- Contact messages and custom design uploads from customers.
create or replace function public.submit_entry(p_type text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ref text; d jsonb;
begin
  if p_type not in ('contact', 'design') then raise exception 'Unknown request.'; end if;
  if (select count(*) from entries where at > now() - interval '1 minute') > 40 then raise exception 'Please try again in a minute.'; end if;
  if p_type = 'contact' then
    if length(trim(coalesce(p_data ->> 'who', ''))) < 1 or length(trim(coalesce(p_data ->> 'msg', ''))) < 1 then raise exception 'Please add your name and a message.'; end if;
    d := jsonb_build_object('who', left(p_data ->> 'who', 80), 'phone', left(coalesce(p_data ->> 'phone', ''), 30),
                            'email', left(coalesce(p_data ->> 'email', ''), 120), 'msg', left(p_data ->> 'msg', 2000));
    ref := 'MSG-';
  else
    if left(coalesce(p_data ->> 'img', ''), 11) <> 'data:image/' then raise exception 'Please upload your design image.'; end if;
    if length(p_data ->> 'img') > 600000 then raise exception 'That image is too large.'; end if;
    d := jsonb_build_object('img', p_data ->> 'img', 'size', left(coalesce(p_data ->> 'size', ''), 10),
                            'qty', greatest(1, least(12, coalesce(nullif(regexp_replace(coalesce(p_data ->> 'qty', ''), '\D', '', 'g'), '')::int, 1))),
                            'note', left(coalesce(p_data ->> 'note', ''), 400));
    ref := 'DSN-';
  end if;
  ref := ref || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into entries (id, type, status, data) values (ref, p_type, 'pending', d);
  return jsonb_build_object('ref', ref);
end $$;

grant execute on function public.place_order(jsonb, jsonb, text) to anon, authenticated;
grant execute on function public.submit_entry(text, jsonb) to anon, authenticated;

-- Product photos: public to view, only the administrator can upload or remove.
insert into storage.buckets (id, name, public) values ('product-images', 'product-images', true)
  on conflict (id) do update set public = true;
drop policy if exists "zyro images read" on storage.objects;
create policy "zyro images read" on storage.objects for select using (bucket_id = 'product-images');
drop policy if exists "zyro images insert" on storage.objects;
create policy "zyro images insert" on storage.objects for insert to authenticated with check (bucket_id = 'product-images' and public.is_admin());
drop policy if exists "zyro images update" on storage.objects;
create policy "zyro images update" on storage.objects for update to authenticated using (bucket_id = 'product-images' and public.is_admin()) with check (bucket_id = 'product-images' and public.is_admin());
drop policy if exists "zyro images delete" on storage.objects;
create policy "zyro images delete" on storage.objects for delete to authenticated using (bucket_id = 'product-images' and public.is_admin());
