import type { ReactNode } from 'react';

export const metadata = { title: 'Winfield Console' };

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
