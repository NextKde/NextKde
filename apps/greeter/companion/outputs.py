"""T06 bounded machine display policy. Pure planning only; never modesets.

Inventory is normalized by a trusted caller from KScreen + validated EDID.
Mode IDs are backend-local hints; resolution and exact refresh are authoritative.
"""
import argparse
import json
import math
import re
from pathlib import Path


def fields(value, names):
    if type(value) is not dict or set(value) != set(names.split()):
        raise ValueError('Invalid fields')


def number(value, low, high):
    if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
        raise ValueError('Invalid number')


def integer(value, low, high):
    if type(value) is not int or not low <= value <= high:
        raise ValueError('Invalid integer')


def mode(value):
    fields(value, 'width height refreshHz')
    integer(value['width'], 1, 16384)
    integer(value['height'], 1, 16384)
    number(value['refreshHz'], 1, 1000)


def validate(manifest):
    fields(manifest, 'schemaVersion outputs')
    integer(manifest['schemaVersion'], 1, 1)
    # No overrides is the portable default: use each output's supported modes.
    if type(manifest['outputs']) is not list or not 0 <= len(manifest['outputs']) <= 16:
        raise ValueError('Invalid output count')
    identities = set()
    for output in manifest['outputs']:
        fields(output, 'hardwareId connector mode scale rotation position priority hdr vrr')
        identity = output['hardwareId']
        if type(identity) is not str or not re.fullmatch(r'edid-sha256:[0-9a-f]{64}', identity):
            raise ValueError('Invalid hardware identity')
        connector = output['connector']
        if type(connector) is not str or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', connector):
            raise ValueError('Invalid connector')
        key = (identity, connector)
        if key in identities:
            raise ValueError('Duplicate identity and connector')
        identities.add(key)
        mode(output['mode'])
        number(output['scale'], 0.5, 4)
        if type(output['rotation']) is not int or output['rotation'] not in (0, 90, 180, 270):
            raise ValueError('Invalid rotation')
        if type(output['position']) is not list or len(output['position']) != 2:
            raise ValueError('Invalid position')
        for coordinate in output['position']:
            integer(coordinate, -64000, 64000)
        integer(output['priority'], 1, 16)
        if output['hdr'] is not False or output['vrr'] != 'never':
            raise ValueError('First version requires HDR off and VRR never')
    return manifest


def match(output, manifest, inventory):
    identity = output.get('hardwareId')
    candidates = [o for o in manifest['outputs'] if identity and o['hardwareId'] == identity]
    # Unique EDID survives connector changes; identical EDIDs need connector help.
    count = sum(o.get('hardwareId') == identity for o in inventory)
    if len(candidates) == 1 and count == 1:
        return candidates[0]
    candidates = [o for o in candidates if o['connector'] == output['connector']]
    return candidates[0] if len(candidates) == 1 else None


def exact(wanted, supported):
    return next((m for m in supported if m['width'] == wanted['width']
                 and m['height'] == wanted['height']
                 and abs(m['refreshHz'] - wanted['refreshHz']) <= 0.001), None)


def plan(manifest, inventory, event='startup'):
    """One decision per inventory. Caller must not retry unchanged failures.

    Hotplug preserves effective settings of active screens. Closed/internal and
    disconnected outputs are excluded. No disabled output is activated at runtime.
    No active output means unavailable, not a fabricated screen or mode.
    """
    validate(manifest)
    if event not in ('startup', 'hotplug', 'user-selection'):
        raise ValueError('Invalid event')
    if type(inventory) is not list or len(inventory) > 16:
        raise ValueError('Invalid inventory')
    connectors = set()
    for output in inventory:
        required = set('connector hardwareId connected enabled modes currentMode preferredMode scale rotation position priority'.split())
        if type(output) is not dict or not required <= set(output) or set(output) - required - {'closed'}:
            raise ValueError('Invalid inventory fields')
        connector = output['connector']
        if type(connector) is not str or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', connector) or connector in connectors:
            raise ValueError('Invalid or duplicate inventory connector')
        connectors.add(connector)
        identity = output['hardwareId']
        if identity is not None and (type(identity) is not str or not re.fullmatch(r'edid-sha256:[0-9a-f]{64}', identity)):
            raise ValueError('Invalid inventory identity')
        for key in ('connected', 'enabled'):
            if type(output[key]) is not bool:
                raise ValueError('Invalid inventory flag')
        if 'closed' in output and type(output['closed']) is not bool:
            raise ValueError('Invalid lid flag')
        if type(output['modes']) is not list or len(output['modes']) > 256:
            raise ValueError('Invalid modes')
        for item in output['modes']:
            mode(item)
        for key in ('currentMode', 'preferredMode'):
            if output[key] is not None:
                mode(output[key])
        number(output['scale'], 0.5, 4)
        if type(output['rotation']) is not int or output['rotation'] not in (0, 90, 180, 270):
            raise ValueError('Invalid inventory rotation')
        if type(output['position']) is not list or len(output['position']) != 2:
            raise ValueError('Invalid inventory position')
        for coordinate in output['position']:
            integer(coordinate, -64000, 64000)
        integer(output['priority'], 0, 100)
    if event == 'user-selection':
        return {'state': 'unchanged', 'outputs': [], 'primary': None, 'modeRequests': []}
    decisions = []
    for output in inventory:
        if not output['connected'] or output.get('closed', False):
            continue
        if event == 'hotplug' and not output['enabled']:
            continue
        supported = output['modes']
        if not supported:
            continue
        for candidate in supported:
            mode(candidate)
        current = exact(output['currentMode'], supported) if output.get('currentMode') else None
        target = match(output, manifest, inventory)
        if event == 'startup' and not output['enabled'] and target is None and any(
                o['connected'] and o['enabled'] and not o.get('closed', False) for o in inventory):
            continue
        desired = exact(target['mode'], supported) if target else None
        reason = 'matched' if desired else ('unsupported-mode' if target else 'unknown-or-ambiguous-hardware')
        preferred = exact(output['preferredMode'], supported) if output.get('preferredMode') else None
        selected = desired or preferred or current
        if event == 'hotplug':
            selected = current
            reason = 'preserve-active-hotplug'
        if selected is None:
            continue  # No supported recommendation/current mode; fail closed.
        configured = target is not None and desired is not None and event == 'startup'
        scale = target['scale'] if configured else output['scale'] if current and output['enabled'] else 1
        rotation = target['rotation'] if configured else output['rotation'] if current and output['enabled'] else 0
        position = target['position'] if configured else output['position'] if current and output['enabled'] else [0, 0]
        number(scale, 0.5, 4)
        if rotation not in (0, 90, 180, 270):
            raise ValueError('Invalid inventory rotation')
        width, height = selected['width'], selected['height']
        if rotation in (90, 270):
            width, height = height, width
        decisions.append(dict(connector=output['connector'], mode=selected, scale=scale, rotation=rotation,
                              position=position, priority=target['priority'] if configured else output['priority'],
                              logicalSize=[width / scale, height / scale], reason=reason,
                              hdr=False, vrr='never', modeChange=selected != current))
    if event == 'startup':
        # Manifest targets win ties over existing priorities; send a complete,
        # unique ordering so KScreen cannot silently keep another primary.
        configured_names = {o['connector'] for o in inventory if match(o, manifest, inventory) is not None}
        decisions.sort(key=lambda o: (o['priority'] <= 0, o['priority'], o['connector'] not in configured_names, o['connector']))
        for priority, output in enumerate(decisions, 1):
            output['priority'] = priority
    else:
        decisions.sort(key=lambda o: (o['priority'] <= 0, o['priority'], o['connector']))
    primary = decisions[0] if decisions else None
    return {'state': 'ready' if primary else 'unavailable', 'outputs': decisions,
            'primary': primary['connector'] if primary else None,
            'modeRequests': [o['connector'] for o in decisions if o['modeChange']]}


def form_rect(output, width=340, height=520, margin=16):
    """Logical global bounds; a scrollable viewport is required for small screens."""
    w, h = output['logicalSize']
    if w <= margin * 2 or h <= margin * 2:
        return None
    width, height = min(width, w - 2 * margin), min(height, h - 2 * margin)
    x, y = output['position']
    return [x + (w - width) / 2, y + (h - height) / 2, width, height]


def read_json(path):
    with Path(path).open('rb') as stream:
        data = stream.read(65537)
    if len(data) > 65536:
        raise ValueError('Input exceeds 64 KiB')
    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError('Duplicate JSON key')
            value[key] = item
        return value
    return json.loads(data, object_pairs_hook=unique)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Read-only T06 display planner; does not apply settings')
    parser.add_argument('manifest')
    parser.add_argument('inventory')
    parser.add_argument('--event', choices=['startup', 'hotplug', 'user-selection'], default='startup')
    args = parser.parse_args()
    try:
        print(json.dumps(plan(read_json(args.manifest), read_json(args.inventory), args.event), indent=2))
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(1, 'Display plan refused: ' + str(error) + '\n')
