"""
FastAPI server for ML models
Provides APY prediction and risk assessment endpoints
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, List, Optional
import uvicorn
import sys
import os

# Add current directory to path
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

# Import our ML models - using lazy import to avoid issues
try:
    from apy_predictor import apy_predictor, degen_predictor
    from risk_assessor import risk_assessor
    ML_MODELS_AVAILABLE = True
except ImportError as e:
    print(f"Warning: ML models not available - {e}")
    print("Running in mock mode")
    ML_MODELS_AVAILABLE = False
    apy_predictor = None
    degen_predictor = None
    risk_assessor = None

app = FastAPI(title="DeFi ML Models API", version="1.0.0")

# Enable CORS for Next.js frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:3001"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class PoolData(BaseModel):
    current_apy: float
    tvl: float
    volume_24h: float
    volume_7d: Optional[float] = 0
    token0_volatility: Optional[float] = 0.1
    token1_volatility: Optional[float] = 0.1
    correlation: Optional[float] = 0.5
    is_new_pool: Optional[bool] = False
    emission_rate: Optional[float] = 0
    social_hype: Optional[float] = 0.5
    audit_status: Optional[str] = "unaudited"

class RiskAssessmentRequest(BaseModel):
    pool_data: Dict
    chain: str
    protocol: str

@app.get("/")
def read_root():
    return {"message": "DeFi ML Models API", "status": "running"}

@app.post("/predict/apy")
def predict_apy(pool_data: PoolData):
    """Predict future APY for a pool"""
    try:
        if not ML_MODELS_AVAILABLE or not apy_predictor:
            # Mock prediction when models not available
            base_apy = pool_data.current_apy
            predicted = base_apy * (1 + (pool_data.social_hype - 0.5) * 0.2)
            
            return {
                "success": True,
                "predicted_apy": predicted,
                "confidence_interval": [predicted * 0.8, predicted * 1.2],
                "horizon_days": 7,
                "mock": True
            }
        
        # Convert to dict for predictor
        data = pool_data.dict()
        
        # Get prediction
        result = apy_predictor.predict(data)
        
        return {
            "success": True,
            "predicted_apy": result["predicted_apy"],
            "confidence_interval": result["confidence_interval"],
            "horizon_days": result["horizon_days"]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/predict/degen")
def predict_degen_apy(pool_data: PoolData):
    """Predict APY for degen strategies"""
    try:
        if not ML_MODELS_AVAILABLE or not degen_predictor:
            # Mock degen prediction
            base_apy = pool_data.current_apy
            multiplier = 2.0 if pool_data.is_new_pool else 1.5
            if pool_data.emission_rate > 100:
                multiplier *= 1.5
            
            predicted = base_apy * multiplier
            warnings = []
            if pool_data.audit_status != "audited":
                warnings.append("⚠️ Unaudited protocol - high smart contract risk")
            if pool_data.tvl < 100000:
                warnings.append("⚠️ Low TVL - high liquidity risk")
            
            return {
                "success": True,
                "predicted_apy": predicted,
                "base_apy": base_apy,
                "degen_multiplier": multiplier,
                "risk_level": "EXTREME",
                "warnings": warnings,
                "mock": True
            }
        
        data = pool_data.dict()
        result = degen_predictor.predict_degen(data)
        
        return {
            "success": True,
            "predicted_apy": result["predicted_apy"],
            "base_apy": result["base_apy"],
            "degen_multiplier": result["degen_multiplier"],
            "risk_level": result["risk_level"],
            "warnings": result["warnings"]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/assess/risk")
def assess_risk(request: RiskAssessmentRequest):
    """Comprehensive risk assessment"""
    try:
        if not ML_MODELS_AVAILABLE or not risk_assessor:
            # Mock risk assessment
            tvl = request.pool_data.get("tvl", 0)
            audit_status = request.pool_data.get("audit_status", "unaudited")
            
            # Simple risk scoring
            risk_score = 5.0
            if tvl < 100000:
                risk_score += 3
            elif tvl < 1000000:
                risk_score += 1
            
            if audit_status == "unaudited":
                risk_score += 2
            
            risk_tier = "LOW" if risk_score < 4 else "MEDIUM" if risk_score < 7 else "HIGH"
            
            return {
                "success": True,
                "overall_score": min(risk_score, 10),
                "risk_tier": risk_tier,
                "recommendations": [
                    f"💰 Maximum allocation: {15 if risk_score < 7 else 5}% of portfolio",
                    "⏰ Monitor position daily" if risk_score > 6 else "✅ Stable opportunity"
                ],
                "suitable_for": ["Aggressive", "Degen"] if risk_score < 7 else ["Degen"],
                "max_allocation_percentage": 15 if risk_score < 7 else 5,
                "mock": True
            }
        
        # Prepare data for risk assessor
        opportunity_data = {
            **request.pool_data,
            "chain": request.chain,
            "protocol": request.protocol
        }
        
        # Get risk assessment
        result = risk_assessor.assess_opportunity(opportunity_data)
        
        return {
            "success": True,
            "overall_score": result["overall_score"],
            "risk_tier": result["risk_tier"],
            "recommendations": result["recommendations"],
            "suitable_for": result["suitable_for"],
            "max_allocation_percentage": result["max_allocation_percentage"]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/discover/opportunities")
def discover_opportunities(min_apy: float = 10, max_risk: float = 7):
    """Discover yield opportunities (simulated)"""
    try:
        # Simulated high-yield opportunities
        opportunities = [
            {
                "id": "eth-gmx-staking",
                "chain": "arbitrum",
                "protocol": "GMX",
                "type": "staking",
                "current_apy": 25.5,
                "predicted_apy": 28.3,
                "tvl": 450000000,
                "risk_score": 4.2,
                "description": "GMX staking with esGMX rewards"
            },
            {
                "id": "pendle-steth",
                "chain": "ethereum",
                "protocol": "Pendle",
                "type": "yield-tokenization",
                "current_apy": 12.4,
                "predicted_apy": 14.7,
                "tvl": 280000000,
                "risk_score": 3.8,
                "description": "Pendle stETH yield tokenization"
            },
            {
                "id": "beefy-pancake-bnb-usdt",
                "chain": "bsc",
                "protocol": "Beefy",
                "type": "auto-compound",
                "current_apy": 45.2,
                "predicted_apy": 42.1,
                "tvl": 15000000,
                "risk_score": 5.5,
                "description": "Auto-compounding PancakeSwap LP"
            },
            {
                "id": "convex-frax",
                "chain": "ethereum",
                "protocol": "Convex",
                "type": "curve-boost",
                "current_apy": 18.9,
                "predicted_apy": 20.2,
                "tvl": 890000000,
                "risk_score": 3.2,
                "description": "Boosted Curve FRAX pool"
            },
            {
                "id": "degen-new-protocol",
                "chain": "base",
                "protocol": "NewDegen",
                "type": "liquidity-mining",
                "current_apy": 185.5,
                "predicted_apy": 150.2,
                "tvl": 2500000,
                "risk_score": 8.5,
                "description": "⚠️ HIGH RISK - New protocol with high emissions"
            },
            {
                "id": "leveraged-aave-eth",
                "chain": "polygon",
                "protocol": "Aave",
                "type": "leveraged",
                "current_apy": 35.8,
                "predicted_apy": 38.2,
                "tvl": 120000000,
                "risk_score": 6.2,
                "description": "3x leveraged ETH lending"
            }
        ]
        
        # Filter by criteria
        filtered = [
            opp for opp in opportunities
            if opp["current_apy"] >= min_apy and opp["risk_score"] <= max_risk
        ]
        
        return {
            "success": True,
            "count": len(filtered),
            "opportunities": filtered
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    print("Starting ML Models API Server on http://localhost:8000")
    print("Available endpoints:")
    print("  POST /predict/apy - APY prediction")
    print("  POST /predict/degen - Degen strategy prediction") 
    print("  POST /assess/risk - Risk assessment")
    print("  POST /discover/opportunities - Discover yields")
    uvicorn.run(app, host="0.0.0.0", port=8000)