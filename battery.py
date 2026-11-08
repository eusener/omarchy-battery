"""Read physical battery telemetry locally; never infer a part number or brand."""
import json
import math
from pathlib import Path


def collect(root=Path('/sys/class/power_supply')):
    batteries = []
    for device in sorted(root.glob('*')):
        def read(name):
            try:
                return (device / name).read_text()[:512].strip() or None
            except (OSError, UnicodeError):
                return None

        def number(name):
            try:
                value = float(read(name))
                return value if math.isfinite(value) and value >= 0 else None
            except (TypeError, ValueError):
                return None

        if read('type') != 'Battery' or read('present') == '0':
            continue
        # Exclude mouse/headset batteries when the driver marks device scope.
        if read('scope') == 'Device':
            continue
        prefix, scale, unit = 'energy', 1e6, 'Wh'
        if number('energy_full') is None or number('energy_full_design') is None:
            prefix, scale, unit = 'charge', 1e3, 'mAh'
        capacities = {key: number(prefix + '_' + suffix) for key, suffix in
                      [('design', 'full_design'), ('full', 'full'), ('now', 'now')]}
        design, full = capacities['design'], capacities['full']
        health = full / design * 100 if design and full is not None else None
        voltage = number('voltage_now')
        power = number('power_now')
        current = number('current_now')
        if power is None and current is not None and voltage is not None:
            power = current * voltage / 1e6
        temperature = number('temp')
        batteries.append(dict(
            name=device.name, manufacturer=read('manufacturer'),
            brand=read('brand'), model=read('model_name'),
            part_number=read('part_number'), serial=read('serial_number'),
            technology=read('technology'), cycles=number('cycle_count'),
            capacity_unit=unit, **{k: v / scale if v is not None else None for k, v in capacities.items()},
            health=health, degradation=max(0, 100 - health) if health is not None else None,
            voltage=voltage / 1e6 if voltage is not None else None,
            power=power / 1e6 if power is not None else None,
            temperature=temperature / 10 if temperature is not None else None,
        ))
    return batteries


if __name__ == '__main__':
    print(json.dumps(collect(), ensure_ascii=False, allow_nan=False))
