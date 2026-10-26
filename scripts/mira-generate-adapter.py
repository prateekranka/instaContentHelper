import pathlib
import os
import json
import shutil
import subprocess
import uuid

root = pathlib.Path(__file__).resolve().parent.parent
tooling = root / 'work/omarchy-apple-dev'
pin = 'ceda63aa6ff04fc2e550a7c6a7eb13aa6cacd4de'
actual = subprocess.check_output(['git', '-C', str(tooling), 'rev-parse', 'HEAD'], text=True).strip()
if actual != pin:
    raise SystemExit('Use the omarchy tooling commit pinned in docs/mira-toolchain.md')
generated=root/'work'/('mira-adapter-'+uuid.uuid4().hex)
subprocess.run(['python3', str(tooling/'tools/xcodeproj2xtool.py'), str(root/'CreatorContentOS.xcodeproj'), '--target', 'CreatorContentOS', '--out', str(generated)], check=True)
for source in generated.rglob('*'):
    destination=root/'omarchy-xtool'/source.relative_to(generated)
    if source.is_symlink():
        destination.parent.mkdir(parents=True,exist_ok=True)
        if destination.is_symlink() and destination.resolve()==source.resolve():
            continue
        if destination.exists() or destination.is_symlink():
            raise SystemExit('Adapter symlink changed; review '+str(destination))
        destination.symlink_to(os.path.relpath(source.resolve(),destination.parent))
    elif source.is_dir():
        destination.mkdir(parents=True,exist_ok=True)
    else:
        if destination.is_symlink():
            raise SystemExit('Refusing to overwrite a source symlink: '+str(destination))
        shutil.copyfile(source,destination)
build_server=root/'.bsp/xtool.json'
if build_server.exists():
    data=json.loads(build_server.read_text());index=data['argv'].index('--package-path')
    data['argv'][index+1]='omarchy-xtool';build_server.write_text(json.dumps(data,indent=2)+'\n')
config = root/'omarchy-xtool/xtool.yml'
config.write_text(config.read_text().replace('infoPath: Info.plist', 'infoPath: Info.local.plist'))
lock = root/'CreatorContentOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
if lock.exists():
    shutil.copyfile(lock, root/'omarchy-xtool/Package.resolved')
