// SPDX-License-Identifier: MIT
'use strict';
// pr-lint.js — the pull-request checks behind the `Lint the pull request`
// step in .github/workflows/ci.yml. Same shape as scripts/issue-labeler.js
// (ADR-0008): a pure lint() the tests exercise, and one run() the workflow
// calls through actions/github-script.
//
// What it enforces — the conventions AGENTS.md states and the PR template
// carries, which were being broken silently:
//   1. the head branch is `<type>/<issue#>-<slug>`;
//   2. the PR closes exactly one issue, in this repository, and it is the
//      branch's issue;
//   3. that issue is still open (a closed one cannot be closed by merging).
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
const BRANCH_RE = new RegExp(`^(${TYPES.join('|')})/(\\d+)-[a-z0-9][a-z0-9._-]*$`);
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

// Pure. `refs` is what GitHub says the PR closes: [{ repo: 'owner/name',
// number, state: 'OPEN' | 'CLOSED' }]. `repo` is this repository's
// 'owner/name'; a reference to it is local. `author` is the PR author's login
// and `labels` the PR's label names.
// Returns { exempt, why, problems: [string], branchIssue, linked: [number], cross: [string] }.
function lint({ headRef, refs, repo, author, labels }) {
  const ref = String(headRef || '');
  const all = refs || [];
  const here = String(repo || '').toLowerCase();
  const isLocal = (r) => !r.repo || String(r.repo).toLowerCase() === here;
  const local = all.filter(isLocal);
  const linked = [...new Set(local.map((r) => r.number))];
  const cross = all.filter((r) => !isLocal(r)).map(describe);
  const why = isExempt({ author, labels });
  if (why) {
    return { exempt: true, why, problems: [], branchIssue: null, linked, cross };
  }
  const problems = [];
  const branch = ref.match(BRANCH_RE);
  const branchIssue = branch ? Number(branch[2]) : null;
  if (!branch) {
    problems.push(
      `branch '${ref}' is not <type>/<issue#>-<slug> (types: ${TYPES.join(', ')}; e.g. fix/42-label-sync) — ` +
        'the usual slip is an empty issue number, which reads as "<type>/-<slug>"',
    );
  }
  if (linked.length === 0) {
    problems.push(
      'this PR closes no issue in this repository — the PR template line is `Closes #<!-- issue number -->`; replace the ' +
        'comment with the number. Any GitHub closing keyword works (Closes / Fixes / Resolves, #N or a full issue URL) in ' +
        'prose — not in code or an HTML comment. An issue linked only in the sidebar does not count (changing that link ' +
        're-runs no check). A number that is a pull request, or an issue that was deleted, closes nothing. If this PR only ' +
        'advances an issue, give it a sub-issue it can close — ' +
        'skills/pr-authoring rule 5',
    );
  }
  if (cross.length > 0) {
    problems.push(
      `this PR closes ${cross.join(', ')} in another repository — one issue per PR, and it lives here (skills/pr-authoring rule 5); ` +
        'mention the other issue with "Refs" instead',
    );
  }
  if (linked.length > 1) {
    problems.push(
      `this PR closes #${linked.join(', #')} — one issue per PR (skills/pr-authoring rule 5): keep the one this branch is for, ` +
        'and close a genuine duplicate by hand after merge',
    );
  } else if (linked.length === 1) {
    if (branchIssue !== null && linked[0] !== branchIssue) {
      problems.push(`branch names issue #${branchIssue} but the PR closes #${linked[0]} — one of them is wrong`);
    }
    const closed = local.find((r) => r.number === linked[0] && String(r.state).toUpperCase() === 'CLOSED');
    if (closed) {
      problems.push(
        `issue #${linked[0]} is already closed, so merging cannot close it — reopen it, or open a follow-up issue and link that`,
      );
    }
  }
  return { exempt: false, why: null, problems, branchIssue, linked, cross };
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
  const result = lint({ headRef: pr.head && pr.head.ref, refs, repo, author, labels });
  if (result.problems.length > 0) {
    core.setFailed(`PR lint failed:\n- ${result.problems.join('\n- ')}`);
    return result;
  }
  core.info(`PR lint passed: branch issue #${result.branchIssue}, the PR closes #${result.linked[0]}`);
  return result;
}

module.exports = { run, lint, closingRead, closingRefs, settledRefs, isExempt, describe, TYPES, BRANCH_RE, EXEMPT_AUTHORS, EXEMPT_LABELS, CLOSING_QUERY };
