// SPDX-License-Identifier: MIT
'use strict';
// pr-lint.test.js — exercises scripts/pr-lint.js under plain node.
// Run by scripts/check-node-tests.sh from `make check`. Which issues a PR
// closes comes from GitHub (closingIssuesReferences); here it is a stub.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { lint, run, settledRefs, TYPES } = require('./pr-lint.js');

const REPO = 'o/r';
const open = (number, repo = REPO) => ({ repo, number, state: 'OPEN' });
const check = (headRef, refs, extra = {}) => lint({ headRef, refs, repo: REPO, ...extra });

test('a conforming PR passes', () => {
  assert.deepEqual(check('fix/42-label-sync', [open(42)]), {
    exempt: false, why: null, problems: [], branchIssue: 42, linked: [42], cross: [],
  });
});

test("TYPES equals the list in AGENTS.md's Branch step (the one home for it)", () => {
  const agents = fs.readFileSync(path.join(__dirname, '..', 'AGENTS.md'), 'utf8');
  const line = agents.split('\n').find((l) => l.includes('**Branch**') && l.includes('<type>/<issue#>-<slug>'));
  assert.ok(line, 'AGENTS.md Branch step not found');
  const listed = [...line.matchAll(/`([a-z]+)`/g)].map((m) => m[1]);
  assert.deepEqual(listed, TYPES);
});

test('the six-PR failure shape: empty issue slot in the branch and nothing closed', () => {
  const r = check('chore/-initial-version-docs', []);
  assert.equal(r.problems.length, 2);
  assert.match(r.problems[0], /not <type>\/<issue#>-<slug>/);
  assert.match(r.problems[1], /closes no issue in this repository — the PR template line/);
  assert.match(r.problems[1], /sub-issue it can close/);
});

test('only the body counts: the query leaves out issues linked in the sidebar (no event re-runs the check when they change)', () => {
  assert.match(require('./pr-lint.js').CLOSING_QUERY, /closingIssuesReferences\(first: 20, excludeUserLinked: true\)/);
  assert.match(check('fix/42-x', []).problems[0], /linked only in the sidebar does not count/);
});

test('a reference to this repository by its full name is local, case-insensitively', () => {
  assert.deepEqual(check('fix/42-x', [open(42, 'O/R')]).problems, []);
});

test('a cross-repository close is a second issue: rejected alone and alongside a local one', () => {
  const alone = check('fix/42-x', [open(9, 'other/repo')]);
  assert.equal(alone.problems.length, 2);
  assert.match(alone.problems[0], /closes no issue in this repository/);
  assert.match(alone.problems[1], /closes other\/repo#9 in another repository/);
  const both = check('fix/42-x', [open(42), open(9, 'other/repo')]);
  assert.equal(both.problems.length, 1);
  assert.match(both.problems[0], /another repository/);
});

test('exactly one local issue: a second one fails (one issue per PR), a mismatched one fails, a duplicate is one', () => {
  const two = check('feat/10-x', [open(10), open(11)]);
  assert.equal(two.problems.length, 1);
  assert.match(two.problems[0], /closes #10, #11 — one issue per PR/);
  const other = check('feat/10-x', [open(11)]);
  assert.equal(other.problems.length, 1);
  assert.match(other.problems[0], /branch names issue #10 but the PR closes #11/);
  assert.deepEqual(check('feat/10-x', [open(10), open(10)]).problems, []);
});

test('a closed issue cannot be closed by merging', () => {
  const r = check('fix/42-x', [{ repo: REPO, number: 42, state: 'CLOSED' }]);
  assert.equal(r.problems.length, 1);
  assert.match(r.problems[0], /issue #42 is already closed/);
});

test('branch grammar: every CONTRIBUTING type, lowercase slug with dots/underscores; rejects others', () => {
  for (const t of TYPES) {
    assert.deepEqual(check(`${t}/7-a.b_c-1`, [open(7)]).problems, []);
  }
  for (const bad of ['Feat/7-x', 'feature/7-x', 'fix/7', 'fix/7-', 'fix/x-7', 'fix-7-x', 'main', 'hotfix/7-x']) {
    assert.equal(check(bad, [open(7)]).problems.length, 1, bad);
  }
});

test('bot PRs are exempt by author or by the release-please label — never by branch name', () => {
  assert.equal(check('release-please--branches--main', [], { author: 'github-actions[bot]' }).exempt, true);
  assert.equal(check('dependabot/github_actions/actions-f3c1f23acc', [], { author: 'dependabot[bot]' }).exempt, true);
  // release-please run with a PAT: human author, but the label it applies is proof enough
  assert.equal(check('release-please--branches--main', [], { author: 'someone', labels: ['autorelease: pending'] }).exempt, true);
  // a fork author borrowing the bot branch name gets the full lint
  const spoof = check('release-please--branches--main', [], { author: 'someone', labels: [] });
  assert.equal(spoof.exempt, false);
  assert.equal(spoof.problems.length, 2);
  assert.equal(check('dependabot/x', [], { author: 'someone' }).exempt, false);
});

// A GraphQL client stub: returns the queued answers in order (the last one
// repeats), or throws what it is given.
function graphqlStub(answers, updatedAt = '2026-01-01T00:00:00Z') {
  const calls = [];
  let i = 0;
  const github = {
    graphql: async (query, vars) => {
      calls.push(vars);
      const a = answers[Math.min(i++, answers.length - 1)];
      if (a instanceof Error) throw a;
      return { repository: { pullRequest: { updatedAt, closingIssuesReferences: { nodes: a.map((r) => ({
        number: r.number, state: r.state || 'OPEN', repository: { nameWithOwner: r.repo || REPO },
      })) } } } };
    },
  };
  return { github, calls };
}
const noWait = async () => {};
const pr = (over = {}) => ({ number: 7, state: 'open', head: { ref: 'fix/42-x' }, user: { login: 'someone' }, labels: [], ...over });
const ctx = (over) => ({ repo: { owner: 'o', repo: 'r' }, payload: { pull_request: pr(over) } });
const coreSpy = () => {
  const out = [];
  return { out, core: { info: (m) => out.push(['info', m]), setFailed: (m) => out.push(['failed', m]) } };
};

test('settledRefs: returns once two reads agree, and keeps reading while GitHub is still catching up', async () => {
  const steady = graphqlStub([[{ number: 42 }]]);
  assert.deepEqual(await settledRefs(steady.github, 'o', 'r', 7, { sleep: noWait }), [open(42)]);
  assert.equal(steady.calls.length, 2);
  // a body edit still propagating: [] → [42] → [42]
  const lagging = graphqlStub([[], [{ number: 42 }], [{ number: 42 }]]);
  assert.deepEqual(await settledRefs(lagging.github, 'o', 'r', 7, { sleep: noWait }), [open(42)]);
  assert.equal(lagging.calls.length, 3);
  // never settles: bounded, and the last read wins
  const flapping = graphqlStub([[{ number: 1 }], [{ number: 2 }], [{ number: 3 }], [{ number: 4 }], [{ number: 5 }]]);
  assert.deepEqual(await settledRefs(flapping.github, 'o', 'r', 7, { reads: 5, sleep: noWait }), [open(5)]);
  assert.equal(flapping.calls.length, 5);
  // order does not matter
  const reordered = graphqlStub([[{ number: 2 }, { number: 1 }], [{ number: 1 }, { number: 2 }]]);
  assert.deepEqual((await settledRefs(reordered.github, 'o', 'r', 7, { sleep: noWait })).map((r) => r.number), [1, 2]);
});

test('run: passes with an info line, asks GitHub about the right PR', async () => {
  const { github, calls } = graphqlStub([[{ number: 42 }]]);
  const { out, core } = coreSpy();
  await run({ github, context: ctx(), core, sleep: noWait });
  assert.deepEqual(out, [['info', 'PR lint passed: branch issue #42, the PR closes #42']]);
  assert.deepEqual(calls[0], { owner: 'o', repo: 'r', number: 7 });
});

test('run: waits until the triggering edit is 15 s old before the first read, and not when it already is', async () => {
  const waits = [];
  const sleep = async (ms) => { waits.push(ms); };
  const { github } = graphqlStub([[{ number: 42 }]]);
  const t0 = Date.parse('2026-09-29T10:00:00Z');
  await run({ github, context: ctx({ updated_at: '2026-09-29T10:00:00Z' }), core: coreSpy().core, sleep, now: () => t0 + 4000 });
  assert.equal(waits[0], 11000); // 15 s after the edit, minus the 4 s already gone
  waits.length = 0;
  await run({ github, context: ctx({ updated_at: '2026-09-29T10:00:00Z' }), core: coreSpy().core, sleep, now: () => t0 + 60000 });
  assert.equal(waits[0], 5000); // only the settle pause between the two reads
  // a manual re-run: the replayed event is old, but the body was edited 2 s ago — wait on the live time
  waits.length = 0;
  const rerun = graphqlStub([[{ number: 42 }]], '2026-09-29T10:00:58Z');
  await run({ github: rerun.github, context: ctx({ updated_at: '2026-09-29T09:00:00Z' }), core: coreSpy().core, sleep, now: () => t0 + 60000 });
  assert.equal(waits[0], 13000);
});

test('run: fails with every problem listed', async () => {
  const { github } = graphqlStub([[]]);
  const { out, core } = coreSpy();
  await run({ github, context: ctx({ head: { ref: 'chore/-x' } }), core, sleep: noWait });
  assert.equal(out.length, 1);
  assert.equal(out[0][0], 'failed');
  assert.match(out[0][1], /^PR lint failed:\n- branch .*\n- this PR closes no issue/s);
});

test('run: skips closed PRs, bot PRs and non-PR events without asking GitHub', async () => {
  const { github, calls } = graphqlStub([[{ number: 42 }]]);
  const { out, core } = coreSpy();
  await run({ github, context: ctx({ state: 'closed', number: 23 }), core, sleep: noWait });
  await run({ github, context: ctx({ user: { login: 'github-actions[bot]' } }), core, sleep: noWait });
  await run({ github, context: { payload: {} }, core, sleep: noWait });
  assert.deepEqual(out.map((o) => o[1]), [
    'PR lint skipped: pull request #23 is closed',
    'PR lint skipped: opened by github-actions[bot]',
    'not a pull_request event — nothing to lint',
  ]);
  assert.equal(calls.length, 0);
});

test('run: a refused read names the missing scopes; any other failure fails the check', async () => {
  const forbidden = Object.assign(new Error('Resource not accessible by integration'), { status: 403 });
  const typed = Object.assign(new Error('forbidden'), { errors: [{ type: 'FORBIDDEN' }] });
  for (const err of [forbidden, typed]) {
    const { github } = graphqlStub([err]);
    await assert.rejects(() => run({ github, context: ctx(), core: coreSpy().core, sleep: noWait }),
      /could not read which issues PR #7 closes: .* — .*`issues: read` and `pull-requests: read`/);
  }
  const { github } = graphqlStub([new Error('boom')]);
  await assert.rejects(() => run({ github, context: ctx(), core: coreSpy().core, sleep: noWait }),
    /could not read which issues PR #7 closes: boom/);
});
