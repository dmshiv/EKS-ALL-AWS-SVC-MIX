// Build step: copy src/ to dist/ and stamp the immutable image version into the page, so "which build is running?" is visible
// in the browser and in screenshots during troubleshooting. No bundler: the app is intentionally tiny.
const fs = require("fs");
const path = require("path");

const version = process.env.APP_VERSION || "dev";
const src = path.join(__dirname, "src");
const dist = path.join(__dirname, "dist");

fs.rmSync(dist, { recursive: true, force: true });
fs.cpSync(src, dist, { recursive: true });

const indexPath = path.join(dist, "index.html");
fs.writeFileSync(indexPath, fs.readFileSync(indexPath, "utf8").replace("__VERSION__", version));
console.log(`built frontend version=${version}`);
