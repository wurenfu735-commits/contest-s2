from pathlib import Path
import hashlib,json,re
r=Path(__file__).resolve().parents[1]
m=json.loads((r/'MANIFEST.json').read_text(encoding='utf-8'))
for name,want in m['source_sha256'].items():
 assert hashlib.sha256((r/name).read_bytes()).hexdigest()==want,name
bit=r/m['bitstream']['file']
assert hashlib.sha256(bit.read_bytes()).hexdigest()==m['bitstream']['sha256']
project=r/'OUR_project/hdmi_base_src/td_project'
for name in re.findall(r'<File Path="([^"]+)"',(project/'OUR_K1_4mode.al').read_text(encoding='utf-8')):
 assert (project/name).is_file(),name
timing=(project/'OUR_K1_4mode_Runs/phy_1/OUR_K1_4mode_pr.timing').read_text()
assert 'Confidence          : Routed' in timing
assert 'SWNS: 0.112ns, STNS: 0.000ns' in timing
assert 'HWNS: 0.020ns, HTNS: 0.000ns' in timing
for log in ['build_syn_1.log','build_phy_1.log']:
 text=(r/'sim'/log).read_text(encoding='utf-8-sig')
 assert 'FLOW_OK' in text
 assert not re.search(r'\bERROR:',text),log
for log in ['key_verification.log','rgb_verification.log','adapter_verification.log','eram_full/verification.log']:
 assert 'PASS' in (r/'sim'/log).read_text(encoding='utf-8-sig'),log
assert 'PROJECT_OK' in (r/'sim/project_check.log').read_text(encoding='utf-8-sig')
assert hashlib.md5(Path('E:/fpga/contest-s2/src/p1_colorbar/bitbank/OUR_b4osd_v5_darkfloor.bit').read_bytes()).hexdigest()=='8c1a75f720d2885fa22e4b6d10bab15a'
print(f"PASS delivery: {len(m['source_sha256'])} source/IP hashes, all project paths, bit SHA256, routed timing, four test logs, original bit unchanged")
