import json,re
from pathlib import Path
p=Path('/Users/pedro/.no-mistakes/evidence/01M3SDPW8TREH6V2S6Y8EVAZ4V')
expected={'explicit-luna':'max','explicit-clamp':'xhigh','default-max':'max','default-clamp':'xhigh','env-kept':'max','env-dropped':'xhigh','profile':'xhigh','unknown':'xhigh','non-luna':'max'}
rows=[]
for name,effort in expected.items():
 log=(p/f'live-{name}.log').read_text()
 proc=(p/f'live-{name}-process.txt').read_text()
 launch=p/f'live-{name}-launch.txt'
 command=proc or (launch.read_text() if launch.exists() else '')
 assert f'model_reasoning_effort="{effort}"' in command,(name,'missing expected launch effort')
 notices=[l for l in log.splitlines() if l.startswith('notice:')]
 assert bool(notices)==(effort=='xhigh'),(name,notices)
 environment=p/f'live-{name}-environment.json'
 rows.append(dict(worker_environment=json.loads(environment.read_text()) if environment.exists() else None,scenario=name,requested_effort='max',observed_effort=effort,notice=notices,actual_command=command,transcript=f'live-{name}.log',limit='Installed Codex rejects legacy profile configuration after Firstmate emits the clamp.' if name=='profile' else 'Launch verified; no model response requested or verified.'))
(p/'live-validation.json').write_text(json.dumps(rows,indent=2))
catalog=json.loads((p/'codex-catalog.json').read_text())
(p/'catalog-summary.json').write_text(json.dumps([dict(model=m['slug'],efforts=[e['effort'] for e in m['supported_reasoning_levels']]) for m in catalog['models'] if m['slug'] in ['gpt-5.6-luna','gpt-5.5','gpt-6-luna']],indent=2))
print('All nine live launch outputs match expected effort and notice behavior.')
