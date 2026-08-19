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
  { label: "Delete Account", href: "/delete-account" },
];

/**
 * Copy for /delete-account — the account-deletion URL required by Google
 * Play's Data safety form. Play crawls this page, so the two methods below
 * must stay in sync with what Settings actually does (lib/screens/
 * settings_page.dart) and what SubscriptionService.deleteAccount() wipes.
 */
export const accountDeletion = {
  title: "Delete Your SneakScan Account",
  updated: "August 2026",
  intro:
    "You can permanently delete your SneakScan account and the data tied to it at any time. There are two ways to do it — choose whichever you prefer.",
  methods: [
    {
      label: "Option 1",
      heading: "Delete it in the app",
      body: "The fastest route. Deletion takes effect immediately.",
      steps: [
        "Open SneakScan and sign in, if you aren't already.",
        "Tap your profile photo in the top-right corner to open Settings.",
        "Scroll to the bottom, to the ACCOUNT section.",
        "Tap Delete Account, then confirm.",
      ],
      note: "Your account and scan history are erased right away and you are returned to the sign-in screen.",
    },
    {
      label: "Option 2",
      heading: "Email us",
      body: "If you no longer have the app installed or can't sign in, email us and we'll delete the account for you.",
      steps: [
        "Email support@sneakscan.com from the address your SneakScan account uses.",
        'Use the subject line "Delete my account".',
      ],
      note: "We complete the deletion within 30 days of receiving the request and email you once it's done.",
    },
  ],
  deleted: {
    heading: "What gets deleted",
    intro: "Deleting your account permanently removes:",
    items: [
      "Your account itself — the Google or Apple sign-in record, along with the name, email address, and profile photo it provided",
      "Your entire scan history — every scanned sneaker, style code, size, photo, and timestamp",
      "Your subscription record and in-app preferences stored on our servers",
      "Any marketplace account you connected to SneakScan, including stored StockX authorization tokens",
    ],
    warning:
      "This is permanent. We cannot restore an account or its scan history once it has been deleted.",
  },
  retained: {
    heading: "What we keep, and for how long",
    intro:
      "A small amount of information sits outside the account record and is not removed:",
    items: [
      "Purchase and subscription receipts held by Apple and Google. These live in the App Store and Play Store, not on our servers, and only Apple or Google can remove them.",
      "Anonymous, aggregated usage and crash statistics that are not linked to you or your account.",
      "Records we are required to retain for legal, tax, or fraud-prevention purposes.",
    ],
    note: "Account data is removed from our live databases immediately and purged from encrypted backups within 30 days.",
  },
  subscriptionWarning: {
    heading: "Cancel your subscription separately",
    body: "Deleting your account does not cancel an active SneakScan subscription — Apple and Google manage billing, and we can't cancel it on your behalf. Cancel it in your App Store or Play Store subscription settings first, otherwise you'll keep being charged after the account is gone.",
  },
  footer: {
    body: "Questions, or want only part of your data deleted rather than the whole account? Email us and we'll take care of it.",
  },
};
