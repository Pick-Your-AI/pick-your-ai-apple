#!/usr/bin/env python3
"""Prove existing Swift regressions detect semantic changes in disposable copies."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


MUTATIONS = (
    dict(name='required-field', file='EvaluationReport.swift',
         before='buildID = try c.decode(String.self, forKey: .buildID)',
         after='buildID = try c.decodeIfPresent(String.self, forKey: .buildID) ?? "build.default"',
         test='EvaluationReportTests.testEveryRequiredReportFieldRejectsMissingAndNull',
         assertion='XCTAssertThrowsError'),
    dict(name='decimal-comparison', file='ContractDecimal.swift',
         before='return left.lexicographicallyPrecedes(right)',
         after='return right.lexicographicallyPrecedes(left)',
         test='ContractDecimalTests.testComparisonPreservesUnboundedPrecision',
         assertion='XCTAssertLessThan'),
    dict(name='request-generation', file='AnalysisStore.swift',
         before='activeRequest == request && identity == request.identity',
         after='activeRequest != nil && identity == request.identity',
         test='AnalysisStoreTests.testSameRevisionRetryHasNewGeneration',
         assertion='XCTAssertFalse'),
)


def apply_mutation(package, mutation):
    path = package / 'Sources/PlannerCore' / mutation['file']
    original = path.read_text()
    if original.count(mutation['before']) != 1:
        raise ValueError(f"Expected exactly one source anchor: {mutation['name']}")
    path.write_text(original.replace(mutation['before'], mutation['after'], 1))


def test_identity(name, module='PlannerCoreTests', require_module=False):
    """Normalize the observed Linux/macOS XCTest spellings, with exact names."""
    identifier = r'[A-Za-z_][A-Za-z0-9_]*'
    module = re.escape(module)
    prefix = rf'{module}\.' if require_module else rf'(?:{module}\.)?'
    linux = re.fullmatch(rf'{prefix}({identifier})\.({identifier})', name)
    macos = re.fullmatch(rf'-\[{module}\.({identifier}) ({identifier})\]', name)
    match = linux or macos
    return '.'.join(match.groups()) if match else None


def suite_results(output, suite, outcome, module='PlannerCoreTests', require_module=False):
    """Require one complete XCTest session and its matching nonempty summary.

    The unrelated Swift Testing zero-test footer is not an XCTest result. Unknown,
    duplicate, skipped or truncated case output cannot supply a passing receipt.
    """
    lines = output.splitlines()
    events = []
    for index, line in enumerate(lines):
        if not line.startswith(f"Test Suite '{suite}'"):
            continue
        event = re.fullmatch(rf"Test Suite '{re.escape(suite)}' (started|passed|failed|skipped) at .+", line)
        if not event:
            return None
        events.append((index, event[1]))
    if len(events) != 2 or [event[1] for event in events] != ['started', outcome]:
        return None
    start, end = events[0][0], events[1][0]
    if end + 1 >= len(lines):
        return None
    duration = r'[0-9]+(?:\.[0-9]+)?'
    summary = re.fullmatch(
        r'\s*Executed ([0-9]+) tests?, with ([0-9]+) failures? '
        rf'\(([0-9]+) unexpected\) in {duration} \({duration}\) seconds', lines[end + 1])
    if not summary:
        return None
    count, failures, unexpected = map(int, summary.groups())
    started, finished = set(), {}
    for index, line in enumerate(lines):
        if not line.startswith('Test Case '):
            continue
        beginning = re.fullmatch(r"Test Case '([^']+)' started(?:\.| at .+)", line)
        completion = re.fullmatch(
            rf"Test Case '([^']+)' (passed|failed|skipped) \({duration} seconds\)\.?", line)
        if not (beginning or completion) or not start < index < end:
            return None
        name = test_identity((beginning or completion)[1], module, require_module)
        if name is None:
            return None
        if beginning:
            if name in started:
                return None
            started.add(name)
        else:
            if name not in started or name in finished:
                return None
            finished[name] = completion[2]
    if not finished or started != finished.keys() or count != len(finished):
        return None
    return finished, failures, unexpected, lines[start + 1:end]


def baseline_passed(returncode, output):
    """Prove the unchanged suite actually ran all named mutation regressions."""
    result = suite_results(output, 'All tests', 'passed')
    if returncode != 0 or result is None:
        return False
    cases, failures, unexpected, _ = result
    return (failures == unexpected == 0 and all(status == 'passed' for status in cases.values())
            and all(mutation['test'] in cases for mutation in MUTATIONS))


def detected(returncode, output, mutation):
    """Require the exact selected regression and its actual assertion failure."""
    result = suite_results(output, 'Selected tests', 'failed')
    if returncode != 1 or result is None:
        return False
    cases, failures, unexpected, lines = result
    if cases != {mutation['test']: 'failed'} or failures < 1 or unexpected != 0:
        return False
    for line in lines:
        assertion = re.match(r'^.+:[0-9]+(?::[0-9]+)?: error: (.+?) : ([A-Za-z0-9_]+) failed\b', line)
        if (assertion and test_identity(assertion[1]) == mutation['test']
                and assertion[2] == mutation['assertion']):
            return True
    return False


def invoke(package, swift, arguments, log, timeout):
    command = [swift, 'test', '--package-path', str(package), *arguments]
    with log.open('w') as stream:
        try:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                    timeout=timeout, check=False)
        except subprocess.TimeoutExpired as error:
            raise ValueError(f'Swift test timed out; see {log}') from error
    return result.returncode, log.read_text(errors='replace')


def run(package, output, swift, timeout):
    package = package.resolve()
    if not (package / 'Package.swift').is_file():
        raise ValueError('Expected a Swift package directory')
    output = output.resolve()
    if output == package or output.is_relative_to(package):
        raise ValueError('Evidence output must be outside the source package')
    output.mkdir(parents=True, exist_ok=True)
    receipt = output / 'swift-mutations.json'
    receipt.unlink(missing_ok=True)  # Never leave a stale success receipt on failure.
    results = []
    with tempfile.TemporaryDirectory(prefix='planner-swift-mutations-') as tmp:
        baseline = Path(tmp) / 'baseline'
        shutil.copytree(package, baseline, ignore=shutil.ignore_patterns('.build', '.swiftpm', '.git', '*.xcresult', '*.log'))
        # Fail before expensive compilation if any expected source anchor drifted.
        for mutation in MUTATIONS:
            source = baseline / 'Sources/PlannerCore' / mutation['file']
            if source.read_text().count(mutation['before']) != 1:
                raise ValueError(f"Expected exactly one source anchor: {mutation['name']}")
        code, log = invoke(baseline, swift, [], output / 'baseline.log', timeout)
        if not baseline_passed(code, log):
            raise ValueError('Unmodified Swift suite must execute and pass every named regression; see baseline.log')
        for mutation in MUTATIONS:
            isolated = Path(tmp) / mutation['name']
            shutil.copytree(baseline, isolated, ignore=shutil.ignore_patterns('.build', '.swiftpm', '*.xcresult', '*.log'))
            apply_mutation(isolated, mutation)
            code, log = invoke(isolated, swift, ['--filter', mutation['test']],
                               output / (mutation['name'] + '.log'), timeout)
            if not detected(code, log, mutation):
                raise ValueError(f"Expected assertion failure not observed: {mutation['name']}")
            results.append(dict(mutation=mutation['name'], test=mutation['test'], detected=True))
    receipt.write_text(json.dumps(dict(baseline='passed', mutations=results), indent=2) + '\n')
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--swift', default='swift')
    parser.add_argument('--timeout', type=int, default=300, help='Seconds per Swift invocation')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    try:
        results = run(args.package, args.output_dir, args.swift, args.timeout)
    except (ValueError, OSError) as error:
        parser.exit(1, f'Swift mutation qualification failed: {error}\n')
    print(f'PASS baseline and {len(results)} detected Swift semantic mutations')


if __name__ == '__main__':
    main()
