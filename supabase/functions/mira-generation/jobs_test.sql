\set ON_ERROR_STOP on
create role anon;
create role authenticated;
create role service_role;
create table public.workspaces(id uuid primary key);
create table public.creators(id uuid primary key, workspace_id uuid references public.workspaces);
create table public.members(id uuid primary key, workspace_id uuid references public.workspaces);
\i /migration.sql
insert into public.workspaces values('10000000-0000-4000-8000-000000000001');
insert into public.creators values('10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001');
insert into public.members values('10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001');
do $$
declare row public.mira_generation_jobs; repeated public.mira_generation_jobs; claims integer;
begin
 row=public.mira_enqueue('10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003',1,'{"operation":"ideas"}');
 repeated=public.mira_enqueue(row.id,row.workspace_id,row.creator_id,row.member_id,1,row.input);
 assert repeated.created_at=row.created_at,'duplicate submission created a different job';
 begin
  perform public.mira_enqueue(row.id,row.workspace_id,row.creator_id,row.member_id,2,row.input);
  raise exception 'expected idempotency conflict';
 exception when others then
  if sqlerrm not like '%idempotency_conflict%' then raise; end if;
 end;
 select count(*) into claims from public.mira_claim(row.id);assert claims=1,'job not claimed';
 select count(*) into claims from public.mira_claim(row.id);assert claims=0,'concurrent claim acquired an active lease';
 update public.mira_generation_jobs set lease_until=now()-interval '1 second' where id=row.id;
 select count(*) into claims from public.mira_claim(row.id);assert claims=1,'interrupted worker not recovered';
 update public.mira_generation_jobs set attempts=3,lease_until=now()-interval '1 second' where id=row.id;
 perform public.mira_claim(row.id);
 assert (select status='failed' from public.mira_generation_jobs where id=row.id),'interrupted worker exceeded retry bound';
 update public.mira_generation_jobs set status='cancelled',attempts=0 where id=row.id;
 select count(*) into claims from public.mira_claim(row.id);assert claims=0,'cancelled job restarted';
end $$;
set role anon;
do $$begin
 begin
  perform public.mira_claim('10000000-0000-4000-8000-000000000004');
  raise exception 'anonymous caller obtained a claim';
 exception when insufficient_privilege then null;
 end;
 begin
  perform count(*) from public.mira_generation_jobs;
  raise exception 'anonymous caller read private jobs';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
select 'PASS: job idempotency, lease exclusion, interrupted recovery, bounded attempts, cancellation and anonymous access restrictions' as verification;
