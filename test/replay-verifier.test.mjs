import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { verifyRecord } from '../scripts/verify-replay.mjs';
import { init, receipt } from '../build/dev/javascript/loophole/loophole/reputation_ui.mjs';

const record = fragment => JSON.parse(receipt(init(fragment)));

test('original compute v1 browser export still recomputes', async () => {
  const old = JSON.parse(await readFile(new URL('./fixtures/compute-v1.json', import.meta.url), 'utf8'));
  assert.match(verifyRecord(old), /Rogue 12 vs baseline 4/);
});

test('reputation baseline, exploit, repair and stricter thresholds recompute', () => {
  for (const policy of ['rating', 'bond']) {
    for (const threshold of [50, 80, 90, 95, 99]) {
      for (const ceiling of [8, 32, 64]) {
        for (const mode of ['baseline', 'searched']) {
          const replay = record(`rep1:${policy}:${threshold}:${ceiling}:${mode}:0`);
          assert.match(verifyRecord(replay), /reputation frames/);
        }
      }
    }
  }
});

test('rejects altered loss, collateral, rating, outcome and strategy', () => {
  const original = record('rep1:rating:80:64:searched:5');
  for (const mutate of [
    r => { r.loss = 0; },
    r => { r.frames[4].bond = 64; },
    r => { r.frames[4].rating = 100; },
    r => { r.frames[5].outcome = 'delivered'; },
    r => { r.strategy.history = 8; },
    r => { r.baseline_loss = 60; },
    r => { r.strategies_tested = 49; },
  ]) {
    const altered = structuredClone(original);
    mutate(altered);
    assert.throws(() => verifyRecord(altered));
  }
});

test('rejects invalid schema, rule bounds, replay position and policy mismatch', () => {
  for (const mutate of [
    r => { r.schema = 'unknown'; },
    r => { r.threshold = 100; },
    r => { r.ceiling = -1; },
    r => { r.policy = 'trust-all'; },
    r => { r.replay_fragment = '#rep1:rating:80:64:searched:999'; },
    r => { r.replay_fragment = '#rep1:rating:80:64:searched:-1'; },
    r => { r.replay_fragment = '#rep1:bond:80:64:searched:5'; },
  ]) {
    const altered = record('rep1:rating:80:64:searched:5');
    mutate(altered);
    assert.throws(() => verifyRecord(altered));
  }
});

const ringUI = await import('../build/dev/javascript/loophole/loophole/collusion_ui.mjs');
const ringRecord = fragment => JSON.parse(ringUI.receipt(ringUI.init(fragment)));

test('review baseline, exploit, cap and bypass recompute across 60 configurations', () => {
  for (const policy of ['all', 'unique']) {
    for (const budget of [3, 10, 20, 24, 40]) {
      for (const threshold of [60, 80, 95]) {
        for (const mode of ['baseline', 'searched']) {
          assert.match(verifyRecord(ringRecord(`ring1:${policy}:${budget}:${threshold}:${mode}:0`)), /review frames/);
        }
      }
    }
  }
});

test('review verifier rejects altered accounting, ratings, search and replay bounds', () => {
  for (const mutate of [
    r => { r.frames[3].spent = 0; },
    r => { r.frames[3].reviews[0] = 8; },
    r => { r.frames[3].counted = 20; },
    r => { r.frames[3].rating = 100; },
    r => { r.frames[3].promoted = true; },
    r => { r.rating = 40; },
    r => { r.promoted = false; },
    r => { r.strategy.accounts = 8; },
    r => { r.feasible = 24; },
    r => { r.budget = 41; },
    r => { r.threshold = 100; },
    r => { r.policy = 'trust-all'; },
    r => { r.replay_fragment = '#ring1:all:20:80:searched:999'; },
    r => { r.replay_fragment = '#ring1:all:20:80:searched:-1'; },
    r => { r.replay_fragment = '#ring1:unique:20:80:searched:19'; },
  ]) {
    const altered = ringRecord('ring1:all:20:80:searched:19');
    mutate(altered);
    assert.throws(() => verifyRecord(altered));
  }
});
