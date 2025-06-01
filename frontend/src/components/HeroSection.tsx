'use client'

import { usePrivy } from '@privy-io/react-auth'
import { useAccount, useChainId } from 'wagmi'
import { Button } from '@/components/ui/button'
import { ArrowRight, TrendingUp } from 'lucide-react'
import Link from 'next/link'

export function HeroSection() {
  const { ready, authenticated, login } = usePrivy()
  const { isConnected } = useAccount()
  const chainId = useChainId()

  const handleConnect = async () => {
    try {
      await login()
    } catch (error) {
      console.error('Connection error:', error)
    }
  }

  return (
    <section className="relative overflow-hidden py-20 bg-gradient-to-br from-background via-background to-muted">
      <div className="absolute inset-0 bg-gradient-to-r from-primary/5 via-transparent to-secondary/5"></div>
      <div className="relative container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center">
          <div className="flex items-center justify-center mb-6">
            <div className="h-16 w-16 bg-primary rounded-lg flex items-center justify-center mr-4">
              <TrendingUp className="h-8 w-8 text-primary-foreground" />
            </div>
            <div className="text-left">
              <h1 className="text-2xl font-bold">PredictYield</h1>
              <p className="text-muted-foreground">DeFi Prediction Markets</p>
            </div>
          </div>
          
          <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold tracking-tight mb-6">
            Predict
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-primary to-secondary"> DeFi Yields</span>
          </h1>
          
          <p className="text-xl text-muted-foreground mb-8 max-w-3xl mx-auto">
            Stake FXRP to bet on future yield rates of DeFi pools. Powered by Flare's multi-oracle infrastructure 
            with FTSOv2, FDC, and secure randomness for fair, transparent markets.
          </p>
          
          {!ready ? (
            <div className="flex items-center justify-center">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
          ) : !authenticated ? (
            <Button onClick={handleConnect} size="lg" className="text-lg px-8 py-6">
              <span>Get Started</span>
              <ArrowRight className="h-5 w-5 ml-2" />
            </Button>
          ) : (
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <Link href="/markets">
                <Button size="lg" className="text-lg px-8 py-6">
                  <span>Browse Markets</span>
                  <TrendingUp className="h-5 w-5 ml-2" />
                </Button>
              </Link>
              <Button variant="outline" size="lg" className="text-lg px-8 py-6">
                Create Market
              </Button>
            </div>
          )}
        </div>
      </div>
    </section>
  )
} 