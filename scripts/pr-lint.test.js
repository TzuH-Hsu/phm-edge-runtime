// SPDX-License-Identifier: MIT
'use strict';
// pr-lint.test.js — exercises scripts/pr-lint.js under plain node.
// Run by scripts/check-node-tests.sh from `make check`. Which issues a PR
// closes comes from GitHub (closingIssuesReferences); here it is a stub.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { lint, run, settledRefs, parseBody, TYPES } = require('./pr-lint.js');

const REPO = 'o/r';
const open = (number, repo = REPO) => ({ repo, number, state: 'OPEN' });
const check = (headRef, refs, extra = {}) => lint({ headRef, refs, repo: REPO, ...extra });
const withBody = (headRef, body, refs = []) => check(headRef, refs, { body });

test('a conforming PR passes', () => {
  assert.deepEqual(check('fix/42-label-sync', [open(42)]), {
    exempt: false, why: null, problems: [], branchIssue: 42, linked: [42], cross: [], mentioned: [], noIssue: null,
  });
});

test("TYPES equals the list in AGENTS.md's Branch step (the one home for it)", () => {
  const agents = fs.readFileSync(path.join(__dirname, '..', 'AGENTS.md'), 'utf8');
  const line = agents.split('\n').find((l) => l.includes('**Branch**') && l.includes('<type>/<issue#>-<slug>') && l.includes('<type>/<slug>'));
  assert.ok(line, 'AGENTS.md Branch step not found');
  const listed = [...line.matchAll(/`([a-z]+)`/g)].map((m) => m[1]);
  assert.deepEqual(listed, TYPES);
});

test('the six-PR failure shape: empty issue slot in the branch and no issue relation', () => {
  const r = check('chore/-initial-version-docs', []);
  assert.equal(r.problems.length, 2);
  assert.match(r.problems[0], /not <type>\/<issue#>-<slug> or <type>\/<slug>/);
  assert.match(r.problems[1], /does not say how this PR relates to an issue/);
  assert.match(r.problems[1], /"Closes #N".*"Refs #N".*"No issue: <reason>"/);
});

test('only the body counts: the query leaves out issues linked in the sidebar (no event re-runs the check when they change)', () => {
  assert.match(require('./pr-lint.js').CLOSING_QUERY, /closingIssuesReferences\(first: 20, excludeUserLinked: true\)/);
  assert.match(check('fix/42-x', []).problems[0], /linked only in the sidebar does not count/);
});

test('a reference to this repository by its full name is local, case-insensitively', () => {
  assert.deepEqual(check('fix/42-x', [open(42, 'O/R')]).problems, []);
});

test('a cross-repository close is rejected, alone and alongside a local one; Refs is the way', () => {
  const alone = check('fix/x', [open(9, 'other/repo')]);
  assert.equal(alone.problems.length, 1);
  assert.match(alone.problems[0], /closes other\/repo#9 in another repository — .*"Refs <owner>\/<repo>#N"/);
  const both = check('fix/42-x', [open(42), open(9, 'other/repo')]);
  assert.equal(both.problems.length, 1);
  assert.match(both.problems[0], /another repository/);
});

test('at most one local close: a second one fails, a mismatched one fails, a duplicate is one', () => {
  const two = check('feat/10-x', [open(10), open(11)]);
  assert.equal(two.problems.length, 1);
  assert.match(two.problems[0], /closes #10, #11 — close one issue per PR/);
  const other = check('feat/10-x', [open(11)]);
  assert.equal(other.problems.length, 1);
  assert.match(other.problems[0], /branch names issue #10 but the PR body neither closes nor refs it/);
  assert.deepEqual(check('feat/10-x', [open(10), open(10)]).problems, []);
});

test('a closed issue cannot be closed by merging', () => {
  const r = check('fix/42-x', [{ repo: REPO, number: 42, state: 'CLOSED' }]);
  assert.equal(r.problems.length, 1);
  assert.match(r.problems[0], /issue #42 is already closed/);
});

test('branch grammar: <type>/<issue#>-<slug> or <type>/<slug>, every type; rejects others', () => {
  for (const t of TYPES) {
    assert.deepEqual(check(`${t}/7-a.b_c-1`, [open(7)]).problems, []);
    assert.deepEqual(check(`${t}/a.b_c-1`, [open(7)]).problems, []);
  }
  assert.equal(check('fix/x-7', [open(7)]).branchIssue, null); // a slug may end in digits
  for (const bad of ['Feat/7-x', 'feature/7-x', 'fix/7', 'fix/7-', 'fix/-x', 'fix/Readme', 'fix-7-x', 'main', 'hotfix/7-x']) {
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
  assert.equal(spoof.problems.length, 2); // branch, and no issue relation
  assert.equal(check('dependabot/x', [], { author: 'someone' }).exempt, false);
});

test('Refs alone passes: here or in another repository, several per line, several lines; Closes and Refs together pass', () => {
  assert.deepEqual(withBody('docs/x', 'Refs #12').problems, []);
  assert.deepEqual(withBody('docs/x', 'Refs: #12, o/other#3 https://github.com/o/edge/issues/9').mentioned, ['#12', 'o/other#3', 'o/edge#9']);
  assert.deepEqual(withBody('docs/x', 'refs #1\nRefs #2').mentioned, ['#1', '#2']);
  assert.deepEqual(withBody('docs/x', 'Refs O/R#5').mentioned, ['#5']); // this repository by full name is local
  const both = withBody('fix/42-x', 'Closes #42\nRefs o/other#7', [open(42)]);
  assert.deepEqual(both.problems, []);
  assert.deepEqual(both.mentioned, ['o/other#7']);
});

test('a branch issue is satisfied by Refs of it, not by Refs of another one', () => {
  assert.deepEqual(withBody('feat/10-x', 'Refs #10').problems, []);
  assert.deepEqual(withBody('feat/10-x', 'Refs o/r#10').problems, []);
  const wrong = withBody('feat/10-x', 'Refs #11');
  assert.equal(wrong.problems.length, 1);
  assert.match(wrong.problems[0], /branch names issue #10 but the PR body neither closes nor refs it/);
  const elsewhere = withBody('feat/10-x', 'Refs o/other#10'); // another repository's #10 is not this one
  assert.equal(elsewhere.problems.length, 1);
});

test('No issue: passes with a reason; placeholders and an empty reason fail', () => {
  const ok = withBody('docs/readme-typo', 'No issue: fix a typo in README');
  assert.deepEqual(ok.problems, []);
  assert.equal(ok.noIssue, 'fix a typo in README');
  assert.deepEqual(withBody('docs/x', 'No issue：修正錯字').problems, []); // full-width colon
  for (const bad of ['No issue:', 'No issue: ', 'No issue: N/A', 'No issue: n/a.', 'No issue: none', 'No issue: TBD',
    'No issue: -', 'No issue: <reason>', 'No issue: <原因>', 'No issue: 無', 'No issue: 123']) {
    const r = withBody('docs/x', bad);
    assert.equal(r.problems.length, 1, bad);
    assert.match(r.problems[0], /"No issue:" needs a real reason/, bad);
  }
});

test('No issue together with Closes or Refs fails; with a branch issue it fails too', () => {
  const withClose = withBody('docs/x', 'Closes #4\nNo issue: tidy', [open(4)]);
  assert.equal(withClose.problems.length, 1);
  assert.match(withClose.problems[0], /both "No issue:" and an issue link/);
  assert.match(withBody('docs/x', 'Refs #4\nNo issue: tidy').problems[0], /both "No issue:" and an issue link/);
  const branch = withBody('docs/4-x', 'No issue: tidy');
  assert.equal(branch.problems.length, 1);
  assert.match(branch.problems[0], /branch names issue #4/);
});

test('only line-start keywords outside code and comments count', () => {
  const ignored = [
    'See Refs #12 for context', // not at the start of the line
    '`Refs #12`', // inline code
    '<!-- Refs #12 -->', // HTML comment
    '<!--\nNo issue: tidy\n-->', // multi-line HTML comment
    '```\nRefs #12\n```', // fenced code
    '~~~md\nNo issue: tidy\n~~~', // tilde fence
    '    Refs #12', // indented code block
    '- Refs #12', // list item
    '> Refs #12', // quote
    'References #12', // a different word
    '<!-- unterminated\nRefs #12', // an unclosed comment hides the rest
    '<pre>\nNo issue: tidy\n</pre>', // raw HTML code block
    '<PRE lang="md">\nRefs #12\n</PRE>', // any case, with attributes
  ];
  for (const body of ignored) {
    const r = parseBody(body);
    assert.deepEqual([r.refs, r.noIssue], [[], []], body);
  }
  assert.deepEqual(parseBody('   Refs #12').refs, [{ repo: null, number: 12 }]); // up to three spaces
  assert.deepEqual(parseBody('```\nx\n```\nRefs #12').refs, [{ repo: null, number: 12 }]); // after a closed fence
  assert.deepEqual(parseBody('```\n```still-code\nRefs #12\n```').refs, []); // a marker with text after it does not close
  assert.deepEqual(parseBody('````\n```\nRefs #12\n````').refs, []); // a shorter marker does not close a longer fence
  assert.deepEqual(parseBody('Refs #12\r\nNo issue: x').noIssue, ['x']); // CRLF
});

test('a Refs line with something other than issues is reported, not ignored', () => {
  const r = withBody('docs/x', 'Refs: see the thread below');
  assert.equal(r.problems.length, 2);
  assert.match(r.problems[0], /cannot read the line 'Refs: see the thread below'/);
  assert.match(r.problems[1], /does not say how this PR relates to an issue/);
  assert.match(withBody('docs/x', 'Refs #0').problems[0], /cannot read the line 'Refs #0'/); // issue numbers start at 1
  const mixed = withBody('docs/x', 'Refs #3, PR #4'); // the whole line is rejected, so nothing links
  assert.equal(mixed.problems.length, 2);
  assert.match(mixed.problems[0], /cannot read the line 'Refs #3, PR #4'/);
});

test('the PR template body fails until one option is filled in', () => {
  const template = fs.readFileSync(path.join(__dirname, '..', '.github', 'PULL_REQUEST_TEMPLATE.md'), 'utf8');
  const blank = withBody('docs/x', template);
  assert.equal(blank.problems.length, 1);
  assert.match(blank.problems[0], /does not say how this PR relates to an issue/);
  const filled = template.replace('<!-- related-issue -->', 'No issue: template test');
  assert.notEqual(filled, template, 'template marker <!-- related-issue --> not found');
  assert.deepEqual(withBody('docs/x', filled).problems, []);
});

// A GraphQL client stub: returns the queued answers in order (the last one
// repeats), or throws what it is given.
function graphqlStub(answers, updatedAt = '2026-01-01T00:00:00Z', body = '') {
  const calls = [];
  let i = 0;
  const github = {
    graphql: async (query, vars) => {
      calls.push(vars);
      const a = answers[Math.min(i++, answers.length - 1)];
      if (a instanceof Error) throw a;
      return { repository: { pullRequest: { updatedAt, body, closingIssuesReferences: { nodes: a.map((r) => ({
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
  assert.deepEqual(out, [['info', 'PR lint passed: closes #42']]);
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

test('run: reads Refs and No issue from the live body, not the event (a re-run replays an old event)', async () => {
  const refs = graphqlStub([[]], undefined, 'Refs #3\nRefs o/edge#9');
  const a = coreSpy();
  await run({ github: refs.github, context: ctx({ head: { ref: 'docs/x' }, body: 'stale' }), core: a.core, sleep: noWait });
  assert.deepEqual(a.out, [['info', 'PR lint passed: refs #3, o/edge#9']]);
  const none = graphqlStub([[]], undefined, 'No issue: fix a typo');
  const b = coreSpy();
  await run({ github: none.github, context: ctx({ head: { ref: 'docs/x' } }), core: b.core, sleep: noWait });
  assert.deepEqual(b.out, [['info', 'PR lint passed: no issue (fix a typo)']]);
  const both = graphqlStub([[{ number: 42 }]], undefined, 'Closes #42\nRefs #3');
  const c = coreSpy();
  await run({ github: both.github, context: ctx(), core: c.core, sleep: noWait });
  assert.deepEqual(c.out, [['info', 'PR lint passed: closes #42; refs #3']]);
});

test('run: fails with every problem listed', async () => {
  const { github } = graphqlStub([[]]);
  const { out, core } = coreSpy();
  await run({ github, context: ctx({ head: { ref: 'chore/-x' } }), core, sleep: noWait });
  assert.equal(out.length, 1);
  assert.equal(out[0][0], 'failed');
  assert.match(out[0][1], /^PR lint failed:\n- branch .*\n- the PR body does not say how this PR relates to an issue/s);
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
