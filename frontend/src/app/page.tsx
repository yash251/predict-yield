'use client'

import { usePrivy } from '@privy-io/react-auth'
import { useAccount, useBalance, useChainId } from 'wagmi'
import { useState, useEffect } from 'react'
import { 
  ArrowRight, 
  TrendingUp, 
  Shield, 
  Zap, 
  Users,
  BarChart3,
  Coins,
  ExternalLink
} from 'lucide-react'
import { flareCoston2 } from '../lib/wagmi'
// import { getSupportedChainInfo, isSupportedNetwork } from '../lib/privy'
import { BlockscoutAPI, MeritsAPI } from '../lib/blockscout'
import Link from 'next/link'
import { HeroSection } from '@/components/HeroSection'
import { MarketStats } from '@/components/MarketStats'
import { FeatureCards } from '@/components/FeatureCards'
import { ContractStatus } from '@/components/ContractStatus'

export default function HomePage() {
  const { ready, authenticated, login, logout, user } = usePrivy()
  const { address, isConnected } = useAccount()
  const chainId = useChainId()
  const [meritsBalance, setMeritsBalance] = useState(0)
  const [isLoading, setIsLoading] = useState(false)

  // Get native balance
  const { data: balance } = useBalance({
    address: address,
  })

  // Load merits balance
  useEffect(() => {
    if (address && chainId) {
      loadMeritsBalance()
    }
  }, [address, chainId])

  const loadMeritsBalance = async () => {
    if (!address || !chainId) return
    
    try {
      const meritsAPI = new MeritsAPI(chainId)
      const balance = await meritsAPI.getMeritsBalance(address)
      setMeritsBalance(balance)
    } catch (error) {
      console.error('Error loading merits balance:', error)
    }
  }

  const handleConnect = async () => {
    setIsLoading(true)
    try {
      await login()
    } catch (error) {
      console.error('Connection error:', error)
    } finally {
      setIsLoading(false)
    }
  }

  // Simplified chain info logic
  const chainInfo = chainId === flareCoston2.id ? {
    name: 'Flare Coston2',
    isTestnet: true,
    supportsFeatures: {
      fdcJsonApi: true,
      ftsoV2: true,
      secureRandom: true,
      fAssets: true,
    },
  } : null
  
  const isSupported = chainId === flareCoston2.id

  // Show content immediately with loading states for specific components
  // Remove the full-page loading that was blocking everything
  
  return (
    <div className="flex flex-col min-h-screen">
      <main className="flex-1">
        <HeroSection />
        
        {/* Live Contract Integration Section */}
        <section className="py-12 px-4 bg-muted/50">
          <div className="container mx-auto">
            <div className="text-center mb-8">
              <h2 className="text-3xl font-bold tracking-tight mb-4">
                🎉 Live Smart Contracts on Flare Coston2
              </h2>
              <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
                PredictYield is now live! Interact with deployed smart contracts, mint test tokens, 
                and create prediction markets directly on the Flare blockchain.
              </p>
              {!ready && (
                <div className="mt-4 text-sm text-muted-foreground">
                  <div className="inline-flex items-center gap-2">
                    <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-primary"></div>
                    Initializing Web3 providers...
                  </div>
                </div>
              )}
            </div>
            <ContractStatus />
          </div>
        </section>
        
        <MarketStats />
        <FeatureCards />
      </main>
    </div>
  )
}
