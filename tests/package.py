import sys,json,configparser,struct
from pathlib import Path
root=Path(sys.argv[1]);source=Path(__file__).resolve().parents[1]/'mod'
m=json.loads((root/'zml-package.json').read_text());assert m['id']=='first-person'
assert len(set(m['files']))==len(m['files'])==6
ini=configparser.ConfigParser();ini.read(root/'mod.ini',encoding='utf8')
assert ini['mod']['depends']=='keybinds' and ini['mod']['config_menu']=='standard'
assert ini['mod']['icon']=='icon.png' and 'config_entry' not in ini['mod']
for name in m['files']:
    assert Path(name).name==name and (root/name).is_file()
    if name!='FirstPerson.dll':assert (root/name).read_bytes()==(source/name).read_bytes()
schema=configparser.ConfigParser();schema.read(root/'config.ini',encoding='utf8')
_src=configparser.ConfigParser();_src.read(source/'config.ini',encoding='utf8')
assert len(schema.sections())==len(_src.sections())
assert set(schema.sections())==set(_src.sections())
assert schema['field.turn_threshold']['default']=='90' and schema['field.native_body_turn']['default']=='false'
assert schema['field.head_look_binding']['default']=='false'
assert schema['field.turn_in_place']['default']=='true'
assert schema['field.height_variation']['default']=='false' and schema['field.show_body']['default']=='true'
for name in schema.sections():
    if name.startswith('field.'):
        f=schema[name];assert f['type'] in ('bool','number')
        if f['type']=='bool':assert f['default'] in ('true','false')
        else:assert float(f['min'])<=float(f['default'])<=float(f['max']) and float(f['step'])>0
p=(root/'icon.png').read_bytes();assert p[:8]==b'\x89PNG\r\n\x1a\n' and len(p)<=65536
assert struct.unpack('>II',p[16:24])==(256,256) and p[25]==6
print('PASS exact whitelist, independent keybind dependency, standard-only schema, PNG')
