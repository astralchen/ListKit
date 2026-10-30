#!/usr/bin/env python3
"""Aggregate exported XCTest JSON snapshots and retain actual assertion failures."""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('attachments', type=Path)
parser.add_argument('log', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
manifest = json.loads((args.attachments / 'manifest.json').read_text())
cases = {}
for test in manifest:
    for attachment in test.get('attachments', []):
        path = args.attachments / attachment['exportedFileName']
        if path.suffix.lower() not in ['.txt', '.json']:
            continue
        try:
            value = json.loads(path.read_text())
        except (ValueError, UnicodeDecodeError):
            continue
        if not isinstance(value, dict) or 'mode' not in value or 'frames' not in value:
            continue
        name = attachment['suggestedHumanReadableName']
        stage = next((s for s in ['after-second', 'after-first', 'initial', 'stable', 'ready']
                      if name.split('_0_')[0].removesuffix('.json').endswith(f'-{s}')), None)
        if not stage:
            continue
        axis = 'vertical' if value['vertical'] else 'horizontal'
        variant = 'fixed' if value['fixed'] else 'single' if value['single'] else 'nested'
        key = f"{value['mode']}-{axis}-{variant}"
        cases.setdefault(key, {})[stage] = value

for case in cases.values():
    for state in case.values():
        frames = {f['item']: f['frame'] for f in state['frames']}
        axis = 1 if state['vertical'] else 0
        capacity = 1 if state['single'] else 6
        state['group_starts'] = [frames[i][axis] for i in [0, capacity, capacity * 2] if i in frames]
        state['main_offset'] = state['offset'][axis]
        state['first_group_measured_extent'] = max(frames[i][axis] + frames[i][axis + 2]
                                                  for i in range(capacity)) - frames[0][axis]
log = args.log.read_text()
errors = {}
for key, stage, error in re.findall(r'PAGING_RESULT (\S+) (first|second) error=(\S+)', log):
    errors.setdefault(key, {})[stage] = error
result = {'cases': cases, 'observed_ui_errors_pt': errors,
          'assertion_failures': [line for line in log.splitlines() if 'error:' in line and 'XCTAssert' in line],
          'note': 'Failure assertions are retained. A green fixed control does not imply an estimated solution.'}
args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False))
for key in sorted(cases):
    initial = cases[key].get('stable', {})
    ready = cases[key].get('ready', {})
    print(key, 'providers', initial.get('providers'), '->', ready.get('providers'),
          'fits', initial.get('fits'), '->', ready.get('fits'), 'errors', errors.get(key))
