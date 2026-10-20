from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1]
suffixes={'.v','.sv','.adc','.sdc','.al','.xml','.ipc','.hex','.mem','.mif','.tcl'}
files={}
for base in (r/'rtl',r/'OUR_project'):
 for p in sorted(base.rglob('*')):
  if p.is_file() and p.suffix.lower() in suffixes and not any(x.endswith('_Runs') for x in p.parts):
   files[p.relative_to(r).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
bit=r/'bitbank/OUR_K1_4mode.bit'
result={'source_sha256':files,'source_file_count':len(files)}
if bit.exists():
 data=bit.read_bytes()
 result['bitstream']={'file':bit.relative_to(r).as_posix(),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'md5':hashlib.md5(data).hexdigest()}
(r/'MANIFEST.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='source_sha256'},indent=2))
