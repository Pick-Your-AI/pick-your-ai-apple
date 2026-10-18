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


def detected(returncode, output, mutation):
    """Require assertion, named test failure and normal selected-suite completion."""
    classname, method = mutation['test'].split('.')
    lines = output.splitlines()
    assertion = any(mutation['assertion'] in line and 'failed' in line
                    and classname in line and method in line for line in lines)
    test_failed = any('Test Case ' in line and classname in line and method in line
                      and re.search(r'\bfailed\b', line) for line in lines)
    suite_failed = any("Test Suite 'Selected tests' failed" in line for line in lines)
    return returncode == 1 and assertion and test_failed and suite_failed


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
        shutil.copytree(package, baseline, ignore=shutil.ignore_patterns('.build', '.swiftpm', '.git'))
        # Fail before expensive compilation if any expected source anchor drifted.
        for mutation in MUTATIONS:
            source = baseline / 'Sources/PlannerCore' / mutation['file']
            if source.read_text().count(mutation['before']) != 1:
                raise ValueError(f"Expected exactly one source anchor: {mutation['name']}")
        code, _ = invoke(baseline, swift, [], output / 'baseline.log', timeout)
        if code != 0:
            raise ValueError('Unmodified Swift suite must pass; see baseline.log')
        for mutation in MUTATIONS:
            isolated = Path(tmp) / mutation['name']
            shutil.copytree(baseline, isolated, ignore=shutil.ignore_patterns('.build', '.swiftpm'))
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
