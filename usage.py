"""Measure observed awake time on battery; persist only the latest local session."""
import copy
from contextlib import ExitStack
import fcntl
import json
import math
import os
from pathlib import Path
import tempfile
import time

from battery import collect

MAX_SAMPLES = 241
MAX_DEVICES = 16
MAX_STATE_BYTES = 1024 * 1024
MAX_GAP = 90


def number(value, maximum=float('inf')):
    try:
        return (type(value) in (int, float) and math.isfinite(value)
                and 0 <= value <= maximum)
    except OverflowError:
        return False


def advance(state, devices, on_battery, now, monotonic, boot_id):
    """Advance a snapshot using CLOCK_MONOTONIC, which excludes Linux suspend."""
    previous = state.get('monotonic')
    continuous = (state.get('boot_id') == boot_id and number(previous)
                  and 0 <= monotonic - previous <= MAX_GAP)
    delta = monotonic - previous if continuous else 0
    was_on_battery = state.get('on_battery')
    sessions = copy.deepcopy(state.get('devices', {}))
    present = {device['name'] for device in devices}
    for name, session in sessions.items():
        if session['active'] and (not continuous or name not in present):
            session.update(active=False, ended_at=state.get('wall', now))

    for device in devices[:MAX_DEVICES]:
        name = device['name']
        percent = device.get('percentage')
        valid_percent = number(percent, 100)
        session = sessions.get(name)
        if on_battery is None:
            if session and session['active']:
                session['partial'] = True
            continue
        if on_battery and (not session or not session['active']):
            if not valid_percent:
                continue
            session = dict(active=True, partial=not (continuous and was_on_battery is False),
                           started_at=now, ended_at=None, elapsed=0,
                           start_percentage=percent, end_percentage=percent,
                           samples=[dict(elapsed=0, percentage=percent)])
            sessions[name] = session
            continue
        if not session or not session['active']:
            continue
        if continuous and was_on_battery is True:
            session['elapsed'] += delta
        else:
            session['partial'] = True
        if valid_percent:
            session['end_percentage'] = percent
            point = dict(elapsed=session['elapsed'], percentage=percent)
            if session['samples'][-1]['elapsed'] == session['elapsed'] and len(session['samples']) > 1:
                session['samples'][-1] = point
            elif session['samples'][-1] != point:
                session['samples'].append(point)
            if len(session['samples']) > MAX_SAMPLES:
                points = session['samples']
                session['samples'] = points[::2]
                if session['samples'][-1] != points[-1]:
                    session['samples'].append(points[-1])
        if not on_battery:
            session.update(active=False, ended_at=now)

    # Prefer batteries that are present if hardware names change over time.
    names = sorted(sessions, key=lambda name: (name not in present, name))[:MAX_DEVICES]
    return dict(version=1, boot_id=boot_id, monotonic=monotonic, wall=now,
                on_battery=on_battery, devices={name: sessions[name] for name in names})


def validate(state):
    """Treat persisted JSON as untrusted, including finite numbers and bounds."""
    if not isinstance(state, dict) or state.get('version') != 1:
        return False
    if not isinstance(state.get('boot_id'), str) or not 1 <= len(state['boot_id']) <= 128:
        return False
    if not number(state.get('monotonic')) or not number(state.get('wall')):
        return False
    if state.get('on_battery') is not None and type(state['on_battery']) is not bool:
        return False
    devices = state.get('devices')
    if not isinstance(devices, dict) or len(devices) > MAX_DEVICES:
        return False
    for name, session in devices.items():
        if not isinstance(name, str) or not 1 <= len(name) <= 128 or not isinstance(session, dict):
            return False
        if any(type(session.get(key)) is not bool for key in ('active', 'partial')):
            return False
        if any(not number(session.get(key)) for key in ('started_at', 'elapsed')):
            return False
        if session.get('ended_at') is not None and not number(session['ended_at']):
            return False
        if any(not number(session.get(key), 100) for key in ('start_percentage', 'end_percentage')):
            return False
        samples = session.get('samples')
        if not isinstance(samples, list) or not 1 <= len(samples) <= MAX_SAMPLES:
            return False
        previous = -1
        for point in samples:
            if (not isinstance(point, dict) or not number(point.get('elapsed'), session['elapsed'])
                    or not number(point.get('percentage'), 100) or point['elapsed'] < previous):
                return False
            previous = point['elapsed']
    return True


def power_source(root, devices):
    online = []
    for device in root.glob('*'):
        try:
            if (device / 'type').read_text().strip() == 'Battery':
                continue
            if (device / 'scope').exists() and (device / 'scope').read_text().strip() == 'Device':
                continue
            value = (device / 'online').read_text().strip()
            if value in ('0', '1'):
                online.append(value == '1')
        except (OSError, UnicodeError):
            continue
    if online:
        return not any(online)
    statuses = [device.get('status') for device in devices]
    if 'Discharging' in statuses:
        return True
    if any(status in ('Charging', 'Full') for status in statuses):
        return False
    return None


def snapshot(root=Path('/sys/class/power_supply'), state_path=None):
    if state_path is None:
        base = os.environ.get('XDG_STATE_HOME', '')
        state_path = (Path(base) if base and Path(base).is_absolute() else Path.home() / '.local/state')
        state_path = state_path / 'omarchy-battery/usage.json'
    # Widgets are instantiated per monitor. Lock the complete transaction, not
    # just the atomic replacement, so a stale writer cannot undo a power event.
    with ExitStack() as stack:
        try:
            state_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            lock = stack.enter_context(state_path.with_suffix('.lock').open('a'))
            fcntl.flock(lock, fcntl.LOCK_EX)
        except OSError:
            return _snapshot(root, state_path, persist=False)
        return _snapshot(root, state_path)


def _snapshot(root, state_path, persist=True):
    state = {}
    try:
        with state_path.open() as stream:
            raw = stream.read(MAX_STATE_BYTES + 1)
        if len(raw) <= MAX_STATE_BYTES:
            candidate = json.loads(raw)
            if validate(candidate):
                state = candidate
    except (OSError, UnicodeError, ValueError, RecursionError):
        pass
    devices = collect(root)
    try:
        boot_id = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    except OSError:
        # Without a boot identity do not resume persisted monotonic timestamps.
        boot_id = str(time.time_ns())
    state = advance(state, devices, power_source(root, devices),
                    time.time(), time.monotonic(), boot_id)
    if not persist:
        return dict(devices=state['devices'], storage_error=True)
    storage_error = False
    temporary = None
    try:
        state_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.NamedTemporaryFile(mode='w', dir=state_path.parent,
                                         suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(state, stream, ensure_ascii=False, allow_nan=False)
        os.replace(temporary, state_path)
    except OSError:
        storage_error = True
    finally:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
    return dict(devices=state['devices'], storage_error=storage_error)


if __name__ == '__main__':
    print(json.dumps(snapshot(), ensure_ascii=False, allow_nan=False))
