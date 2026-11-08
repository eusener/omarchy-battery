import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('battery', Path(__file__).parents[1] / 'battery.py')
battery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(battery)


class BatteryTests(unittest.TestCase):
    def read(self, **values):
        with tempfile.TemporaryDirectory() as directory:
            device = Path(directory) / 'BAT0'
            device.mkdir()
            for key, value in dict(type='Battery', **values).items():
                (device / key).write_text(str(value))
            return battery.collect(Path(directory))

    def test_energy_health_and_identity(self):
        result = self.read(energy_full_design=57050000, energy_full=37400000,
                           energy_now=29220000, manufacturer='SMP', model_name='5B11M90056', cycle_count=257)[0]
        self.assertAlmostEqual(result['health'], 65.5565, places=3)
        self.assertAlmostEqual(result['degradation'], 34.4435, places=3)
        self.assertEqual(result['full'], 37.4)
        self.assertEqual(result['now'], 29.22)
        self.assertEqual(result['manufacturer'], 'SMP')
        self.assertIsNone(result['part_number'])

    def test_charge_only_uses_mah_without_inventing_energy(self):
        result = self.read(charge_full_design=5000000, charge_full=4000000, charge_now=0, cycle_count=0)[0]
        self.assertEqual(result['capacity_unit'], 'mAh')
        self.assertEqual(result['full'], 4000)
        self.assertEqual(result['now'], 0)
        self.assertEqual(result['health'], 80)
        self.assertEqual(result['cycles'], 0)

    def test_missing_invalid_and_absent_data(self):
        result = self.read(energy_full_design=0, energy_full='bad', cycle_count=-1)[0]
        self.assertIsNone(result['health'])
        self.assertIsNone(result['cycles'])
        self.assertEqual(self.read(present=0), [])

    def test_full_above_design_has_no_negative_wear(self):
        result = self.read(energy_full_design=10000000, energy_full=11000000)[0]
        self.assertEqual(result['degradation'], 0)
        self.assertAlmostEqual(result['health'], 110)

    def test_markup_is_kept_as_inert_data(self):
        result = self.read(manufacturer='<img src="https://example.invalid/x">')[0]
        self.assertEqual(result['manufacturer'], '<img src="https://example.invalid/x">')

    def test_multiple_batteries_keep_independent_units_and_ignore_peripherals(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            devices = {
                'BAT0': dict(type='Battery', energy_full_design=50000000, energy_full=40000000),
                'BAT1': dict(type='Battery', charge_full_design=4000000, charge_full=2000000),
                'headset': dict(type='Battery', scope='Device'),
                'AC': dict(type='Mains'),
            }
            for name, fields in devices.items():
                device = root / name
                device.mkdir()
                for key, value in fields.items():
                    (device / key).write_text(str(value))
            result = battery.collect(root)
        self.assertEqual([d['name'] for d in result], ['BAT0', 'BAT1'])
        self.assertEqual([d['capacity_unit'] for d in result], ['Wh', 'mAh'])
        self.assertEqual([d['health'] for d in result], [80, 50])

    def test_voltage_and_current_fallback_to_power(self):
        result = self.read(voltage_now=12000000, current_now=2000000, temp=325)[0]
        self.assertEqual(result['voltage'], 12)
        self.assertEqual(result['power'], 24)
        self.assertEqual(result['temperature'], 32.5)

    def test_percentage_and_status_are_reported(self):
        result = self.read(capacity=72, status='Discharging')[0]
        self.assertEqual(result['percentage'], 72)
        self.assertEqual(result['status'], 'Discharging')

    def test_percentage_falls_back_to_capacity_ratio(self):
        result = self.read(energy_full_design=50000000, energy_full=40000000,
                           energy_now=10000000, capacity='bad')[0]
        self.assertEqual(result['percentage'], 25)

    def test_percentage_rejects_out_of_range(self):
        self.assertIsNone(self.read(capacity=101)[0]['percentage'])


if __name__ == '__main__':
    unittest.main()
