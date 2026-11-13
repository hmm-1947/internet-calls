export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#FFFFFF",
        card: "#F3F4F6",
        card2: "#E9ECEF",
        line: "#E5E7EB",
        ink: "#111111",
        brand: { DEFAULT: "#0E8F3C", soft: "#12A044" },
        gold: "#E8B93A",
        online: "#22C55E",
        muted: "#6B7280",
      },
      fontFamily: {
        sans: ["Inter", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"],
      },
    },
  },
  plugins: [],
};
