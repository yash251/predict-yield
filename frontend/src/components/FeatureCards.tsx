'use client'

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Coins, Zap, Shield, Users } from 'lucide-react'

export function FeatureCards() {
  const features = [
    {
      title: 'FXRP Staking',
      description: 'Stake synthetic XRP via FAssets protocol for secure, collateralized betting with real blockchain value.',
      icon: Coins,
      color: 'text-orange-600',
      bgColor: 'bg-orange-50 dark:bg-orange-900/20',
      details: 'FAssets Integration',
    },
    {
      title: 'FTSOv2 Feeds',
      description: 'Real-time yield data updated every 1.8 seconds with free querying and block-latency accuracy.',
      icon: Zap,
      color: 'text-blue-600',
      bgColor: 'bg-blue-50 dark:bg-blue-900/20',
      details: 'Real-time Oracle Data',
    },
    {
      title: 'FDC Validation',
      description: 'External data verification via JsonApi attestation with Merkle proofs and consensus validation.',
      icon: Shield,
      color: 'text-purple-600',
      bgColor: 'bg-purple-50 dark:bg-purple-900/20',
      details: 'Flare Data Connector',
    },
    {
      title: 'Fair Settlement',
      description: 'Verifiable randomness from Flare consensus ensures fair market timing and transparent outcomes.',
      icon: Users,
      color: 'text-green-600',
      bgColor: 'bg-green-50 dark:bg-green-900/20',
      details: 'Secure Random Protocol',
    },
  ]

  return (
    <section className="py-16 px-4 bg-muted/50">
      <div className="container mx-auto">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold tracking-tight mb-4">
            Powered by Flare Network
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            Multi-oracle validation ensures accurate, tamper-proof market settlements with enterprise-grade security
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {features.map((feature, index) => {
            const Icon = feature.icon
            return (
              <Card key={index} className="hover:shadow-lg transition-shadow duration-300">
                <CardHeader>
                  <div className={`w-12 h-12 rounded-lg ${feature.bgColor} flex items-center justify-center mb-4`}>
                    <Icon className={`h-6 w-6 ${feature.color}`} />
                  </div>
                  <CardTitle className="text-xl font-semibold mb-2">{feature.title}</CardTitle>
                  <CardDescription className="text-sm font-medium text-primary">
                    {feature.details}
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <p className="text-muted-foreground">{feature.description}</p>
                </CardContent>
              </Card>
            )
          })}
        </div>
      </div>
    </section>
  )
} 