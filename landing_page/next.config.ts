import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Pin the workspace root, otherwise Turbopack walks up past the Flutter repo
  // and picks up an unrelated package-lock.json from the home directory.
  turbopack: {
    root: path.join(__dirname),
  },
};

export default nextConfig;
