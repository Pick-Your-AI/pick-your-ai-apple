#!/usr/bin/env node
// Execute the unchanged, pinned website validator over the published wire bytes.
// This is a local reference harness, not a website build, browser test or deploy.
import { createHash } from "node:crypto";
import { readFile, mkdir, mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const lock = JSON.parse(await readFile(resolve(here, "cross-client-lock.json"), "utf8"));
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
if (process.argv.length !== 3) throw new Error("Usage: node tools/conformance/web_consumer.mjs PINNED_WEBSITE_CHECKOUT");
if (process.versions.node !== lock.nodeVersion) throw new Error(`Expected recorded Node ${lock.nodeVersion}`);
const website = resolve(process.argv[2]);
const corpusBytes = await readFile(resolve(root, lock.wireFixture.path));
if (digest(corpusBytes) !== lock.wireFixture.sha256) throw new Error("Wire fixture bytes differ from their reviewed pin");
const corpus = JSON.parse(corpusBytes.toString("utf8"));
if (corpus.bundleVersion !== lock.bundleVersion || corpus.contractVersion !== lock.contractVersion ||
    corpus.cases.length !== 223 || new Set(corpus.cases.map((item) => item.id)).size !== 223) {
  throw new Error("Unsupported or incomplete wire bundle");
}

const snapshot = await mkdtemp(resolve(tmpdir(), "planner-web-reference-"));
try {
  // Snapshot the exact source and transitive runtime closure before import. A
  // changed input cannot be imported after a separate, earlier hash check.
  for (const [name, pin] of Object.entries(lock.websiteFiles)) {
    const source = resolve(website, name);
    const target = resolve(snapshot, name);
    const sourceRelative = relative(website, source);
    const targetRelative = relative(snapshot, target);
    if (isAbsolute(name) || sourceRelative.startsWith("..") || targetRelative.startsWith("..")) {
      throw new Error("Pinned website input path escapes its snapshot");
    }
    const bytes = await readFile(source);
    if (bytes.length !== pin.bytes || digest(bytes) !== pin.sha256) throw new Error(`Pinned website input differs: ${name}`);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, bytes, { flag: "wx" });
  }
  const dependencyLock = JSON.parse(await readFile(resolve(snapshot, "package-lock.json"), "utf8"));
  for (const [name, pin] of Object.entries(lock.websiteDependencies)) {
    const metadata = JSON.parse(await readFile(resolve(snapshot, "node_modules", name, "package.json"), "utf8"));
    const entry = dependencyLock.packages[`node_modules/${name}`];
    if (metadata.version !== pin.version || entry.version !== pin.version || entry.integrity !== pin.integrity) {
      throw new Error(`Website runtime version/integrity differs: ${name}`);
    }
  }
  const { validatorsReady, validateContract } = await import(pathToFileURL(resolve(snapshot, "src/contracts/validation.ts")).href);
  await validatorsReady;
  const allowed = new Set(["BuildSnapshot", "CatalogItem", "Selection", "EvaluationReport"]);
  let accepted = 0;
  for (const vector of corpus.cases) {
    if (!allowed.has(vector.contract) || typeof vector.valid !== "boolean" ||
        digest(Buffer.from(vector.payloadJSON, "utf8")) !== vector.payloadSHA256) {
      throw new Error(`Malformed or changed wire case: ${vector.id}`);
    }
    const input = JSON.parse(vector.payloadJSON);
    const original = structuredClone(input);
    const result = validateContract(vector.contract, input);
    const preserved = result.ok ? isDeepStrictEqual(original, result.value) : null;
    const observation = { bundleVersion: corpus.bundleVersion, id: vector.id, accepted: result.ok, preserved };
    console.log("WEB_WIRE_CASE " + JSON.stringify(observation));
    if (result.ok !== vector.valid || (result.ok && preserved !== true)) {
      throw new Error(`Website behavior differs from the pinned shared case: ${vector.id}`);
    }
    accepted += Number(result.ok);
  }
  console.log("WEB_WIRE_RUN " + JSON.stringify({
    bundleVersion: corpus.bundleVersion,
    fixtureSHA256: digest(corpusBytes),
    websiteRevision: lock.websiteRevision,
    node: process.versions.node,
    inputPins: lock.websiteFiles,
    dependencies: lock.websiteDependencies,
    passed: corpus.cases.length,
    accepted,
    rejected: corpus.cases.length - accepted,
    limitations: ["Actual pinned validator execution; browser journeys, backend services, Android runtime and release remain separately unverified."],
  }));
} finally {
  await rm(snapshot, { recursive: true, force: true });
}
