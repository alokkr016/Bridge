const REPO_OWNER = "alokkr016";
const REPO_NAME = "Bridge";
const BASE_URL = "https://bridge-updater.alokraj016.workers.dev";
const RELEASE_URL = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest`;
const SAFE_NAME = /^[A-Za-z0-9._-]+$/;

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders() });
    }
    try {
      if (url.pathname.startsWith("/download/")) {
        return await handleDownload(url.pathname.slice("/download/".length));
      }
      if (url.pathname === "/android") {
        return await handleLatestAndroid();
      }
      return await handleLatestMac();
    } catch (error) {
      return jsonError(502, `GitHub API error: ${error.message}`);
    }
  },
};

async function latestRelease() {
  const cache = caches.default;
  const key = new Request("https://bridge-updater.alokraj016.workers.dev/cache/latest-release");
  const hit = await cache.match(key);
  if (hit) return hit.json();

  const response = await fetch(RELEASE_URL, {
    headers: {
      Accept: "application/vnd.github+json",
      "User-Agent": "Bridge-Updater-Worker/1.1",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });
  if (!response.ok) throw new Error(String(response.status));
  const body = await response.text();
  await cache.put(
    key,
    new Response(body, {
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=300",
      },
    })
  );
  return JSON.parse(body);
}

async function handleLatestMac() {
  const release = await latestRelease();
  const dmg = (release.assets || []).find((asset) => asset.name.endsWith(".dmg"));
  if (!dmg || !SAFE_NAME.test(dmg.name)) return jsonError(404, "No DMG asset found in the latest release");
  return json({
    version: String(release.tag_name || "").replace(/^v/, ""),
    notes: release.body || "",
    pub_date: release.published_at,
    platforms: {
      "darwin-universal": { url: `${BASE_URL}/download/${dmg.name}` },
    },
  });
}

async function handleLatestAndroid() {
  const release = await latestRelease();
  const apk = (release.assets || []).find((asset) => asset.name.endsWith(".apk"));
  if (!apk || !SAFE_NAME.test(apk.name)) return jsonError(404, "No APK asset found in the latest release");
  const versionName = String(release.tag_name || "").replace(/^v/, "");
  const parts = versionName.split(".").map(Number);
  const versionCode = (parts[0] || 1) * 10000 + (parts[1] || 0) * 100 + (parts[2] || 0);
  return json({
    versionCode,
    versionName,
    apkUrl: `${BASE_URL}/download/${apk.name}`,
    notes: release.body || "",
  });
}

async function handleDownload(filename) {
  if (!SAFE_NAME.test(filename)) return jsonError(404, "Asset not found");
  const release = await latestRelease();
  const asset = (release.assets || []).find((item) => item.name === filename);
  if (!asset?.browser_download_url) return jsonError(404, `Asset not found: ${filename}`);
  const file = await fetch(asset.browser_download_url, {
    headers: { "User-Agent": "Bridge-Updater-Worker/1.1" },
  });
  if (!file.ok) return jsonError(502, `Failed to stream asset: ${file.status}`);
  return new Response(file.body, {
    status: 200,
    headers: {
      "Content-Type": "application/octet-stream",
      "Content-Disposition": `attachment; filename="${filename}"`,
      "Cache-Control": "no-cache",
    },
  });
}

function json(body) {
  return new Response(JSON.stringify(body, null, 2), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=300",
      ...corsHeaders(),
    },
  });
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function jsonError(status, error) {
  return new Response(JSON.stringify({ error }, null, 2), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
  });
}
