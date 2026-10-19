#!/usr/bin/env python3
"""Deterministic-path source + prebuilt ZIP inventory; Python stdlib, no app dependency.
Run from a clean Git checkout after the documented gates. --candidate permits an
explicitly dirty inventory for pre-release extraction tests; never deliver it.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='deliverables/VIGIL-Phase6-Full-Working.zip')
    parser.add_argument('--candidate', action='store_true')
    args=parser.parse_args()
    dirty=bool(git('status','--porcelain').strip())
    if dirty and not args.candidate:
        raise SystemExit('Refusing a final release from a dirty checkout. Commit the verified source/docs first; use --candidate only for provisional payload tests.')
    paths=set(git('ls-files','-z').decode().split('\0'))-{''}
    if args.candidate:
        paths.update(set(git('ls-files','--others','--exclude-standard','-z').decode().split('\0'))-{''})
    paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT/'dist').rglob('*') if p.is_file())
    banned={'.git','node_modules','.cache','.npm','.local','.arena','playwright-report','test-results','coverage','deliverables','__pycache__','.venv'}
    files=[]
    for name in sorted(paths):
        path=ROOT/name
        if any(part in banned for part in Path(name).parts) or Path(name).name.startswith('.env') or name.endswith('.tsbuildinfo'):
            continue
        if not path.is_file() or path.is_symlink():
            raise SystemExit(f'Expected a regular release file: {name}')
        data=path.read_bytes()
        files.append((name,data))
    required={'README.md','QUICK_START.md','package.json','package-lock.json','START-VIGIL.cmd','start-vigil.sh','scripts/serve.mjs','src/App.tsx','src/adaptive/policy.ts','docs/ADAPTATION_SPEC.md','docs/QA_REPORT_PHASE_6.md','dist/index.html'}
    missing=required-{name for name,_ in files}
    if missing:
        raise SystemExit(f'Missing required release files: {sorted(missing)}')
    manifest={'project':'VIGIL — Adaptive Simulation & Training System','appVersion':json.loads((ROOT/'package.json').read_text())['version'],'generatedAt':datetime.now(timezone.utc).isoformat(),'sourceCommit':git('rev-parse','HEAD').decode().strip(),'candidateDirtyCheckout':dirty,'schemaVersion':3,'generatorVersion':'generator-2','sensorVersion':'sensor-2','rubricVersion':'rubric-1','replayVersion':'replay-1','adaptivePolicyVersion':'rules-1','launch':'node scripts/serve.mjs','defaultURL':'http://localhost:8787','integrityNote':'SHA-256 integrity inventory; not a digital publisher signature or official certification. Manifest excludes itself. See docs/TEST_RESULTS.md and accompanying package-validation.json for execution evidence.','files':[{'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for name,data in files]}
    output=Path(args.output)
    if not output.is_absolute(): output=ROOT/output
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for name,data in files:
            info=zipfile.ZipInfo('VIGIL/'+name,(2026,10,17,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED
            info.external_attr=((0o100755 if name=='start-vigil.sh' or name.startswith('scripts/') and name.endswith(('.mjs','.py')) else 0o100644)<<16)
            archive.writestr(info,data)
        archive.writestr('VIGIL/RELEASE_MANIFEST.json',json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    # Read and compare every archived byte, including the authoritative production assets.
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        names=archive.namelist()
        assert len(names)==len(set(names))==len(files)+1
        for entry in manifest['files']:
            data=archive.read('VIGIL/'+entry['path'])
            assert len(data)==entry['bytes'] and hashlib.sha256(data).hexdigest()==entry['sha256'],entry['path']
        assert all(not n.startswith('/') and '..' not in Path(n).parts for n in names)
    digest=hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.sha256').write_text(f'{digest}  {output.name}\n')
    print(json.dumps({'archive':str(output),'bytes':output.stat().st_size,'filesIncludingManifest':len(files)+1,'sourceCommit':manifest['sourceCommit'],'candidateDirtyCheckout':dirty,'sha256':digest},indent=2))

if __name__=='__main__':
    main()
