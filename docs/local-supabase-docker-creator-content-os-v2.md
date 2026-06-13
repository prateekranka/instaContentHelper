# Local Supabase and Docker Setup: Creator Content OS V2

This workspace now has a local Docker runtime through Homebrew Docker CLI plus Colima.

## Installed Runtime

- Docker CLI: Homebrew `docker`
- Docker Compose plugin: Homebrew `docker-compose`
- Docker VM/runtime: Homebrew `colima`
- Colima profile: default
- Colima runtime: Docker
- Colima resources used for this project: 4 CPU, 8 GB memory, 60 GB disk request

Docker verification:

```sh
docker version
docker compose version
docker info
colima status
```

## Colima Socket Note

Supabase local logging/vector tries to mount a Docker socket into a container.
With Colima, Docker's context socket is at:

```text
$HOME/.colima/default/docker.sock
```

Mounting that path caused:

```text
error while creating mount source path '$HOME/.colima/default/docker.sock':
mkdir ... operation not supported
```

The standard fix is to symlink Colima's socket to `/var/run/docker.sock`, but that requires sudo on this machine. For this project, the working no-sudo path is:

```sh
supabase start -x vector
```

That keeps the Supabase stack usable for Postgres, API, Storage, Auth, Studio, and Edge Functions while skipping the vector log collector.

## Local Start

```sh
colima start --cpu 4 --memory 8 --disk 60
supabase start -x vector
```

Current local endpoints:

- Studio: `http://127.0.0.1:54323`
- API: `http://127.0.0.1:54321`
- REST: `http://127.0.0.1:54321/rest/v1`
- Edge Functions: `http://127.0.0.1:54321/functions/v1`
- Database: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`

## Validated Flow

The local stack was tested with:

1. `supabase db reset`
2. schema count query:
   - 34 public tables
   - 126 RLS policies
   - 143 public indexes
3. seeded local workspace, creator, and device invite
4. called `pair-device`
5. called `publish-week` with the returned device token
6. verified:
   - invite `used_count = 1`
   - one device installation created
   - weekly plan status `published`
   - weekly plan `is_soft_locked = true`
   - seven daily cards written
   - `2026-06-05` Creator Today card exists and is published

## Schema Grant Note

Because `auto_expose_new_tables = false`, Edge Functions need explicit service-role grants. The initial schema migration now grants public schema usage and all public table/function/sequence privileges to `service_role`.
