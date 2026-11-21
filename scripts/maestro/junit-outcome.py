#!/usr/bin/env python3
"""Exit 0 when every given Maestro JUnit report indicates success."""
from pathlib import Path
import sys
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


def main(argv):
    if len(argv) < 2:
        print('Usage: junit-outcome.py <report.xml> [more reports...]', file=sys.stderr)
        return 2
    reports = [Path(item) for item in argv[1:]]
    miss = [report for report in reports if not report.is_file()]
    if miss:
        print(f'Missing JUnit report(s): {", ".join(str(path) for path in miss)}', file=sys.stderr)
        return 2
    for report in reports:
        if not report_passed(report):
            return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))