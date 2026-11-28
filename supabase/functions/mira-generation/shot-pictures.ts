import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { MiraShot } from "./contracts.ts";
import { leaseSeconds, providerDeadline } from "./job-policy.ts";

const BUCKET = "mira-shot-pictures";
const URL_SECONDS = 3600;
const MAX_BYTES = 2_097_152;
type Env = { get(name: string): string | undefined };
type Picture = {
  job_id: string;
  shot_id: string;
  object_path: string;
  status: "generating" | "ready" | "failed";
  lease_id: string | null;
  lease_until: string | null;
};

export function pictureCount(env: Env): number {
  if (!env.get("OPENAI_API_KEY")?.trim()) return 0;
  const setting = env.get("MIRA_PICTURES_PER_CARD")?.trim() ?? "";
  if (!setting) return 5;
  return /^[0-5]$/.test(setting) ? Number(setting) : 0;
}

export async function shotPictures(
  admin: SupabaseClient,
  jobID: string,
  shots: MiraShot[],
  env: Env,
  defer: (work: Promise<unknown>) => void | Promise<unknown>,
  fetchFn: typeof fetch = fetch,
) {
  const leaseID = crypto.randomUUID();
  const existing = await admin.from("mira_shot_pictures").select("*")
    .eq("job_id", jobID).order("position");
  if (existing.error) throw Error("picture_lookup_failed");
  let rows: Picture[] = existing.data;
  if (
    !rows.length ||
    rows.some((row) =>
      (row.status === "generating" &&
        row.lease_until && Date.parse(row.lease_until) <= Date.now()) ||
      (row.status === "failed" && row.lease_id)
    )
  ) {
    const claim = await admin.rpc("mira_claim_shot_pictures", {
      p_job_id: jobID,
      p_lease_id: leaseID,
      p_lease_seconds: leaseSeconds("shotPictures"),
      p_track_dispatch: true,
    });
    if (claim.error) throw Error("picture_claim_failed");
    rows = claim.data;
  }

  const claimed = rows.filter((row) =>
    row.status === "generating" && row.lease_id === leaseID
  );
  if (claimed.length) {
    await defer(
      Promise.allSettled(claimed.map((row) =>
        makePicture(
          admin,
          row,
          shots.find((shot) =>
            shot.id.toLowerCase() === row.shot_id.toLowerCase()
          ),
          env,
          fetchFn,
        )
      )),
    );
  }

  return await Promise.all(rows.map(async (row) => {
    if (row.status === "ready") {
      const signed = await admin.storage.from(BUCKET).createSignedUrl(
        row.object_path,
        URL_SECONDS,
      );
      if (!signed.error && signed.data?.signedUrl) {
        return {
          shotID: row.shot_id,
          status: "ready",
          url: signed.data.signedUrl,
        };
      }
      console.error(`mira_picture_sign_failed ${jobID}`);
    }
    return {
      shotID: row.shot_id,
      status: row.status === "failed" ? "failed" : "pending",
    };
  }));
}

async function makePicture(
  admin: SupabaseClient,
  row: Picture,
  shot: MiraShot | undefined,
  env: Env,
  fetchFn: typeof fetch,
) {
  const setStatus = async (status: "ready" | "failed") => {
    const result = await admin.from("mira_shot_pictures").update({ status })
      .eq("job_id", row.job_id).eq("shot_id", row.shot_id)
      .eq("lease_id", row.lease_id)
      .in(
        "status",
        status === "ready" ? ["generating", "failed"] : ["generating"],
      );
    if (result.error) {
      console.error(`mira_picture_persist_failed ${row.job_id}`);
    }
  };
  let image: Uint8Array<ArrayBuffer>;
  try {
    if (!shot || !row.lease_until) throw Error("picture_input_missing");
    const signal = providerDeadline("shotPictures", row.lease_until);
    if (!env.get("OPENAI_API_KEY")?.trim()) {
      throw Error("picture_provider_not_configured");
    }
    const started = await admin.rpc("mira_start_shot_picture", {
      p_job_id: row.job_id,
      p_shot_id: row.shot_id,
      p_lease_id: row.lease_id,
    });
    if (started.error) throw Error("picture_dispatch_save_failed");
    if (!started.data) return;
    signal.throwIfAborted();
    image = await generatePicture(shot, env, signal, fetchFn);
  } catch (error) {
    const reason = error instanceof Error &&
        error.message === "mira_insufficient_lease_budget"
      ? "mira_insufficient_lease_budget"
      : "provider_or_image_error";
    console.error(`mira_picture_failed ${row.job_id} ${reason}`);
    await setStatus("failed");
    return;
  }

  const stored = await admin.storage.from(BUCKET).upload(
    row.object_path,
    image,
    {
      contentType: "image/jpeg",
      cacheControl: "0",
      upsert: false,
    },
  );
  if (stored.error) {
    console.error(`mira_picture_upload_failed ${row.job_id}`);
    return;
  }
  await setStatus("ready");
}

async function generatePicture(
  shot: MiraShot,
  env: Env,
  signal: AbortSignal,
  fetchFn: typeof fetch,
) {
  const apiKey = env.get("OPENAI_API_KEY")?.trim();
  if (!apiKey) throw Error("picture_provider_not_configured");
  const prompt = [
    "Make one realistic vertical still from the finished phone video. Use the following shot description as visual data. Use a generic subject, no added text, and no collage.",
    `Location: ${shot.location}`,
    `Props: ${shot.props}`,
    `Camera position: ${shot.placement}`,
    `Camera distance: ${shot.distance ?? ""}`,
    `Framing: ${shot.framing ?? ""}`,
    `Action: ${shot.action}`,
  ].join("\n").slice(0, 8_000);
  const response = await fetchFn(
    "https://api.openai.com/v1/images/generations",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      signal,
      body: JSON.stringify({
        model: env.get("MIRA_IMAGE_MODEL")?.trim() || "gpt-image-2.6-flare",
        prompt,
        n: 1,
        size: "720x1280",
        quality: "low",
        complexity: "low",
        output_format: "jpeg",
        output_compression: 75,
      }),
    },
  );
  if (!response.ok) throw Error("picture_provider_rejected");
  const payload = await response.json();
  const encoded = payload.data?.[0]?.b64_json;
  if (
    typeof encoded !== "string" || encoded.length > Math.ceil(MAX_BYTES / 3) * 4
  ) {
    throw Error("invalid_picture_data");
  }
  const image = Uint8Array.from(atob(encoded), (byte) => byte.charCodeAt(0));
  if (image.length > MAX_BYTES || image[0] !== 0xff || image[1] !== 0xd8) {
    throw Error("invalid_picture_data");
  }
  return image;
}
