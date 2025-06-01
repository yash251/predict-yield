import { useReadContract, useWriteContract, useWatchContractEvent } from 'wagmi'
import { parseEther, formatEther } from 'viem'
import { contractConfig, CONTRACT_ADDRESSES } from '../lib/contracts'
import { useAccount } from 'wagmi'

// Hook for MockFXRP token operations
export function useMockFXRP() {
  const { address } = useAccount()

  // Read token balance
  const { data: balance, refetch: refetchBalance } = useReadContract({
    ...contractConfig.mockFXRP,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
  })

  // Read token info
  const { data: name } = useReadContract({
    ...contractConfig.mockFXRP,
    functionName: 'name',
  })

  const { data: symbol } = useReadContract({
    ...contractConfig.mockFXRP,
    functionName: 'symbol',
  })

  const { data: decimals } = useReadContract({
    ...contractConfig.mockFXRP,
    functionName: 'decimals',
  })

  // Write operations
  const { writeContract: writeContractFXRP, isPending: isTransferPending } = useWriteContract()

  const transfer = (to: string, amount: string) => {
    writeContractFXRP({
      ...contractConfig.mockFXRP,
      functionName: 'transfer',
      args: [to as `0x${string}`, parseEther(amount)],
    })
  }

  const approve = (spender: string, amount: string) => {
    writeContractFXRP({
      ...contractConfig.mockFXRP,
      functionName: 'approve',
      args: [spender as `0x${string}`, parseEther(amount)],
    })
  }

  const mint = (to: string, amount: string) => {
    writeContractFXRP({
      ...contractConfig.mockFXRP,
      functionName: 'mint',
      args: [to as `0x${string}`, parseEther(amount)],
    })
  }

  return {
    // Data
    balance: balance ? formatEther(balance) : '0',
    name,
    symbol,
    decimals,
    
    // Actions
    transfer,
    approve,
    mint,
    refetchBalance,
    isTransferPending,
    
    // Contract address
    address: CONTRACT_ADDRESSES.MockFXRP,
  }
}

// Hook for PredictYieldMarketV2 operations
export function usePredictYieldMarket() {
  // Read market count
  const { data: marketCount, refetch: refetchMarketCount } = useReadContract({
    ...contractConfig.predictYieldMarket,
    functionName: 'totalMarkets',
  })

  // Get YES and NO token addresses
  const { data: yesToken } = useReadContract({
    ...contractConfig.predictYieldMarket,
    functionName: 'YES_TOKEN',
  })

  const { data: noToken } = useReadContract({
    ...contractConfig.predictYieldMarket,
    functionName: 'NO_TOKEN',
  })

  // Write operations
  const { writeContract: writeContractMarket, isPending: isMarketPending } = useWriteContract()

  const createMarket = (
    question: string,
    targetYield: number, // in basis points (500 = 5%)
    bettingPeriodDays: number,
    useRandomDuration: boolean = true
  ) => {
    const bettingPeriodSeconds = bettingPeriodDays * 24 * 60 * 60
    writeContractMarket({
      ...contractConfig.predictYieldMarket,
      functionName: 'createMarket',
      args: [question, BigInt(targetYield), BigInt(bettingPeriodSeconds), useRandomDuration],
    })
  }

  const placeBet = (marketId: number, position: string, amount: string) => {
    writeContractMarket({
      ...contractConfig.predictYieldMarket,
      functionName: 'placeBet',
      args: [BigInt(marketId), position as `0x${string}`, parseEther(amount)],
    })
  }

  return {
    // Data
    marketCount: marketCount ? Number(marketCount) : 0,
    yesToken: yesToken as `0x${string}`,
    noToken: noToken as `0x${string}`,
    
    // Actions
    createMarket,
    placeBet,
    refetchMarketCount,
    isMarketPending,
    
    // Contract address
    address: CONTRACT_ADDRESSES.PredictYieldMarketV2,
  }
}

// Hook for reading a specific market
export function useMarket(marketId: number) {
  const { data: market, refetch: refetchMarket } = useReadContract({
    ...contractConfig.predictYieldMarket,
    functionName: 'getMarket',
    args: [BigInt(marketId)],
  })

  const { address } = useAccount()
  
  // Get user's bet for this market
  const { data: userBets, refetch: refetchUserBet } = useReadContract({
    ...contractConfig.predictYieldMarket,
    functionName: 'getUserBets',
    args: address ? [BigInt(marketId), address] : undefined,
  })

  const formatMarket = (rawMarket: any) => {
    if (!rawMarket) return null
    
    return {
      id: Number(rawMarket[0]),
      description: rawMarket[1],
      creator: rawMarket[2],
      targetYield: Number(rawMarket[3]) / 100, // Convert from basis points to percentage
      creationTime: Number(rawMarket[4]),
      bettingEndTime: Number(rawMarket[5]),
      settlementTime: Number(rawMarket[6]),
      totalYesStake: formatEther(rawMarket[7]),
      totalNoStake: formatEther(rawMarket[8]),
      platformFee: formatEther(rawMarket[9]),
      status: rawMarket[10],
      finalYield: Number(rawMarket[11]),
      winner: rawMarket[12],
      useRandomDuration: rawMarket[13],
      randomRequestId: rawMarket[14],
    }
  }

  const formatUserBets = (rawUserBets: any) => {
    if (!rawUserBets || rawUserBets.length === 0) return []
    
    return rawUserBets.map((bet: any) => ({
      bettor: bet[0],
      marketId: Number(bet[1]),
      position: bet[2],
      amount: formatEther(bet[3]),
      timestamp: Number(bet[4]),
      claimed: bet[5],
    }))
  }

  return {
    market: formatMarket(market),
    userBets: formatUserBets(userBets),
    refetchMarket,
    refetchUserBet,
  }
}

// Hook for watching contract events
export function useContractEvents() {
  // Watch for new markets
  useWatchContractEvent({
    ...contractConfig.predictYieldMarket,
    eventName: 'MarketCreated',
    onLogs: (logs) => {
      console.log('New market created:', logs)
      // You could trigger notifications or update state here
    },
  })

  // Watch for new bets
  useWatchContractEvent({
    ...contractConfig.predictYieldMarket,
    eventName: 'BetPlaced',
    onLogs: (logs) => {
      console.log('New bet placed:', logs)
      // You could trigger notifications or update state here
    },
  })

  // Watch for token transfers
  useWatchContractEvent({
    ...contractConfig.mockFXRP,
    eventName: 'Transfer',
    onLogs: (logs) => {
      console.log('Token transfer:', logs)
      // You could update balances or trigger notifications here
    },
  })
}

// Hook for getting multiple markets
export function useMarkets(startId: number = 0, count: number = 10) {
  const { marketCount } = usePredictYieldMarket()
  
  // Generate array of market IDs to fetch
  const marketIds = Array.from(
    { length: Math.min(count, Math.max(0, marketCount - startId)) },
    (_, i) => startId + i
  )

  // You could use useReadContracts here for batch reading, but for simplicity:
  return {
    marketIds,
    totalMarkets: marketCount,
  }
} 