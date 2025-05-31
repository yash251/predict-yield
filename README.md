# PredictYield - DeFi Prediction Market Platform

A DeFi prediction market platform on Flare blockchain where users stake $FXRP (synthetic XRP via FAssets) to bet on future yield rates of DeFi pools.

## 🎯 Project Overview

PredictYield leverages Flare's unique infrastructure to create transparent, verifiable prediction markets:

- **FAssets Integration**: Mint and stake $FXRP (synthetic XRP)
- **FTSOv2**: Real-time yield data feeds (updates every ~1.8 seconds, free querying)
- **FDC JsonApi**: External DeFi yield data validation via Merkle proofs
- **Secure Random**: Fair, verifiable randomness for market settlement
- **Blockscout**: Transaction transparency and Merits rewards

## 🏗️ Architecture

```
├── contracts/          # Solidity smart contracts (Foundry)
│   ├── src/            # Contract source files
│   ├── test/           # Contract tests
│   └── script/         # Deployment scripts
└── frontend/           # Next.js TypeScript frontend
    ├── src/            # Frontend source
    ├── components/     # React components
    └── lib/            # Utilities and configurations
```

## 🚀 Technology Stack

### Smart Contracts
- **Framework**: Foundry
- **Language**: Solidity
- **Network**: Flare Coston2 Testnet
- **Oracles**: FTSOv2 + FDC

### Frontend
- **Framework**: Next.js 15 with TypeScript
- **Styling**: Tailwind CSS
- **Web3**: Wagmi + Viem
- **Authentication**: Privy
- **State Management**: TanStack Query

## 🛠️ Development Setup

### Prerequisites
- Node.js 18+
- Foundry
- Git

### Installation

1. **Clone and install dependencies:**
```bash
git clone <repo-url>
cd ethglobal-prague

# Install frontend dependencies
cd frontend
npm install --legacy-peer-deps

# Install contract dependencies
cd ../contracts
forge install
```

2. **Environment Configuration:**
```bash
# Frontend environment
cp frontend/.env.example frontend/.env.local

# Add your configuration:
# NEXT_PUBLIC_PRIVY_APP_ID=your_privy_app_id
# NEXT_PUBLIC_RPC_URL=https://coston2-api.flare.network/ext/bc/C/rpc
```

3. **Start Development:**
```bash
# Frontend (in frontend/)
npm run dev

# Contracts (in contracts/)
forge test
forge script script/Deploy.s.sol --rpc-url coston2
```

## 🔧 Key Features

- **Real-time Yield Prediction**: Bet on future DeFi yield rates
- **Multi-Oracle Validation**: FTSOv2 + FDC consensus for accurate data
- **Verifiable Randomness**: Fair market settlement using Flare's Secure Random
- **Cost-Effective**: Free FTSOv2 queries + efficient FDC Merkle proofs
- **Transparent**: Full transaction history via Blockscout integration
- **Gamified**: Merits rewards for platform participation

## 📊 Demo Flow

1. **Connect Wallet** (Privy authentication)
2. **Mint $FXRP** (FAssets integration)
3. **Browse Markets** (Real-time yield data from FTSOv2)
4. **Place Bets** (Stake $FXRP on yield predictions)
5. **Settlement** (Secure Random + Multi-oracle consensus)
6. **Rewards** (Winnings + Blockscout Merits)

## 🔒 Security

- Network-level data validation (50%+ signature weight)
- Comprehensive smart contract testing
- Multi-oracle consensus for settlement
- Verifiable randomness for fair markets

## 📝 License

MIT License - Built for ETHGlobal Prague 2025 