import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import * as engine from '../build/dev/javascript/loophole/loophole/engine.mjs';

try {
  assert.ok(process.argv[2], 'Usage: node scripts/verify-replay.mjs <receipt.json> (run npm run build first)');
  const record = JSON.parse(await readFile(process.argv[2], 'utf8'));
  assert.equal(record.schema, 'loophole.replay.v1', 'Unsupported schema');
  assert.equal(record.version, '0.1.0', 'Unsupported model version');
  assert.ok(['shortest', 'fair'].includes(record.policy), 'Unknown policy');
  assert.ok(Number.isInteger(record.queue_cap) && record.queue_cap >= 1 && record.queue_cap <= 8, 'Invalid queue cap');
  assert.ok(Number.isInteger(record.horizon) && record.horizon >= 12 && record.horizon <= 48, 'Invalid horizon');
  assert.equal(typeof record.searched, 'boolean', 'Invalid search state');
  const rules = new engine.Rules(record.policy === 'fair' ? new engine.Fair() : new engine.Shortest(), record.queue_cap, record.horizon);
  const baseline = engine.run(rules, engine.honest());
  const search = record.searched ? engine.search(rules) : null;
  const strategy = search?.strategy || engine.honest();
  const frames = search?.frames || baseline;
  assert.deepEqual(record.strategy, { chunk: strategy.chunk, burst: strategy.burst, delay: strategy.delay }, 'Strategy differs from deterministic result');
  assert.equal(record.strategies_tested, record.searched ? 36 : 0);
  assert.equal(record.baseline_units, engine.score(baseline));
  assert.equal(record.rogue_units, engine.score(frames));
  assert.equal(record.gain, engine.score(frames) - engine.score(baseline));
  assert.deepEqual(record.frames, frames.toArray().map(frame => ({
    tick: frame.tick,
    served: engine.owner_name(frame.served),
    allocated: frame.completed.toArray(),
    submitted: frame.submitted.toArray(),
    queue: frame.queue.toArray().map(job => ({ id: job.id, owner: engine.owner_name(job.owner), remaining: job.remaining })),
  })), 'Frame trace differs from model replay');
  const fragment = record.replay_fragment.split(':');
  assert.deepEqual(fragment.slice(0, 5), ['#v1', record.policy, String(record.queue_cap), String(record.horizon), record.searched ? 'searched' : 'baseline']);
  assert.equal(fragment.length, 6);
  assert.match(fragment[5], /^\d+$/);
  assert.ok(Number(fragment[5]) <= record.horizon, 'Replay tick exceeds horizon');
  console.log(`Verified ${record.frames.length} frames; ${record.strategies_tested} strategies; Rogue ${record.rogue_units} vs baseline ${record.baseline_units}.`);
} catch (error) {
  console.error('Replay verification failed:', error.message);
  process.exitCode = 1;
}
