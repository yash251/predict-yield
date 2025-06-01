import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { Providers } from './providers'

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "PredictYield | DeFi Prediction Markets on Flare",
  description: "Stake FXRP to predict DeFi yield rates on Flare Network. Multi-oracle validation with FTSOv2, FDC, and secure randomness.",
  keywords: "DeFi, prediction markets, Flare Network, FXRP, yield farming, FTSOv2, Blockscout",
  authors: [{ name: "PredictYield Team" }],
  metadataBase: new URL('https://predictyield.com'),
  openGraph: {
    title: "PredictYield | DeFi Prediction Markets",
    description: "Predict DeFi yields on Flare Network with FXRP staking",
    type: "website",
    images: [
      {
        url: "/og-image.png",
        width: 1200,
        height: 630,
        alt: "PredictYield Platform",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "PredictYield | DeFi Prediction Markets",
    description: "Predict DeFi yields on Flare Network with FXRP staking",
    images: ["/og-image.png"],
  },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  themeColor: '#FF6B35',
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased bg-gray-900 text-white min-h-screen`}
      >
        <Providers>
          {children}
        </Providers>
      </body>
    </html>
  );
}
