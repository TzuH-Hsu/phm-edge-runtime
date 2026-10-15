// SPDX-License-Identifier: MIT
'use strict';
// pr-lint.js — the pull-request checks behind the `Lint the pull request`
// step in .github/workflows/ci.yml. Same shape as scripts/issue-labeler.js
// (ADR-0008): a pure lint() the tests exercise, and one run() the workflow
// calls through actions/github-script.
//
// What it enforces — the conventions AGENTS.md states and the PR template
// carries, which were being broken silently:
//   1. the head branch is `<type>/<issue#>-<slug>` or `<type>/<slug>`;
//   2. the body says how the PR relates to an issue, in one of two ways: it links issues (`Closes #N` and/or `Refs #N`), or it says
//      `No issue: <reason>` with a real reason;
//   3. it closes at most one issue, in this repository, still open (a closed
//      one cannot be closed by merging); other repositories get `Refs`;
//   4. a branch that names an issue is backed by `Closes` or `Refs` of it;
//   5. a `Refs` of this repository names an existing issue, not a pull request
//      (GitHub is asked about each number; other repositories are not checked).
// Bot PRs (release-please, Dependabot) have no issue and are exempt — by WHO
// opened them, never by branch name: on a public repository a fork author
// picks the head branch name, so `release-please--…` proves nothing.
//
// Which issues a PR closes is GitHub's answer, not ours: run() reads the
// pull request's `closingIssuesReferences` (GraphQL), restricted to the
// issues the BODY closes (`excludeUserLinked`) — closing keywords in prose,
// never inside code or comments, exactly as GitHub renders them — so the lint
// cannot disagree with GitHub about Markdown. Issues linked by hand in the
// sidebar are left out on purpose: changing that link fires no pull_request
// event, so a green check could go stale without anything re-running it. An
// earlier version parsed the body itself; nine review rounds of CommonMark
// corner cases later, it still could not match GitHub (#104).
//
// `Refs` and `No issue:` have no GitHub counterpart, so bodyLines() reads
// them, and deliberately reads very little: a line counts only if it STARTS
// with the keyword (at most three spaces of indent, no list marker or quote),
// outside fenced code blocks, raw <pre> blocks and HTML comments. Inline code cannot start such
// a line, and four spaces of indent is an indented code block. Anything
// fancier is out of scope by design; the edge cases are pinned in
// pr-lint.test.js.
//
// The field is updated a few seconds after a body edit (measured: 1-9 s). So
// run() first waits until the PR's last update is at least 15 s old — two
// equal reads inside the lag window could both be stale — then reads until two
// reads 5 s apart agree, up to a bound. "Last update" is the later of the
// event's `updated_at` and the live `updatedAt` from the same query: a manual
// re-run replays the old event, but the lint reads live state, so "Re-run
// jobs" re-checks the current body and must wait for its latest edit too.

// The Conventional Commit types AGENTS.md lists (its "Branch" step is the one
// home for this list; pr-lint.test.js asserts the two are equal). The branch
// type mirrors them.
const TYPES = ['feat', 'fix', 'docs', 'chore', 'refactor', 'ci', 'test', 'perf'];
// `<type>/<issue#>-<slug>` or `<type>/<slug>`. A slug without an issue number
// starts with a letter, so `fix/7` and `fix/-x` (an empty issue slot) fail.
const BRANCH_RE = new RegExp(`^(${TYPES.join('|')})/(?:(\\d+)-[a-z0-9][a-z0-9._-]*|[a-z][a-z0-9._-]*)$`);
// Exempt when the PR was opened by one of these accounts (Dependabot;
// release-please run with the default GITHUB_TOKEN), or carries the label
// release-please always applies (covers release-please run with a PAT, where
// the author is a human account). A fork author can choose neither.
const EXEMPT_AUTHORS = ['dependabot[bot]', 'github-actions[bot]'];
const EXEMPT_LABELS = ['autorelease: pending'];

const CLOSING_QUERY = `query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      updatedAt
      body
      closingIssuesReferences(first: 20, excludeUserLinked: true) {
        nodes { number state repository { nameWithOwner } }
      }
    }
  }
}`;

function describe(ref) {
  return ref.repo ? `${ref.repo}#${ref.number}` : `#${ref.number}`;
}

function isExempt({ author, labels }) {
  if (author && EXEMPT_AUTHORS.includes(author)) return `opened by ${author}`;
  const hit = (labels || []).find((l) => EXEMPT_LABELS.includes(l));
  return hit ? `carries the '${hit}' label` : null;
}

// The lines of a PR body that may carry `Refs` or `No issue:`: fenced code
// blocks (``` or ~~~) skipped, HTML comments and raw <pre> blocks removed
// outside them. All are read in source order: inside a fence `<!--` and
// `<pre>` are code, so they can neither hide nor fake a closing fence. Pure;
// the rules are the file header's.
function bodyLines(body) {
  const out = [];
  let fence = null;
  let hidden = null;
  for (const raw of String(body || '').replace(/\r\n?/g, '\n').split('\n')) {
    if (fence) {
      // A closing fence is the marker and nothing else but spaces.
      const close = raw.match(/^ {0,3}(`{3,}|~{3,})[ \t]*$/);
      if (close && close[1][0] === fence[0] && close[1].length >= fence.length) fence = null;
      continue;
    }
    let line = '';
    let rest = raw;
    // `hidden` is the end marker of the HTML comment or <pre> block we are in.
    while (rest.length > 0) {
      if (hidden) {
        const end = rest.search(hidden);
        if (end < 0) break;
        rest = rest.slice(end).replace(hidden, '');
        hidden = null;
      } else {
        const start = rest.search(/<!--|<pre\b/i);
        if (start < 0) { line += rest; break; }
        line += rest.slice(0, start);
        hidden = rest.startsWith('<!--', start) ? /-->/ : /<\/pre>/i;
        rest = rest.slice(start + 4); // past `<!--` or `<pre`
      }
    }
    const m = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (m) { fence = m[1]; hidden = null; continue; }
    out.push(line);
  }
  return out;
}

// Issue numbers start at 1, so #0 is not a reference.
const REF_TOKEN = /^(?:#([1-9]\d*)|([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)#([1-9]\d*)|https:\/\/github\.com\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\/issues\/([1-9]\d*))$/;
// Words that are not a reason (compared case-insensitively, punctuation-stripped).
const PLACEHOLDER_REASONS = ['', 'na', 'n/a', 'none', 'no', 'tbd', 'todo', 'reason', '<reason>', '原因', '<原因>', '無', '没有', '沒有', '略'];

// Pure. { refs: [{ repo|null, number }], noIssue: [reason], badRefs: [line] }
// from a PR body. `Refs` takes #N, owner/repo#N or an issue URL, several per
// line, separated by commas or spaces; a `Refs` line with anything else is
// reported, not silently ignored.
function parseBody(body) {
  const refs = [];
  const noIssue = [];
  const badRefs = [];
  for (const line of bodyLines(body)) {
    const ni = line.match(/^ {0,3}no issue\s*[:：]\s*(.*)$/i);
    if (ni) { noIssue.push(ni[1].trim()); continue; }
    const r = line.match(/^ {0,3}refs\s*:?\s+(.*)$/i);
    if (!r) continue;
    const tokens = r[1].trim().split(/[\s,，、]+/).filter(Boolean);
    const parsed = tokens.map((t) => t.match(REF_TOKEN));
    if (tokens.length === 0 || parsed.some((m) => !m)) { badRefs.push(line.trim()); continue; }
    for (const m of parsed) {
      if (m[1]) refs.push({ repo: null, number: Number(m[1]) });
      else if (m[3]) refs.push({ repo: m[2], number: Number(m[3]) });
      else refs.push({ repo: m[4], number: Number(m[5]) });
    }
  }
  return { refs, noIssue, badRefs };
}

function isPlaceholderReason(reason) {
  const r = String(reason || '').trim().toLowerCase().replace(/[.。…!！]+$/, '');
  return PLACEHOLDER_REASONS.includes(r) || !/[a-z一-鿿]/i.test(r);
}

// Pure. `refs` is what GitHub says the PR closes: [{ repo: 'owner/name',
// number, state: 'OPEN' | 'CLOSED' }]. `body` is the PR body, read for `Refs`
// and `No issue:`. `repo` is this repository's 'owner/name'; a reference to
// it is local. `author` is the PR author's login and `labels` the PR's label
// names.
// `refKinds`, when given, maps each local `Refs` number to what GitHub says it
// is: 'Issue', 'PullRequest', or null when nothing has that number.
// Returns { exempt, why, problems: [string], branchIssue, linked: [number],
// cross: [string], mentioned: [string], noIssue: string|null }.
function lint({ headRef, refs, body, repo, author, labels, refKinds }) {
  const ref = String(headRef || '');
  const all = refs || [];
  const here = String(repo || '').toLowerCase();
  const isLocal = (r) => !r.repo || String(r.repo).toLowerCase() === here;
  const local = all.filter(isLocal);
  const linked = [...new Set(local.map((r) => r.number))];
  const cross = all.filter((r) => !isLocal(r)).map(describe);
  const parsed = parseBody(body);
  const mentioned = [...new Set(parsed.refs.map((r) => (isLocal(r) ? `#${r.number}` : describe(r))))];
  const localRefs = new Set(parsed.refs.filter(isLocal).map((r) => r.number));
  const noIssue = parsed.noIssue.length > 0 ? parsed.noIssue[0] : null;
  const base = { branchIssue: null, linked, cross, mentioned, noIssue };
  const why = isExempt({ author, labels });
  if (why) {
    return { exempt: true, why, problems: [], ...base };
  }
  const problems = [];
  const branch = ref.match(BRANCH_RE);
  const branchIssue = branch && branch[2] ? Number(branch[2]) : null;
  if (!branch) {
    problems.push(
      `branch '${ref}' is not <type>/<issue#>-<slug> or <type>/<slug> (types: ${TYPES.join(', ')}; ` +
        'e.g. fix/42-label-sync or docs/readme-quick-start) — the usual slip is an empty issue number, which reads as "<type>/-<slug>"',
    );
  }
  for (const line of parsed.badRefs) {
    problems.push(
      `cannot read the line '${line}' — a Refs line lists only issues: #N, owner/repo#N or an issue URL, separated by commas or spaces`,
    );
  }
  const linksIssue = linked.length > 0 || cross.length > 0 || parsed.refs.length > 0;
  if (localRefs.size > MAX_LOCAL_REFS) {
    problems.push(
      `Refs lists ${localRefs.size} issues of this repository — at most ${MAX_LOCAL_REFS}; refer to a parent issue instead of every sub-issue`,
    );
  }
  for (const n of localRefs.size > MAX_LOCAL_REFS ? [] : localRefs) {
    const kind = refKinds ? refKinds[n] : 'Issue';
    if (kind === 'PullRequest') {
      problems.push(`Refs #${n} is a pull request, not an issue — refer to the issue it works on, or write "No issue: <reason>"`);
    } else if (kind !== 'Issue') {
      problems.push(`Refs #${n} names no issue in this repository (a typo, or a deleted issue) — fix the number, or write "No issue: <reason>"`);
    }
  }
  if (!linksIssue && noIssue === null) {
    problems.push(
      'the PR body does not say how this PR relates to an issue — put these on lines of their own, outside code and HTML ' +
        'comments: "Closes #N" (merging finishes issue N in this repository) and/or "Refs #N" (it advances issue N, here ' +
        'or in another repository, without closing it; several allowed), or else "No issue: <reason>" alone. An issue linked only in ' +
        'the sidebar does not count (changing that link re-runs no check) — skills/pr-authoring rule 5',
    );
  }
  if (noIssue !== null && linksIssue) {
    problems.push(
      'the PR body has both "No issue:" and an issue link (Closes or Refs) — keep the issue link, or keep "No issue: <reason>", not both',
    );
  }
  if (noIssue !== null && isPlaceholderReason(noIssue)) {
    problems.push(
      `"No issue:" needs a real reason, got '${noIssue}' — say why no issue exists, e.g. "No issue: fix a typo in README"`,
    );
  }
  if (cross.length > 0) {
    problems.push(
      `this PR closes ${cross.join(', ')} in another repository — a PR here can only close issues here; ` +
        'write "Refs <owner>/<repo>#N" for the other one',
    );
  }
  if (linked.length > 1) {
    problems.push(
      `this PR closes #${linked.join(', #')} — close one issue per PR (skills/pr-authoring rule 5): keep the one this PR ` +
        'finishes, write "Refs #N" for the others, and close a genuine duplicate by hand after merge',
    );
  } else if (linked.length === 1) {
    const closed = local.find((r) => r.number === linked[0] && String(r.state).toUpperCase() === 'CLOSED');
    if (closed) {
      problems.push(
        `issue #${linked[0]} is already closed, so merging cannot close it — reopen it, or open a follow-up issue and link that`,
      );
    }
  }
  if (branchIssue !== null && !linked.includes(branchIssue) && !localRefs.has(branchIssue)) {
    problems.push(
      `branch names issue #${branchIssue} but the PR body neither closes nor refs it — add "Closes #${branchIssue}" or ` +
        `"Refs #${branchIssue}", or rename the branch to <type>/<slug>`,
    );
  }
  return { exempt: false, why: null, problems, ...base, branchIssue };
}

function passLine(result) {
  const parts = [];
  if (result.linked.length > 0) parts.push(`closes #${result.linked.join(', #')}`);
  if (result.mentioned.length > 0) parts.push(`refs ${result.mentioned.join(', ')}`);
  if (parts.length === 0) parts.push(`no issue (${result.noIssue})`);
  return `PR lint passed: ${parts.join('; ')}`;
}

// Each local `Refs` number costs one GraphQL call; a body listing more than
// this is refused before any call, so a generated list cannot drain the
// token's hourly GraphQL budget that other workflows share.
const MAX_LOCAL_REFS = 20;

const REF_KIND_QUERY = `query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issueOrPullRequest(number: $number) { __typename }
  }
}`;

// What each local `Refs` number is: { [number]: 'Issue' | 'PullRequest' | null }.
// A number nothing has comes back as a NOT_FOUND error; any other failure
// fails the job, as for the closing read.
async function refKindsRead(github, owner, repo, numbers) {
  const kinds = {};
  for (const number of numbers) {
    try {
      const data = await github.graphql(REF_KIND_QUERY, { owner, repo, number });
      const node = data && data.repository && data.repository.issueOrPullRequest;
      kinds[number] = node ? node.__typename : null;
    } catch (err) {
      const errors = (err && err.errors) || [];
      if (errors.length > 0 && errors.every((e) => e.type === 'NOT_FOUND')) {
        kinds[number] = null;
        continue;
      }
      throw new Error(`could not read what #${number} in Refs is: ${err && err.message ? err.message : err}`);
    }
  }
  return kinds;
}

// One GraphQL read of the issues GitHub will close, and when the PR was last
// updated: { refs, updatedAt }. A refused read is the job's token, not the
// PR: say which scopes it needs. Anything else is a failure too — a check
// that cannot check must not pass.
async function closingRead(github, owner, repo, number) {
  let data;
  try {
    data = await github.graphql(CLOSING_QUERY, { owner, repo, number });
  } catch (err) {
    const forbidden = (err && err.status === 403) || ((err && err.errors) || []).some((e) => e.type === 'FORBIDDEN');
    if (forbidden) {
      throw new Error(`could not read which issues PR #${number} closes: ${err.message} — the workflow's GITHUB_TOKEN ` +
        "cannot read them; on a private repository the job needs `issues: read` and `pull-requests: read` on the ci job's permissions block");
    }
    throw new Error(`could not read which issues PR #${number} closes: ${err && err.message ? err.message : err}`);
  }
  const pr = data && data.repository && data.repository.pullRequest;
  if (!pr) throw new Error(`could not read which issues PR #${number} closes: pull request not found`);
  return {
    updatedAt: pr.updatedAt,
    body: pr.body,
    refs: pr.closingIssuesReferences.nodes.map((n) => ({
      repo: n.repository.nameWithOwner,
      number: n.number,
      state: n.state,
    })),
  };
}
const closingRefs = async (...args) => (await closingRead(...args)).refs;

const sameRefs = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const byKey = (refs) => [...refs].sort((x, y) => `${x.repo}#${x.number}`.localeCompare(`${y.repo}#${y.number}`));

// Read until two consecutive reads agree (the field lags a body edit by a
// few seconds), at most `reads` times; the last read wins if they never do.
async function settledRefs(github, owner, repo, number, { reads = 5, pauseMs = 5000, sleep } = {}) {
  const wait = sleep || ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  let prev = byKey(await closingRefs(github, owner, repo, number));
  for (let i = 1; i < reads; i++) {
    await wait(pauseMs);
    const next = byKey(await closingRefs(github, owner, repo, number));
    if (sameRefs(prev, next)) return next;
    prev = next;
  }
  return prev;
}

const LAG_MS = 15000; // longest measured lag was 9 s

// Entry point for actions/github-script. `sleep`, `pauseMs` and `now` are for tests.
async function run({ github, context, core, sleep, pauseMs, now = Date.now }) {
  const pr = context.payload.pull_request;
  if (!pr) {
    core.info('not a pull_request event — nothing to lint');
    return { exempt: true, problems: [] };
  }
  // A closed PR (merged or not) has no merge left to gate; editing its body
  // still fires `edited`, and a red run there only adds noise.
  if (pr.state === 'closed') {
    core.info(`PR lint skipped: pull request #${pr.number} is closed`);
    return { exempt: true, why: 'closed', problems: [] };
  }
  const repo = `${context.repo.owner}/${context.repo.repo}`;
  const author = pr.user && pr.user.login;
  const labels = (pr.labels || []).map((l) => l.name);
  const why = isExempt({ author, labels });
  if (why) {
    core.info(`PR lint skipped: ${why}`);
    return { exempt: true, why, problems: [] };
  }
  // Let GitHub finish applying the latest edit before settling, so a settled
  // answer cannot be an old one: the later of the event's time and the live
  // one (a re-run replays the event, but the body may have changed since).
  const wait = sleep || ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  const live = await closingRead(github, context.repo.owner, context.repo.repo, pr.number);
  const updated = Math.max(Date.parse(pr.updated_at) || 0, Date.parse(live.updatedAt) || 0);
  const left = updated + LAG_MS - now();
  if (left > 0) await wait(left);
  const refs = await settledRefs(github, context.repo.owner, context.repo.repo, pr.number, { sleep, pauseMs });
  // The live body, not the event's: a manual re-run replays the old event.
  const body = typeof live.body === 'string' ? live.body : pr.body;
  const here = repo.toLowerCase();
  const localNumbers = [...new Set(parseBody(body).refs
    .filter((r) => r.repo === null || r.repo.toLowerCase() === here).map((r) => r.number))];
  // Over the cap, lint() reports it and nothing is looked up.
  const refKinds = localNumbers.length > MAX_LOCAL_REFS ? {} : await refKindsRead(github, context.repo.owner, context.repo.repo, localNumbers);
  const result = lint({ headRef: pr.head && pr.head.ref, refs, body, repo, author, labels, refKinds });
  if (result.problems.length > 0) {
    core.setFailed(`PR lint failed:\n- ${result.problems.join('\n- ')}`);
    return result;
  }
  core.info(passLine(result));
  return result;
}

module.exports = { run, lint, parseBody, bodyLines, isPlaceholderReason, passLine, closingRead, refKindsRead, closingRefs, settledRefs, isExempt, describe, TYPES, BRANCH_RE, EXEMPT_AUTHORS, EXEMPT_LABELS, CLOSING_QUERY, REF_KIND_QUERY, MAX_LOCAL_REFS };
