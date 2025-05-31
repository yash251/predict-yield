import { flareCoston2, flareTestnetEnhanced, songbirdTestnetEnhanced } from './wagmi'

// Blockscout API endpoints for different networks
export const BLOCKSCOUT_APIS = {
  [flareCoston2.id]: {
    baseUrl: 'https://coston2-explorer.flare.network/api',
    explorerUrl: 'https://coston2-explorer.flare.network',
    meritsUrl: 'https://coston2-explorer.flare.network/api/v1/merits',
    socketUrl: 'wss://coston2-explorer.flare.network/socket',
  },
  [flareTestnetEnhanced.id]: {
    baseUrl: 'https://flare-explorer.flare.network/api',
    explorerUrl: 'https://flare-explorer.flare.network',
    meritsUrl: 'https://flare-explorer.flare.network/api/v1/merits',
    socketUrl: 'wss://flare-explorer.flare.network/socket',
  },
  [songbirdTestnetEnhanced.id]: {
    baseUrl: 'https://songbird-explorer.flare.network/api',
    explorerUrl: 'https://songbird-explorer.flare.network',
    meritsUrl: 'https://songbird-explorer.flare.network/api/v1/merits',
    socketUrl: 'wss://songbird-explorer.flare.network/socket',
  },
} as const

// Transaction types for categorization
export type TransactionType = 
  | 'market_creation'
  | 'bet_placement' 
  | 'market_settlement'
  | 'winnings_claim'
  | 'fxrp_mint'
  | 'fxrp_approve'
  | 'other'

// Transaction status from Blockscout
export interface BlockscoutTransaction {
  hash: string
  block_number: number
  block_hash: string
  transaction_index: number
  from: {
    hash: string
    is_contract: boolean
    is_verified: boolean
  }
  to: {
    hash: string
    is_contract: boolean
    is_verified: boolean
  }
  value: string
  gas: string
  gas_price: string
  gas_used: string
  status: 'ok' | 'error'
  timestamp: string
  confirmations: number
  input: string
  logs: Array<{
    address: string
    topics: string[]
    data: string
    decoded?: {
      method_call: string
      method_id: string
      parameters: Array<{
        name: string
        type: string
        value: string
      }>
    }
  }>
  method?: string
  decoded_input?: {
    method_call: string
    method_id: string
    parameters: Array<{
      name: string
      type: string
      value: string
    }>
  }
}

// Blockscout API client
export class BlockscoutAPI {
  private baseUrl: string
  private explorerUrl: string
  private meritsUrl: string

  constructor(chainId: number) {
    const config = BLOCKSCOUT_APIS[chainId as keyof typeof BLOCKSCOUT_APIS]
    if (!config) {
      throw new Error(`Unsupported chain ID: ${chainId}`)
    }
    
    this.baseUrl = config.baseUrl
    this.explorerUrl = config.explorerUrl
    this.meritsUrl = config.meritsUrl
  }

  // Get transaction details
  async getTransaction(hash: string): Promise<BlockscoutTransaction | null> {
    try {
      const response = await fetch(`${this.baseUrl}/v2/transactions/${hash}`)
      if (!response.ok) return null
      
      const data = await response.json()
      return data
    } catch (error) {
      console.error('Error fetching transaction:', error)
      return null
    }
  }

  // Get address transactions with pagination
  async getAddressTransactions(
    address: string, 
    page = 1, 
    limit = 50
  ): Promise<{
    items: BlockscoutTransaction[]
    next_page_params: any
    total_count: number
  } | null> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        limit: limit.toString(),
      })
      
      const response = await fetch(
        `${this.baseUrl}/v2/addresses/${address}/transactions?${params}`
      )
      
      if (!response.ok) return null
      
      const data = await response.json()
      return data
    } catch (error) {
      console.error('Error fetching address transactions:', error)
      return null
    }
  }

  // Get contract method calls for an address
  async getContractTransactions(
    contractAddress: string,
    userAddress?: string,
    method?: string
  ): Promise<BlockscoutTransaction[]> {
    try {
      const params = new URLSearchParams({
        limit: '100',
      })
      
      if (userAddress) {
        params.append('from', userAddress)
      }
      
      if (method) {
        params.append('method', method)
      }

      const response = await fetch(
        `${this.baseUrl}/v2/addresses/${contractAddress}/transactions?${params}`
      )
      
      if (!response.ok) return []
      
      const data = await response.json()
      return data.items || []
    } catch (error) {
      console.error('Error fetching contract transactions:', error)
      return []
    }
  }

  // Monitor transaction status
  async waitForTransaction(
    hash: string, 
    confirmations = 1,
    timeout = 30000
  ): Promise<BlockscoutTransaction | null> {
    const startTime = Date.now()
    
    while (Date.now() - startTime < timeout) {
      const tx = await this.getTransaction(hash)
      
      if (tx && tx.confirmations >= confirmations) {
        return tx
      }
      
      // Wait 2 seconds before checking again
      await new Promise(resolve => setTimeout(resolve, 2000))
    }
    
    return null
  }

  // Get transaction URL for explorer
  getTransactionUrl(hash: string): string {
    return `${this.explorerUrl}/tx/${hash}`
  }

  // Get address URL for explorer
  getAddressUrl(address: string): string {
    return `${this.explorerUrl}/address/${address}`
  }

  // Categorize transaction based on method and logs
  categorizeTransaction(tx: BlockscoutTransaction): TransactionType {
    const method = tx.decoded_input?.method_call || tx.method || ''
    
    if (method.includes('createMarket')) return 'market_creation'
    if (method.includes('placeBet')) return 'bet_placement'
    if (method.includes('settleMarket')) return 'market_settlement'
    if (method.includes('claimWinnings')) return 'winnings_claim'
    if (method.includes('mint')) return 'fxrp_mint'
    if (method.includes('approve')) return 'fxrp_approve'
    
    return 'other'
  }

  // Get smart contract verification status
  async getContractVerification(address: string): Promise<{
    is_verified: boolean
    name?: string
    compiler_version?: string
    optimization?: boolean
  } | null> {
    try {
      const response = await fetch(`${this.baseUrl}/v2/addresses/${address}`)
      if (!response.ok) return null
      
      const data = await response.json()
      return {
        is_verified: data.is_verified,
        name: data.name,
        compiler_version: data.compiler_version,
        optimization: data.optimization_enabled,
      }
    } catch (error) {
      console.error('Error fetching contract verification:', error)
      return null
    }
  }
}

// Merits API integration
export interface Merit {
  id: string
  address: string
  amount: number
  action_type: string
  timestamp: string
  transaction_hash?: string
  metadata?: {
    market_id?: string
    bet_amount?: string
    position?: string
  }
}

export class MeritsAPI {
  private meritsUrl: string

  constructor(chainId: number) {
    const config = BLOCKSCOUT_APIS[chainId as keyof typeof BLOCKSCOUT_APIS]
    if (!config) {
      throw new Error(`Unsupported chain ID: ${chainId}`)
    }
    
    this.meritsUrl = config.meritsUrl
  }

  // Get user's merit balance
  async getMeritsBalance(address: string): Promise<number> {
    try {
      const response = await fetch(`${this.meritsUrl}/users/${address}/balance`)
      if (!response.ok) return 0
      
      const data = await response.json()
      return data.balance || 0
    } catch (error) {
      console.error('Error fetching merits balance:', error)
      return 0
    }
  }

  // Get user's merit history
  async getMeritsHistory(
    address: string,
    page = 1,
    limit = 20
  ): Promise<Merit[]> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        limit: limit.toString(),
      })
      
      const response = await fetch(
        `${this.meritsUrl}/users/${address}/history?${params}`
      )
      
      if (!response.ok) return []
      
      const data = await response.json()
      return data.items || []
    } catch (error) {
      console.error('Error fetching merits history:', error)
      return []
    }
  }

  // Award merits for specific actions (if we have API access)
  async awardMerits(
    address: string,
    amount: number,
    actionType: string,
    metadata?: Record<string, any>
  ): Promise<boolean> {
    try {
      const response = await fetch(`${this.meritsUrl}/award`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          address,
          amount,
          action_type: actionType,
          metadata,
        }),
      })
      
      return response.ok
    } catch (error) {
      console.error('Error awarding merits:', error)
      return false
    }
  }

  // Get leaderboard
  async getLeaderboard(limit = 10): Promise<Array<{
    address: string
    balance: number
    rank: number
  }>> {
    try {
      const response = await fetch(`${this.meritsUrl}/leaderboard?limit=${limit}`)
      if (!response.ok) return []
      
      const data = await response.json()
      return data.items || []
    } catch (error) {
      console.error('Error fetching leaderboard:', error)
      return []
    }
  }
}

// Utility functions
export const formatTransactionHash = (hash: string): string => {
  return `${hash.slice(0, 6)}...${hash.slice(-4)}`
}

export const formatAddress = (address: string): string => {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

export const getTransactionStatus = (tx: BlockscoutTransaction): 'pending' | 'success' | 'failed' => {
  if (tx.confirmations === 0) return 'pending'
  return tx.status === 'ok' ? 'success' : 'failed'
}

// Real-time transaction monitoring with WebSocket
export class BlockscoutWebSocket {
  private socket: WebSocket | null = null
  private chainId: number
  private listeners: Map<string, Set<(data: any) => void>> = new Map()

  constructor(chainId: number) {
    this.chainId = chainId
  }

  connect(): Promise<void> {
    const config = BLOCKSCOUT_APIS[this.chainId as keyof typeof BLOCKSCOUT_APIS]
    if (!config) {
      throw new Error(`Unsupported chain ID: ${this.chainId}`)
    }

    return new Promise((resolve, reject) => {
      try {
        this.socket = new WebSocket(config.socketUrl)
        
        this.socket.onopen = () => {
          console.log('Blockscout WebSocket connected')
          resolve()
        }
        
        this.socket.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data)
            this.handleMessage(data)
          } catch (error) {
            console.error('Error parsing WebSocket message:', error)
          }
        }
        
        this.socket.onclose = () => {
          console.log('Blockscout WebSocket disconnected')
          this.socket = null
        }
        
        this.socket.onerror = (error) => {
          console.error('Blockscout WebSocket error:', error)
          reject(error)
        }
      } catch (error) {
        reject(error)
      }
    })
  }

  private handleMessage(data: any) {
    const eventType = data.event || data.type
    const listeners = this.listeners.get(eventType)
    
    if (listeners) {
      listeners.forEach(callback => callback(data))
    }
  }

  subscribe(event: string, callback: (data: any) => void) {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set())
    }
    
    this.listeners.get(event)!.add(callback)
    
    // Subscribe to the event via WebSocket
    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      this.socket.send(JSON.stringify({
        topic: event,
        event: 'phx_join',
        payload: {},
        ref: Date.now().toString()
      }))
    }
  }

  unsubscribe(event: string, callback: (data: any) => void) {
    const listeners = this.listeners.get(event)
    if (listeners) {
      listeners.delete(callback)
      
      if (listeners.size === 0) {
        this.listeners.delete(event)
        
        // Unsubscribe from the event via WebSocket
        if (this.socket && this.socket.readyState === WebSocket.OPEN) {
          this.socket.send(JSON.stringify({
            topic: event,
            event: 'phx_leave',
            payload: {},
            ref: Date.now().toString()
          }))
        }
      }
    }
  }

  disconnect() {
    if (this.socket) {
      this.socket.close()
      this.socket = null
    }
    this.listeners.clear()
  }
} 