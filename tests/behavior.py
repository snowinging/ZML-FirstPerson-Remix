import sys,argparse,configparser
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--lupa-dir',required=True);p.add_argument('--keybinds',default='');a=p.parse_args()
sys.path.insert(0,a.lupa_dir)
from lupa.lua54 import LuaRuntime
root=Path(__file__).resolve().parents[1];lua=LuaRuntime()
c=configparser.ConfigParser();c.read(root/'mod/config.ini',encoding='utf8')
values={k[6:]:v['default'] for k,v in c.items() if k.startswith('field.')}
lua.globals().defaults=lua.table_from(values)
lua.globals().Factory=lua.execute((root/'mod/controller.lua').read_text(encoding='utf8'))
lua.execute((root/'tests/behavior.lua').read_text(encoding='utf8'))
if a.keybinds:
    lua.globals().KBFactory=lua.execute(Path(a.keybinds).read_text(encoding='utf8'))
    lua.execute('''
    local held={};local written
    local k=KBFactory({read=function() return nil end,validKey=function(key) return key=='Ctrl+F5' or key=='F8' or key=='None' end,
        owner=function(id) return id=='first-person-remix' and '第一人称' end,down=function(key)
            if key=='Ctrl+F5' then return held.Ctrl==true and held.F5==true end
            return held[key]
        end,
        allowed=function() return not blockKeys end,write=function(text) written=text;return true end})
    local a=assert(k.register('first-person-remix',{id='toggle',name='第一人称 · 切换视角',primary='Ctrl+F5'}))
    assert(a.get()[1]=='Ctrl+F5');assert(not a.pressed())
    held.F4=true;assert(not a.pressed());held.F5=true;assert(not a.pressed())
    held.F5=false;held.Ctrl=true;assert(not a.pressed());held.F5=true;assert(a.pressed());assert(not a.pressed())
    blockKeys=true;assert(not a.pressed());blockKeys=false;assert(not a.pressed())
    held.F5=false;assert(not a.pressed());assert(k._stage(a.id,1,'F8'));assert(k._save());assert(written:find('F8'))
    held.F5=true;assert(not a.pressed());held.F8=true;assert(a.pressed());assert(k.list()[1].owner=='first-person-remix')
    ''')
    print('PASS actual public keybind library registration, rebind, focus gate, edge debounce')
