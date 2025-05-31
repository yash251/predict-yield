import React from 'react'
import { PrivyProvider } from '@privy-io/react-auth'

// Simplified Privy provider component for initial setup
export function Web3Provider({ children }: { children: React.ReactNode }) {
  return (
    <PrivyProvider
      appId={process.env.NEXT_PUBLIC_PRIVY_APP_ID || ''}
      config={{
        appearance: {
          theme: 'light',
        },
        loginMethods: ['wallet'],
      }}
    >
        {children}
    </PrivyProvider>
  )
} 