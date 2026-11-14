import { defineRailway, project, service, volume } from "railway/iac";
// This repository manages only its own resources in the environment. Other
// repositories export their own partial name.
// See https://docs.railway.com/infrastructure-as-code#multi-repo-projects
export const partial = "indoorbility";
export default defineRailway(() => {
  const data = volume("indoorbility-volume", { sizeMB: 500, region: "iad" });
  const indoorbility = service("indoorbility", {
    build: { buildEnvironment: "V3", builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    healthcheck: "/ready",
    healthcheckTimeout: 120,
    replicas: { "iad": 1 },
    deploy: { sleepApplication: false, restartPolicyType: "ON_FAILURE", restartPolicyMaxRetries: 5 },
    volumeMounts: { "/data": data },
  });

  // Enable scheduled backups in the Railway dashboard; verify them independently.

  return project("mindful-perception", {
    variables: { managed: false },
    resources: [indoorbility, data],
  });
});
