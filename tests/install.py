"""Installer tests."""
import sys,tempfile,subprocess,json,hashlib,shutil
from pathlib import Path
installer=Path(sys.argv[1]).resolve();source=Path(sys.argv[2]).resolve()
def hashset(path):return {str(p.relative_to(path)):hashlib.sha256(p.read_bytes()).hexdigest() for p in path.rglob('*') if p.is_file()}
with tempfile.TemporaryDirectory(prefix='zml-firstperson-install-') as folder:
    root=Path(folder).resolve();assert root.parent==Path(tempfile.gettempdir()).resolve() and root.name.startswith('zml-firstperson-install-')
    installRoot=root/'framework';installRoot.mkdir()
    protected=installRoot/'mods/other';protected.mkdir(parents=True);(protected/'private.txt').write_text('unrelated')
    state=installRoot/'state/first-person-remix';state.mkdir(parents=True);(state/'config.ini').write_text('fov=97\n')
    before=hashset(protected);private=hashset(state)
    def install(pkg,ok=True):
        result=subprocess.run(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(installer),'-ModPackage',str(pkg),'-PackageRoot',str(installRoot)],capture_output=True,text=True)
        assert (result.returncode==0)==ok,result.stdout+result.stderr
    install(source)
    target=installRoot/'mods/first-person-remix';expected=json.loads((source/'zml-package.json').read_text())['files']+['zml-package.json']
    assert set(hashset(target))==set(expected)
    assert all((target/n).read_bytes()==(source/n).read_bytes() for n in expected)
    old=hashset(target)
    changed=root/'new-package';shutil.copytree(source,changed)
    with (changed/'native.lua').open('a',encoding='utf8')as f:f.write('\n-- updated copy fixture\n')
    install(changed)
    assert hashset(target)!=old
    backup=list((installRoot/'.mod-backups').iterdir());assert len(backup)==1 and hashset(backup[0])==old
    malformed=root/'malformed';shutil.copytree(changed,malformed);(malformed/'native.lua').unlink()
    stable=hashset(target);install(malformed,False);assert hashset(target)==stable
    displaced=root/'rollback-new';restore=backup[0].resolve()
    for path in (target.resolve(),displaced.resolve(),restore):assert path.is_relative_to(root)
    target.rename(displaced);restore.rename(target)
    assert hashset(target)==old and hashset(protected)==before and hashset(state)==private
    print('PASS installer forward/update/backup/rollback')
