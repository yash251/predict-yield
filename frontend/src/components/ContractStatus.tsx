'use client'

import { useState, useEffect } from 'react'
import { useAccount, useConnect } from 'wagmi'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { ExternalLink, Coins, TrendingUp, Dice1, CheckCircle } from 'lucide-react'
import { useMockFXRP, usePredictYieldMarket, useContractEvents, useMarket } from '@/hooks/useContracts'
import { getExplorerLink, NETWORK_CONFIG } from '@/lib/contracts'

export function ContractStatus() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const [mintAmount, setMintAmount] = useState('100')
  const [marketQuestion, setMarketQuestion] = useState('Will Aave USDC yield reach 6% by next week?')
  const [targetYield, setTargetYield] = useState('600') // 6% in basis points
  const [showMarkets, setShowMarkets] = useState(false)
  const [betAmount, setBetAmount] = useState('10')
  
  // Use contract hooks
  const mockFXRP = useMockFXRP()
  const predictMarket = usePredictYieldMarket()
  
  // Watch for contract events
  useContractEvents()

  // Auto-refresh data when transactions complete
  useEffect(() => {
    if (!predictMarket.isMarketPending && !mockFXRP.isTransferPending) {
      // Refresh balances and market count after transactions
      mockFXRP.refetchBalance()
      predictMarket.refetchMarketCount()
    }
  }, [predictMarket.isMarketPending, mockFXRP.isTransferPending])

  // Show markets list when markets exist
  useEffect(() => {
    if (predictMarket.marketCount > 0) {
      setShowMarkets(true)
    }
  }, [predictMarket.marketCount])

  if (!isConnected) {
    return (
      <Card className="w-full max-w-md mx-auto">
        <CardHeader className="text-center">
          <CardTitle className="flex items-center justify-center gap-2">
            <Coins className="w-5 h-5" />
            Connect Wallet
          </CardTitle>
          <CardDescription>
            Connect to interact with PredictYield contracts on Flare Coston2
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {connectors.map((connector) => (
            <Button
              key={connector.uid}
              onClick={() => connect({ connector })}
              className="w-full"
              variant="outline"
            >
              Connect {connector.name}
            </Button>
          ))}
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-6">
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {/* Network Status */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center justify-between">
              <span>Network Status</span>
              <Badge variant="secondary">Live</Badge>
            </CardTitle>
            <CardDescription>Flare Coston2 Testnet</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Chain ID:</span>
                <span className="font-mono">{NETWORK_CONFIG.chainId}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Network:</span>
                <span>{NETWORK_CONFIG.name}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Connected:</span>
                <span className="font-mono text-xs">{address?.slice(0, 6)}...{address?.slice(-4)}</span>
              </div>
            </div>
            <Button
              variant="outline"
              size="sm"
              className="w-full"
              onClick={() => window.open(NETWORK_CONFIG.explorerUrl, '_blank')}
            >
              <ExternalLink className="w-4 h-4 mr-2" />
              View on Explorer
            </Button>
          </CardContent>
        </Card>

        {/* Mock FXRP Token */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Coins className="w-5 h-5" />
              Mock FXRP Token
              {mockFXRP.balance !== '0' && <CheckCircle className="w-4 h-4 text-green-500" />}
            </CardTitle>
            <CardDescription>Test token for predictions</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Balance:</span>
                <span className="font-mono font-bold">{mockFXRP.balance} FXRP</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Symbol:</span>
                <span>{mockFXRP.symbol}</span>
              </div>
            </div>
            
            <Separator />
            
            <div className="space-y-3">
              <Label htmlFor="mint-amount">Mint Test Tokens</Label>
              <div className="flex gap-2">
                <Input
                  id="mint-amount"
                  type="number"
                  value={mintAmount}
                  onChange={(e) => setMintAmount(e.target.value)}
                  placeholder="Amount"
                  className="flex-1"
                />
                <Button
                  onClick={() => mockFXRP.mint(address!, mintAmount)}
                  disabled={mockFXRP.isTransferPending}
                  size="sm"
                >
                  {mockFXRP.isTransferPending ? 'Minting...' : 'Mint'}
                </Button>
              </div>
              {mockFXRP.isTransferPending && (
                <p className="text-sm text-blue-500">⏳ Transaction pending...</p>
              )}
            </div>
            
            <Button
              variant="outline"
              size="sm"
              className="w-full"
              onClick={() => window.open(getExplorerLink(mockFXRP.address), '_blank')}
            >
              <ExternalLink className="w-4 h-4 mr-2" />
              View Contract
            </Button>
          </CardContent>
        </Card>

        {/* Prediction Market */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <TrendingUp className="w-5 h-5" />
              Prediction Markets
              {predictMarket.marketCount > 0 && <CheckCircle className="w-4 h-4 text-green-500" />}
            </CardTitle>
            <CardDescription>Create yield prediction markets</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Total Markets:</span>
                <span className="font-mono font-bold">{predictMarket.marketCount}</span>
              </div>
            </div>
            
            <Separator />
            
            <div className="space-y-3">
              <div>
                <Label htmlFor="market-question">Market Question</Label>
                <Input
                  id="market-question"
                  value={marketQuestion}
                  onChange={(e) => setMarketQuestion(e.target.value)}
                  placeholder="Enter market question"
                  className="mt-1"
                />
              </div>
              
              <div>
                <Label htmlFor="target-yield">Target Yield (basis points)</Label>
                <Input
                  id="target-yield"
                  type="number"
                  value={targetYield}
                  onChange={(e) => setTargetYield(e.target.value)}
                  placeholder="600 = 6%"
                  className="mt-1"
                />
              </div>
              
              <Button
                onClick={() => predictMarket.createMarket(marketQuestion, parseInt(targetYield), 7, true)}
                disabled={predictMarket.isMarketPending}
                className="w-full"
              >
                {predictMarket.isMarketPending ? 'Creating...' : 'Create Market'}
              </Button>
              {predictMarket.isMarketPending && (
                <p className="text-sm text-blue-500">⏳ Creating market...</p>
              )}
            </div>
            
            <Button
              variant="outline"
              size="sm"
              className="w-full"
              onClick={() => window.open(getExplorerLink(predictMarket.address), '_blank')}
            >
              <ExternalLink className="w-4 h-4 mr-2" />
              View Contract
            </Button>
          </CardContent>
        </Card>
      </div>

      {/* Markets List */}
      {showMarkets && predictMarket.marketCount > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              🎯 Active Markets ({predictMarket.marketCount})
            </CardTitle>
            <CardDescription>
              Place bets on yield prediction markets
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {Array.from({ length: predictMarket.marketCount }, (_, i) => (
                <MarketCard 
                  key={i} 
                  marketId={i} 
                  yesToken={predictMarket.yesToken}
                  noToken={predictMarket.noToken}
                  betAmount={betAmount}
                  setBetAmount={setBetAmount}
                  placeBet={predictMarket.placeBet}
                  isPlacingBet={predictMarket.isMarketPending}
                />
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Contract Addresses */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Dice1 className="w-5 h-5" />
            Deployed Contracts
          </CardTitle>
          <CardDescription>All contract addresses on Flare Coston2 testnet</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-3">
            <div className="space-y-2">
              <h4 className="font-semibold text-sm">MockFXRP Token</h4>
              <code className="text-xs bg-muted p-2 rounded block overflow-hidden">
                {mockFXRP.address}
              </code>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => window.open(getExplorerLink(mockFXRP.address), '_blank')}
              >
                <ExternalLink className="w-3 h-3 mr-1" />
                Explorer
              </Button>
            </div>
            
            <div className="space-y-2">
              <h4 className="font-semibold text-sm">PredictYieldMarketV2</h4>
              <code className="text-xs bg-muted p-2 rounded block overflow-hidden">
                {predictMarket.address}
              </code>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => window.open(getExplorerLink(predictMarket.address), '_blank')}
              >
                <ExternalLink className="w-3 h-3 mr-1" />
                Explorer
              </Button>
            </div>
            
            <div className="space-y-2">
              <h4 className="font-semibold text-sm">FlareSecureRandom</h4>
              <code className="text-xs bg-muted p-2 rounded block overflow-hidden">
                0x92833902c7A76c9718FeB4273B8b174703907376
              </code>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => window.open(getExplorerLink('0x92833902c7A76c9718FeB4273B8b174703907376'), '_blank')}
              >
                <ExternalLink className="w-3 h-3 mr-1" />
                Explorer
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

// Individual Market Card Component
function MarketCard({ 
  marketId, 
  yesToken, 
  noToken, 
  betAmount, 
  setBetAmount, 
  placeBet, 
  isPlacingBet 
}: { 
  marketId: number
  yesToken: string
  noToken: string
  betAmount: string
  setBetAmount: (amount: string) => void
  placeBet: (marketId: number, position: string, amount: string) => void
  isPlacingBet: boolean
}) {
  const market = useMarket(marketId)
  
  if (!market.market) {
    return <div className="p-4 border rounded">Loading market {marketId}...</div>
  }

  return (
    <div className="p-4 border rounded-lg space-y-4">
      <div className="space-y-2">
        <h3 className="font-semibold">{market.market.description}</h3>
        <div className="grid grid-cols-2 gap-4 text-sm">
          <div>
            <span className="text-muted-foreground">Target Yield:</span>
            <span className="ml-2 font-mono">{market.market.targetYield}%</span>
          </div>
          <div>
            <span className="text-muted-foreground">Status:</span>
            <span className="ml-2">
              {market.market.status === 0 ? (
                <Badge variant="default">Active</Badge>
              ) : (
                <Badge variant="secondary">Closed</Badge>
              )}
            </span>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-4 text-sm">
          <div>
            <span className="text-muted-foreground">YES Stakes:</span>
            <span className="ml-2 font-mono">{market.market.totalYesStake} FXRP</span>
          </div>
          <div>
            <span className="text-muted-foreground">NO Stakes:</span>
            <span className="ml-2 font-mono">{market.market.totalNoStake} FXRP</span>
          </div>
        </div>
      </div>
      
      <Separator />
      
      <div className="space-y-3">
        <Label>Place Your Bet</Label>
        <div className="flex gap-2">
          <Input
            type="number"
            value={betAmount}
            onChange={(e) => setBetAmount(e.target.value)}
            placeholder="Amount in FXRP"
            className="flex-1"
          />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <Button
            onClick={() => placeBet(marketId, yesToken, betAmount)}
            disabled={isPlacingBet || !yesToken}
            variant="default"
            className="bg-green-600 hover:bg-green-700"
          >
            {isPlacingBet ? 'Betting...' : `Bet YES`}
          </Button>
          <Button
            onClick={() => placeBet(marketId, noToken, betAmount)}
            disabled={isPlacingBet || !noToken}
            variant="destructive"
          >
            {isPlacingBet ? 'Betting...' : `Bet NO`}
          </Button>
        </div>
        {isPlacingBet && (
          <p className="text-sm text-blue-500">⏳ Placing bet...</p>
        )}
      </div>
      
      {market.userBets && market.userBets.length > 0 && (
        <div className="space-y-2">
          <Label>Your Bets</Label>
          {market.userBets.map((bet, index) => (
            <div key={index} className="text-sm p-2 bg-muted rounded">
              Position: {bet.position === yesToken ? 'YES' : 'NO'} | 
              Amount: {bet.amount} FXRP |
              {bet.claimed ? ' ✅ Claimed' : ' ⏳ Pending'}
            </div>
          ))}
        </div>
      )}
    </div>
  )
} 