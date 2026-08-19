/**
 * Legal copy, ported from the pages previously served at privacy.sneakscan.com
 * and terms.sneakscan.com so they can live at sneakscan.com/privacy and
 * sneakscan.com/terms.
 *
 * NOTE: the published text refers to the app as "Sneaker Scanner", the old
 * product name. Left as-published rather than silently rewritten — rename here
 * if the legal copy should say "SneakScan".
 *
 * The PRIVACY POLICY was rewritten in August 2026 (no longer verbatim). The
 * original claimed the app "does not require account creation" and listed name
 * and email under "we do not collect" — untrue since Google/Apple sign-in was
 * added, and a direct contradiction of the Play Data safety declaration.
 * Sections 2, 3, 5, 7, 9, 10 describe what the app actually stores; keep them in
 * sync with login_screen.dart, subscription_service.dart, and the RTDB shape
 * (users/{uid}, scans/{uid}, stockxTokens/{uid}, androidTrialIds/{androidId}).
 * The TERMS below are still the verbatim published text.
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
  updated: "August 2026",
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
      heading: "2. Your Account",
      blocks: [
        {
          p: "Sneaker Scanner requires an account. You sign in with Google or with Apple — we do not offer a password-based sign-up, and we never see or store a password.",
        },
        {
          p: "When you sign in, Google or Apple provides us with the following, which we store to identify your account and display it back to you in the app:",
        },
        {
          ul: [
            "A unique account identifier",
            "Your name, as your Google or Apple account provides it",
            "Your email address",
            "Your profile photo, if your Google or Apple account has one",
          ],
        },
        {
          p: "If you use Sign in with Apple and choose to hide your email address, we receive only Apple’s private relay address and never your real one.",
        },
        {
          p: "Your account exists so that your scan history syncs across your devices and so that your subscription stays attached to you rather than to a single phone.",
        },
      ],
    },
    {
      heading: "3. Information We Collect",
      blocks: [
        {
          p: "Beyond the account information described above, we process the following to provide app functionality:",
        },
        {
          ul: [
            "SKU or style code",
            "Barcode (UPC / EAN / GTIN)",
            "Model name",
            "Brand",
            "Shoe size",
            "Timestamp of scan",
            "Market prices retrieved for the scanned product",
          ],
        },
        {
          p: "Scan results are stored in Firebase, under your account, so that your scan history persists and syncs across devices.",
        },
        {
          p: "On Android, we collect your device’s Android ID. It is used solely to determine whether a free trial has already been used on that device, in order to prevent repeat trials. It is not used for advertising or tracking across apps.",
        },
        { p: "We do not collect or store:" },
        {
          ul: [
            "Your phone number",
            "Payment or credit card information",
            "Your contacts",
            "Your location",
            "Photos from your camera roll",
            "Advertising identifiers",
          ],
        },
      ],
    },
    {
      heading: "4. Camera Access",
      blocks: [
        {
          p: "Sneaker Scanner requests access to your device camera solely to scan barcodes and text on shoe labels.",
        },
        {
          p: "Images are processed locally on your device for recognition purposes, using on-device text and barcode recognition. Raw camera images are never uploaded to or stored on our servers — only the text and codes recognized from them.",
        },
      ],
    },
    {
      heading: "5. Subscription Information",
      blocks: [
        {
          p: "Subscriptions are processed and managed through the Apple App Store or Google Play. We never receive or store payment card information.",
        },
        { p: "We may receive and store limited information such as:" },
        {
          ul: [
            "Product identifier",
            "Subscription status",
            "Renewal or expiration status",
            "A purchase or transaction identifier, used to verify the purchase",
          ],
        },
        {
          p: "We use RevenueCat to help us measure subscription performance. RevenueCat receives purchase events under an anonymous identifier and is not given your name or email address.",
        },
      ],
    },
    {
      heading: "6. How We Use Information",
      blocks: [
        { p: "We use collected information to:" },
        {
          ul: [
            "Sign you in and maintain your account",
            "Identify sneaker products",
            "Display product details and pricing information",
            "Maintain and sync your scan history",
            "Manage your subscription and free-trial eligibility",
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
            "Selling to third parties",
            "Tracking you across other companies’ apps or websites",
          ],
        },
      ],
    },
    {
      heading: "7. Data Storage and Security",
      blocks: [
        {
          p: "Your account record and scan history are stored securely in Firebase, operated by Google, on servers located in the United States.",
        },
        { p: "We implement safeguards such as:" },
        {
          ul: [
            "Encrypted data transmission (HTTPS)",
            "Encryption of stored data at rest",
            "Access controls that limit each account to its own data",
            "Least-privilege backend configuration",
            "Secure credential management",
          ],
        },
      ],
    },
    {
      heading: "8. Third-Party Data Sources",
      blocks: [
        {
          p: "Sneaker Scanner may retrieve product information from third-party APIs or marketplaces in order to display product details and pricing.",
        },
        { p: "These services operate under their own privacy policies." },
        {
          p: "We transmit only necessary product identifiers (such as SKU or barcode) to retrieve relevant product data. We do not send your name, email address, or account identifier to these services.",
        },
        {
          p: "If you choose to connect a marketplace account, such as StockX, we store the authorization token that connection produces so the app can act on your behalf. That token is deleted when you delete your account, and can also be revoked from the marketplace’s own account settings.",
        },
      ],
    },
    {
      heading: "9. Data Sharing and Service Providers",
      blocks: [
        { p: "We do not sell, rent, or trade user data." },
        {
          p: "We share limited information with service providers strictly to deliver app functionality:",
        },
        {
          ul: [
            "Google (Firebase) — authentication, database, and cloud functions",
            "Google and Apple — sign-in, and subscription billing and validation",
            "RevenueCat — anonymous subscription analytics",
          ],
        },
        {
          p: "These providers process data on our behalf and are not permitted to use it for their own purposes.",
        },
        {
          p: "We may disclose information if required by law, subpoena, or court order.",
        },
      ],
    },
    {
      heading: "10. Data Retention and Deletion",
      blocks: [
        {
          p: "Your account information and scan history are retained for as long as your account exists.",
        },
        {
          p: "You can delete your account and its data at any time from within the app: tap your profile photo in the top-right corner to open Settings, scroll to the Account section, and tap Delete Account. Deletion takes effect immediately.",
        },
        {
          p: "You can also request deletion by emailing support@sneakscan.com from the address your account uses. We complete such requests within 30 days. Full instructions are available at sneakscan.com/delete-account.",
        },
        {
          p: "Deleting your account removes your sign-in record, your scan history, your stored subscription record, and any marketplace authorization tokens. Deleted data cannot be restored. Residual copies are purged from encrypted backups within 30 days.",
        },
        {
          p: "Purchase records held by Apple and Google, anonymous aggregate statistics, and records we must keep for legal or tax reasons are not removed by account deletion.",
        },
        {
          p: "Individual scans can also be deleted from your history without deleting your account. Deleted scans cannot be restored.",
        },
      ],
    },
    {
      heading: "11. Your Rights and Choices",
      blocks: [
        {
          p: "You can, at any time:",
        },
        {
          ul: [
            "Access your account information and scan history from within the app",
            "Delete individual scans from your history",
            "Delete your entire account and all associated data",
            "Revoke Sneaker Scanner’s access from a linked marketplace’s own account settings",
            "Revoke camera access in your device settings, though scanning will no longer work",
            "Withdraw Sneaker Scanner’s access from your Google or Apple account settings",
          ],
        },
        {
          p: "Depending on where you live, you may have additional rights over your personal data — including the right to request a copy of it, to correct it, or to object to its processing. Email support@sneakscan.com and we will respond within 30 days.",
        },
      ],
    },
    {
      heading: "12. Children’s Privacy",
      blocks: [
        {
          p: "Sneaker Scanner is not directed to children under 13, and we do not knowingly collect personal information from them. If you believe a child has provided us with personal information, email support@sneakscan.com and we will delete it.",
        },
      ],
    },
    {
      heading: "13. Changes to This Policy",
      blocks: [
        { p: "We may update this Privacy Policy from time to time." },
        {
          p: "Continued use of Sneaker Scanner after changes are posted constitutes acceptance of the updated Policy.",
        },
      ],
    },
    {
      heading: "14. Contact Us",
      blocks: [
        {
          p: "Questions about this Privacy Policy, or about the data we hold, can be sent to support@sneakscan.com.",
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
