# Team development instructions

- This is a shared Salesforce project. Other people edit both the repository and the OrgFarm org. Preserve their changes and coordinate component ownership.
- Use a feature branch and a pull request for new work. Read `docs/COLLABORATION.md` before retrieving or deploying.
- Before deployment, retrieve the affected live components into a fresh directory under ignored `artifacts/`, compare them with local source, and incorporate current teammate changes. Never assume the local baseline still matches the org.
- Prefer a deployment limited to reviewed components and all required dependencies. Do not deploy the full project over unmerged org changes.
- Never commit passwords, tokens, Salesforce authentication state, private keys or real customer evidence. The owner explicitly requested public visibility. Keep internal event materials out of Git.
- Run `npm run check` for relevant source changes and execute appropriate Apex tests in an authorized org for backend changes. Local parsing is not Salesforce runtime validation.
- The metadata generator rewrites files. Do not rerun it over manually edited metadata without checking every diff.
- Maintain the human sign-off boundary. AI drafts and inspect/prepare actions cannot approve reviews or activate agents.
