Your task is to create a version of the deployment script intended specifically for execution by AI agents.

Break the task down into these steps:

## 1: Create agent specific deployment script

Identify the deployment script used to deploy new versions of this repository onto the target. If you are unsure which script is the current deployment script, ask the user for clarification.

After you've identified the deployment script, your task is to create an agent-specific variant of this, whose purpose is to deploy the codebase by executing a script that minimizes unnecessary verbosity.

- Unlike the main version of the deployment script in this repository, the agent-specific version, which should be named `agent_deploy.sh`, is intended for execution by AI agents. 

- Unlike the main deployment script, its objective is to minimize the number of console lines, reducing the verbosity to the minimum extent necessary for the agent to be able to provide the user with status updates regarding the deployment.

Once  you have created the agent specific deployment script, you should update CLAUDE.md (and AGENTS.md if it also exists) noting that:

- `agent-deploy.sh` should be used for deployments (and not deploy.sh which is reserved for human execution).
- Add a VS Code task for initaiting agent deploy