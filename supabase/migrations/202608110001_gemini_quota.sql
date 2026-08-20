create table if not exists public.gemini_usage (
  user_id uuid primary key references auth.users(id) on delete cascade,
  minute_started_at timestamptz not null default now(),
  minute_count integer not null default 0 check (minute_count >= 0),
  day_started_at date not null default current_date,
  day_count integer not null default 0 check (day_count >= 0),
  updated_at timestamptz not null default now()
);

alter table public.gemini_usage enable row level security;
revoke all on public.gemini_usage from anon, authenticated;

create or replace function public.consume_gemini_quota(
  p_minute_limit integer default 6,
  p_daily_limit integer default 50
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_usage public.gemini_usage%rowtype;
begin
  if v_user_id is null then return false; end if;

  insert into public.gemini_usage (user_id, minute_count, day_count)
  values (v_user_id, 0, 0)
  on conflict (user_id) do nothing;

  select * into v_usage
  from public.gemini_usage
  where user_id = v_user_id
  for update;

  if v_usage.day_started_at <> current_date then
    v_usage.day_started_at := current_date;
    v_usage.day_count := 0;
  end if;
  if v_usage.minute_started_at < now() - interval '1 minute' then
    v_usage.minute_started_at := now();
    v_usage.minute_count := 0;
  end if;
  if v_usage.minute_count >= p_minute_limit or
     v_usage.day_count >= p_daily_limit then
    update public.gemini_usage set
      minute_started_at = v_usage.minute_started_at,
      minute_count = v_usage.minute_count,
      day_started_at = v_usage.day_started_at,
      day_count = v_usage.day_count,
      updated_at = now()
    where user_id = v_user_id;
    return false;
  end if;

  update public.gemini_usage set
    minute_started_at = v_usage.minute_started_at,
    minute_count = v_usage.minute_count + 1,
    day_started_at = v_usage.day_started_at,
    day_count = v_usage.day_count + 1,
    updated_at = now()
  where user_id = v_user_id;
  return true;
end;
$$;

revoke all on function public.consume_gemini_quota(integer, integer)
  from public, anon;
grant execute on function public.consume_gemini_quota(integer, integer)
  to authenticated;
