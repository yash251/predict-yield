'use client'

import { useAccount, useChainId } from 'wagmi'
import { useState, useEffect } from 'react'
import { 
  ArrowLeft,
  TrendingUp, 
  Clock, 
  Users,
  ExternalLink,
  BarChart3,
  DollarSign,
  Shield
} from 'lucide-react'
import Link from 'next/link'
import { BlockscoutAPI, formatTransactionHash } from '../../lib/blockscout'
import { getSupportedChainInfo } from '../../lib/privy'

// Mock market data for demo
const mockMarkets = [
  {
    id: 1,
    description: "Will Aave USDC yield reach 5% by next week?",
    targetYield: 500, // 5%
    currentYield: 420, // 4.2%
    totalYesStake: "1,250",
    totalNoStake: "830",
    bettingEndTime: Date.now() + (2 * 24 * 60 * 60 * 1000), // 2 days
    settlementTime: Date.now() + (7 * 24 * 60 * 60 * 1000), // 7 days
    status: 'Active',
    creator: '0x742d35Cc6481D3C2Ef68C4e8f8DAa3F4e8E8F8DA',
    useRandomDuration: true,
    volume: "2,080",
    participants: 23
  },
  {
    id: 2,
    description: "Will Compound DAI yield exceed 3.5% this month?",
    targetYield: 350, // 3.5%
    currentYield: 315, // 3.15%
    totalYesStake: "890",
    totalNoStake: "1,150",
    bettingEndTime: Date.now() + (5 * 24 * 60 * 60 * 1000), // 5 days
    settlementTime: Date.now() + (30 * 24 * 60 * 60 * 1000), // 30 days
    status: 'Active',
    creator: '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC',
    useRandomDuration: false,
    volume: "2,040",
    participants: 18
  },
  {
    id: 3,
    description: "Will Curve 3Pool yield stay above 2% for the week?",
    targetYield: 200, // 2%
    currentYield: 245, // 2.45%
    totalYesStake: "2,100",
    totalNoStake: "450",
    bettingEndTime: Date.now() - (1 * 24 * 60 * 60 * 1000), // 1 day ago (closed)
    settlementTime: Date.now() + (6 * 24 * 60 * 60 * 1000), // 6 days
    status: 'Closed',
    creator: '0x90F79bf6EB2c4f870365E785982E1f101E93b906',
    useRandomDuration: true,
    volume: "2,550",
    participants: 31
  }
]

export default function MarketsPage() {
  const { address, isConnected } = useAccount()
  const chainId = useChainId()
  const [recentTransactions, setRecentTransactions] = useState<any[]>([])
  const [isLoading, setIsLoading] = useState(false)

  useEffect(() => {
    if (address && chainId) {
      loadRecentTransactions()
    }
  }, [address, chainId])

  const loadRecentTransactions = async () => {
    if (!address || !chainId) return
    
    setIsLoading(true)
    try {
      const blockscout = new BlockscoutAPI(chainId)
      const data = await blockscout.getAddressTransactions(address, 1, 5)
      setRecentTransactions(data?.items || [])
    } catch (error) {
      console.error('Error loading transactions:', error)
    } finally {
      setIsLoading(false)
    }
  }

  const formatTimeRemaining = (timestamp: number) => {
    const now = Date.now()
    const diff = timestamp - now
    
    if (diff <= 0) return 'Ended'
    
    const days = Math.floor(diff / (1000 * 60 * 60 * 24))
    const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60))
    
    if (days > 0) return `${days}d ${hours}h`
    return `${hours}h`
  }

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'Active': return 'bg-green-500/10 text-green-400 border-green-500/20'
      case 'Closed': return 'bg-yellow-500/10 text-yellow-400 border-yellow-500/20'
      case 'Settled': return 'bg-blue-500/10 text-blue-400 border-blue-500/20'
      default: return 'bg-gray-500/10 text-gray-400 border-gray-500/20'
    }
  }

  const chainInfo = chainId ? getSupportedChainInfo(chainId) : null

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900">
      {/* Header */}
      <header className="border-b border-gray-800">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between py-6">
            <div className="flex items-center space-x-4">
              <Link 
                href="/"
                className="flex items-center space-x-2 text-gray-400 hover:text-white transition-colors"
              >
                <ArrowLeft className="h-5 w-5" />
                <span>Back to Home</span>
              </Link>
            </div>
            
            <div className="flex items-center space-x-4">
              {isConnected && chainInfo && (
                <div className="flex items-center space-x-2 px-3 py-2 bg-gray-800 rounded-lg">
                  <div className="h-2 w-2 rounded-full bg-green-500"></div>
                  <span className="text-sm text-gray-300">{chainInfo.name}</span>
                </div>
              )}
            </div>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Page Header */}
        <div className="mb-8">
          <h1 className="text-4xl font-bold text-white mb-4">Prediction Markets</h1>
          <p className="text-xl text-gray-300 max-w-2xl">
            Stake FXRP on DeFi yield predictions. All markets use multi-oracle validation for fair settlement.
          </p>
        </div>

        {/* Stats Overview */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <div className="bg-gray-800 border border-gray-700 rounded-xl p-6">
            <div className="flex items-center space-x-3">
              <div className="h-10 w-10 bg-orange-500/10 rounded-lg flex items-center justify-center">
                <BarChart3 className="h-5 w-5 text-orange-500" />
              </div>
              <div>
                <p className="text-2xl font-bold text-white">3</p>
                <p className="text-sm text-gray-400">Active Markets</p>
              </div>
            </div>
          </div>

          <div className="bg-gray-800 border border-gray-700 rounded-xl p-6">
            <div className="flex items-center space-x-3">
              <div className="h-10 w-10 bg-blue-500/10 rounded-lg flex items-center justify-center">
                <DollarSign className="h-5 w-5 text-blue-500" />
              </div>
              <div>
                <p className="text-2xl font-bold text-white">6,670 FXRP</p>
                <p className="text-sm text-gray-400">Total Volume</p>
              </div>
            </div>
          </div>

          <div className="bg-gray-800 border border-gray-700 rounded-xl p-6">
            <div className="flex items-center space-x-3">
              <div className="h-10 w-10 bg-green-500/10 rounded-lg flex items-center justify-center">
                <Users className="h-5 w-5 text-green-500" />
              </div>
              <div>
                <p className="text-2xl font-bold text-white">72</p>
                <p className="text-sm text-gray-400">Participants</p>
              </div>
            </div>
          </div>

          <div className="bg-gray-800 border border-gray-700 rounded-xl p-6">
            <div className="flex items-center space-x-3">
              <div className="h-10 w-10 bg-purple-500/10 rounded-lg flex items-center justify-center">
                <Shield className="h-5 w-5 text-purple-500" />
              </div>
              <div>
                <p className="text-2xl font-bold text-white">4</p>
                <p className="text-sm text-gray-400">Oracle Sources</p>
              </div>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Markets List */}
          <div className="lg:col-span-2">
            <div className="bg-gray-800 border border-gray-700 rounded-xl p-6">
              <h2 className="text-2xl font-bold text-white mb-6">Active Markets</h2>
              
              <div className="space-y-6">
                {mockMarkets.map((market) => (
                  <div 
                    key={market.id}
                    className="bg-gray-900 border border-gray-600 rounded-lg p-6 hover:border-orange-500/50 transition-colors cursor-pointer"
                  >
                    <div className="flex items-start justify-between mb-4">
                      <div className="flex-1">
                        <div className="flex items-center space-x-3 mb-2">
                          <h3 className="text-lg font-semibold text-white">{market.description}</h3>
                          <span className={`px-2 py-1 text-xs rounded-full border ${getStatusColor(market.status)}`}>
                            {market.status}
                          </span>
                        </div>
                        <p className="text-sm text-gray-400">
                          Target: {(market.targetYield / 100).toFixed(1)}% | 
                          Current: {(market.currentYield / 100).toFixed(2)}% |
                          Creator: {market.creator.slice(0, 6)}...{market.creator.slice(-4)}
                        </p>
                      </div>
                    </div>

                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
                      <div>
                        <p className="text-xs text-gray-400 mb-1">YES Stakes</p>
                        <p className="text-lg font-semibold text-green-400">{market.totalYesStake} FXRP</p>
                      </div>
                      <div>
                        <p className="text-xs text-gray-400 mb-1">NO Stakes</p>
                        <p className="text-lg font-semibold text-red-400">{market.totalNoStake} FXRP</p>
                      </div>
                      <div>
                        <p className="text-xs text-gray-400 mb-1">Volume</p>
                        <p className="text-lg font-semibold text-white">{market.volume} FXRP</p>
                      </div>
                      <div>
                        <p className="text-xs text-gray-400 mb-1">Participants</p>
                        <p className="text-lg font-semibold text-white">{market.participants}</p>
                      </div>
                    </div>

                    <div className="flex items-center justify-between">
                      <div className="flex items-center space-x-4 text-sm text-gray-400">
                        <div className="flex items-center space-x-1">
                          <Clock className="h-4 w-4" />
                          <span>Ends: {formatTimeRemaining(market.bettingEndTime)}</span>
                        </div>
                        {market.useRandomDuration && (
                          <div className="flex items-center space-x-1">
                            <Shield className="h-4 w-4 text-green-400" />
                            <span className="text-green-400">Random Duration</span>
                          </div>
                        )}
                      </div>
                      
                      <button className="bg-orange-500 hover:bg-orange-600 text-white px-4 py-2 rounded-lg font-medium transition-colors">
                        Place Bet
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Sidebar */}
          <div className="space-y-6">
            {/* Recent Activity */}
            {isConnected && (
              <div className="bg-gray-800 border border-gray-700 rounded-xl p-6">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-lg font-semibold text-white">Recent Activity</h3>
                  <button 
                    onClick={loadRecentTransactions}
                    disabled={isLoading}
                    className="text-orange-500 hover:text-orange-400 text-sm disabled:opacity-50"
                  >
                    {isLoading ? 'Loading...' : 'Refresh'}
                  </button>
                </div>
                
                {recentTransactions.length > 0 ? (
                  <div className="space-y-3">
                    {recentTransactions.map((tx, index) => (
                      <div key={index} className="flex items-center justify-between py-2 border-b border-gray-700 last:border-b-0">
                        <div>
                          <p className="text-sm text-white font-medium">
                            {formatTransactionHash(tx.hash)}
                          </p>
                          <p className="text-xs text-gray-400">
                            {new Date(tx.timestamp).toLocaleDateString()}
                          </p>
                        </div>
                        <a
                          href={`https://coston2-explorer.flare.network/tx/${tx.hash}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-orange-500 hover:text-orange-400"
                        >
                          <ExternalLink className="h-4 w-4" />
                        </a>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="text-gray-400 text-sm">
                    {isLoading ? 'Loading transactions...' : 'No recent transactions found'}
                  </p>
                )}
              </div>
            )}

            {/* Oracle Status */}
            <div className="bg-gray-800 border border-gray-700 rounded-xl p-6">
              <h3 className="text-lg font-semibold text-white mb-4">Oracle Status</h3>
              
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-300">FTSOv2</span>
                  <div className="flex items-center space-x-2">
                    <div className="h-2 w-2 rounded-full bg-green-500"></div>
                    <span className="text-sm text-green-400">Active</span>
                  </div>
                </div>
                
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-300">FDC JsonApi</span>
                  <div className="flex items-center space-x-2">
                    <div className="h-2 w-2 rounded-full bg-green-500"></div>
                    <span className="text-sm text-green-400">Active</span>
                  </div>
                </div>
                
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-300">Secure Random</span>
                  <div className="flex items-center space-x-2">
                    <div className="h-2 w-2 rounded-full bg-green-500"></div>
                    <span className="text-sm text-green-400">Active</span>
                  </div>
                </div>
                
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-300">FAssets</span>
                  <div className="flex items-center space-x-2">
                    <div className="h-2 w-2 rounded-full bg-green-500"></div>
                    <span className="text-sm text-green-400">Active</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Blockscout Integration */}
            <div className="bg-gray-800 border border-gray-700 rounded-xl p-6">
              <h3 className="text-lg font-semibold text-white mb-4">Blockscout Explorer</h3>
              
              <div className="space-y-3">
                <a
                  href="https://coston2-explorer.flare.network"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center justify-between p-3 bg-gray-900 rounded-lg hover:bg-gray-700 transition-colors"
                >
                  <span className="text-sm text-gray-300">View Explorer</span>
                  <ExternalLink className="h-4 w-4 text-orange-500" />
                </a>
                
                {isConnected && address && (
                  <a
                    href={`https://coston2-explorer.flare.network/address/${address}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center justify-between p-3 bg-gray-900 rounded-lg hover:bg-gray-700 transition-colors"
                  >
                    <span className="text-sm text-gray-300">My Address</span>
                    <ExternalLink className="h-4 w-4 text-orange-500" />
                  </a>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
} 