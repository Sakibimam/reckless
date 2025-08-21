import { yieldDiscoveryEngine } from '@/lib/yield-discovery-engine';
import { NextRequest, NextResponse } from 'next/server';

export async function GET() {
  try {
    // Call Python ML API for opportunities
    const mlResponse = await fetch('http://localhost:8000/discover/opportunities', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ min_apy: 10, max_risk: 10 })
    }).catch(() => null);
    
    if (mlResponse && mlResponse.ok) {
      const mlData = await mlResponse.json();
      return NextResponse.json({
        success: true,
        count: mlData.count,
        opportunities: mlData.opportunities,
        source: 'ml-models',
        timestamp: Date.now()
      });
    }
    
    // Fallback to mock data if ML API is not running
    const mockOpportunities = [
      {
        id: 'aerodrome-weth-usdc',
        chain: 'base',
        protocol: 'Aerodrome',
        type: 'liquidity-pool',
        current_apy: 28.5,
        predicted_apy: 30.2,
        tvl: 45000000,
        risk_score: 4.5,
        description: 'WETH/USDC volatile pool on Aerodrome'
      },
      {
        id: 'aerodrome-stable',
        chain: 'base', 
        protocol: 'Aerodrome',
        type: 'stable-pool',
        current_apy: 12.3,
        predicted_apy: 13.1,
        tvl: 120000000,
        risk_score: 2.8,
        description: 'USDC/DAI stable pool with low IL'
      },
      {
        id: 'gmx-arbitrum',
        chain: 'arbitrum',
        protocol: 'GMX',
        type: 'staking',
        current_apy: 23.8,
        predicted_apy: 25.5,
        tvl: 380000000,
        risk_score: 4.2,
        description: 'GMX staking with multiplier points'
      },
      {
        id: 'pendle-lrt',
        chain: 'ethereum',
        protocol: 'Pendle',
        type: 'yield-tokenization',
        current_apy: 15.7,
        predicted_apy: 18.2,
        tvl: 220000000,
        risk_score: 5.1,
        description: 'Liquid Restaking Token yield trading'
      },
      {
        id: 'degen-base-memecoin',
        chain: 'base',
        protocol: 'DegenFarm',
        type: 'high-risk',
        current_apy: 250.5,
        predicted_apy: 180.2,
        tvl: 1500000,
        risk_score: 9.2,
        description: '⚠️ EXTREME RISK - New memecoin farm'
      }
    ];
    
    return NextResponse.json({
      success: true,
      count: mockOpportunities.length,
      opportunities: mockOpportunities,
      source: 'mock-data',
      timestamp: Date.now()
    });
  } catch (error) {
    console.error('Error discovering opportunities:', error);
    
    return NextResponse.json(
      {
        success: false,
        error: 'Failed to discover yield opportunities',
        message: error instanceof Error ? error.message : 'Unknown error'
      },
      { status: 500 }
    );
  }
}

export async function POST(request: NextRequest) {
  try {
    const { chain, minAPY, maxRisk } = await request.json();
    
    // Discover opportunities with filters
    const allOpportunities = await yieldDiscoveryEngine.discoverOpportunities();
    
    // Apply filters
    const filtered = allOpportunities.filter(opp => {
      const matchesChain = !chain || opp.chain === chain;
      const matchesAPY = !minAPY || opp.currentAPY >= minAPY;
      const matchesRisk = !maxRisk || opp.riskScore <= maxRisk;
      
      return matchesChain && matchesAPY && matchesRisk;
    });
    
    return NextResponse.json({
      success: true,
      count: filtered.length,
      opportunities: filtered.slice(0, 50),
      filters: { chain, minAPY, maxRisk },
      timestamp: Date.now()
    });
  } catch (error) {
    console.error('Error filtering opportunities:', error);
    
    return NextResponse.json(
      {
        success: false,
        error: 'Failed to filter opportunities',
        message: error instanceof Error ? error.message : 'Unknown error'
      },
      { status: 500 }
    );
  }
}