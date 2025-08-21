/**
 * GET /api/vault/positions - Get user's vault positions
 */

import { NextRequest, NextResponse } from 'next/server';
import { vaultService } from '@/lib/vault/vaultService';
import { priceService } from '@/lib/vault/priceService';
import type { 
  VaultApiResponse, 
  UserVaultSummary,
  VaultPosition 
} from '@/types/vault';

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const userAddress = searchParams.get('userAddress');
    const includeHistory = searchParams.get('includeHistory') === 'true';
    const chain = searchParams.get('chain'); // Filter by chain
    const protocol = searchParams.get('protocol'); // Filter by protocol
    
    if (!userAddress) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Missing user address',
        message: 'userAddress parameter is required',
        timestamp: Date.now()
      }, { status: 400 });
    }
    
    // Validate Ethereum address format
    if (!/^0x[a-fA-F0-9]{40}$/.test(userAddress)) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Invalid address format',
        message: 'userAddress must be a valid Ethereum address',
        timestamp: Date.now()
      }, { status: 400 });
    }
    
    console.log(`Fetching positions for ${userAddress}${chain ? ` on ${chain}` : ''}${protocol ? ` from ${protocol}` : ''}`);
    
    // Get user positions
    let positions = await vaultService.getUserPositions(userAddress);
    
    // Apply filters
    if (chain) {
      positions = positions.filter(p => p.chain.toLowerCase() === chain.toLowerCase());
    }
    
    if (protocol) {
      positions = positions.filter(p => p.protocol.toLowerCase() === protocol.toLowerCase());
    }
    
    // Get user vault summary
    const summary = await vaultService.getUserVaultSummary(userAddress);
    
    // Calculate additional metrics
    const totalPnL = BigInt(summary.totalPnL);
    const totalValue = BigInt(summary.totalValue);
    
    const performanceMetrics = {
      totalROI: Number(summary.totalPnL) / (Number(summary.totalValue) - Number(summary.totalPnL)) * 100,
      bestPosition: positions.length > 0 
        ? positions.reduce((best, current) => 
            current.pnlPercentage > best.pnlPercentage ? current : best
          )
        : null,
      worstPosition: positions.length > 0
        ? positions.reduce((worst, current) => 
            current.pnlPercentage < worst.pnlPercentage ? current : worst
          )
        : null,
      activeStrategies: [...new Set(positions.map(p => p.strategy.name))].length,
      averagePositionAge: positions.length > 0
        ? positions.reduce((sum, p) => sum + (Date.now() - p.depositTimestamp), 0) / positions.length / (1000 * 60 * 60 * 24) // days
        : 0
    };
    
    // Add historical performance if requested
    let historicalPerformance = undefined;
    if (includeHistory && positions.length > 0) {
      historicalPerformance = await generateHistoricalPerformance(positions);
    }
    
    const response = {
      summary: {
        ...summary,
        performanceMetrics,
        historicalPerformance
      },
      positions: positions.map(position => ({
        ...position,
        // Add calculated fields
        daysHeld: Math.floor((Date.now() - position.depositTimestamp) / (1000 * 60 * 60 * 24)),
        annualizedReturn: position.apy, // Current APY of the strategy
        valueAtRisk: calculateValueAtRisk(position),
        liquidityScore: calculateLiquidityScore(position)
      })),
      filters: {
        chain: chain || 'all',
        protocol: protocol || 'all'
      },
      metadata: {
        totalPositions: positions.length,
        totalFiltered: positions.length,
        totalUnfiltered: summary.totalPositions,
        lastUpdated: Math.max(...positions.map(p => p.lastUpdateTimestamp), 0)
      }
    };
    
    return NextResponse.json<VaultApiResponse<typeof response>>({
      success: true,
      data: response,
      message: `Found ${positions.length} position${positions.length !== 1 ? 's' : ''}`,
      timestamp: Date.now()
    });
    
  } catch (error) {
    console.error('Positions API error:', error);
    
    return NextResponse.json<VaultApiResponse<null>>({
      success: false,
      error: 'Failed to fetch positions',
      message: error instanceof Error ? error.message : 'Unknown error occurred',
      timestamp: Date.now()
    }, { status: 500 });
  }
}

// POST endpoint for position actions (compound, harvest, etc.)
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action, positionId, userAddress } = body;
    
    if (!action || !positionId || !userAddress) {
      return NextResponse.json({
        success: false,
        error: 'Missing required fields',
        message: 'action, positionId, and userAddress are required'
      }, { status: 400 });
    }
    
    // Validate user owns the position
    const positions = await vaultService.getUserPositions(userAddress);
    const position = positions.find(p => p.id === positionId);
    
    if (!position) {
      return NextResponse.json({
        success: false,
        error: 'Position not found',
        message: `Position ${positionId} not found for user ${userAddress}`
      }, { status: 404 });
    }
    
    let result;
    
    switch (action) {
      case 'compound':
        // Compound rewards back into the position
        result = await compoundPosition(position);
        break;
        
      case 'harvest':
        // Harvest rewards to user wallet
        result = await harvestRewards(position);
        break;
        
      case 'rebalance':
        // Rebalance position if strategy supports it
        result = await rebalancePosition(position, body.targetAllocation);
        break;
        
      default:
        return NextResponse.json({
          success: false,
          error: 'Invalid action',
          message: `Action "${action}" is not supported`
        }, { status: 400 });
    }
    
    return NextResponse.json({
      success: true,
      data: result,
      message: `${action} completed successfully`,
      timestamp: Date.now()
    });
    
  } catch (error) {
    console.error('Position action error:', error);
    
    return NextResponse.json({
      success: false,
      error: 'Action failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 });
  }
}

// Helper functions
async function generateHistoricalPerformance(positions: VaultPosition[]) {
  // Generate mock historical performance data
  // In production, this would query actual historical data
  const days = 30;
  const historical = [];
  
  for (let i = days; i >= 0; i--) {
    const timestamp = Date.now() - (i * 24 * 60 * 60 * 1000);
    let totalValue = 0;
    
    for (const position of positions) {
      // Simulate historical growth based on APY
      const daysSinceDeposit = Math.max(0, (timestamp - position.depositTimestamp) / (1000 * 60 * 60 * 24));
      const growth = Math.pow(1 + position.apy / 100 / 365, daysSinceDeposit);
      totalValue += Number(position.depositAmount) * growth;
    }
    
    historical.push({
      timestamp,
      totalValue: totalValue.toString(),
      pnl: (totalValue - positions.reduce((sum, p) => sum + Number(p.depositAmount), 0)).toString(),
      pnlPercentage: totalValue > 0 
        ? ((totalValue - positions.reduce((sum, p) => sum + Number(p.depositAmount), 0)) / positions.reduce((sum, p) => sum + Number(p.depositAmount), 0)) * 100
        : 0
    });
  }
  
  return historical;
}

function calculateValueAtRisk(position: VaultPosition): number {
  // Calculate Value at Risk (VaR) based on strategy risk and volatility
  const volatility = 0.15; // 15% assumed volatility
  const confidence = 0.95; // 95% confidence interval
  const zScore = 1.645; // Z-score for 95% confidence
  
  const currentValue = Number(position.currentValue);
  const var95 = currentValue * volatility * zScore;
  
  return Math.round(var95);
}

function calculateLiquidityScore(position: VaultPosition): number {
  // Calculate liquidity score based on strategy type and lockup
  let score = 100;
  
  // Reduce score for lockup periods
  if (position.strategy.type === 'staking') {
    score -= 20; // Staking typically has some lockup
  }
  
  // Reduce score for complex strategies
  if (position.strategy.type === 'options' || position.strategy.type === 'perpetuals') {
    score -= 30; // More complex exit mechanisms
  }
  
  // Reduce score for smaller protocols (higher risk of liquidity issues)
  const protocolLiquidity = {
    'Aerodrome': 95,
    'GMX': 90,
    'Pendle': 85,
    'Uniswap': 98,
    'Aave': 95
  };
  
  const protocolScore = protocolLiquidity[position.protocol as keyof typeof protocolLiquidity] || 70;
  score = Math.min(score, protocolScore);
  
  return Math.max(0, Math.min(100, score));
}

async function compoundPosition(position: VaultPosition) {
  // Mock compound implementation
  console.log(`Compounding position ${position.id}`);
  
  return {
    transactionId: `compound_${Date.now()}`,
    compoundedAmount: '0', // Would calculate actual rewards
    newShares: '0',
    gasUsed: '150000'
  };
}

async function harvestRewards(position: VaultPosition) {
  // Mock harvest implementation
  console.log(`Harvesting rewards for position ${position.id}`);
  
  return {
    transactionId: `harvest_${Date.now()}`,
    harvestedRewards: position.strategy.type === 'staking' ? ['100'] : ['50', '25'], // Mock rewards
    rewardTokens: position.strategy.type === 'staking' ? ['GMX'] : ['AERO', 'ETH'],
    gasUsed: '100000'
  };
}

async function rebalancePosition(position: VaultPosition, targetAllocation?: any) {
  // Mock rebalance implementation
  console.log(`Rebalancing position ${position.id}`);
  
  return {
    transactionId: `rebalance_${Date.now()}`,
    oldAllocation: { strategy: 100 },
    newAllocation: targetAllocation || { strategy: 100 },
    gasUsed: '200000'
  };
}