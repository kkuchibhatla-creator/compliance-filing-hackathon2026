# Compliance Filing

Public team source repository for the Salesforce-native Compliance Filing prototype. Both the Lightning frontend and Apex backend deploy to the team's existing OrgFarm org. The browser renders the Lightning UI; Salesforce runs the Apex and stores records and files.

## Source layout

| Path | Purpose |
| --- | --- |
| `force-app/main/default/lwc/` | Lightning frontend components |
| `force-app/main/default/classes/` | Apex controllers, business logic, AI drafting and tests |
| `force-app/main/default/objects/` | Governance objects and fields |
| `force-app/main/default/approvalProcesses/` | Native human sign-off configuration |
| `force-app/main/default/permissionsets/` | Builder and Reviewer permissions |
| `force-app/main/default/staticresources/` | Versioned control library and other project resources |
| `scripts/` | Source checks, metadata scaffolding and synthetic demo helpers |
| `docs/COLLABORATION.md` | Branch, review and shared-org deployment workflow |

## Start locally

Install Git, Node.js 24, Python 3 and Salesforce CLI. Clone this repository, enter its directory, then run:

```sh
npm ci
npm run check
```

Authorize the team org using your own Salesforce user and the team's login URL:

```sh
sf org login web --instance-url <TEAM_ORG_LOGIN_URL> --alias compliance-demo
sf org open --target-org compliance-demo --path /lightning/n/Gov
```

The placeholders are intentional. Passwords, OAuth tokens, Salesforce CLI authentication state, customer evidence, internal event materials and local deployment artifacts are not stored in Git. Access to this repository does not grant Salesforce access; an administrator must provision the appropriate user, permissions and sharing separately.

## Work together

Read [the collaboration guide](docs/COLLABORATION.md) before editing or deploying. Start from the latest `main`, create a feature branch and submit a pull request. Coordinate ownership of any shared component with its current editor. Import direct org changes for review before deploying over those components.

GitHub stores source history; it does not automatically synchronize with OrgFarm. Source changes take effect only after an agreed Salesforce deployment. No automatic org deployment or Salesforce credentials are configured in GitHub.

## Validation and scope

The last verified build before repository setup deployed 85 components and passed 17 Apex tests across `GovServiceTest` and `GovAiDraftTest`. Local `npm run check` parses Apex, compiles the workspace LWC and validates metadata references; it does not execute Apex tests in Salesforce. See `docs/ORG_SYNC.md` for the initial org synchronization and its validation boundaries.

Evidence uploads accept file types allowed by the org, including PNG, JPG/JPEG, PDF, DOC/DOCX and TXT. Small UTF-8 text files have readable snapshots. Other files retain a pinned original version and metadata; OCR and document text extraction are not implemented. Human reviewers assess evidence adequacy and approve the assessed filing scope.

The risk template and selected commercial-bank regulatory controls are illustrative and require specialist validation. A completed governance filing does not deploy or activate an Agentforce agent.
