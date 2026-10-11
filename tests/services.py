"""Loader service API tests."""
import sys,subprocess
from pathlib import Path
fixture=Path(sys.argv[1]).resolve();package=Path(sys.argv[2]).resolve()
p=subprocess.Popen([str(fixture),'--serve',str(package/'mod.ini')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
def route(name):
    p.stdin.write((name+'\n').encode());p.stdin.flush()
    n=p.stdout.readline();assert n,n.decode(errors='replace')
    return p.stdout.read(int(n)).decode('utf8')
try:
    registry=route('ZML/Api');assert 'first-person-remix' in registry and 'keybinds' in registry and 'standard' in registry
    data=route('ZML/Get/first-person-remix');assert 'ok=true' in data and '["fov"]="85"' in data
    for key,value in [('fov','100'),('head_tilt','true'),('fun_effects','true'),('scan_period','2.25'),('show_body','false')]:
        result=route('ZML/Set/first-person-remix/'+key+'/'+value.encode().hex());assert 'ok=true' in result and 'restart=false' in result
    for key,value in [('fov','121'),('sensitivity','nan'),('enabled','yes'),('scan_period','2.13')]:
        assert 'ok=false' in route('ZML/Set/first-person-remix/'+key+'/'+value.encode().hex())
    assert '["fov"]="100"' in route('ZML/Get/first-person-remix')
    print('PASS actual public registry/schema/defaults/range validation/hot apply/persistence in temporary fixture')
finally:
    p.stdin.close()
    try:p.wait(timeout=10)
    except subprocess.TimeoutExpired:p.kill();p.wait()
    if p.returncode:raise RuntimeError(p.stderr.read().decode(errors='replace'))
