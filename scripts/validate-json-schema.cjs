'use strict';

const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');
const validatorModules = path.join(repoRoot, '.tools', 'schema-validator', 'node_modules');
const Ajv2020 = require(path.join(validatorModules, 'ajv', 'dist', '2020')).default;
const addFormats = require(path.join(validatorModules, 'ajv-formats'));

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'));
}

function assertValid(validate, value, label) {
  if (validate(value)) {
    return;
  }

  const details = validate.errors
    .map((error) => `${error.instancePath || '/'} ${error.message}`)
    .join('; ');
  throw new Error(`${label} does not satisfy its schema: ${details}`);
}

function assertInvalid(validate, value, label) {
  if (!validate(value)) {
    return;
  }

  throw new Error(`${label} unexpectedly satisfied its schema`);
}

const canonicalSchema = readJson('spec/apf-cp/v1/message.schema.json');
const providerResultSchema = readJson('spec/apf-cp/v1/provider-result.schema.json');
const workOrder = readJson('spec/apf-cp/v1/examples/work-order.json');
const result = readJson('spec/apf-cp/v1/examples/result.json');
const providerResult = readJson('spec/apf-cp/v1/examples/provider-result.json');

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);

const validateCanonical = ajv.compile(canonicalSchema);
assertValid(validateCanonical, workOrder, 'work-order.json');
assertValid(validateCanonical, result, 'result.json');
for (const documentPath of process.argv.slice(2)) {
  const document = JSON.parse(fs.readFileSync(documentPath, 'utf8'));
  assertValid(validateCanonical, document, path.basename(documentPath));
}

const validateProviderResult = ajv.compile(providerResultSchema);
assertValid(validateProviderResult, providerResult, 'provider-result.json');

assertInvalid(
  validateCanonical,
  { ...workOrder, message_id: 'RES-WRONG-TYPE' },
  'WORK_ORDER with RESULT message_id'
);
const resultWithoutRun = { ...result };
delete resultWithoutRun.run_id;
assertInvalid(validateCanonical, resultWithoutRun, 'RESULT without run_id');

const budgetWithoutEnforcement = structuredClone(workOrder);
delete budgetWithoutEnforcement.budget.enforcement;
assertInvalid(validateCanonical, budgetWithoutEnforcement, 'WORK_ORDER budget without enforcement');

const providerAuthoredWorkOrder = structuredClone(workOrder);
providerAuthoredWorkOrder.actor.authority = 'PROVIDER';
assertInvalid(validateCanonical, providerAuthoredWorkOrder, 'provider-authored WORK_ORDER');

const forbiddenProductionGrant = structuredClone(workOrder);
forbiddenProductionGrant.payload.grants = [{
  capability: 'production',
  decision: 'ALLOW',
  enforcement: 'OS_ENFORCED',
  scope: { environment: 'PRODUCTION', expires_at: '2026-08-28T22:00:00Z' }
}];
assertInvalid(validateCanonical, forbiddenProductionGrant, 'V1 production ALLOW grant');

const advisoryAllow = structuredClone(workOrder);
advisoryAllow.payload.grants[0].enforcement = 'ADVISORY';
assertInvalid(validateCanonical, advisoryAllow, 'ALLOW grant with advisory enforcement');

const escapingPath = structuredClone(workOrder);
escapingPath.payload.allowed_paths = ['../outside.txt'];
assertInvalid(validateCanonical, escapingPath, 'parent-relative allowed path');

const unprotectedInfrastructure = structuredClone(workOrder);
unprotectedInfrastructure.payload.protected_paths = ['.git/**', '.apf/**'];
assertInvalid(validateCanonical, unprotectedInfrastructure, 'WORK_ORDER without protected tool cache');

const actualListCost = structuredClone(result);
actualListCost.payload.usage.cost_basis = 'LIST';
assertInvalid(validateCanonical, actualListCost, 'ACTUAL usage with list-basis cost');

const terminalEscape = structuredClone(result);
terminalEscape.payload.summary = '\u001b]8;;https://example.invalid\u0007spoof';
assertInvalid(validateCanonical, terminalEscape, 'RESULT containing terminal control sequences');

const cancelWithoutRun = structuredClone(workOrder);
cancelWithoutRun.message_id = 'CAN-0001';
cancelWithoutRun.message_type = 'CANCEL_REQUEST';
cancelWithoutRun.payload = { reason: 'Operator requested cancellation.', descendants: 'CANCEL' };
assertInvalid(validateCanonical, cancelWithoutRun, 'CANCEL_REQUEST without run_id');

assertInvalid(
  validateProviderResult,
  { ...providerResult, usage: result.payload.usage },
  'provider payload containing runtime-owned usage'
);

process.stdout.write('APF-CP schemas: positive controls and 12 negative controls valid\n');
