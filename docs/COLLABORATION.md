# Working together in the shared org

Use reviewed source in GitHub to coordinate changes. Both teammates may use the same OrgFarm org, so a deployment must account for changes already made directly in that org.

## Agree on ownership

Record who is editing the UI, each Apex module and shared metadata in the pull request or team discussion. Before changing another person's component, coordinate the handoff. If the team adopts a replacement UI or backend, import that implementation and review its interfaces before modifying it. Preserve existing implementations in Git history.

## Make a change

Start with a clean working tree:

```sh
git switch main
git pull --ff-only
git switch -c feature/describe-your-change
```

Make focused changes and run `npm run check`. Commit the intended files, push the feature branch and open a pull request against `main`:

```sh
git add <CHANGED_PATHS>
git commit -m "Describe the resulting behavior"
git push -u origin feature/describe-your-change
gh pr create --base main
```

The teammate reviews the diff and confirms which UI and backend should be deployed. Resolve conflicts on the feature branch while preserving both people's intended behavior.

## Bring direct org edits into Git

First preserve local work on a branch. Retrieve the specific components into a new ignored directory, rather than directly replacing the working source. For example:

```sh
sf project retrieve start --target-org compliance-demo --metadata LightningComponentBundle:complianceFilingWorkspace --metadata ApexClass:GovController --metadata ApexClass:GovService --output-dir artifacts/org-review-20261028-01 --wait 1
```

Use a fresh output directory each time. Extend the metadata list for every changed component and dependency, including any replacement UI, Apex classes, objects, flows or permissions. The command may return a job ID if retrieval is still running; finish the retrieve before comparing files.

Compare the retrieved files with the corresponding source under `force-app/main/default`. Review differences with the person editing the org. Copy the agreed changes into a feature branch and submit a pull request. Retrieved XML may differ only in formatting or explicitly returned default values; inspect its meaning before treating it as a functional change.

Keep a note of retrieval time and component scope. A snapshot is a point-in-time observation: the org can change again while you are reviewing it. Recheck the affected components immediately before deployment.

## Deploy an agreed change

Choose one deployment owner for each deployment window. That person checks for fresh org changes, incorporates them, and deploys only the agreed components. For example, when the change is confined to the existing workspace and its two backend classes:

```sh
sf project deploy start --target-org compliance-demo --source-dir force-app/main/default/lwc/complianceFilingWorkspace --source-dir force-app/main/default/classes/GovController.cls --source-dir force-app/main/default/classes/GovService.cls --test-level RunSpecifiedTests --tests GovServiceTest --tests GovAiDraftTest --wait 1
```

Add every required changed field, permission set and other dependency to the deployment scope. The command above is an example, not a substitute for inspecting the actual diff. Avoid deploying the entire `force-app` directory when the teammate has unmerged changes in the same org.

Record the commit, target org alias, exact deployed components, deployment job ID and test results in the pull request. If the command times out while the deployment continues, check that job rather than starting a duplicate deployment. Smoke-test the affected screen after deployment.

## Files that remain local

Keep `.sf/`, `.sfdx/`, `.env` files, private keys, tokens, real customer evidence and deployment artifacts out of Git. Each teammate authenticates independently. The ignored `project-status.json` and `submission-brief.txt` remain local working notes rather than the team's shared deployment record.

`scripts/generate_metadata.py` is a scaffolding generator. Running it rewrites object, permission and workflow files. Do not run it as a normal build step or over another person's edited metadata without reviewing every resulting change.

## References

- [Salesforce retrieve command](https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference_project_retrieve_start.html)
- [GitHub pull requests](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests)
