/**
 * Every piece of copy and every outbound link on the marketing site.
 * Edit here rather than in the components.
 */

export const site = {
  name: "SneakScan",
  title: "SneakScan — Know what your sneakers are worth.",
  description:
    "Scan a shoe box label or barcode and get live StockX, GOAT, and eBay resale prices in seconds.",
  url: "https://sneakscan.com",
  supportEmail: "support@sneakscan.com",
  tagline: "Made for thrifters, resellers, and anyone who just wants to know.",
};

export const stores = {
  appStore: "https://apps.apple.com/us/app/sneakscan/id6759068528",
  googlePlay:
    "https://play.google.com/store/apps/details?id=com.albertazzilabs.sneakscan&hl=en_US",
};

export const hero = {
  // Split so the headline lands on two lines at the reference's 68px/max-w-3xl,
  // matching SpendView's two-line hero rather than wrapping to three.
  headline: "Know what your",
  headlineAccent: "sneakers are worth.",
  subhead:
    "Scan the box label or the barcode and SneakScan pulls live StockX, GOAT, and eBay resale prices in seconds — for your exact size.",
};

export const featuresIntro = {
  pill: "Features",
  headline: "Everything you need to",
  headlineSecondLine: "price a pair",
  subhead:
    "From box label to resale value without opening a single browser tab.",
};

export const features = [
  {
    emoji: "📷",
    title: "Label Scanning",
    body: "Photograph the box label and OCR reads the brand, model, colorway, and style code.",
  },
  {
    emoji: "🔳",
    title: "Barcode Scanning",
    body: "Point the camera at the barcode and SneakScan auto-detects the GTIN — no shutter button.",
  },
  {
    emoji: "💵",
    title: "StockX & GOAT Prices",
    body: "Live market prices from both platforms, pulled the moment a pair is identified.",
  },
  {
    emoji: "🏷️",
    title: "eBay Sold Comps",
    body: "Real sold listings with fees factored in, so you see what actually lands in your pocket.",
  },
  {
    emoji: "📐",
    title: "Size-Specific Pricing",
    body: "Prices for the exact size on the label, not a vague range for the whole model.",
  },
  {
    emoji: "🕘",
    title: "Scan History",
    body: "Every scan saved, searchable by name or style code, and filterable by date.",
  },
];

export type DeepDive = {
  pill: string;
  headline: string;
  headlineAccent: string;
  body: string;
  bullets: string[];
  image: string;
  alt: string;
  /** true = screenshot sits to the left of the copy on desktop */
  reversed: boolean;
  rotate: number;
};

export const deepDives: DeepDive[] = [
  {
    pill: "Scan",
    headline: "Point. Shoot.",
    headlineAccent: "Identified.",
    body: "Snap the label on the box or let the camera pick up the barcode. SneakScan reads it, matches it against a live sneaker database, and confirms the exact pair — down to the colorway.",
    bullets: [
      "OCR reads brand, model, colorway, and style code",
      "Live barcode detection, no shutter button",
      "Or type a style code in by hand",
    ],
    image: "/scan-screen.webp",
    alt: "SneakScan home screen showing a Nike shoe box label ready to scan",
    reversed: false,
    rotate: -5,
  },
  {
    pill: "Instant ID",
    headline: "Every detail,",
    headlineAccent: "pulled for you.",
    body: "The moment a pair is matched you get the full product record — brand, style code, size, and a product photo — filled in automatically. No typing, no guessing which colorway you're holding.",
    bullets: [
      "Brand, style code, and size captured automatically",
      "Product photo pulled straight from the catalog",
      "Every scan timestamped and saved",
    ],
    image: "/details-screen.webp",
    alt: "SneakScan scan details screen showing a matched Nike Air Max Correlate with its brand, SKU, and scan time",
    reversed: true,
    rotate: 5,
  },
  {
    pill: "Market Prices",
    headline: "See what it's",
    headlineAccent: "actually selling for.",
    body: "SneakScan pulls live StockX and GOAT prices for your size alongside recent eBay sold comps. Tap through and you land directly on the marketplace listing — ready to buy, list, or make an offer.",
    bullets: [
      "Live StockX and GOAT prices, side by side",
      "eBay sold listings with seller fees factored in",
      "One tap straight to the listing",
    ],
    image: "/market-screen.webp",
    alt: "A GOAT marketplace listing opened straight from SneakScan, showing buy new and buy used prices",
    reversed: false,
    rotate: -5,
  },
  {
    pill: "History",
    headline: "Your whole haul,",
    headlineAccent: "in one place.",
    body: "Every pair you scan is saved to a searchable history. Come back to a thrift run from last week, pull up a style code, and check whether the price moved.",
    bullets: [
      "Search by product name or style code",
      "Filter by today, this week, or this month",
      "Synced to your account across devices",
    ],
    image: "/history-screen.webp",
    alt: "SneakScan scan history screen listing previously scanned Nike sneakers with their style codes",
    reversed: true,
    rotate: 5,
  },
];

export const cta = {
  headline: "Start scanning today.",
  headlineAccent: "Free trial, no commitment.",
  subhead:
    "Try SneakScan free for 7 days — then keep going for less than the profit on a single flip.",
};

export const legalLinks = [
  { label: "Privacy Policy", href: "/privacy" },
  { label: "Terms of Service", href: "/terms" },
];
