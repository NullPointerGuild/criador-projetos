import fs from 'node:fs';
import { spawn } from 'node:child_process';
import readline from 'node:readline';
import net from 'node:net';

const [mode, attack, scratchRoot, ledgerPath, depthText = '3'] = process.argv.slice(2);

function record(kind) {
  fs.appendFileSync(ledgerPath, `${JSON.stringify({
    pid: process.pid,
    ppid: process.ppid,
    kind,
    observed_at_ms: Date.now()
  })}\n`, 'utf8');
}

if (mode === 'launcher') {
  record('launcher');
  const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  input.once('line', (line) => {
    if (line !== 'GO') process.exit(71);
    const child = spawn(process.execPath, [
      new URL(import.meta.url).pathname.replace(/^\/(?:[A-Za-z]:)/, (value) => value.slice(1)),
      attack,
      attack,
      scratchRoot,
      ledgerPath,
      depthText
    ], { stdio: ['ignore', 'inherit', 'inherit'], env: process.env, windowsHide: true });
    child.once('exit', (code, signal) => {
      if (signal) process.exit(72);
      process.exit(code ?? 73);
    });
  });
} else if (mode === 'tree') {
  const depth = Number.parseInt(depthText, 10);
  record(`tree-${depth}`);
  if (depth > 0) {
    spawn(process.execPath, [
      new URL(import.meta.url).pathname.replace(/^\/(?:[A-Za-z]:)/, (value) => value.slice(1)),
      'tree',
      'tree',
      scratchRoot,
      ledgerPath,
      String(depth - 1)
    ], { stdio: ['ignore', 'inherit', 'inherit'], env: process.env, windowsHide: true });
  }
  setInterval(() => {}, 60000);
} else if (mode === 'env') {
  record('env');
  const names = [
    'APF_CANARY_TOKEN', 'GITHUB_TOKEN', 'OPENAI_API_KEY', 'ANTHROPIC_API_KEY',
    'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AZURE_CLIENT_SECRET',
    'GOOGLE_APPLICATION_CREDENTIALS', 'NPM_TOKEN', 'GIT_ASKPASS', 'SSH_AUTH_SOCK'
  ];
  const values = Object.fromEntries(names.map((name) => [name, process.env[name] ?? null]));
  process.stdout.write(`${JSON.stringify({ values, home: process.env.HOME, userprofile: process.env.USERPROFILE })}\n`);
} else if (mode === 'flood') {
  record('flood');
  const stdoutChunk = Buffer.alloc(8192, 0x58);
  const stderrChunk = Buffer.alloc(8192, 0x59);
  for (let index = 0; index < 256; index += 1) {
    fs.writeSync(1, stdoutChunk);
    fs.writeSync(2, stderrChunk);
  }
} else if (mode === 'network') {
  record('network');
  const client = net.createConnection({ host: '127.0.0.1', port: Number.parseInt(depthText, 10) });
  client.once('connect', () => {
    client.end('APF-SYNTHETIC-LOOPBACK-CANARY');
  });
  client.once('error', (error) => {
    process.stderr.write(`${error.code ?? error.message}\n`);
    process.exit(74);
  });
} else {
  process.stderr.write(`unknown mode: ${mode}\n`);
  process.exit(70);
}
