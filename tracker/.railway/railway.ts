import { defineRailway, project, service, volume } from "railway/iac";

export default defineRailway(() => {
  const miraBuildProgressVolume = volume("mira-build-progress-volume", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "us-west2", sizeMB: 5000 });
  const miraBuildProgress = service("mira-build-progress", {
    build: { buildEnvironment: "V3", builder: "DOCKERFILE", dockerfilePath: "/Dockerfile" },
    healthcheck: "/health",
    replicas: { "us-west2": 1 },
    volumeMounts: { "/data": miraBuildProgressVolume },
  });

  return project("mira-build-progress", {
    variables: { managed: false },
    resources: [miraBuildProgress, miraBuildProgressVolume],
  });
});
