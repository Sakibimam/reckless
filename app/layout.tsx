import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Reckless AI - AI-Powered DeFi Yield Optimizer",
  description:
    "Let AI help you build your DeFi strategy and get insights",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body suppressHydrationWarning={true}>{children}</body>
    </html>
  );
}
