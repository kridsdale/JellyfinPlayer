#!/usr/bin/env python3
"""Accept the frozen tvOS test build against approved media only.

Build first. Do not rebuild its DerivedData while this runner is active.
The run number affects artifact names only; device/media IDs are never rewritten.
No uninstall, SQL edits, server configuration or media-file operations occur.
Progress restoration uses simulator_resume.py's SwiftData SDK tool.
"""
from pathlib import Path
import json, os, plistlib, subprocess, sys
import argparse
parser = argparse.ArgumentParser(description="Run frozen-build simulator acceptance and restore all SDK progress.")
parser.add_argument('--run-number', type=int, required=True)
parser.add_argument('--device', default='C185BD69-BF46-4520-AC7E-8174AEA534E3')
args = parser.parse_args()
if args.run_number < 1:
    parser.error('--run-number must be positive')
number = str(args.run_number)
root=Path(__file__).resolve().parents[2]
device=args.device
baseline=root/f'build/validation/packages-original-session-{number}.json'
restored=root/f'build/validation/packages-restored-session-{number}.json'
seedbackup=root/f'build/validation/packages-before-natural-{number}.json'
source=root/'build/DerivedData/Build/Products/KidsValidation_appletvsimulator27.0-arm64.xctestrun'
run=source.with_name(f'Kids-Packages-Session-{number}.xctestrun')
data=plistlib.loads(source.read_bytes())
env=data['KidsUITests'].setdefault('EnvironmentVariables',{})
env.update({'KIDS_PROFILE_LIVE':'1','KIDS_RUN_LIVE':'1','KIDS_RECOVERY_ITEM_ID':'1f74938947519192e646194fd9e6b86c','KIDS_RECOVERY_MIN_SECONDS':'113','KIDS_RUN_NATURAL':'1','KIDS_NATURAL_FIRST_ID':'1f74938947519192e646194fd9e6b86c','KIDS_NATURAL_NEXT_ID':'4ab00c91031efca8643d24373020a0c5'})
if run.exists() or baseline.exists() or restored.exists() or seedbackup.exists():
    raise RuntimeError('Run artifacts already exist; choose a fresh run number')
for label in ['Acceptance', 'Natural', 'Cap']:
    if (root/f'build/validation/Kids-Packages-{label}-{number}.xcresult').exists():
        raise RuntimeError('Result bundle already exists; choose a fresh run number')
run.write_bytes(plistlib.dumps(data));os.chmod(run,0o600)
state_log=open(f'/private/tmp/kids-packages-session-{number}-state.log','x')
os.chmod(state_log.name,0o600)
def state(action,backup,*extra):
    subprocess.run(['python3',str(root/'Scripts/Kids/simulator_resume.py'),action,'--device',device,'--backup',str(backup),*extra],cwd=root,check=True,stdout=state_log,stderr=subprocess.STDOUT)
def test(name,selectors):
    cmd=['xcodebuild','test-without-building','-xctestrun',str(run),'-destination',f'platform=tvOS Simulator,id={device}','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-resultBundlePath',str(root/f'build/validation/Kids-Packages-{name}.xcresult')]
    cmd += ['-only-testing:'+selector for selector in selectors]
    with open('/private/tmp/kids-packages-'+name.lower()+'.log','x') as out:
        os.chmod(out.name,0o600)
        subprocess.run(cmd,cwd=root,check=True,stdout=out,stderr=subprocess.STDOUT)
    print(name+' passed',flush=True)
state('snapshot',baseline)
failures=[]
def checked_test(name, selectors):
    try: test(name, selectors)
    except subprocess.CalledProcessError as error:
        failures.append((name,error.returncode))
        print(name+' FAILED with exit '+str(error.returncode),flush=True)
try:
    checked_test(f'Acceptance-{number}',['KidsUITests/KidsApplicationBoundaryTests','KidsUITests/KidsArtworkBoundaryTests','KidsUITests/KidsNavigationTests','KidsUITests/PreferencesOwnershipTests','KidsUITests/VLCPlaybackOwnershipTests','KidsUITests/NativePlaybackOwnershipTests','KidsUITests/NowPlayingArtworkOwnershipTests','KidsUITests/ServerImageCacheIdentityTests','KidsNativeTests/CredentialInteropTests']+['KidsUITests/KidsLivePlaybackTests/'+t for t in ['testRealApprovedLegacyMoviePlayback','testRealEpisodePauseSeekAndResumeAfterRelaunch','testRealMoviePauseSeekAndResume','testRealRecoveryClearsCatalogAndPreservesSavedAccount','testRealStreamFailureRetriesExactItem','testRealShufflePlaysEpisode']])
    state('restore',baseline)
    state('seed',seedbackup,'--show-id','92835060f3344b9b3b57a281e15b5626','--item-id','1f74938947519192e646194fd9e6b86c','--season','1','--episode','1','--runtime','1353.194','--completed','0')
    checked_test(f'Natural-{number}',['KidsUITests/KidsLivePlaybackTests/testRealNaturalEpisodeTransition'])
    state('seed',seedbackup,'--show-id','92835060f3344b9b3b57a281e15b5626','--item-id','4ab00c91031efca8643d24373020a0c5','--season','1','--episode','2','--runtime','1353.898','--completed','1')
    checked_test(f'Cap-{number}',['KidsUITests/KidsLivePlaybackTests/testRealSessionCapAtNaturalEnd'])
finally:
    state('restore',baseline)
    state('snapshot',restored)
    equal=json.loads(baseline.read_text())==json.loads(restored.read_text())
    print('Full SDK progress restoration equals original: '+str(equal),flush=True)
    state_log.close()
    if not equal: raise RuntimeError('Simulator progress restoration did not match original')

if failures:
    print("Retained failed results: "+str(failures),flush=True)
    sys.exit(1)
