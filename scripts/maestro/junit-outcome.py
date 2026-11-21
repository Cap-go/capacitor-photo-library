#!/usr/bin/env python3
"""Exit 0 when every given Maestro JUnit report indicates success."""
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys


def load_run_maestro():
    path = Path(__file__).with_name('run-maestro.py')
    return SourceFileLoader('run_maestro', str(path)).load_module()


def main(argv):
    rm = load_run_maestro()
    if len(argv) < 2:
        print('Usage: junit-outcome.py <report.xml> [more reports...]', file=sys.stderr)
        return 2
    reports = [Path(item) for item in argv[1:]]
    miss = [report for report in reports if not report.is_file()]
    if miss:
        print(f'Missing JUnit report(s): {", ".join(str(path) for path in miss)}', file=sys.stderr)
        return 2
    for report in reports:
        if not rm.report_passed(report):
            return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))