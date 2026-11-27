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
    migrations = [
        '20261026170000_mira_generation_jobs.sql',
        '20261119012500_mira_three_active_jobs.sql',
        '20261127190000_mira_job_state_machine.sql',
        '20261127200000_mira_steps_and_shot_pictures.sql',
    ]
    for migration in migrations:
        subprocess.run(docker + ['cp', str(root/'supabase/migrations'/migration), f'{name}:/{migration}'], check=True)
    with (root/'supabase/functions/mira-generation/jobs_test.sql').open('rb') as stream:
        subprocess.run(docker + ['exec', '-i', name, 'psql', '-U', 'postgres'], stdin=stream, check=True, timeout=40)
finally:
    subprocess.run(docker + ['rm', '--force', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
