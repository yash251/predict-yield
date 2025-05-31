import { defineChain } from 'viem'

// Flare Mainnet
export const flare = defineChain({
  id: 14,
  name: 'Flare',
  nativeCurrency: {
    decimals: 18,
    name: 'Flare',
    symbol: 'FLR',
  },
  rpcUrls: {
    default: {
      http: ['https://flare-api.flare.network/ext/bc/C/rpc'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Flare Explorer',
      url: 'https://flare-explorer.flare.network',
    },
  },
  contracts: {
    multicall3: {
      address: '0xcA11bde05977b3631167028862bE2a173976CA11',
      blockCreated: 1,
    },
  },
})

// Flare Coston2 Testnet - Our primary development network
export const coston2 = defineChain({
  id: 114,
  name: 'Coston2',
  nativeCurrency: {
    decimals: 18,
    name: 'Coston2 Flare',
    symbol: 'C2FLR',
  },
  rpcUrls: {
    default: {
      http: ['https://coston2-api.flare.network/ext/bc/C/rpc'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Coston2 Explorer',
      url: 'https://coston2-explorer.flare.network',
    },
  },
  contracts: {
    multicall3: {
      address: '0xcA11bde05977b3631167028862bE2a173976CA11',
      blockCreated: 1,
    },
  },
  testnet: true,
})

// Songbird Testnet (alternative)
export const songbird = defineChain({
  id: 19,
  name: 'Songbird',
  nativeCurrency: {
    decimals: 18,
    name: 'Songbird',
    symbol: 'SGB',
  },
  rpcUrls: {
    default: {
      http: ['https://songbird-api.flare.network/ext/bc/C/rpc'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Songbird Explorer',
      url: 'https://songbird-explorer.flare.network',
    },
  },
  contracts: {
    multicall3: {
      address: '0xcA11bde05977b3631167028862bE2a173976CA11',
      blockCreated: 1,
    },
  },
  testnet: true,
})

export const supportedChains = [coston2, flare, songbird] as const
export type SupportedChain = typeof supportedChains[number] 