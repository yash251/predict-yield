'use client'

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { TrendingUp, DollarSign, Users, Activity } from 'lucide-react'
import { usePredictYieldMarket } from '@/hooks/useContracts'

export function MarketStats() {
  const { marketCount } = usePredictYieldMarket()

  const stats = [
    {
      title: 'Total Markets',
      value: marketCount.toString(),
      description: 'Active prediction markets',
      icon: TrendingUp,
      color: 'text-blue-600',
      bgColor: 'bg-blue-50 dark:bg-blue-900/20',
    },
    {
      title: 'Bounty Pool',
      value: '$18K',
      description: 'ETH Global Prague bounties',
      icon: DollarSign,
      color: 'text-green-600',
      bgColor: 'bg-green-50 dark:bg-green-900/20',
    },
    {
      title: 'Oracle Integrations',
      value: '4',
      description: 'FTSOv2, FDC, SecureRandom, FAssets',
      icon: Activity,
      color: 'text-purple-600',
      bgColor: 'bg-purple-50 dark:bg-purple-900/20',
    },
    {
      title: 'Merits per Bet',
      value: '5',
      description: 'Blockscout reputation points',
      icon: Users,
      color: 'text-orange-600',
      bgColor: 'bg-orange-50 dark:bg-orange-900/20',
    },
  ]

  return (
    <section className="py-16 px-4">
      <div className="container mx-auto">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold tracking-tight mb-4">
            Platform Statistics
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            Real-time metrics from our DeFi prediction market platform on Flare Network
          </p>
        </div>
        
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {stats.map((stat, index) => {
            const Icon = stat.icon
            return (
              <Card key={index} className="text-center">
                <CardHeader className="pb-2">
                  <div className={`w-12 h-12 rounded-lg ${stat.bgColor} flex items-center justify-center mx-auto mb-2`}>
                    <Icon className={`h-6 w-6 ${stat.color}`} />
                  </div>
                  <CardTitle className="text-2xl font-bold">{stat.value}</CardTitle>
                  <CardDescription className="font-medium">{stat.title}</CardDescription>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-muted-foreground">{stat.description}</p>
                </CardContent>
              </Card>
            )
          })}
        </div>
      </div>
    </section>
  )
} 