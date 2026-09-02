<!-- markdownlint-disable-next-line MD041 -->
## Summary

<!-- One-line description of changes -->

## Related issue

Closes #<!-- issue number -->

## Validation

Pick validation depth by blast radius. A level that applies but could not run becomes a `RISK:` line below. See AGENTS.md for the validation ladder.

- [ ] L0 static — `make lint`
- [ ] L1 unit — `make test`
- [ ] L2 integration — (if applicable)
- [ ] L3 e2e / preview — (if applicable)

## Risk / rollback

Declare skipped validation levels. Reference AGENTS.md for context.

```text
RISK: <level> not run — <reason>
Rollback: <how to undo this change if needed>
```

## Checklist

Before merging:

- [ ] Conventional Commit PR title (`<type>: <description>`)
- [ ] Linked issue using "Closes #N"
- [ ] No secrets, no `*.local.md` files committed
- [ ] Documentation updated where affected
