import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // SneakScan's in-app accent (AppColors.brand, 0xFFE66B25, in lib/).
        brand: "#e66b25",
        page: "#F2F2F7",
      },
      borderRadius: {
        "4xl": "2rem",
      },
    },
  },
  plugins: [],
};

export default config;
