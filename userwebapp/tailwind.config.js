export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#0B0B0B",
        card: "#1A1A1A",
        card2: "#141821",
        line: "rgba(255,255,255,0.05)",
        brand: { DEFAULT: "#E11D48", soft: "#E53950" },
        gold: "#FFC94A",
        online: "#22C55E",
        muted: "#9CA3AF",
      },
      fontFamily: {
        sans: ["Inter", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"],
      },
    },
  },
  plugins: [],
};
