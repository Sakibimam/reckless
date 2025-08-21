# AI-Powered DeFi Yield Optimizer 🚀

An advanced AI-driven platform for discovering and optimizing DeFi yield farming opportunities across multiple chains, with yields ranging from 5% to 250%+ APY.

## 🎯 Features

### Core Capabilities
- **AI-Powered Yield Discovery**: Finds opportunities from 12% stable pools to 250%+ degen farms
- **Multi-Chain Support**: Ethereum, Arbitrum, Base, Polygon, BSC, Avalanche, Fantom
- **Risk Assessment**: Comprehensive 8-category risk analysis with ML models
- **Cross-Chain Aggregation**: Optimal routing through LayerZero, Wormhole, Axelar
- **Real-Time Monitoring**: WebSocket connections for live position tracking
- **Aerodrome Integration**: Direct integration with Aerodrome pools on Base

### Yield Strategies
- **Conservative (5-30% APY)**: Stablecoin lending, blue-chip LPs
- **Moderate (30-100% APY)**: Major token LPs, liquid staking derivatives
- **Aggressive (100-200%+ APY)**: Leveraged farming, new protocol emissions
- **Degen (200%+ APY)**: High-risk opportunities with extreme returns

## 🚀 Quick Start

### Prerequisites
- Node.js 20+
- Python 3.10+
- Anthropic API key (for AI optimization)
- QuickNode endpoint (optional, for live data)

### Installation

1. **Clone the repository**
```bash
git clone <repository-url>
cd ai-powered-defi-yield-optimizer
```

2. **Install frontend dependencies**
```bash
npm install
```

3. **Set up environment variables**
```bash
cp .env.example .env.local
# Edit .env.local with your API keys
```

4. **Start the ML API server**
```bash
cd ml-models
./start_server.sh
```

5. **Start the development server**
```bash
npm run dev
```

Visit http://localhost:3000 to access the application.

## 🐳 Docker Deployment

### Using Docker Compose (Recommended)
```bash
docker-compose up
```

This will start:
- Frontend on http://localhost:3000
- ML API on http://localhost:8000

### Individual Containers
```bash
# Build and run ML API
cd ml-models
docker build -t defi-ml-api .
docker run -p 8000:8000 defi-ml-api

# Build and run frontend
docker build -t defi-frontend .
docker run -p 3000:3000 defi-frontend
```

## 📡 API Endpoints

### Frontend APIs

#### `/api/discover` - Discover Yield Opportunities
Returns top yield farming opportunities across chains.

**Response Example:**
```json
{
  "success": true,
  "opportunities": [{
    "id": "gmx-arbitrum",
    "chain": "arbitrum",
    "protocol": "GMX",
    "current_apy": 25.5,
    "predicted_apy": 28.3,
    "tvl": 450000000,
    "risk_score": 4.2
  }]
}
```

#### `/api/cross-chain` - Cross-Chain Portfolio
Get aggregated portfolio data across chains.

#### `/api/optimize` - AI Optimization
Generate AI-powered portfolio recommendations using Claude.

### ML API Endpoints (Port 8000)

#### `POST /predict/apy` - APY Prediction
Predict future APY using ML models.

#### `POST /predict/degen` - Degen Strategy Prediction
Specialized predictions for high-risk strategies.

#### `POST /assess/risk` - Risk Assessment
Comprehensive risk analysis across 8 categories.

#### `POST /discover/opportunities` - Opportunity Discovery
Find yield opportunities with filtering.

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│            Frontend (Next.js)           │
│   • Pool Overview  • Risk Assessment    │
│   • Strategy Results • AI Integration   │
└────────────────┬───────────────────────┘
                 │
      ┌──────────┴──────────┐
      │                     │
┌─────▼──────┐    ┌─────────▼──────────┐
│  AI APIs   │    │   ML Models API    │
│ • Claude   │    │ • APY Prediction   │
│ • QuickNode│    │ • Risk Assessment  │
└────────────┘    │ • Degen Strategies │
                  └────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
┌───────▼────────┐ ┌──────▼──────┐ ┌─────────▼──────┐
│ Yield Discovery│ │Cross-Chain  │ │  Real-Time     │
│     Engine     │ │ Aggregator  │ │   Monitor      │
└────────────────┘ └─────────────┘ └────────────────┘
```

## 📁 Project Structure

```
ai-powered-defi-yield-optimizer/
├── app/                    # Next.js app directory
│   ├── api/               # API routes
│   └── page.tsx           # Main UI
├── components/            # React components
├── lib/                   # Core libraries
│   ├── yield-discovery-engine.ts
│   ├── cross-chain-aggregator.ts
│   └── real-time-monitor.ts
├── ml-models/            # Python ML models
│   ├── apy_predictor.py
│   ├── risk_assessor.py
│   └── api_server.py
└── types/                # TypeScript types
```

## 🔧 Configuration

### Environment Variables

```env
# Required
ANTHROPIC_API_KEY=your_claude_api_key

# Optional (for live data)
NEXT_PUBLIC_QUICKNODE_ENDPOINT=your_quicknode_endpoint

# Chain RPC URLs
ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your-key
ARB_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/your-key
# ... more chains

# ML API Configuration
ML_API_URL=http://localhost:8000
```

## 🧪 Testing

```bash
# Run frontend tests
npm test

# Test ML API
cd ml-models
python -m pytest

# Integration tests
npm run test:integration
```

## 🚢 Production Deployment

### Using Vercel (Frontend)
```bash
vercel deploy
```

### Using Cloud Run (ML API)
```bash
gcloud run deploy defi-ml-api \
  --source=./ml-models \
  --port=8000 \
  --allow-unauthenticated
```

### Environment Setup
1. Set production API keys
2. Configure CORS for your domain
3. Enable rate limiting
4. Set up monitoring (recommended: Datadog, New Relic)

## 🛡️ Security Considerations

- **API Keys**: Never commit API keys to version control
- **Smart Contract Audits**: Always verify protocol audits
- **Risk Management**: Never invest more than you can afford to lose
- **DYOR**: This tool provides suggestions, not financial advice

## 📊 Performance

- **Response Time**: <500ms for API calls
- **ML Prediction Accuracy**: ~75% for 7-day APY predictions
- **Cross-Chain Routing**: Optimizes for lowest gas costs
- **Real-Time Updates**: WebSocket connections for live data

## 🤝 Contributing

We welcome contributions! Please see CONTRIBUTING.md for guidelines.

## 📄 License

MIT License - see LICENSE file for details.

## ⚠️ Disclaimer

This tool is for educational purposes only. DeFi investments carry significant risks including:
- Smart contract vulnerabilities
- Impermanent loss
- Protocol exploits
- Market volatility

Always do your own research and never invest more than you can afford to lose.

## 🔗 Resources

- [Aerodrome Documentation](https://docs.aerodrome.finance)
- [QuickNode API](https://www.quicknode.com)
- [Anthropic Claude](https://www.anthropic.com)
- [DeFi Safety](https://defisafety.com)

## 📞 Support

- GitHub Issues: [Report bugs](https://github.com/your-repo/issues)
- Discord: [Join our community](https://discord.gg/your-discord)
- Twitter: [@YourHandle](https://twitter.com/your-handle)

---

Built with ❤️ by the DeFi community