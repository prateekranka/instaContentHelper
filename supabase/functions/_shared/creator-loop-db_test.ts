const localURL = Deno.env.get("MCO_LOCAL_DATABASE_URL");

Deno.test({
  name: "local database creator loop transactions and immutable history",
  ignore: !localURL,
  async fn() {
    const parsed = new URL(localURL!);
    if (
      !["postgres:", "postgresql:"].includes(parsed.protocol) ||
      !["127.0.0.1", "localhost", "[::1]"].includes(parsed.hostname) ||
      parsed.search !== "" || parsed.hash !== ""
    ) {
      throw new Error("MCO_LOCAL_DATABASE_URL must target a local database");
    }
    const sql = await Deno.readTextFile(
      new URL("./creator-loop-db.sql", import.meta.url),
    );
    const command = new Deno.Command("psql", {
      clearEnv: true,
      env: {
        PATH: Deno.env.get("PATH") ?? "/opt/homebrew/bin:/usr/bin:/bin",
        PGCONNECT_TIMEOUT: "5",
        PGPASSFILE: "/dev/null",
        PGSERVICEFILE: "/dev/null",
      },
      args: [localURL!, "-X", "-v", "ON_ERROR_STOP=1", "-q"],
      stdin: "piped",
      stdout: "piped",
      stderr: "piped",
    });
    const child = command.spawn();
    const writer = child.stdin.getWriter();
    await writer.write(new TextEncoder().encode(sql));
    await writer.close();
    const result = await child.output();
    if (!result.success) {
      throw new Error(new TextDecoder().decode(result.stderr));
    }
  },
});
