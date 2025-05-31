import { http, createConfig } from 'wagmi'
import { flareTestnet, songbirdTestnet } from 'wagmi/chains'

// Custom Flare Coston2 chain definition (enhanced for FDC JsonApi support)
export const flareCoston2 = {
  id: 114,
  name: 'Flare Testnet Coston2',
  nativeCurrency: {
    decimals: 18,
    name: 'Coston2 Flare',
    symbol: 'C2FLR',
  },
  rpcUrls: {
    default: {
      http: ['https://coston2-api.flare.network/ext/C/rpc'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Flare Coston2 Explorer',
      url: 'https://coston2-explorer.flare.network',
      apiUrl: 'https://coston2-explorer.flare.network/api',
    },
  },
  testnet: true,
} as const

// Enhanced Flare testnet for FTSOv2 support  
export const flareTestnetEnhanced = {
  ...flareTestnet,
  blockExplorers: {
    default: {
      name: 'Flare Explorer',
      url: 'https://flare-explorer.flare.network',
      apiUrl: 'https://flare-explorer.flare.network/api',
    },
  },
}

// Enhanced Songbird testnet
export const songbirdTestnetEnhanced = {
  ...songbirdTestnet,
  blockExplorers: {
    default: {
      name: 'Songbird Explorer', 
      url: 'https://songbird-explorer.flare.network',
      apiUrl: 'https://songbird-explorer.flare.network/api',
    },
  },
}

export const config = createConfig({
  chains: [flareCoston2, flareTestnetEnhanced, songbirdTestnetEnhanced],
  transports: {
    [flareCoston2.id]: http(),
    [flareTestnetEnhanced.id]: http(),
    [songbirdTestnetEnhanced.id]: http(),
  },
})

declare module 'wagmi' {
  interface Register {
    config: typeof config
  }
} 