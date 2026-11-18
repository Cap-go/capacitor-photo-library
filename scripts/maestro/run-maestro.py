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


ROOT = Path(__file__).resolve().parents[2]
FLOWS = {
    'permission-check': ROOT / '.maestro/flows/permission-check.yaml',
    'permission-grant-library': ROOT / '.maestro/flows/permission-grant-library.yaml',
    'permission-denied': ROOT / '.maestro/flows/permission-denied.yaml',
    'pick-media-cancel': ROOT / '.maestro/flows/pick-media-cancel.yaml',
    'kill-relaunch-mid-library': ROOT / '.maestro/flows/kill-relaunch-mid-library.yaml',
    'kill-relaunch-mid-library-pre': ROOT / '.maestro/flows/kill-relaunch-mid-library-pre.yaml',
    'kill-relaunch-mid-library-post': ROOT / '.maestro/flows/kill-relaunch-mid-library-post.yaml',
    'low-memory-mid-library-pre': ROOT / '.maestro/flows/low-memory-mid-library-pre.yaml',
    'low-memory-mid-library-post': ROOT / '.maestro/flows/low-memory-mid-library-post.yaml',
    'permission-denied-boot': ROOT / '.maestro/flows/permission-denied-boot.yaml',
    'permission-denied-assert': ROOT / '.maestro/flows/permission-denied-assert.yaml',
}


def run_permission_denied_suite(timeout, device, platform, results):
    boot_status = run_command(
        build_maestro_command('permission-denied-boot', device, platform, results),
        results / 'junit.xml',
        timeout,
    )
    if boot_status != 0:
        return boot_status
    app_id = 'app.capgo.photo.library'
    prep = subprocess.run(
        ['bash', str(ROOT / 'scripts/maestro/prepare-android-permissions.sh'), app_id, 'permission-denied'],
        cwd=ROOT,
        check=False,
    )
    if prep.returncode != 0:
        return prep.returncode
    return run_command(
        build_maestro_command('permission-denied-assert', device, platform, results),
        results / 'junit.xml',
        timeout,
    )


def run_kill_relaunch_suite(timeout, device, platform, results):
    app_id = 'app.capgo.photo.library'
    pre_status = run_command(
        build_maestro_command('kill-relaunch-mid-library-pre', device, platform, results),
        results / 'junit.xml',
        timeout,
    )
    if pre_status != 0:
        return pre_status
    if platform == 'android':
        stop = subprocess.run(['adb', 'shell', 'am', 'force-stop', app_id], check=False)
        if stop.returncode != 0:
            return stop.returncode
    else:
        stop = subprocess.run(['xcrun', 'simctl', 'terminate', device, app_id], check=False)
        if stop.returncode not in (0, 3):
            return stop.returncode
    return run_command(
        build_maestro_command('kill-relaunch-mid-library-post', device, platform, results),
        results / 'junit.xml',
        timeout,
    )


def run_low_memory_suite(timeout, device, platform, results):
    app_id = 'app.capgo.photo.library'
    pre_status = run_command(
        build_maestro_command('low-memory-mid-library-pre', device, platform, results),
        results / 'junit.xml',
        timeout,
    )
    if pre_status != 0:
        return pre_status
    pressure = subprocess.run(
        ['bash', str(ROOT / 'scripts/maestro/memory-pressure.sh')],
        cwd=ROOT,
        check=False,
    )
    if pressure.returncode != 0:
        return pressure.returncode
    if platform == 'android':
        stop = subprocess.run(['adb', 'shell', 'am', 'force-stop', app_id], check=False)
        if stop.returncode != 0:
            return stop.returncode
    else:
        stop = subprocess.run(['xcrun', 'simctl', 'terminate', device, app_id], check=False)
        if stop.returncode not in (0, 3):
            return stop.returncode
    return run_command(
        build_maestro_command('low-memory-mid-library-post', device, platform, results),
        results / 'junit.xml',
        timeout,
    )


def build_maestro_command(scenario, device, platform, results):
  report = results / 'junit.xml'
  return [
    'maestro', 'test', '--config', str(ROOT / '.maestro/config.yaml'), str(FLOWS[scenario]),
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
        try:
            os.remove(results / 'junit.xml')
        except FileNotFoundError:
            pass
        if scenario == 'low-memory-mid-library':
            return run_low_memory_suite(timeout, device, platform, results)
        if scenario == 'kill-relaunch-mid-library':
            return run_kill_relaunch_suite(timeout, device, platform, results)
        if platform == 'ios':
            return run_command(
                build_maestro_command('permission-denied', device, platform, results),
                results / 'junit.xml',
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
    command = build_maestro_command(scenario, device, platform, results)
    # A report from an earlier attempt must never authorize success.
    try:
        os.remove(report)
    except FileNotFoundError:
        pass
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
    deadline = time.monotonic() + timeout
    passed_at = None
    output = ''
    while process.poll() is None:
        if termination_signal():
            return 128 + termination_signal()
        output = read_output(selector, output)
        summary_passed = bool(re.search(r'\b(\d+)/\1 Flow Passed\b', output))
        if summary_passed and report_passed(report):
            passed_at = passed_at or time.monotonic()
            if time.monotonic() - passed_at >= 2:
                print('Maestro flow and JUnit report passed; stopping stalled CLI teardown.', flush=True)
                return 0
        else:
            passed_at = None
        if time.monotonic() >= deadline:
            return 124
    return process.returncode


def signal_process_group(process, signum):
    try:
        os.killpg(process.pid, signum)
    except ProcessLookupError:
        pass


def stop_process(process):
    signal_process_group(process, signal.SIGTERM)
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    # Descendants may outlive the CLI and keep its output pipe or device session open.
    signal_process_group(process, signal.SIGKILL)
    process.wait()
    os.set_blocking(process.stdout.fileno(), False)
    remaining = process.stdout.read()
    if remaining:
        sys.stdout.buffer.write(remaining)
    process.stdout.close()


if __name__ == '__main__':
    platform = sys.argv[4] if len(sys.argv) > 4 else 'android'
    results_dir = sys.argv[5] if len(sys.argv) > 5 else None
    sys.exit(run(float(sys.argv[1]), sys.argv[2], sys.argv[3], platform, results_dir))
