import { flareCoston2, flareTestnetEnhanced, songbirdTestnetEnhanced } from './wagmi'
import { Address } from 'viem'
import deploymentConfig from '../deployment-coston2.json'

// Import the real ABIs from the compiled artifacts
import PredictYieldMarketV2ABI from '../PredictYieldMarketV2.json'
import MockFXRPABI from '../MockFXRP.json'

// Contract addresses from deployment
export const CONTRACT_ADDRESSES = {
  MockFXRP: deploymentConfig.contracts.MockFXRP as `0x${string}`,
  PredictYieldMarketV2: deploymentConfig.contracts.PredictYieldMarketV2 as `0x${string}`,
  FlareSecureRandom: deploymentConfig.contracts.FlareSecureRandom as `0x${string}`,
}

// Network configuration
export const NETWORK_CONFIG = {
  chainId: deploymentConfig.networkId,
  name: deploymentConfig.networkName,
  rpcUrl: deploymentConfig.rpcUrl,
  explorerUrl: deploymentConfig.explorerUrl,
}

// Contract addresses for different networks
export const contractAddresses = {
  [flareCoston2.id]: {
    predictionMarket: CONTRACT_ADDRESSES.PredictYieldMarketV2,
    fxrpToken: CONTRACT_ADDRESSES.MockFXRP,
    ftsoOracle: process.env.NEXT_PUBLIC_FTSO_ORACLE_CONTRACT as `0x${string}`,
    fdcOracle: process.env.NEXT_PUBLIC_FDC_ORACLE_CONTRACT as `0x${string}`,
    secureRandom: CONTRACT_ADDRESSES.FlareSecureRandom,
    
    // For demo purposes, we'll use the deployed addresses
    predictionMarketDemo: CONTRACT_ADDRESSES.PredictYieldMarketV2,
    fxrpTokenDemo: CONTRACT_ADDRESSES.MockFXRP,
  },
  [flareTestnetEnhanced.id]: {
    predictionMarket: undefined,
    fxrpToken: undefined,
    ftsoOracle: undefined,
    fdcOracle: undefined,
    secureRandom: undefined,
    predictionMarketDemo: undefined,
    fxrpTokenDemo: undefined,
  },
  [songbirdTestnetEnhanced.id]: {
    predictionMarket: undefined,
    fxrpToken: undefined,
    ftsoOracle: undefined,
    fdcOracle: undefined,
    secureRandom: undefined,
    predictionMarketDemo: undefined,
    fxrpTokenDemo: undefined,
  },
} as const

// Contract ABIs (simplified for frontend use)
export const predictionMarketABI = [
  // Market creation
  {
    name: 'createMarket',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'description', type: 'string' },
      { name: 'targetYield', type: 'uint256' },
      { name: 'bettingDuration', type: 'uint256' },
      { name: 'useRandomDuration', type: 'bool' }
    ],
    outputs: [{ name: 'marketId', type: 'uint256' }]
  },
  
  // Betting
  {
    name: 'placeBet',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'position', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    outputs: []
  },
  
  // Settlement
  {
    name: 'settleMarket',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'marketId', type: 'uint256' }],
    outputs: []
  },
  
  // Claiming
  {
    name: 'claimWinnings',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'marketId', type: 'uint256' }],
    outputs: []
  },
  
  // View functions
  {
    name: 'getMarket',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'marketId', type: 'uint256' }],
    outputs: [{
      name: 'market',
      type: 'tuple',
      components: [
        { name: 'id', type: 'uint256' },
        { name: 'description', type: 'string' },
        { name: 'creator', type: 'address' },
        { name: 'targetYield', type: 'uint256' },
        { name: 'creationTime', type: 'uint256' },
        { name: 'bettingEndTime', type: 'uint256' },
        { name: 'settlementTime', type: 'uint256' },
        { name: 'totalYesStake', type: 'uint256' },
        { name: 'totalNoStake', type: 'uint256' },
        { name: 'platformFee', type: 'uint256' },
        { name: 'status', type: 'uint8' },
        { name: 'finalYield', type: 'uint256' },
        { name: 'winner', type: 'address' },
        { name: 'useRandomDuration', type: 'bool' },
        { name: 'randomRequestId', type: 'bytes32' }
      ]
    }]
  },
  
  {
    name: 'getMarketStats',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'totalMarketsCount', type: 'uint256' },
      { name: 'totalVolumeAmount', type: 'uint256' },
      { name: 'activeMarkets', type: 'uint256' }
    ]
  },
  
  {
    name: 'calculatePayout',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'position', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    outputs: [{ name: 'payout', type: 'uint256' }]
  },
  
  // Constants
  {
    name: 'YES_TOKEN',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }]
  },
  
  {
    name: 'NO_TOKEN',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }]
  },
  
  // Events
  {
    name: 'MarketCreated',
    type: 'event',
    inputs: [
      { name: 'marketId', type: 'uint256', indexed: true },
      { name: 'creator', type: 'address', indexed: true },
      { name: 'description', type: 'string', indexed: false },
      { name: 'targetYield', type: 'uint256', indexed: false },
      { name: 'bettingEndTime', type: 'uint256', indexed: false },
      { name: 'settlementTime', type: 'uint256', indexed: false },
      { name: 'useRandomDuration', type: 'bool', indexed: false }
    ]
  },
  
  {
    name: 'BetPlaced',
    type: 'event',
    inputs: [
      { name: 'marketId', type: 'uint256', indexed: true },
      { name: 'bettor', type: 'address', indexed: true },
      { name: 'position', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'totalStake', type: 'uint256', indexed: false }
    ]
  },
  
  {
    name: 'MarketSettled',
    type: 'event',
    inputs: [
      { name: 'marketId', type: 'uint256', indexed: true },
      { name: 'finalYield', type: 'uint256', indexed: false },
      { name: 'winner', type: 'address', indexed: false },
      { name: 'totalPayout', type: 'uint256', indexed: false },
      { name: 'platformFees', type: 'uint256', indexed: false }
    ]
  }
] as const

// FXRP Token ABI
export const fxrpTokenABI = [
  // ERC20 standard
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }]
  },
  
  {
    name: 'transfer',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    outputs: [{ name: '', type: 'bool' }]
  },
  
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    outputs: [{ name: '', type: 'bool' }]
  },
  
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' }
    ],
    outputs: [{ name: '', type: 'uint256' }]
  },
  
  // FAssets specific
  {
    name: 'mint',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'amount', type: 'uint256' },
      { name: 'collateralAmount', type: 'uint256' }
    ],
    outputs: [{ name: 'success', type: 'bool' }]
  },
  
  {
    name: 'redeem',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amount', type: 'uint256' }],
    outputs: [{ name: 'success', type: 'bool' }]
  },
  
  {
    name: 'getCollateralRatio',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: 'ratio', type: 'uint256' }]
  },
  
  {
    name: 'getMinMintAmount',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: 'amount', type: 'uint256' }]
  }
] as const

// Market status enum
export enum MarketStatus {
  Active = 0,
  Closed = 1,
  Settled = 2,
  Cancelled = 3
}

// Helper function to get contract address for current network
export const getContractAddress = (chainId: number, contractName: keyof typeof contractAddresses[114]) => {
  const addresses = contractAddresses[chainId as keyof typeof contractAddresses]
  return addresses?.[contractName]
}

// Market position constants
export const POSITION_TOKENS = {
  YES: '0x0000000000000000000000000000000000000001' as `0x${string}`,
  NO: '0x0000000000000000000000000000000000000002' as `0x${string}`,
} as const

// Mock FXRP ABI (essential functions for testing)
export const MOCK_FXRP_ABI = [
  {
    inputs: [],
    name: 'name',
    outputs: [{ internalType: 'string', name: '', type: 'string' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'symbol',
    outputs: [{ internalType: 'string', name: '', type: 'string' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'decimals',
    outputs: [{ internalType: 'uint8', name: '', type: 'uint8' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'totalSupply',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ internalType: 'address', name: '', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'address', name: 'to', type: 'address' },
      { internalType: 'uint256', name: 'amount', type: 'uint256' }
    ],
    name: 'transfer',
    outputs: [{ internalType: 'bool', name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'address', name: 'spender', type: 'address' },
      { internalType: 'uint256', name: 'amount', type: 'uint256' }
    ],
    name: 'approve',
    outputs: [{ internalType: 'bool', name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'address', name: 'to', type: 'address' },
      { internalType: 'uint256', name: 'amount', type: 'uint256' }
    ],
    name: 'mint',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: 'address', name: 'from', type: 'address' },
      { indexed: true, internalType: 'address', name: 'to', type: 'address' },
      { indexed: false, internalType: 'uint256', name: 'value', type: 'uint256' }
    ],
    name: 'Transfer',
    type: 'event',
  },
] as const

// PredictYieldMarketV2 ABI (essential functions)
export const PREDICT_YIELD_MARKET_ABI = [
  {
    inputs: [
      { internalType: 'string', name: 'question', type: 'string' },
      { internalType: 'uint256', name: 'targetYield', type: 'uint256' },
      { internalType: 'uint256', name: 'bettingPeriod', type: 'uint256' },
      { internalType: 'bool', name: 'useRandomDuration', type: 'bool' }
    ],
    name: 'createMarket',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'payable',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'uint256', name: 'marketId', type: 'uint256' },
      { internalType: 'bool', name: 'betYes', type: 'bool' },
      { internalType: 'uint256', name: 'amount', type: 'uint256' }
    ],
    name: 'placeBet',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ internalType: 'uint256', name: 'marketId', type: 'uint256' }],
    name: 'getMarket',
    outputs: [
      {
        components: [
          { internalType: 'string', name: 'question', type: 'string' },
          { internalType: 'uint256', name: 'targetYield', type: 'uint256' },
          { internalType: 'uint256', name: 'bettingPeriod', type: 'uint256' },
          { internalType: 'uint256', name: 'createdAt', type: 'uint256' },
          { internalType: 'uint256', name: 'settlementTime', type: 'uint256' },
          { internalType: 'uint256', name: 'totalYesStake', type: 'uint256' },
          { internalType: 'uint256', name: 'totalNoStake', type: 'uint256' },
          { internalType: 'bool', name: 'settled', type: 'bool' },
          { internalType: 'bool', name: 'outcome', type: 'bool' },
          { internalType: 'address', name: 'creator', type: 'address' }
        ],
        internalType: 'struct PredictYieldMarketV2.Market',
        name: '',
        type: 'tuple',
      }
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getMarketCount',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'uint256', name: 'marketId', type: 'uint256' },
      { internalType: 'address', name: 'user', type: 'address' }
    ],
    name: 'getUserBet',
    outputs: [
      { internalType: 'uint256', name: 'yesAmount', type: 'uint256' },
      { internalType: 'uint256', name: 'noAmount', type: 'uint256' }
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: 'uint256', name: 'marketId', type: 'uint256' },
      { indexed: false, internalType: 'string', name: 'question', type: 'string' },
      { indexed: true, internalType: 'address', name: 'creator', type: 'address' }
    ],
    name: 'MarketCreated',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: 'uint256', name: 'marketId', type: 'uint256' },
      { indexed: true, internalType: 'address', name: 'bettor', type: 'address' },
      { indexed: false, internalType: 'bool', name: 'betYes', type: 'bool' },
      { indexed: false, internalType: 'uint256', name: 'amount', type: 'uint256' }
    ],
    name: 'BetPlaced',
    type: 'event',
  },
] as const

// FlareSecureRandom ABI (essential functions)
export const FLARE_SECURE_RANDOM_ABI = [
  {
    inputs: [{ internalType: 'uint256', name: 'seed', type: 'uint256' }],
    name: 'requestRandomness',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'payable',
    type: 'function',
  },
  {
    inputs: [{ internalType: 'uint256', name: 'requestId', type: 'uint256' }],
    name: 'getRandomness',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const

// Contract configuration with real ABIs and addresses
export const contractConfig = {
  mockFXRP: {
    address: CONTRACT_ADDRESSES.MockFXRP,
    abi: MockFXRPABI.abi,
  },
  predictYieldMarket: {
    address: CONTRACT_ADDRESSES.PredictYieldMarketV2,
    abi: PredictYieldMarketV2ABI.abi,
  },
  flareSecureRandom: {
    address: CONTRACT_ADDRESSES.FlareSecureRandom,
    abi: FLARE_SECURE_RANDOM_ABI,
  },
} as const

// Explorer links helper
export const getExplorerLink = (address: string, type: 'address' | 'tx' = 'address') => {
  const baseUrl = NETWORK_CONFIG.explorerUrl
  return `${baseUrl}/${type}/${address}`
} 