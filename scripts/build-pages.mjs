import { cp, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repositoryRoot = fileURLToPath(new URL("../", import.meta.url));
const publicDirectory = path.join(repositoryRoot, "public");
const outputDirectory = path.resolve(process.argv[2] || path.join(repositoryRoot, "_site"));
const indexPath = path.join(outputDirectory, "index.html");

await mkdir(outputDirectory, { recursive: true });
for (const entry of await readdir(publicDirectory)) {
  await cp(path.join(publicDirectory, entry), path.join(outputDirectory, entry), { recursive: true });
}

const html = await readFile(indexPath, "utf8");
if (!html.includes("</head>")) {
  throw new Error("public/index.html must contain a closing </head> tag.");
}
await writeFile(
  indexPath,
  html.replace("</head>", "  <script>window.__PAGES_DEMO__ = true;</script>\n</head>"),
  "utf8",
);
await writeFile(path.join(outputDirectory, ".nojekyll"), "", "utf8");
console.log(`Built static Pages demo in ${outputDirectory}`);
