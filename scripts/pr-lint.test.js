// SPDX-License-Identifier: MIT
'use strict';
// pr-lint.test.js — exercises scripts/pr-lint.js under plain node.
// Run by scripts/check-node-tests.sh from `make check`.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { lint, linkedIssues, run, TYPES } = require('./pr-lint.js');
const numbers = (body, repo) => linkedIssues(body, repo).filter((r) => !r.repo).map((r) => r.number);

const GOOD_BODY = '## Summary\n\nx\n\n## Related issue\n\nCloses #42\n';

test('a conforming PR passes', () => {
  const r = lint({ headRef: 'fix/42-label-sync', body: GOOD_BODY });
  assert.deepEqual(r, { exempt: false, why: null, problems: [], branchIssue: 42, linked: [42], cross: [] });
});

test("TYPES equals the list in AGENTS.md's Branch step (the one home for it)", () => {
  const agents = fs.readFileSync(path.join(__dirname, '..', 'AGENTS.md'), 'utf8');
  const line = agents.split('\n').find((l) => l.includes('**Branch**') && l.includes('<type>/<issue#>-<slug>'));
  assert.ok(line, 'AGENTS.md Branch step not found');
  const listed = [...line.matchAll(/`([a-z]+)`/g)].map((m) => m[1]);
  assert.deepEqual(listed, TYPES);
});

test('the six-PR failure shape: empty issue slot in the branch and a bare "Closes #"', () => {
  const r = lint({ headRef: 'chore/-initial-version-docs', body: 'Closes #\n' });
  assert.equal(r.problems.length, 2);
  assert.match(r.problems[0], /not <type>\/<issue#>-<slug>/);
  assert.match(r.problems[1], /links no issue/);
});

test('the untouched template line still fails: the number is inside an HTML comment', () => {
  const r = lint({ headRef: 'fix/42-x', body: 'Closes #<!-- issue number -->' });
  assert.deepEqual(r.linked, []);
  assert.equal(r.problems.length, 1);
});

test('a closing keyword inside an HTML comment, a fenced block or inline code does not count', () => {
  assert.deepEqual(numbers('<!-- Closes #12 -->\nsome text'), []);
  assert.deepEqual(numbers('<!--\nCloses #42'), []); // unterminated block comment runs to EOF
  assert.deepEqual(numbers('  <!--\nCloses #43'), []);
  assert.deepEqual(numbers('Closes #<!--\nCloses #44'), [44]); // unterminated mid-line: literal text, GitHub links the next line
  assert.deepEqual(numbers('<!-- a --> Closes #45 <!-- b -->'), []); // line-start <!-- makes the WHOLE line an HTML block (CommonMark type 2), even past -->
  assert.deepEqual(numbers('x <!-- a --> Closes #45 <!-- b -->'), [45]); // mid-line comments are inline; the prose between them counts
  // nesting: whichever block opens first wins
  assert.deepEqual(numbers('```\n<!--\n```\nCloses #46'), [46]); // `<!--` inside a fence is code
  assert.deepEqual(numbers('<!--\n```\n-->\nCloses #47'), [47]); // ``` inside a comment block is comment
  assert.deepEqual(numbers('<!--\n```\nCloses #48'), []); // unclosed comment block swallows the fence line too
  assert.deepEqual(numbers('`<!--` Closes #49 `-->`'), [49]); // leftmost construct wins: the backtick makes <!-- code
  assert.deepEqual(numbers('text <!--\nCloses #50\n--> Closes #51'), [51]); // inline comment across lines
  assert.deepEqual(numbers('```\nCloses #12\n```\n'), []);
  assert.deepEqual(numbers('~~~bash\ngit commit -m "Closes #12"\n~~~'), []);
  assert.deepEqual(numbers('use `Closes #12` in the body'), []);
  assert.deepEqual(numbers('```\nCloses #12\n```\nCloses #13'), [13]);
  assert.deepEqual(numbers('`x` Closes #14 `y`'), [14]);
  assert.deepEqual(numbers('``Closes #15``'), []);
  assert.deepEqual(numbers('`` `Closes #16` `` and Closes #17'), [17]);
  assert.deepEqual(numbers('```Closes #18``` Closes #19'), [19]);
  // CRLF bodies: both fence characters close (GitHub normalises line endings)
  assert.deepEqual(numbers('~~~\r\nCloses #20\r\n~~~\r\n\r\nCloses #21'), [21]);
  assert.deepEqual(numbers('```\r\nCloses #22\r\n```\r\n\r\nCloses #23'), [23]);
  // a fence inside a blockquote is code; a plain quoted line is still prose
  assert.deepEqual(numbers('> ~~~\n> Closes #24\n> ~~~\nCloses #25'), [25]);
  assert.deepEqual(numbers('> Closes #26'), [26]);
  // an indented code block is code; the same indentation continuing a list item or a paragraph is prose
  assert.deepEqual(numbers('Summary\n\n    Closes #27\n'), []);
  assert.deepEqual(numbers('    Closes #28'), []);
  assert.deepEqual(numbers('Summary\n\n\tCloses #29'), []);
  assert.deepEqual(numbers('- item\n\n    Closes #30'), [30]);
  assert.deepEqual(numbers('1. item\n\n    Closes #31'), [31]);
  assert.deepEqual(numbers('text\n    Closes #32'), [32]);
  assert.deepEqual(numbers('- item\n\nparagraph\n\n    Closes #33'), []); // the paragraph ended the list
  assert.deepEqual(numbers('    code\n\n    Closes #34\nCloses #35'), [35]); // one indented block across a blank line
  // a quoted fence ends with its quote; the unquoted ``` after it opens a new fence
  assert.deepEqual(numbers('> ```\n> Closes #36\n```\nCloses #37'), []);
  assert.deepEqual(numbers('> ```\n> Closes #38\n\nCloses #39'), [39]);
  // inside a top-level fence, a quoted ``` line is content, not the closing fence
  assert.deepEqual(numbers('```\n> ```\nCloses #40\n```\nCloses #41'), [41]);
  // indentation is measured from the list item's content column
  assert.deepEqual(numbers('- item\n\n        Closes #42'), []);
  assert.deepEqual(numbers('1. item\n\n       Closes #43'), []);
  assert.deepEqual(numbers('10. item\n\n    Closes #44'), [44]); // content column 4: still the item's prose
  // tabs expand to 4-column stops
  assert.deepEqual(numbers('Summary\n\n \tCloses #45'), []);
  assert.deepEqual(numbers('Summary\n\n  \tCloses #46'), []);
  assert.deepEqual(numbers('- item\n\n\tCloses #47'), [47]); // tab to column 4 = item content column 2 + 2
  // only an open paragraph stops indented code: after a comment block or a fence, it is code
  assert.deepEqual(numbers('<!-- x -->\n    Closes #48'), []);
  assert.deepEqual(numbers('```\nx\n```\n    Closes #49'), []);
  assert.deepEqual(numbers('# Heading\n    Closes #50'), []);
  // nested lists: when the inner list ends, the outer item's column applies again
  assert.deepEqual(numbers('- outer\n  - inner\n\n  text\n\n    Closes #51'), [51]);
  assert.deepEqual(numbers('- outer\n  - inner\n\n        Closes #52'), []); // inner content column 4 + 4
  // a fence interrupting a list item's paragraph at column 0 ends the list, so its lines are measured from column 0
  assert.deepEqual(numbers('- item\n```\nCloses #53\n```\nCloses #54'), [54]);
  // a tab after the marker reaches the next tab stop: content column 4, so six spaces continue the item
  assert.deepEqual(numbers('-\titem\n\n      Closes #55'), [55]);
  // more than 4 columns after the marker: one is padding, the rest makes the item's first line code
  assert.deepEqual(numbers('-     Closes #56'), []);
  assert.deepEqual(numbers('-    Closes #57'), [57]); // exactly 4: ordinary padding
  // an ordered marker other than 1 cannot interrupt a paragraph, so no list opens and the indented line is code
  assert.deepEqual(numbers('text\n2. item\n\n    Closes #58'), []);
  assert.deepEqual(numbers('text\n1. item\n\n    Closes #59'), [59]);
  assert.deepEqual(numbers('2. item\n\n    Closes #60'), [60]); // no paragraph open: 2. starts a list
  // a tab after `>` gives one column of padding; the rest of it is not enough to make code
  assert.deepEqual(numbers('>\tCloses #61'), [61]);
  assert.deepEqual(numbers('> \tCloses #62'), [62]); // space padding, then a tab to column 4: 2 columns of indent
  // an invalid backtick fence (backtick in the info string) is paragraph text: it continues the item, the list stays open
  assert.deepEqual(numbers('- item\n```bad`\n\n    Closes #63'), [63]);
  // a quote inside a list item: after the quote, the item's content column applies again
  assert.deepEqual(numbers('- item\n  > quote\n\n    Closes #64'), [64]);
  assert.deepEqual(numbers('- item\n> quote\n\n    Closes #65'), []); // quote at column 0 ends the list: top-level code
  // the same one level down: a list inside a quote survives a nested quote
  assert.deepEqual(numbers('> - item\n>   > nested\n>\n>     Closes #66'), [66]);
  // a lazy continuation (no `>`) keeps the quote and its list open
  assert.deepEqual(numbers('> - item\n>   text\nlazy continuation\n>\n>     Closes #67'), [67]);
  // marker padding may mix spaces and tabs: "- \t" reaches column 4
  assert.deepEqual(numbers('- \titem\n\n      Closes #69'), [69]);
});

test('all GitHub closing keywords, the colon form and the full URL form are recognised, case-insensitively', () => {
  assert.deepEqual(numbers('closes #1 Fixes #2 RESOLVED #3 close #5 resolves #6 Closes: #9 CLOSES: #10'), [1, 2, 3, 5, 6, 9, 10]);
  assert.deepEqual(numbers('Closes https://github.com/o/r/issues/77', 'o/r'), [77]);
  assert.deepEqual(numbers('Closes o/r#78', 'O/R'), [78]);
  assert.deepEqual(numbers('see #7 and refs #8 closes#9 Closes:#10'), []);
});

test('a cross-repository close is a second issue: rejected alone and alongside a local one', () => {
  const only = lint({ headRef: 'fix/4-x', body: 'Closes other/repo#4', repo: 'o/r' });
  assert.deepEqual(only.linked, []);
  assert.deepEqual(only.cross, ['other/repo#4']);
  assert.equal(only.problems.length, 2); // no local issue + a cross-repo close
  assert.match(only.problems[1], /closes other\/repo#4 in another repository/);
  const both = lint({ headRef: 'fix/12-x', body: 'Closes #12, closes https://github.com/other/repo/issues/4', repo: 'o/r' });
  assert.deepEqual(both.problems.length, 1);
  assert.match(both.problems[0], /another repository/);
  assert.deepEqual(lint({ headRef: 'fix/12-x', body: 'Closes #12, refs other/repo#4', repo: 'o/r' }).problems, []);
});

test('a Refs-only body is told to split the work into a sub-issue', () => {
  const r = lint({ headRef: 'feat/3-x', body: 'Refs #3' });
  assert.match(r.problems[0], /sub-issue it can close/);
});

test('exactly one local issue: a second Closes fails (one issue per PR), a mismatched one fails', () => {
  const two = lint({ headRef: 'feat/10-x', body: 'Closes #10\nCloses #11' });
  assert.equal(two.problems.length, 1);
  assert.match(two.problems[0], /one issue per PR/);
  const r = lint({ headRef: 'feat/10-x', body: 'Closes #11' });
  assert.equal(r.problems.length, 1);
  assert.match(r.problems[0], /branch names issue #10 but the body closes #11/);
  assert.deepEqual(lint({ headRef: 'feat/10-x', body: 'Closes #10\nCloses #10' }).problems, []); // same issue twice is one issue
});

test('branch grammar: every CONTRIBUTING type, lowercase slug with dots/underscores; rejects others', () => {
  for (const t of ['feat', 'fix', 'docs', 'chore', 'refactor', 'ci', 'test', 'perf']) {
    assert.deepEqual(lint({ headRef: `${t}/7-a.b_c-1`, body: 'Closes #7' }).problems, []);
  }
  for (const bad of ['Feat/7-x', 'feature/7-x', 'fix/7', 'fix/7-', 'fix/x-7', 'fix-7-x', 'main', 'hotfix/7-x']) {
    assert.equal(lint({ headRef: bad, body: 'Closes #7' }).problems.length, 1, bad);
  }
});

test('bot PRs are exempt by author or by the release-please label — never by branch name', () => {
  assert.equal(lint({ headRef: 'release-please--branches--main', body: ':robot:', author: 'github-actions[bot]' }).exempt, true);
  assert.equal(lint({ headRef: 'dependabot/github_actions/actions-f3c1f23acc', body: '', author: 'dependabot[bot]' }).exempt, true);
  // release-please run with a PAT: human author, but the label it applies is proof enough
  assert.equal(lint({ headRef: 'release-please--branches--main', body: ':robot:', author: 'someone', labels: ['autorelease: pending'] }).exempt, true);
  // a fork author borrowing the bot branch name gets the full lint
  const spoof = lint({ headRef: 'release-please--branches--main', body: 'hi', author: 'someone', labels: [] });
  assert.equal(spoof.exempt, false);
  assert.equal(spoof.problems.length, 2);
  assert.equal(lint({ headRef: 'dependabot/x', body: '', author: 'someone' }).exempt, false);
});

test('run: fails with every problem listed, verifies the issue exists and is not a PR, passes with an info line, skips non-PR events', async () => {
  const out = [];
  const core = { info: (m) => out.push(['info', m]), setFailed: (m) => out.push(['failed', m]) };
  await run({ context: { payload: { pull_request: { head: { ref: 'chore/-x' }, body: 'Closes #' } } }, core });
  assert.equal(out.length, 1);
  assert.equal(out[0][0], 'failed');
  assert.match(out[0][1], /^PR lint failed:\n- branch .*\n- body links no issue/s);
  out.length = 0;
  const gh = (issue) => ({ rest: { issues: { get: async () => { if (issue === 404 || issue === 403 || issue === 410) { const e = new Error({ 404: 'Not Found', 403: 'Resource not accessible by integration', 410: 'This issue was deleted' }[issue]); e.status = issue; throw e; } if (issue === 'boom') throw new Error('boom'); return { data: issue }; } } } });
  const ctx = (ref, body) => ({ repo: { owner: 'o', repo: 'r' }, payload: { pull_request: { head: { ref }, body } } });
  await run({ github: gh({ number: 42, state: 'open' }), context: ctx('fix/42-x', GOOD_BODY + 'Closes o/r#42\n'), core });
  assert.deepEqual(out, [['info', 'PR lint passed: branch issue #42, body closes #42']]); // o/r#42 is this repo → local
  out.length = 0;
  await run({ github: gh(404), context: ctx('fix/999999-x', 'Closes #999999'), core });
  assert.match(out[0][1], /issue #999999 does not exist/);
  out.length = 0;
  await run({ github: gh(410), context: ctx('fix/22-x', 'Closes #22'), core });
  assert.equal(out[0][0], 'failed');
  assert.match(out[0][1], /issue #22 was deleted/);
  out.length = 0;
  // a closed PR is not linted at all — no API call, no failure
  let called = false;
  const spy = { rest: { issues: { get: async () => { called = true; return { data: {} }; } } } };
  await run({ github: spy, context: { repo: { owner: 'o', repo: 'r' }, payload: { pull_request: { number: 23, state: 'closed', head: { ref: 'nope' }, body: 'Closes #22' } } }, core });
  assert.deepEqual(out, [['info', 'PR lint skipped: pull request #23 is closed']]);
  assert.equal(called, false);
  out.length = 0;
  await run({ github: gh({ number: 42, pull_request: { url: 'x' } }), context: ctx('fix/42-x', GOOD_BODY), core });
  assert.match(out[0][1], /#42 is a pull request, not an issue/);
  out.length = 0;
  await run({ github: gh({ number: 42, state: 'closed' }), context: ctx('fix/42-x', GOOD_BODY), core });
  assert.match(out[0][1], /issue #42 is already closed/);
  out.length = 0;
  await assert.rejects(() => run({ github: gh('boom'), context: ctx('fix/42-x', GOOD_BODY), core }), /could not verify issue #42/);
  // a private repository under `contents: read` alone: the token, not the PR, is at fault — say which scopes
  await assert.rejects(() => run({ github: gh(403), context: ctx('fix/42-x', GOOD_BODY), core }), /Resource not accessible by integration — .*`issues: read` and `pull-requests: read`/);
  out.length = 0;
  await run({ context: { payload: {} }, core });
  assert.equal(out[0][0], 'info');
  out.length = 0;
  await run({ context: { payload: { pull_request: { head: { ref: 'release-please--branches--main' }, body: '', user: { login: 'github-actions[bot]' }, labels: [{ name: 'autorelease: pending' }] } } }, core });
  assert.deepEqual(out, [['info', 'PR lint skipped: opened by github-actions[bot]']]);
});
