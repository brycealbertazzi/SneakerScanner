/**
 * Legal copy, ported verbatim from the pages previously served at
 * privacy.sneakscan.com and terms.sneakscan.com so they can live at
 * sneakscan.com/privacy and sneakscan.com/terms.
 *
 * NOTE: the published text refers to the app as "Sneaker Scanner", the old
 * product name. Left as-published rather than silently rewritten — rename here
 * if the legal copy should say "SneakScan".
 */

export type LegalBlock = { p: string } | { ul: string[] };

export type LegalSection = {
  heading: string;
  blocks: LegalBlock[];
};

export type LegalDoc = {
  title: string;
  updated: string;
  sections: LegalSection[];
};

export const privacyPolicy: LegalDoc = {
  title: "Sneaker Scanner Privacy Policy",
  updated: "February 2026",
  sections: [
    {
      heading: "1. Introduction",
      blocks: [
        {
          p: "Sneaker Scanner (“the app”, “we”, “our”) is a mobile application that allows users to scan sneaker labels, barcodes, and product information to identify models and view related market data.",
        },
        {
          p: "We are committed to protecting your privacy and handling information securely and responsibly.",
        },
        { p: "This Privacy Policy explains:" },
        {
          ul: [
            "What information we collect",
            "How we use it",
            "Where it is stored",
            "When it is shared",
            "Your rights and choices",
          ],
        },
        { p: "By using Sneaker Scanner, you agree to this Privacy Policy." },
      ],
    },
    {
      heading: "2. Information We Collect",
      blocks: [
        {
          p: "Sneaker Scanner does not require account creation and does not collect personal identity information.",
        },
        {
          p: "We may process the following information to provide app functionality:",
        },
        {
          ul: [
            "SKU or style code",
            "Barcode (UPC / EAN / GTIN)",
            "Model name",
            "Brand",
            "Timestamp of scan",
          ],
        },
        {
          p: "Scan results may be stored in Firebase to allow persistence of your scan history.",
        },
        { p: "We do not collect or store:" },
        {
          ul: [
            "Your name",
            "Email address",
            "Phone number",
            "Payment information",
            "Contacts",
            "Location data",
          ],
        },
      ],
    },
    {
      heading: "3. Camera Access",
      blocks: [
        {
          p: "Sneaker Scanner requests access to your device camera solely to scan barcodes and text on shoe labels.",
        },
        {
          p: "Images are processed locally on your device for recognition purposes. We do not store or retain raw camera images on our servers.",
        },
      ],
    },
    {
      heading: "4. Subscription Information (If Applicable)",
      blocks: [
        { p: "If Sneaker Scanner offers paid subscriptions:" },
        {
          p: "Subscriptions are processed and managed through the Apple App Store or Google Play.",
        },
        { p: "We may receive limited information such as:" },
        {
          ul: [
            "Product identifier",
            "Subscription status",
            "Renewal or expiration status",
          ],
        },
        { p: "We do not receive or store payment card information." },
      ],
    },
    {
      heading: "5. How We Use Information",
      blocks: [
        { p: "We use collected information to:" },
        {
          ul: [
            "Identify sneaker products",
            "Display product details and pricing information",
            "Maintain scan history",
            "Improve app accuracy and performance",
            "Diagnose technical issues",
            "Comply with legal obligations",
          ],
        },
        { p: "We do not use information for:" },
        {
          ul: [
            "Advertising",
            "Behavioral profiling",
            "Selling or renting user data",
          ],
        },
      ],
    },
    {
      heading: "6. Data Storage and Security",
      blocks: [
        {
          p: "Scan results may be stored securely in Firebase to maintain app functionality and persistence.",
        },
        { p: "We implement safeguards such as:" },
        {
          ul: [
            "Encrypted data transmission (HTTPS)",
            "Access controls",
            "Least-privilege backend configuration",
            "Secure credential management",
          ],
        },
        { p: "We do not store personal identity data on our servers." },
      ],
    },
    {
      heading: "7. Third-Party Data Sources",
      blocks: [
        {
          p: "Sneaker Scanner may retrieve product information from third-party APIs or marketplaces in order to display product details and pricing.",
        },
        { p: "These services operate under their own privacy policies." },
        {
          p: "We transmit only necessary product identifiers (such as SKU or barcode) to retrieve relevant product data.",
        },
      ],
    },
    {
      heading: "8. Data Sharing",
      blocks: [
        { p: "We do not sell, rent, or trade user data." },
        {
          p: "We may share limited information with service providers strictly for the purpose of delivering app functionality.",
        },
        {
          p: "We may disclose information if required by law, subpoena, or court order.",
        },
      ],
    },
    {
      heading: "9. Data Retention and Deletion",
      blocks: [
        {
          p: "Scan history stored in Firebase is retained only to provide app functionality.",
        },
        {
          p: "If scan deletion is supported within the app, deleted scans cannot be restored.",
        },
        { p: "We do not maintain long-term personal user profiles." },
      ],
    },
    {
      heading: "10. Security Practices",
      blocks: [
        { p: "We follow industry-standard practices including:" },
        {
          ul: [
            "Encrypted data transport",
            "Restricted backend access",
            "Secure cloud infrastructure",
            "Data minimization principles",
          ],
        },
        {
          p: "We do not maintain long-term storage of personal information.",
        },
      ],
    },
    {
      heading: "11. Changes to This Policy",
      blocks: [
        { p: "We may update this Privacy Policy from time to time." },
        {
          p: "Continued use of Sneaker Scanner after changes are posted constitutes acceptance of the updated Policy.",
        },
      ],
    },
  ],
};

export const termsOfService: LegalDoc = {
  title: "Sneaker Scanner Terms of Service",
  updated: "February 2026",
  sections: [
    {
      heading: "1. Acceptance of Terms",
      blocks: [
        {
          p: "By accessing or using Sneaker Scanner (“the app”, “we”, “our”), you agree to be bound by these Terms of Service. If you do not agree, please discontinue use of the app.",
        },
        {
          p: "These Terms govern your use of the app, including all features, functionality, and related services.",
        },
      ],
    },
    {
      heading: "2. Use of the App",
      blocks: [
        {
          p: "Sneaker Scanner provides tools to scan sneaker labels, barcodes, and product identifiers to retrieve model and market-related information.",
        },
        {
          p: "You agree not to misuse the app or attempt to interfere with its normal operation.",
        },
        { p: "You agree not to:" },
        {
          ul: [
            "Use the app for unlawful purposes",
            "Attempt to access data not intended for you",
            "Reverse-engineer or copy the app’s functionality",
            "Interfere with API integrations or backend services",
            "Upload or transmit harmful code or content",
          ],
        },
        {
          p: "We reserve the right to suspend or restrict access if these Terms are violated.",
        },
      ],
    },
    {
      heading: "3. Subscriptions and Payments",
      blocks: [
        {
          p: "Sneaker Scanner may offer subscription plans that provide access to premium features or enhanced functionality.",
        },
        {
          p: "Subscriptions are managed and billed through the Apple App Store or Google Play. We do not process payment information directly.",
        },
        { p: "By purchasing a subscription, you agree to:" },
        {
          ul: [
            "The payment terms of the applicable app marketplace",
            "Automatic renewal unless canceled",
            "Applicable fees and taxes",
          ],
        },
        {
          p: "You may cancel your subscription at any time through your App Store or Google Play account settings. We do not provide refunds for unused time or partial billing periods.",
        },
      ],
    },
    {
      heading: "4. User Responsibility",
      blocks: [
        {
          p: "You are responsible for how you use information provided by the app.",
        },
        {
          p: "Product information, pricing data, and market estimates are provided for informational purposes only. We do not guarantee the accuracy, completeness, or timeliness of such information.",
        },
        { p: "You are solely responsible for:" },
        {
          ul: [
            "Decisions made based on app data",
            "Any transactions conducted outside the app",
            "Compliance with applicable laws and regulations",
          ],
        },
      ],
    },
    {
      heading: "5. Data Storage and Processing",
      blocks: [
        {
          p: "Scan results may be stored in cloud infrastructure to maintain app functionality and persistence.",
        },
        {
          p: "Barcode and text recognition occur on-device unless otherwise specified.",
        },
        {
          p: "Use of third-party services and APIs is governed by their respective terms and policies.",
        },
      ],
    },
    {
      heading: "6. Third-Party Services",
      blocks: [
        {
          p: "Sneaker Scanner integrates with third-party APIs and services to retrieve product and pricing information.",
        },
        { p: "We are not responsible for:" },
        {
          ul: [
            "Availability or accuracy of third-party data",
            "Changes made by third-party services",
            "Disruptions caused by external platforms",
          ],
        },
        { p: "Your use of third-party services is at your own risk." },
      ],
    },
    {
      heading: "7. Intellectual Property",
      blocks: [
        {
          p: "The app, including its software, design, text, graphics, branding, and functionality, is protected by intellectual property laws.",
        },
        { p: "You may not:" },
        {
          ul: [
            "Copy, modify, or distribute the app",
            "Use our branding without permission",
            "Create derivative works based on the app",
            "Extract or systematically scrape data from the app",
          ],
        },
        { p: "All rights not expressly granted are reserved." },
      ],
    },
    {
      heading: "8. Disclaimer of Warranties",
      blocks: [
        {
          p: "The app is provided “as is” and “as available,” without warranties of any kind, express or implied.",
        },
        { p: "We do not guarantee that the app will:" },
        {
          ul: [
            "Be free of errors or inaccuracies",
            "Meet your specific needs",
            "Operate without interruption",
            "Maintain compatibility with future devices or software",
            "Provide real-time or guaranteed market pricing accuracy",
          ],
        },
        { p: "Use of the app is at your own risk." },
      ],
    },
    {
      heading: "9. Limitation of Liability",
      blocks: [
        {
          p: "To the maximum extent permitted by law, we are not liable for:",
        },
        {
          ul: [
            "Any indirect, incidental, or consequential damages",
            "Financial losses resulting from buying or selling decisions",
            "Loss of data, revenue, or business opportunities",
            "Errors or inaccuracies in product or pricing data",
          ],
        },
        {
          p: "Our total liability, if any, shall not exceed the amount paid by you to use the app in the 12 months preceding the claim.",
        },
      ],
    },
    {
      heading: "10. Termination",
      blocks: [
        { p: "You may stop using the app at any time." },
        { p: "We may suspend or terminate access to the app if:" },
        {
          ul: [
            "You violate these Terms",
            "You misuse the app",
            "The app is discontinued",
          ],
        },
        {
          p: "Upon termination, access to cloud-stored scan history may no longer be available.",
        },
      ],
    },
    {
      heading: "11. Changes to the App or Terms",
      blocks: [
        {
          p: "We may update or modify the app, features, or these Terms at any time.",
        },
        {
          p: "Continued use of the app after changes are posted constitutes acceptance of the updated Terms.",
        },
      ],
    },
    {
      heading: "12. Governing Law",
      blocks: [
        {
          p: "These Terms are governed by the laws of the United States.",
        },
      ],
    },
  ],
};
