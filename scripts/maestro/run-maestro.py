#!/usr/bin/env python3
"""Bound Maestro teardown after its final summary and successful JUnit report."""
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET


def report_passed(report):
    try:
        root = ET.parse(report).getroot()
        cases = list(root.iter('testcase'))
        return bool(cases) and not any(
            list(root.iter(tag)) for tag in ('failure', 'error', 'skipped')
        ) and all(
            int(suite.get('failures', '0')) == 0 and int(suite.get('errors', '0')) == 0
            for suite in root.iter('testsuite')
        )
    except (OSError, ET.ParseError, ValueError):
        return False


def report_failed(report):
    try:
        root = ET.parse(report).getroot()
        cases = list(root.iter('testcase'))
        if not cases:
            return False
        if any(list(root.iter(tag)) for tag in ('failure', 'error')):
            return True
        return any(
            int(suite.get('failures', '0')) > 0 or int(suite.get('errors', '0')) > 0
            for suite in root.iter('testsuite')
        )
    except (OSError, ET.ParseError, ValueError):
        return False


def flow_summary_failed(output):
    return bool(re.search(r'\b(\d+)/\1 Flow Failed\b', output))


ROOT = Path(__file__).resolve().parents[2]
FLOWS = {
    'permission-check': ROOT / '.maestro/flows/permission-check.yaml',
    'permission-grant-library': ROOT / '.maestro/flows/permission-grant-library.yaml',
    'permission-denied': ROOT / '.maestro/flows/permission-denied.yaml',
    'pick-media-cancel': ROOT / '.maestro/flows/pick-media-cancel.yaml',
    'pick-media-cancel-pre': ROOT / '.maestro/flows/pick-media-cancel-pre.yaml',
    'pick-media-cancel-post': ROOT / '.maestro/flows/pick-media-cancel-post.yaml',
    'pick-media-cancel-android-boot': ROOT / '.maestro/flows/pick-media-cancel-android-boot.yaml',
    'pick-media-cancel-phase': ROOT / '.maestro/flows/pick-media-cancel-phase.yaml',
    'kill-relaunch-mid-library': ROOT / '.maestro/flows/kill-relaunch-mid-library.yaml',
    'kill-relaunch-mid-library-pre': ROOT / '.maestro/flows/kill-relaunch-mid-library-pre.yaml',
    'kill-relaunch-mid-library-post': ROOT / '.maestro/flows/kill-relaunch-mid-library-post.yaml',
    'low-memory-mid-library-pre': ROOT / '.maestro/flows/low-memory-mid-library-pre.yaml',
    'low-memory-mid-library-post': ROOT / '.maestro/flows/low-memory-mid-library-post.yaml',
    'permission-denied-boot': ROOT / '.maestro/flows/permission-denied-boot.yaml',
    'permission-denied-assert': ROOT / '.maestro/flows/permission-denied-assert.yaml',
}


def flow_path(scenario, platform):
    platform_file = ROOT / '.maestro/flows' / f'{scenario}.{platform}.yaml'
    if platform_file.is_file():
        return platform_file
    return FLOWS[scenario]


def remove_report(report):
    try:
        os.remove(report)
    except FileNotFoundError:
        pass


def remaining_timeout(deadline, minimum=30):
    left = deadline - time.monotonic()
    if left < minimum:
        return 0
    return left


def allocate_suite_budgets(deadline, post_reserve=110, pre_minimum=55):
    """Reserve wall time for a suite's post phase so pre cannot consume the whole budget."""
    remaining = max(0, deadline - time.monotonic() - 5)
    if remaining <= pre_minimum + post_reserve:
        post_reserve = max(90, remaining // 2)
    pre = max(0, remaining - post_reserve)
    post = max(0, remaining - pre)
    return pre, post


def prep_env(device, platform):
    env = os.environ.copy()
    if platform == 'android':
        env['ANDROID_SERIAL'] = device
    else:
        env['CAPGO_MAESTRO_IOS_SIMULATOR_ID'] = device
    return env


def run_permission_denied_suite(timeout, device, platform, results):
    deadline = time.monotonic() + timeout - 5
    boot_report = results / 'permission-denied-boot.xml'
    remove_report(boot_report)
    boot_budget = remaining_timeout(deadline)
    if not boot_budget:
        return 124
    boot_status = run_command(
        build_maestro_command('permission-denied-boot', device, platform, results, boot_report),
        boot_report,
        boot_budget,
    )
    if boot_status != 0:
        return boot_status
    app_id = 'app.capgo.photo.library'
    prep = subprocess.run(
        ['bash', str(ROOT / 'scripts/maestro/prepare-android-permissions.sh'), app_id, 'permission-denied'],
        cwd=ROOT,
        check=False,
        env=prep_env(device, platform),
    )
    if prep.returncode != 0:
        return prep.returncode
    assert_report = results / 'permission-denied-assert.xml'
    remove_report(assert_report)
    assert_budget = remaining_timeout(deadline)
    if not assert_budget:
        return 124
    return run_command(
        build_maestro_command('permission-denied-assert', device, platform, results, assert_report),
        assert_report,
        assert_budget,
    )


def run_kill_relaunch_suite(timeout, device, platform, results):
    deadline = time.monotonic() + timeout - 5
    app_id = 'app.capgo.photo.library'
    pre_report = results / 'kill-relaunch-mid-library-pre.xml'
    remove_report(pre_report)
    pre_budget, post_reserve = allocate_suite_budgets(deadline)
    if pre_budget < 60:
        return 124
    pre_status = run_command(
        build_maestro_command('kill-relaunch-mid-library-pre', device, platform, results, pre_report),
        pre_report,
        pre_budget,
    )
    if pre_status != 0:
        return pre_status
    if platform == 'android':
        stop = subprocess.run(['adb', '-s', device, 'shell', 'am', 'force-stop', app_id], check=False)
        if stop.returncode != 0:
            return stop.returncode
    else:
        stop = subprocess.run(['xcrun', 'simctl', 'terminate', device, app_id], check=False)
        if stop.returncode not in (0, 3):
            return stop.returncode
    post_report = results / 'kill-relaunch-mid-library-post.xml'
    remove_report(post_report)
    post_budget = remaining_timeout(deadline, minimum=90)
    if post_budget < 90:
        print(
            f'Insufficient suite budget for kill-relaunch-mid-library post phase ({post_budget}s left).',
            flush=True,
        )
        return 124
    return run_command(
        build_maestro_command('kill-relaunch-mid-library-post', device, platform, results, post_report),
        post_report,
        min(post_budget, post_reserve),
    )


def run_low_memory_suite(timeout, device, platform, results):
    deadline = time.monotonic() + timeout - 5
    app_id = 'app.capgo.photo.library'
    pre_report = results / 'low-memory-mid-library-pre.xml'
    remove_report(pre_report)
    pre_budget, post_reserve = allocate_suite_budgets(deadline)
    if pre_budget < 60:
        return 124
    pre_status = run_command(
        build_maestro_command('low-memory-mid-library-pre', device, platform, results, pre_report),
        pre_report,
        pre_budget,
    )
    if pre_status != 0:
        return pre_status
    pressure = subprocess.run(
        ['bash', str(ROOT / 'scripts/maestro/memory-pressure.sh'), platform, device],
        cwd=ROOT,
        check=False,
        env=prep_env(device, platform),
    )
    if pressure.returncode != 0:
        return pressure.returncode
    if platform == 'android':
        stop = subprocess.run(['adb', '-s', device, 'shell', 'am', 'force-stop', app_id], check=False)
        if stop.returncode != 0:
            return stop.returncode
    else:
        stop = subprocess.run(['xcrun', 'simctl', 'terminate', device, app_id], check=False)
        if stop.returncode not in (0, 3):
            return stop.returncode
    post_report = results / 'low-memory-mid-library-post.xml'
    remove_report(post_report)
    post_budget = remaining_timeout(deadline, minimum=90)
    if post_budget < 90:
        print(
            f'Insufficient suite budget for low-memory-mid-library post phase ({post_budget}s left).',
            flush=True,
        )
        return 124
    return run_command(
        build_maestro_command('low-memory-mid-library-post', device, platform, results, post_report),
        post_report,
        min(post_budget, post_reserve),
    )


def build_maestro_command(scenario, device, platform, results, report):
  return [
    'maestro', 'test', '--config', str(ROOT / '.maestro/config.yaml'), str(flow_path(scenario, platform)),
    '--platform', platform, '--udid', device,
    '--format', 'junit', '--output', str(report),
    '--debug-output', str(results / 'debug'), '--flatten-debug-output',
    '--test-output-dir', str(results / 'artifacts'),
  ]


def run(timeout, scenario, device, platform='android', results_dir=None):
    if not 0 < timeout <= 600:
        raise ValueError('Maestro timeout must be between 0 and 600 seconds')
    if scenario in {'low-memory-mid-library', 'kill-relaunch-mid-library', 'permission-denied'}:
        if platform not in {'android', 'ios'}:
            raise ValueError('Maestro platform must be android or ios')
        if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}', device):
            raise ValueError('Invalid device identifier')
        results = Path(results_dir) if results_dir else ROOT / (
            'maestro-results-ios' if platform == 'ios' else 'maestro-results'
        )
        results.mkdir(exist_ok=True)
        if scenario == 'low-memory-mid-library':
            return run_low_memory_suite(timeout, device, platform, results)
        if scenario == 'kill-relaunch-mid-library':
            return run_kill_relaunch_suite(timeout, device, platform, results)
        if platform == 'ios':
            report = results / 'junit.xml'
            remove_report(report)
            return run_command(
                build_maestro_command('permission-denied', device, platform, results, report),
                report,
                timeout,
            )
        return run_permission_denied_suite(timeout, device, platform, results)
    if scenario not in FLOWS and scenario not in {
        'low-memory-mid-library',
        'kill-relaunch-mid-library',
        'permission-denied',
    }:
        raise ValueError('Unknown Maestro E2E flow')
    if platform not in {'android', 'ios'}:
        raise ValueError('Maestro platform must be android or ios')
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}', device):
        raise ValueError('Invalid device identifier')
    results = Path(results_dir) if results_dir else ROOT / (
        'maestro-results-ios' if platform == 'ios' else 'maestro-results'
    )
    results.mkdir(exist_ok=True)
    report = results / 'junit.xml'
    remove_report(report)
    command = build_maestro_command(scenario, device, platform, results, report)
    return run_command(command, report, timeout)


def run_command(command, report, timeout):
    process = None
    termination_signal = 0

    def request_termination(signum, _frame):
        nonlocal termination_signal
        termination_signal = signum

    # Record cancellation instead of raising during Popen or interrupting cleanup.
    previous_handler = signal.signal(signal.SIGTERM, request_termination)
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            status = monitor_process(process, selector, report, timeout, lambda: termination_signal)
    finally:
        try:
            if process is not None:
                stop_process(process)
        except PermissionError:
            print(
                'Maestro CLI cleanup could not signal its process group; treating flow result as authoritative.',
                flush=True,
            )
        finally:
            signal.signal(signal.SIGTERM, previous_handler)
    return 128 + termination_signal if termination_signal else status


def read_output(selector, output):
    for key, _ in selector.select(0.2):
        chunk = os.read(key.fileobj.fileno(), 65536)
        if not chunk:
            selector.unregister(key.fileobj)
            continue
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        output = (output + chunk.decode('utf-8', errors='replace'))[-8192:]
    return output


def monitor_process(process, selector, report, timeout, termination_signal):
    flow_deadline = time.monotonic() + timeout
    teardown_deadline = None
    passed_at = None
    failed_at = None
    output = ''
    while process.poll() is None:
        if termination_signal():
            return 128 + termination_signal()
        output = read_output(selector, output)
        summary_passed = bool(re.search(r'\b(\d+)/\1 Flow Passed\b', output))
        summary_failed = flow_summary_failed(output)
        if teardown_deadline is not None:
            if time.monotonic() >= teardown_deadline:
                if passed_at and process.poll() is None:
                    try:
                        process.kill()
                    except OSError:
                        pass
                return 0 if passed_at else 1
            continue
        if summary_passed and report_passed(report):
            passed_at = passed_at or time.monotonic()
            failed_at = None
            if time.monotonic() - passed_at >= 0:
                print('Maestro flow and JUnit report passed; stopping stalled CLI teardown.', flush=True)
                teardown_deadline = time.monotonic() + 0.5
                continue
        elif summary_failed and report_failed(report):
            failed_at = failed_at or time.monotonic()
            passed_at = None
            if time.monotonic() - failed_at >= 0.5:
                print('Maestro flow and JUnit report failed; stopping stalled CLI teardown.', flush=True)
                teardown_deadline = time.monotonic() + 0.5
                continue
        else:
            passed_at = None
            failed_at = None
        if time.monotonic() >= flow_deadline:
            return 124
    return process.returncode


def signal_process_group(process, signum):
    try:
        os.killpg(process.pid, signum)
    except ProcessLookupError:
        pass
    except PermissionError:
        try:
            process.send_signal(signum)
        except (ProcessLookupError, PermissionError):
            pass


def stop_process(process):
    signal_process_group(process, signal.SIGTERM)
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    # Descendants may outlive the CLI and keep its output pipe or device session open.
    try:
        signal_process_group(process, signal.SIGKILL)
        process.wait()
    except PermissionError:
        pass
    os.set_blocking(process.stdout.fileno(), False)
    remaining = process.stdout.read()
    if remaining:
        sys.stdout.buffer.write(remaining)
    process.stdout.close()


if __name__ == '__main__':
    platform = sys.argv[4] if len(sys.argv) > 4 else 'android'
    results_dir = sys.argv[5] if len(sys.argv) > 5 else None
    sys.exit(run(float(sys.argv[1]), sys.argv[2], sys.argv[3], platform, results_dir))
