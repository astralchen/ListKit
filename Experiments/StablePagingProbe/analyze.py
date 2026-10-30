#!/usr/bin/env python3
"""Extract native paging observations without changing failed assertions."""
import argparse
import json
import re
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument('attachments', type=Path)
p.add_argument('log', type=Path)
p.add_argument('output', type=Path)
a = p.parse_args()
snapshots = {}
for test in json.loads((a.attachments / 'manifest.json').read_text()):
    for attachment in test.get('attachments', []):
        file = a.attachments / attachment['exportedFileName']
        if file.suffix not in ['.txt', '.json']:
            continue
        try:
            data = json.loads(file.read_text())
        except (ValueError, UnicodeDecodeError):
            continue
        if isinstance(data, dict) and 'pageExtent' in data and 'frames' in data:
            name = attachment['suggestedHumanReadableName'].split('_0_')[0].removesuffix('.json')
            axis = 1 if data['vertical'] else 0
            frames = {v['item']: v['frame'] for v in data['frames']}
            data['mainOffset'] = data['offset'][axis]
            data['groupStarts'] = [frames[i][axis] for i in range(0, 42, 6) if i in frames]
            snapshots[name] = data
log = a.log.read_text()
result = {'snapshots': snapshots,
          'paging': re.findall(r'STABLE_RESULT (\S+) target=(\S+) offsetError=(\S+) screenError=(\S+) stride=(\S+)', log),
          'updates': re.findall(r'STABLE_UPDATE (\S+) (\S+) anchorError=(\S+)', log),
          'assertionFailures': [l for l in log.splitlines() if 'error:' in l and 'XCTAssert' in l]}
a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
for row in result['paging']:
    print('PAGE', *row)
for row in result['updates']:
    print('UPDATE', *row)
print('assertion failures:', len(result['assertionFailures']))
