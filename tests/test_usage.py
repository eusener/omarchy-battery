import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('usage', Path(__file__).parents[1] / 'usage.py')
usage = importlib.util.module_from_spec(spec)
if spec.loader and Path(spec.origin).exists():
    spec.loader.exec_module(usage)


class UsageTests(unittest.TestCase):
    def step(self, state=None, *, plugged=False, t=100, wall=None, percent=80,
             boot='boot-a', names=('BAT0',)):
        devices = [{'name': name, 'percentage': percent} for name in names]
        return usage.advance(state or {}, devices, None if plugged is None else not plugged,
                             t + 1000 if wall is None else wall, t, boot)

    def test_unplug_counts_and_replug_finishes(self):
        state = self.step(plugged=True)
        self.assertEqual(state['devices'], {})
        state = self.step(state, t=130)
        self.assertFalse(state['devices']['BAT0']['partial'])
        self.assertEqual(state['devices']['BAT0']['elapsed'], 0)
        state = self.step(state, t=190, percent=75)
        state = self.step(state, t=220, plugged=True, percent=74)
        session = state['devices']['BAT0']
        self.assertFalse(session['active'])
        self.assertEqual(session['elapsed'], 90)
        self.assertEqual(session['start_percentage'], 80)
        self.assertEqual(session['end_percentage'], 74)
        self.assertEqual(session['samples'][-1], {'elapsed': 90, 'percentage': 74})
        self.assertEqual(self.step(state, t=250, plugged=True)['devices']['BAT0'], session)

    def test_new_unplug_starts_a_new_session(self):
        state = self.step()
        state = self.step(state, t=130, plugged=True)
        state = self.step(state, t=160, percent=100)
        self.assertEqual(state['devices']['BAT0']['elapsed'], 0)
        self.assertEqual(state['devices']['BAT0']['start_percentage'], 100)
        self.assertTrue(state['devices']['BAT0']['active'])

    def test_starting_on_battery_is_labeled_partial(self):
        self.assertTrue(self.step()['devices']['BAT0']['partial'])

    def test_suspend_and_wall_clock_changes_do_not_add_usage(self):
        state = self.step()
        state = self.step(state, t=130, wall=1100 + 4 * 3600)
        self.assertEqual(state['devices']['BAT0']['elapsed'], 30)
        state = self.step(state, t=160, wall=500)
        self.assertEqual(state['devices']['BAT0']['elapsed'], 60)

    def test_short_restart_preserves_a_session(self):
        state = json.loads(json.dumps(self.step()))
        self.assertEqual(self.step(state, t=130)['devices']['BAT0']['elapsed'], 30)

    def test_reboot_and_long_unobserved_gaps_start_partial_session(self):
        for t, boot in [(5, 'boot-b'), (500, 'boot-a')]:
            with self.subTest(t=t, boot=boot):
                session = self.step(self.step(), t=t, boot=boot)['devices']['BAT0']
                self.assertEqual(session['elapsed'], 0)
                self.assertTrue(session['partial'])

    def test_missing_percentage_does_not_invent_graph_values(self):
        self.assertEqual(self.step(percent=None)['devices'], {})
        state = self.step()
        state = self.step(state, t=130, percent=None)
        self.assertEqual(state['devices']['BAT0']['elapsed'], 30)
        self.assertEqual(len(state['devices']['BAT0']['samples']), 1)

    def test_unknown_power_source_does_not_count_or_finish(self):
        state = self.step()
        state = self.step(state, t=130, plugged=None)
        self.assertEqual(state['devices']['BAT0']['elapsed'], 0)
        self.assertTrue(state['devices']['BAT0']['active'])
        state = self.step(state, t=160)
        self.assertEqual(state['devices']['BAT0']['elapsed'], 0)
        self.assertTrue(state['devices']['BAT0']['partial'])

    def test_unknown_power_interval_preserves_initial_observation(self):
        state = self.step(percent=80)
        state = self.step(state, t=130, plugged=None, percent=79)
        state = self.step(state, t=160, percent=78)
        samples = state['devices']['BAT0']['samples']
        self.assertEqual(samples[0], {'elapsed': 0, 'percentage': 80})
        self.assertEqual(samples[-1], {'elapsed': 0, 'percentage': 78})

    def test_batteries_are_independent_and_removal_ends_measurement(self):
        state = self.step(names=('BAT0', 'BAT1'))
        state = self.step(state, names=('BAT1',), t=130)
        self.assertFalse(state['devices']['BAT0']['active'])
        self.assertEqual(state['devices']['BAT1']['elapsed'], 30)

    def test_samples_stay_bounded_and_preserve_first_and_last(self):
        state = self.step()
        for i in range(1, 2000):
            state = self.step(state, t=100 + i * 30, percent=80 - i / 100)
        samples = state['devices']['BAT0']['samples']
        self.assertLessEqual(len(samples), usage.MAX_SAMPLES)
        self.assertEqual(samples[0], {'elapsed': 0, 'percentage': 80})
        self.assertEqual(samples[-1]['elapsed'], 1999 * 30)
        self.assertEqual(samples, sorted(samples, key=lambda sample: sample['elapsed']))


class PersistenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'sys'
        self.root.mkdir()
        self.state_path = Path(self.temp.name) / 'state' / 'usage.json'
        for name, values in {
            'BAT0': {'type': 'Battery', 'capacity': 80, 'status': 'Not charging'},
            'AC': {'type': 'Mains', 'online': 1},
        }.items():
            device = self.root / name
            device.mkdir()
            for key, value in values.items():
                (device / key).write_text(str(value))

    def snapshot(self):
        return usage.snapshot(self.root, self.state_path)

    def test_ac_charge_limit_does_not_start_session(self):
        result = self.snapshot()
        self.assertEqual(result['devices'], {})
        (self.root / 'AC' / 'online').write_text('0')
        result = self.snapshot()
        self.assertTrue(result['devices']['BAT0']['active'])
        self.assertFalse(result['devices']['BAT0']['partial'])

    def test_fallback_to_discharging_when_adapter_has_no_online_reading(self):
        (self.root / 'AC' / 'online').unlink()
        (self.root / 'BAT0' / 'status').write_text('Discharging')
        self.assertTrue(self.snapshot()['devices']['BAT0']['active'])

    def test_atomic_persistence_and_reload(self):
        (self.root / 'AC' / 'online').write_text('0')
        self.assertFalse(self.snapshot()['storage_error'])
        saved = json.loads(self.state_path.read_text())
        self.assertEqual(saved['version'], 1)
        self.assertEqual(saved['devices']['BAT0']['start_percentage'], 80)
        self.assertTrue(self.snapshot()['devices']['BAT0']['active'])
        self.assertEqual(list(self.state_path.parent.glob('*.tmp')), [])

    def test_corrupt_and_wrong_shape_state_recovers(self):
        self.state_path.parent.mkdir()
        for content in ['broken', '[]', '{"version":1,"devices":{"BAT0":null}}',
                        '{"version":1,"devices":{},"monotonic":"bad"}']:
            with self.subTest(content=content):
                self.state_path.write_text(content)
                self.assertEqual(self.snapshot()['devices'], {})
                self.assertIsInstance(json.loads(self.state_path.read_text()), dict)

    def test_huge_numeric_state_recovers(self):
        self.snapshot()
        state = json.loads(self.state_path.read_text())
        state['monotonic'] = 10 ** 500
        self.state_path.write_text(json.dumps(state))
        self.assertEqual(self.snapshot()['devices'], {})
        self.assertTrue(usage.validate(json.loads(self.state_path.read_text())))

    def test_concurrent_snapshots_cannot_resurrect_a_finished_session(self):
        (self.root / 'AC' / 'online').write_text('0')
        self.snapshot()
        first_ready = threading.Event()
        release_first = threading.Event()
        second_done = threading.Event()
        replace = usage.os.replace
        errors = []

        def delayed_replace(source, target):
            if threading.current_thread().name == 'discharge':
                first_ready.set()
                release_first.wait(3)
            replace(source, target)

        def run(done=None):
            try:
                self.snapshot()
            except Exception as error:
                errors.append(error)
            finally:
                if done:
                    done.set()

        with patch.object(usage.os, 'replace', delayed_replace):
            first = threading.Thread(target=run, name='discharge')
            first.start()
            try:
                self.assertTrue(first_ready.wait(3))
                (self.root / 'AC' / 'online').write_text('1')
                second = threading.Thread(target=run, args=(second_done,))
                second.start()
                second_done.wait(0.2)
            finally:
                release_first.set()
                first.join(3)
            second.join(3)
        self.assertEqual(errors, [])
        self.assertFalse(json.loads(self.state_path.read_text())['devices']['BAT0']['active'])

    def test_state_read_is_bounded(self):
        self.state_path.parent.mkdir()
        self.state_path.write_text(' ' * (usage.MAX_STATE_BYTES + 1))
        self.assertEqual(self.snapshot()['devices'], {})

    def test_write_failure_is_reported_instead_of_crashing(self):
        (self.root / 'AC' / 'online').write_text('0')
        self.state_path.parent.write_text('not a directory')
        result = self.snapshot()
        self.assertTrue(result['storage_error'])
        self.assertTrue(result['devices']['BAT0']['active'])
