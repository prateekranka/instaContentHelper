alter table public.members
  add column if not exists email text;

update public.members as member
set email = lower(btrim(auth_user.email))
from auth.users as auth_user
where member.auth_user_id = auth_user.id
  and member.email is null
  and auth_user.email is not null;

alter table public.members
  add constraint members_email_normalized_check
  check (email is null or email = lower(btrim(email)))
  not valid;

alter table public.members
  validate constraint members_email_normalized_check;

create unique index if not exists members_active_workspace_email_uidx
  on public.members (workspace_id, lower(email))
  where status = 'active' and email is not null;

create unique index if not exists members_active_workspace_auth_user_uidx
  on public.members (workspace_id, auth_user_id)
  where status = 'active' and auth_user_id is not null;

create index if not exists device_installations_active_member_idx
  on public.device_installations (member_id, id)
  where revoked_at is null;

comment on column public.members.email is
  'Normalized approved sign-in email. Auth identity remains bound by auth_user_id.';
