"""Validate signing inputs with synthetic profiles; no Apple account required."""
import copy
import datetime
import hashlib
import unittest

from ios_signing import export_options


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 11, 3)
        self.certificate = b'synthetic-certificate'
        self.fingerprint = hashlib.sha1(self.certificate).hexdigest().upper()
        self.profile = {
            'UUID': '12345678-1234-1234-1234-123456789012',
            'TeamIdentifier': ['ABCDEFGHIJ'],
            'ApplicationIdentifierPrefix': ['OLDPREFIX1'],
            'Platform': ['iOS'],
            'ExpirationDate': self.now + datetime.timedelta(days=30),
            'DeveloperCertificates': [self.certificate],
            'Entitlements': {
                'application-identifier': 'OLDPREFIX1.com.moonrailgun.sillydraft',
                'com.apple.developer.team-identifier': 'ABCDEFGHIJ',
                'get-task-allow': False,
            },
        }

    def test_app_store_profile_and_legacy_app_prefix(self):
        result = export_options(self.profile, {self.fingerprint}, self.now)
        self.assertEqual(result['method'], 'app-store-connect')
        self.assertEqual(result['teamID'], 'ABCDEFGHIJ')
        self.assertEqual(result['signingCertificate'], self.fingerprint)
        self.assertFalse(result['manageAppVersionAndBuildNumber'])
        self.assertEqual(result['provisioningProfiles'], {
            'com.moonrailgun.sillydraft': self.profile['UUID'],
        })

    def test_rejects_wrong_app_and_wildcard(self):
        for app in ['OLDPREFIX1.com.example.other', 'OLDPREFIX1.*']:
            with self.subTest(app=app):
                self.profile['Entitlements']['application-identifier'] = app
                with self.assertRaises(ValueError):
                    export_options(self.profile, {self.fingerprint}, self.now)

    def test_rejects_non_store_profiles(self):
        for field, value in [('ProvisionedDevices', ['device']),
                             ('ProvisionsAllDevices', True),
                             ('Platform', ['OSX'])]:
            with self.subTest(field=field):
                profile = copy.deepcopy(self.profile)
                profile[field] = value
                with self.assertRaises(ValueError):
                    export_options(profile, {self.fingerprint}, self.now)
        self.profile['Entitlements']['get-task-allow'] = True
        with self.assertRaises(ValueError):
            export_options(self.profile, {self.fingerprint}, self.now)

    def test_rejects_expired_profile_and_missing_private_key(self):
        with self.assertRaises(ValueError):
            export_options(self.profile, {'0' * 40}, self.now)
        self.profile['ExpirationDate'] = self.now
        with self.assertRaises(ValueError):
            export_options(self.profile, {self.fingerprint}, self.now)

    def test_rejects_injected_identifiers_and_inconsistent_team(self):
        for field, value in [('UUID', '../../profile'),
                             ('TeamIdentifier', ['TEAM\nSETTING=bad'])]:
            with self.subTest(field=field):
                profile = copy.deepcopy(self.profile)
                profile[field] = value
                with self.assertRaises(ValueError):
                    export_options(profile, {self.fingerprint}, self.now)
        self.profile['Entitlements']['com.apple.developer.team-identifier'] = 'WRONGTEAM1'
        with self.assertRaises(ValueError):
            export_options(self.profile, {self.fingerprint}, self.now)


if __name__ == '__main__':
    unittest.main()
