/**
 * GET /api/vault/estimate - Estimate returns for deposits
 */

import { NextRequest, NextResponse } from 'next/server';
import { vaultService } from '@/lib/vault/vaultService';
import { strategyService } from '@/lib/vault/strategyService';
import { crossChainService } from '@/lib/vault/crossChainService';
import { priceService } from '@/lib/vault/priceService';
import type { 
  VaultApiResponse, 
  VaultEstimate,
  DepositRequest 
} from '@/types/vault';

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const amount = searchParams.get('amount');
    const token = searchParams.get('token');
    const strategyId = searchParams.get('strategyId');
    const fromChain = searchParams.get('fromChain');
    const toChain = searchParams.get('toChain');
    const timeHorizon = searchParams.get('timeHorizon'); // days
    const compoundFrequency = searchParams.get('compoundFrequency') || 'daily';
    
    // Validate required parameters
    if (!amount || !token || !strategyId || !fromChain || !toChain) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Missing required parameters',
        message: 'amount, token, strategyId, fromChain, and toChain are required',
        timestamp: Date.now()
      }, { status: 400 });
    }
    
    // Validate amount
    let depositAmount: bigint;
    try {
      depositAmount = BigInt(amount);
      if (depositAmount <= 0) {
        throw new Error('Amount must be positive');
      }
    } catch (error) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Invalid amount',
        message: 'Amount must be a valid positive number',
        timestamp: Date.now()
      }, { status: 400 });
    }
    
    // Get strategy details
    const strategy = await strategyService.getStrategy(strategyId);
    if (!strategy) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Strategy not found',
        message: `Strategy ${strategyId} does not exist`,
        timestamp: Date.now()
      }, { status: 404 });
    }
    
    // Check strategy limits
    if (depositAmount < BigInt(strategy.minDeposit)) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Amount below minimum',
        message: `Minimum deposit is ${strategy.minDeposit} ${token}`,
        timestamp: Date.now()
      }, { status: 400 });
    }
    
    if (depositAmount > BigInt(strategy.maxDeposit)) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Amount above maximum',
        message: `Maximum deposit is ${strategy.maxDeposit} ${token}`,
        timestamp: Date.now()
      }, { status: 400 });
    }
    
    console.log(`Estimating deposit: ${amount} ${token} to ${strategy.name} (${fromChain} -> ${toChain})`);
    
    // Create mock deposit request for estimation
    const mockRequest: DepositRequest = {
      amount,
      token,
      strategyId,
      fromChain,
      toChain,
      userAddress: '0x0000000000000000000000000000000000000000', // Mock for estimation
      slippageTolerance: 0.5,
      deadline: Date.now() + 300000, // 5 minutes
      minReceived: (depositAmount * BigInt(995) / BigInt(1000)).toString() // 0.5% slippage
    };
    
    // Get basic estimate
    const baseEstimate = await vaultService.estimateDeposit(mockRequest, strategy);
    
    // Get token price for USD calculations
    const tokenPrice = await priceService.getPrice(token);
    const usdValue = Number(amount) * tokenPrice;
    
    // Calculate extended projections
    const projections = calculateProjections(
      strategy,
      Number(amount),
      tokenPrice,
      timeHorizon ? parseInt(timeHorizon) : 365,
      compoundFrequency
    );
    
    // Get cross-chain route details if needed
    let crossChainDetails = undefined;
    if (fromChain !== toChain) {
      try {
        const route = await crossChainService.findOptimalRoute(fromChain, toChain, amount, strategy.protocol);
        crossChainDetails = {
          route,
          alternativeRoutes: await getAlternativeRoutes(fromChain, toChain, amount),
          estimatedTime: route.estimatedTime,
          reliability: route.reliability
        };
      } catch (error) {
        console.warn('Failed to get cross-chain route:', error);
      }
    }
    
    // Calculate price impact
    const priceImpact = await priceService.getPriceImpact(token, 'USDC', amount, toChain);
    
    // Get market context
    const marketContext = await getMarketContext(strategy, token);
    
    // Build comprehensive estimate response
    const extendedEstimate = {
      ...baseEstimate,
      
      // USD values
      usdAmounts: {
        deposit: usdValue,
        expectedYearlyReturn: Number(baseEstimate.estimatedYearlyReturn) * tokenPrice,
        expectedDailyReturn: Number(baseEstimate.estimatedDailyReturn) * tokenPrice,
        totalFees: Number(baseEstimate.fees.total) * tokenPrice
      },
      
      // Time-based projections
      projections,
      
      // Cross-chain details
      crossChain: crossChainDetails,
      
      // Market conditions
      marketConditions: {
        tokenPrice,
        priceImpact,
        volatility: strategy.historical.volatility,
        marketTrend: marketContext.trend,
        liquidityDepth: marketContext.liquidity
      },
      
      // Strategy-specific metrics
      strategyMetrics: {
        currentTVL: strategy.tvl,
        capacity: strategy.maxCapacity,
        utilizationAfterDeposit: ((Number(strategy.tvl) + Number(amount)) / Number(strategy.maxCapacity)) * 100,
        averageDepositSize: calculateAverageDepositSize(strategy),
        yourPositionSize: (Number(amount) / Number(strategy.tvl)) * 100
      },
      
      // Risk assessment
      riskAssessment: {
        ...baseEstimate.risks,
        riskLevel: strategy.riskLevel,
        historicalDrawdown: strategy.historical.maxDrawdown,
        liquidationRisk: calculateLiquidationRisk(strategy),
        concentrationRisk: calculateConcentrationRisk(strategy, Number(amount))
      },
      
      // Alternative strategies
      alternatives: await getAlternativeStrategies(strategy, Number(amount)),
      
      // Optimal entry timing
      timing: {
        currentScore: calculateTimingScore(strategy, marketContext),
        recommendation: 'good', // good, excellent, wait, caution
        reasoning: generateTimingRecommendation(strategy, marketContext),
        nextRebalanceDate: Date.now() + (7 * 24 * 60 * 60 * 1000) // 7 days
      }
    };
    
    return NextResponse.json<VaultApiResponse<typeof extendedEstimate>>({
      success: true,
      data: extendedEstimate,
      message: `Estimate calculated for ${amount} ${token} deposit`,
      timestamp: Date.now()
    });
    
  } catch (error) {
    console.error('Estimate API error:', error);
    
    return NextResponse.json<VaultApiResponse<null>>({
      success: false,
      error: 'Estimation failed',
      message: error instanceof Error ? error.message : 'Unknown error occurred',
      timestamp: Date.now()
    }, { status: 500 });
  }
}

// POST endpoint for batch estimates
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { estimates } = body;
    
    if (!Array.isArray(estimates) || estimates.length === 0) {
      return NextResponse.json({
        success: false,
        error: 'Invalid request',
        message: 'estimates array is required'
      }, { status: 400 });
    }
    
    if (estimates.length > 10) {
      return NextResponse.json({
        success: false,
        error: 'Too many estimates',
        message: 'Maximum 10 estimates per batch request'
      }, { status: 400 });
    }
    
    // Process all estimates in parallel
    const results = await Promise.allSettled(
      estimates.map(async (est: any) => {
        const strategy = await strategyService.getStrategy(est.strategyId);
        if (!strategy) {
          throw new Error(`Strategy ${est.strategyId} not found`);
        }
        
        const mockRequest: DepositRequest = {
          amount: est.amount,
          token: est.token || 'USDC',
          strategyId: est.strategyId,
          fromChain: est.fromChain || 'ethereum',
          toChain: est.toChain || 'ethereum',
          userAddress: '0x0000000000000000000000000000000000000000',
          slippageTolerance: 0.5,
          deadline: Date.now() + 300000,
          minReceived: (BigInt(est.amount) * BigInt(995) / BigInt(1000)).toString()
        };
        
        const estimate = await vaultService.estimateDeposit(mockRequest, strategy);
        
        return {
          strategyId: est.strategyId,
          strategyName: strategy.name,
          estimate
        };
      })
    );
    
    // Process results
    const successful = results
      .filter((result): result is PromiseFulfilledResult<any> => result.status === 'fulfilled')
      .map(result => result.value);
      
    const failed = results
      .filter((result): result is PromiseRejectedResult => result.status === 'rejected')
      .map(result => result.reason.message);
    
    // Find best options
    const bestAPY = successful.reduce((best, current) => 
      current.estimate.expectedAPY > best.estimate.expectedAPY ? current : best, successful[0]
    );
    
    const bestRiskAdjusted = successful.reduce((best, current) => {
      const currentScore = current.estimate.expectedAPY / (1 + current.estimate.risks.overall);
      const bestScore = best.estimate.expectedAPY / (1 + best.estimate.risks.overall);
      return currentScore > bestScore ? current : best;
    }, successful[0]);
    
    return NextResponse.json({
      success: true,
      data: {
        estimates: successful,
        summary: {
          total: estimates.length,
          successful: successful.length,
          failed: failed.length,
          failedReasons: failed
        },
        recommendations: {
          highest_apy: bestAPY,
          best_risk_adjusted: bestRiskAdjusted,
          lowest_fees: successful.reduce((best, current) => 
            Number(current.estimate.fees.total) < Number(best.estimate.fees.total) ? current : best, successful[0]
          )
        }
      },
      timestamp: Date.now()
    });
    
  } catch (error) {
    console.error('Batch estimate error:', error);
    
    return NextResponse.json({
      success: false,
      error: 'Batch estimation failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 });
  }
}

// Helper functions
function calculateProjections(
  strategy: any,
  amount: number,
  tokenPrice: number,
  days: number,
  compoundFrequency: string
) {
  const dailyAPY = strategy.currentAPY / 365 / 100;
  const compoundPeriods = {
    'daily': 365,
    'weekly': 52,
    'monthly': 12,
    'quarterly': 4
  };
  
  const periodsPerYear = compoundPeriods[compoundFrequency as keyof typeof compoundPeriods] || 365;
  const periodAPY = strategy.currentAPY / periodsPerYear / 100;
  
  const projections = [];
  
  // Calculate projections for different time periods
  const periods = [7, 30, 90, 180, 365, 730]; // days
  
  for (const period of periods) {
    if (period > days) continue;
    
    const periodsElapsed = (period / 365) * periodsPerYear;
    const compoundedAmount = amount * Math.pow(1 + periodAPY, periodsElapsed);
    const profit = compoundedAmount - amount;
    
    projections.push({
      days: period,
      amount: compoundedAmount.toString(),
      profit: profit.toString(),
      profitUSD: (profit * tokenPrice).toString(),
      apy: ((compoundedAmount / amount - 1) * (365 / period) * 100),
      breakeven: period < 30 // Most strategies breakeven within 30 days
    });
  }
  
  return {
    projections,
    compoundFrequency,
    assumptions: {
      constantAPY: strategy.currentAPY,
      noFeeChanges: true,
      noStrategyChanges: true,
      reinvestmentRate: strategy.autoCompound ? 100 : 0
    }
  };
}

async function getAlternativeRoutes(fromChain: string, toChain: string, amount: string) {
  try {
    const bridges = crossChainService.getAvailableBridges(fromChain, toChain);
    return bridges.slice(0, 3).map(bridge => ({
      name: bridge.name,
      estimatedTime: bridge.estimateTime(fromChain, toChain),
      reliability: bridge.reliability,
      estimatedFee: '5000' // Mock fee
    }));
  } catch (error) {
    return [];
  }
}

async function getMarketContext(strategy: any, token: string) {
  // Mock market context - in production would fetch real data
  return {
    trend: Math.random() > 0.5 ? 'bullish' : 'bearish',
    liquidity: Math.random() * 100000000, // Mock liquidity depth
    volatility: strategy.historical.volatility,
    sentiment: Math.random() > 0.6 ? 'positive' : 'neutral',
    technicalIndicators: {
      rsi: 45 + Math.random() * 20, // 45-65 range
      macdSignal: Math.random() > 0.5 ? 'buy' : 'sell'
    }
  };
}

function calculateAverageDepositSize(strategy: any): number {
  // Mock calculation - in production would use real data
  return Number(strategy.tvl) / 1000; // Assume 1000 positions
}

function calculateLiquidationRisk(strategy: any): number {
  // Risk based on strategy type and market conditions
  const baseRisk = {
    'lending': 2,
    'liquidity': 5,
    'staking': 1,
    'yield-farming': 7,
    'options': 15,
    'perpetuals': 20
  }[strategy.type] || 5;
  
  return Math.min(baseRisk * (strategy.riskScore / 5), 100);
}

function calculateConcentrationRisk(strategy: any, depositAmount: number): number {
  const positionSize = (depositAmount / Number(strategy.tvl)) * 100;
  
  if (positionSize > 10) return 8; // High concentration
  if (positionSize > 5) return 5;  // Medium concentration
  if (positionSize > 1) return 2;  // Low concentration
  return 1; // Minimal concentration
}

async function getAlternativeStrategies(currentStrategy: any, amount: number) {
  try {
    const alternatives = await strategyService.discoverAllStrategies({
      chains: [currentStrategy.chain],
      minAPY: Math.max(5, currentStrategy.currentAPY - 10), // Within 10% APY
      maxRisk: currentStrategy.riskScore + 2 // Similar risk level
    });
    
    return alternatives
      .filter(s => s.id !== currentStrategy.id) // Exclude current strategy
      .filter(s => Number(s.minDeposit) <= amount && Number(s.maxDeposit) >= amount)
      .slice(0, 3) // Top 3 alternatives
      .map(s => ({
        id: s.id,
        name: s.name,
        protocol: s.protocol,
        currentAPY: s.currentAPY,
        riskScore: s.riskScore,
        comparison: {
          apyDifference: s.currentAPY - currentStrategy.currentAPY,
          riskDifference: s.riskScore - currentStrategy.riskScore,
          recommendation: s.currentAPY > currentStrategy.currentAPY ? 'better' : 'similar'
        }
      }));
  } catch (error) {
    return [];
  }
}

function calculateTimingScore(strategy: any, marketContext: any): number {
  let score = 50; // Neutral
  
  // APY trend
  if (strategy.currentAPY > strategy.historical.apy30d) score += 15;
  if (strategy.currentAPY < strategy.historical.apy30d) score -= 10;
  
  // Market conditions
  if (marketContext.trend === 'bullish') score += 10;
  if (marketContext.sentiment === 'positive') score += 10;
  
  // Capacity utilization
  const utilization = Number(strategy.tvl) / Number(strategy.maxCapacity);
  if (utilization < 0.5) score += 10; // Low utilization is good for entry
  if (utilization > 0.8) score -= 15; // High utilization may limit returns
  
  return Math.max(0, Math.min(100, score));
}

function generateTimingRecommendation(strategy: any, marketContext: any): string[] {
  const recommendations = [];
  
  if (strategy.currentAPY > strategy.historical.apy30d) {
    recommendations.push('Strategy APY is trending upward');
  }
  
  if (Number(strategy.tvl) / Number(strategy.maxCapacity) < 0.5) {
    recommendations.push('Low capacity utilization allows for better returns');
  }
  
  if (marketContext.trend === 'bullish') {
    recommendations.push('Favorable market conditions for growth strategies');
  }
  
  if (strategy.riskScore < 4) {
    recommendations.push('Low-risk strategy suitable for current market volatility');
  }
  
  return recommendations.length > 0 ? recommendations : ['Market conditions are neutral for entry'];
}