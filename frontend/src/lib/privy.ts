import { PrivyClientConfig } from '@privy-io/react-auth'
import { flareCoston2, flareTestnetEnhanced, songbirdTestnetEnhanced } from './wagmi'

export const privyConfig: PrivyClientConfig = {
  appId: process.env.NEXT_PUBLIC_PRIVY_APP_ID || 'clyy0v8fr06tj11ej8e8o7vjg',
  config: {
    // Wallet connection options
    loginMethods: ['wallet', 'email', 'sms'],
    appearance: {
      theme: 'dark',
      accentColor: '#FF6B35',
      logo: '/logo.png',
      showWalletLoginFirst: true,
    },
    
    // Embedded wallet configuration
    embeddedWallets: {
      createOnLogin: 'users-without-wallets',
      noPromptOnSignature: false,
    },
    
    // Flare network support
    defaultChain: flareCoston2,
    supportedChains: [flareCoston2, flareTestnetEnhanced, songbirdTestnetEnhanced],
    
    // Legal and branding
    legal: {
      termsAndConditionsUrl: 'https://predictyield.com/terms',
      privacyPolicyUrl: 'https://predictyield.com/privacy',
    },
    
    // Additional configuration for DeFi features
    walletConnectProjectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID,
    
    // Callback URLs
    callbacks: {
      onAuthFlow: {
        success: '/dashboard',
        error: '/?error=auth-failed',
      },
    },
  },
}

// Utility function to check if user is connected to supported network
export function isSupportedNetwork(chainId: number): boolean {
  return [
    flareCoston2.id,
    flareTestnetEnhanced.id, 
    songbirdTestnetEnhanced.id
  ].includes(chainId)
}

// Network switching helper
export function getSupportedChainInfo(chainId: number) {
  switch (chainId) {
    case flareCoston2.id:
      return {
        name: 'Flare Coston2',
        isTestnet: true,
        supportsFeatures: {
          fdcJsonApi: true,
          ftsoV2: true,
          secureRandom: true,
          fAssets: true,
        },
      }
    case flareTestnetEnhanced.id:
      return {
        name: 'Flare Testnet',
        isTestnet: true,
        supportsFeatures: {
          fdcJsonApi: false,
          ftsoV2: true,
          secureRandom: true,
          fAssets: true,
        },
      }
    case songbirdTestnetEnhanced.id:
      return {
        name: 'Songbird Testnet',
        isTestnet: true,
        supportsFeatures: {
          fdcJsonApi: false,
          ftsoV2: true,
          secureRandom: true,
          fAssets: false,
        },
      }
    default:
      return null
  }
}

// Explicit re-exports to ensure proper module loading
export { isSupportedNetwork as isSupportedNetworkUtil }
export { getSupportedChainInfo as getSupportedChainInfoUtil } 