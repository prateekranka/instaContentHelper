import os
import pathlib
import subprocess
import signal
import uuid

root = pathlib.Path(__file__).resolve().parent.parent
name = 'mira-contract-' + uuid.uuid4().hex[:12]
docker = ['docker', f"--host={os.environ.get('DOCKER_HOST', 'unix:///var/run/docker.sock')}"]
def interrupted(_number, _frame):
    raise SystemExit('SQL check interrupted')
signal.signal(signal.SIGTERM, interrupted)
try:
    subprocess.run(docker + ['run', '--rm', '-d', '--name', name, '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17-alpine@sha256:266d3c257594e195b309ae9d1805e54c788f1d7b375f56bf6c367aac6c917e7b'], check=True, stdout=subprocess.DEVNULL)
    log = subprocess.Popen(docker + ['logs', '--follow', name], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    initialized = False
    try:
        for line in log.stdout:
            if 'PostgreSQL init process complete' in line:
                initialized = True
            if initialized and 'database system is ready to accept connections' in line:
                break
    finally:
        log.terminate()
        log.wait(timeout=5)
    migrations = sorted((root / 'supabase/migrations').glob('*mira*.sql'))
    if not migrations:
        raise RuntimeError('No Mira migrations found')
    for migration in migrations:
        print(f'Checking {migration.name}', flush=True)
    suite = (root / 'supabase/functions/mira-generation/jobs_test.sql').read_text()
    suite = suite.replace(r'\i /mira-migrations.sql', '\n'.join(path.read_text() for path in migrations))
    subprocess.run(docker + ['exec', '-i', name, 'psql', '-U', 'postgres'], input=suite,
                   text=True, check=True, timeout=40)
finally:
    subprocess.run(docker + ['rm', '--force', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
