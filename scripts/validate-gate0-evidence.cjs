'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');
const validatorModules = path.join(repoRoot, '.tools', 'schema-validator', 'node_modules');
const Ajv2020 = require(path.join(validatorModules, 'ajv', 'dist', '2020')).default;
const addFormats = require(path.join(validatorModules, 'ajv-formats'));

function readBuffer(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath));
}

function readJson(relativePath) {
  return JSON.parse(readBuffer(relativePath).toString('utf8'));
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function validationDetails(validate) {
  return (validate.errors || [])
    .map((error) => `${error.instancePath || '/'} ${error.message}`)
    .join('; ');
}

function assertValid(validate, value, label) {
  if (!validate(value)) {
    throw new Error(`${label} does not satisfy Gate 0 schema: ${validationDetails(validate)}`);
  }
}

function assertInvalid(validate, value, label) {
  if (validate(value)) {
    throw new Error(`${label} unexpectedly satisfied Gate 0 schema`);
  }
}

function assertUnique(values, label) {
  if (new Set(values).size !== values.length) {
    throw new Error(`${label} contains duplicate identifiers`);
  }
}

const schema = readJson('evidence/gate0/gate0.schema.json');
const matrixBuffer = readBuffer('evidence/gate0/capability-matrix.v1.json');
const matrix = JSON.parse(matrixBuffer.toString('utf8'));
const decisions = readJson('evidence/gate0/security-decisions.v1.json');

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validate = ajv.compile(schema);

assertValid(validate, matrix, 'capability-matrix.v1.json');
assertValid(validate, decisions, 'security-decisions.v1.json');

const matrixDigest = sha256(matrixBuffer);
if (decisions.matrix.sha256 !== matrixDigest) {
  throw new Error(`Security decision matrix digest mismatch: expected ${matrixDigest}, got ${decisions.matrix.sha256}`);
}

const evidenceIds = matrix.evidence_refs.map((entry) => entry.evidence_id);
const controlIds = matrix.host_controls.map((entry) => entry.control_id);
const claimIds = matrix.provider_claims.map((entry) => entry.claim_id);
const defectIds = matrix.classifier_defects.map((entry) => entry.defect_id);
const unknownIds = matrix.unknowns.map((entry) => entry.unknown_id);
const basisIds = new Set([...controlIds, ...claimIds, ...defectIds, ...unknownIds]);

assertUnique(evidenceIds, 'Evidence references');
assertUnique(controlIds, 'Host controls');
assertUnique(claimIds, 'Provider claims');
assertUnique(defectIds, 'Classifier defects');
assertUnique(unknownIds, 'Unknowns');
assertUnique(decisions.decisions.map((entry) => entry.decision_id), 'Security decisions');

for (const item of [...matrix.host_controls, ...matrix.provider_claims]) {
  for (const evidenceRef of item.evidence_refs) {
    if (!evidenceIds.includes(evidenceRef)) {
      throw new Error(`${item.control_id || item.claim_id} references missing evidence ${evidenceRef}`);
    }
  }
}
for (const defect of matrix.classifier_defects) {
  if (!evidenceIds.includes(defect.evidence_ref)) {
    throw new Error(`${defect.defect_id} references missing evidence ${defect.evidence_ref}`);
  }
}
for (const decision of decisions.decisions) {
  for (const basisId of decision.evidence_basis) {
    if (!basisIds.has(basisId)) {
      throw new Error(`${decision.decision_id} references missing basis ${basisId}`);
    }
  }
}

const expectedDecisionIds = ['T0.8', 'T0.8a', 'T0.8b', 'T0.8c'];
const actualDecisionIds = decisions.decisions.map((entry) => entry.decision_id).sort();
if (JSON.stringify(actualDecisionIds) !== JSON.stringify(expectedDecisionIds.sort())) {
  throw new Error(`Unexpected Security decision set: ${actualDecisionIds.join(', ')}`);
}

const deferredAllow = structuredClone(decisions);
const deferredGrant = deferredAllow.decisions.find((entry) => entry.decision_id === 'T0.8').effective_grants[0];
deferredGrant.decision = 'ALLOW';
deferredGrant.observed_enforcement = 'APF_VERIFIED';
deferredGrant.expires_at = '2026-09-01T00:00:00Z';
assertInvalid(validate, deferredAllow, 'deferred decision containing ALLOW');

const unknownAllow = structuredClone(decisions);
const unknownGrant = unknownAllow.decisions.find((entry) => entry.decision_id === 'T0.8a').effective_grants[0];
unknownGrant.decision = 'ALLOW';
unknownGrant.observed_enforcement = 'UNKNOWN';
unknownGrant.expires_at = '2026-09-01T00:00:00Z';
assertInvalid(validate, unknownAllow, 'UNKNOWN enforcement containing ALLOW');

const hardVetoAllow = structuredClone(decisions);
const productionGrant = hardVetoAllow.decisions.find((entry) => entry.decision_id === 'T0.8a')
  .effective_grants.find((entry) => entry.capability === 'production');
productionGrant.decision = 'ALLOW';
productionGrant.observed_enforcement = 'OS_ENFORCED';
productionGrant.expires_at = '2026-09-01T00:00:00Z';
assertInvalid(validate, hardVetoAllow, 'V1 production ALLOW');

const fabricatedProviderClaim = structuredClone(matrix);
const notEvaluatedClaim = fabricatedProviderClaim.provider_claims.find((entry) => entry.claim_id === 'PC-04');
notEvaluatedClaim.enforcement = 'PROVIDER_ENFORCED';
notEvaluatedClaim.positive_control = 'PASSED';
assertInvalid(validate, fabricatedProviderClaim, 'NOT_EVALUATED provider enforcement claim');

const unsafeProjection = structuredClone(matrix);
unsafeProjection.scope = 'C:/Users/example/private';
assertInvalid(validate, unsafeProjection, 'projection containing a personal absolute path');

process.stdout.write('Gate 0 evidence: 2 documents, cross-references and 5 negative controls valid\n');
