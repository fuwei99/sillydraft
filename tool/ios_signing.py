"""Check App Store signing inputs and write Xcode's export options."""
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import sys

BUNDLE_ID = 'com.moonrailgun.sillydraft'


def export_options(profile, identities, now):
    entitlements = profile.get('Entitlements', {})
    teams = profile.get('TeamIdentifier', [])
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    uuid = profile.get('UUID', '')
    if (len(teams) != 1 or not re.fullmatch(r'[A-Z0-9]{10}', teams[0])
            or not re.fullmatch(r'[0-9a-fA-F-]{36}', uuid)):
        raise ValueError('Invalid team identifier or provisioning profile UUID')
    if entitlements.get('com.apple.developer.team-identifier') != teams[0]:
        raise ValueError('Provisioning profile team identifiers do not match')
    if entitlements.get('application-identifier') not in {
            f'{prefix}.{BUNDLE_ID}' for prefix in prefixes}:
        raise ValueError(f'Provisioning profile must explicitly match {BUNDLE_ID}')
    if ('iOS' not in profile.get('Platform', [])
            or entitlements.get('get-task-allow') is not False
            or 'ProvisionedDevices' in profile
            or profile.get('ProvisionsAllDevices', False)):
        raise ValueError('An iOS App Store distribution profile is required')
    if profile.get('ExpirationDate', datetime.datetime.min) <= now:
        raise ValueError('Provisioning profile has expired')
    # Apple embeds the allowed signing certificates in the profile.
    matches = sorted({hashlib.sha1(cert).hexdigest().upper()
                      for cert in profile.get('DeveloperCertificates', [])}
                     & identities)
    if not matches:
        raise ValueError('No valid signing identity/private key matches the profile')
    return {
        'method': 'app-store-connect',
        'destination': 'export',
        'signingStyle': 'manual',
        'teamID': teams[0],
        'signingCertificate': matches[0],
        'provisioningProfiles': {BUNDLE_ID: uuid},
        'manageAppVersionAndBuildNumber': False,
        'uploadSymbols': True,
    }


def main():
    profile_path, identities_path, output_path = map(Path, sys.argv[1:])
    profile = plistlib.loads(profile_path.read_bytes())
    identities = set(re.findall(r'\b[0-9A-F]{40}\b', identities_path.read_text()))
    options = export_options(profile, identities, datetime.datetime.utcnow())
    output_path.write_bytes(plistlib.dumps(options))
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f"team_id={options['teamID']}\n")
        output.write(f"profile_uuid={options['provisioningProfiles'][BUNDLE_ID]}\n")
        output.write(f"certificate_sha1={options['signingCertificate']}\n")


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError) as error:
        sys.exit(f'Signing configuration rejected: {error}')
