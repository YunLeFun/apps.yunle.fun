"""Run one explicitly selected acceptance case using already built products."""
import argparse
import json
from pathlib import Path
import plistlib
import signal
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('task_directory', type=Path)
    parser.add_argument('--name', required=True)
    parser.add_argument('--presented', action='store_true', help='The real extension was opened from the system share menu on the reserved device')
    parser.add_argument('--beta', action='store_true')
    parser.add_argument('--beta-close', action='store_true')
    parser.add_argument('--draft', action='store_true', help='Verify the host App draft picker and native preview on the same prepared device')
    parser.add_argument('--rotation', action='store_true', help='Verify the host draft preview in both landscape directions; no API fixture required')
    args = parser.parse_args()
    assert sum([args.beta, args.beta_close, args.draft, args.rotation]) <= 1, 'Select one acceptance case'
    assert args.presented or args.rotation, 'System-share acceptance requires the explicit --presented flag'
    task = args.task_directory.resolve()
    device = json.loads((task / 'ownership.json').read_text())['simulator']
    control = None if args.rotation else json.loads((task / 'server-control.json').read_text())
    if control:
        assert control['origin'] == 'https://127.0.0.1:18473'
    products = task / 'DerivedData/Build/Products'
    run = next(products.glob('*.xctestrun'))
    value = plistlib.loads(run.read_bytes())
    targets = [t for c in value.get('TestConfigurations', []) for t in c.get('TestTargets', [])]
    if not targets:
        targets = [t for t in value.values() if isinstance(t, dict) and t.get('IsUITestBundle')]
    for target in targets:
        env = target.setdefault('EnvironmentVariables', {})
        if control:
            env.update({'SHARE_FEEDBACK_VALIDATION_KEY': control['controlKey']})
        else:
            env.pop('SHARE_FEEDBACK_VALIDATION_KEY', None)
        for key, enabled in [('SHARE_FEEDBACK_LOCAL_QA', control is not None), ('SHARE_FEEDBACK_PRESENTED', args.presented), ('SHARE_FEEDBACK_BETA_QA', args.beta or args.beta_close), ('SCREENSHOT_ROTATION_QA', args.rotation)]:
            if enabled:
                env[key] = '1'
            else:
                env.pop(key, None)
    run.write_bytes(plistlib.dumps(value))
    case = 'testBetaGuidanceRequiresAnExplicitGeneralFeedbackChoice' if args.beta else 'testSystemShareRetryReceiptRelaunchAndPrivateScreenshot'
    suite = 'ShareFeedbackEndToEndUITests'
    if args.beta_close:
        case = 'testBetaOfficialChoiceClosesWithoutSubmitting'
    if args.draft:
        assert not args.beta and not args.beta_close
        case = 'testNativeFeedbackDraftPreviewKeepsTheImageAndDescriptionUntilRemoval'
    if args.rotation:
        suite = 'ScreenshotPreviewOrientationUITests'
        case = 'testDraftPreviewRotatesBothWaysAndPreservesDraftOnClose'
    result = task / (args.name + '.xcresult')
    assert not result.exists(), 'Use a fresh result name'
    with (task / (args.name + '.log')).open('w') as log:
        process = subprocess.Popen(['xcodebuild', 'test-without-building', '-xctestrun', str(run), '-destination', 'platform=iOS Simulator,id=' + device,
                                    '-only-testing:YunleFunUITests/' + suite + '/' + case, '-parallel-testing-enabled', 'NO',
                                    '-collect-test-diagnostics', 'never',
                                    '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '240', '-maximum-test-execution-time-allowance', '300',
                                    '-resultBundlePath', str(result)], stdout=log, stderr=subprocess.STDOUT)
        try:
            return process.wait(timeout=420)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == '__main__':
    def stop(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
