/**
 * GET /api/vault/strategies - Get active strategies and APYs
 */

import { NextRequest, NextResponse } from 'next/server';
import { strategyService } from '@/lib/vault/strategyService';
import { yieldDiscoveryEngine } from '@/lib/yield-discovery-engine';
import type { 
  VaultApiResponse, 
  VaultStrategy 
} from '@/types/vault';

// Initialize mock strategies on service start
strategyService.initializeMockStrategies();

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const chain = searchParams.get('chain');
    const minAPY = searchParams.get('minAPY') ? parseFloat(searchParams.get('minAPY')!) : undefined;
    const maxRisk = searchParams.get('maxRisk') ? parseFloat(searchParams.get('maxRisk')!) : undefined;
    const protocols = searchParams.get('protocols')?.split(',');
    const types = searchParams.get('types')?.split(',');
    const sortBy = searchParams.get('sortBy') || 'riskAdjustedAPY'; // riskAdjustedAPY, apy, risk, tvl
    const limit = searchParams.get('limit') ? parseInt(searchParams.get('limit')!) : 50;
    const riskTolerance = searchParams.get('riskTolerance') as 'conservative' | 'moderate' | 'aggressive' | 'degen' || undefined;
    
    console.log(`Fetching strategies with filters:`, {
      chain,
      minAPY,
      maxRisk,
      protocols,
      types,
      sortBy,
      limit,
      riskTolerance
    });
    
    // Get strategies with filters
    const strategies = await strategyService.discoverAllStrategies({
      chains: chain ? [chain] : undefined,
      minAPY,
      maxRisk,
      protocols,
      types
    });
    
    // Get additional opportunities from yield discovery engine
    let additionalOpportunities: any[] = [];
    try {
      const opportunities = await yieldDiscoveryEngine.discoverOpportunities();
      // Convert opportunities to strategy format
      additionalOpportunities = opportunities.slice(0, 10).map(opp => ({
        id: opp.id,
        name: `${opp.protocol} ${opp.tokenPair[0]}/${opp.tokenPair[1]}`,
        protocol: opp.protocol,
        chain: opp.chain,
        type: 'liquidity' as const,
        description: `${opp.tokenPair[0]}/${opp.tokenPair[1]} liquidity provision on ${opp.protocol}`,
        currentAPY: opp.currentAPY,
        predictedAPY: opp.predictedAPY,
        tvl: opp.tvl.toString(),
        maxCapacity: (opp.tvl * 2).toString(),
        utilizationRate: 0.5,
        riskScore: opp.riskScore,
        riskLevel: opp.riskScore < 3 ? 'low' : opp.riskScore < 6 ? 'medium' : 'high' as const,
        minDeposit: '100',
        maxDeposit: '1000000',
        depositFee: 0.1,
        withdrawalFee: 0.1,
        performanceFee: 10,
        managementFee: 2,
        autoCompound: true,
        lockupPeriod: 0,
        impermanentLossRisk: 5,
        smartContractRisk: 4,
        liquidityRisk: 3,
        assets: {
          primary: opp.tokenPair[0],
          secondary: opp.tokenPair[1]
        },
        rewards: {
          tokens: ['AERO'],
          emissions: ['100'],
          claimable: true
        },
        historical: {
          apy7d: opp.currentAPY * 0.9,
          apy30d: opp.currentAPY * 1.1,
          maxDrawdown: 5,
          volatility: 15
        },
        lastUpdated: Date.now()
      }));
    } catch (error) {
      console.warn('Failed to fetch additional opportunities:', error);
    }
    
    // Combine strategies and opportunities (remove duplicates by protocol + chain)
    const allStrategies = [...strategies];
    const existingKeys = new Set(strategies.map(s => `${s.protocol.toLowerCase()}-${s.chain.toLowerCase()}`));
    
    for (const opp of additionalOpportunities) {
      const key = `${opp.protocol.toLowerCase()}-${opp.chain.toLowerCase()}`;
      if (!existingKeys.has(key)) {
        allStrategies.push(opp);
        existingKeys.add(key);
      }
    }
    
    // Apply risk tolerance filter if provided
    let filteredStrategies = allStrategies;
    if (riskTolerance) {
      const riskLimits = {
        conservative: 3,
        moderate: 5,
        aggressive: 7,
        degen: 10
      };
      filteredStrategies = allStrategies.filter(s => s.riskScore <= riskLimits[riskTolerance]);
    }
    
    // Apply sorting
    const sortedStrategies = sortStrategies(filteredStrategies, sortBy);
    
    // Apply limit
    const limitedStrategies = sortedStrategies.slice(0, limit);
    
    // Calculate metrics for response
    const metrics = {
      totalStrategies: limitedStrategies.length,
      averageAPY: limitedStrategies.reduce((sum, s) => sum + s.currentAPY, 0) / limitedStrategies.length,
      averageRiskScore: limitedStrategies.reduce((sum, s) => sum + s.riskScore, 0) / limitedStrategies.length,
      totalTVL: limitedStrategies.reduce((sum, s) => sum + Number(s.tvl), 0).toString(),
      chainDistribution: getDistribution(limitedStrategies, 'chain'),
      protocolDistribution: getDistribution(limitedStrategies, 'protocol'),
      typeDistribution: getDistribution(limitedStrategies, 'type'),
      riskDistribution: getRiskDistribution(limitedStrategies)
    };
    
    // Add strategy recommendations if risk tolerance provided
    let recommendations = undefined;
    if (riskTolerance) {
      recommendations = await strategyService.getRecommendations({
        riskTolerance,
        investmentAmount: '10000', // Default $10k for recommendations
        preferredChains: chain ? [chain] : undefined,
        timeHorizon: 'medium',
        diversification: true
      });
    }
    
    const response = {
      strategies: limitedStrategies.map(strategy => ({
        ...strategy,
        // Add calculated fields
        riskAdjustedAPY: calculateRiskAdjustedAPY(strategy),
        capacityUtilization: (Number(strategy.tvl) / Number(strategy.maxCapacity)) * 100,
        yieldSources: analyzeYieldSources(strategy),
        competitiveRanking: 0 // Will be calculated
      })),
      metrics,
      recommendations: recommendations?.slice(0, 5), // Top 5 recommendations
      filters: {
        applied: {
          chain,
          minAPY,
          maxRisk,
          protocols,
          types,
          riskTolerance
        },
        available: {
          chains: [...new Set(allStrategies.map(s => s.chain))],
          protocols: [...new Set(allStrategies.map(s => s.protocol))],
          types: [...new Set(allStrategies.map(s => s.type))]
        }
      },
      sorting: {
        currentSort: sortBy,
        availableSorts: ['riskAdjustedAPY', 'apy', 'risk', 'tvl', 'capacity']
      }
    };
    
    // Add competitive rankings
    response.strategies = addCompetitiveRankings(response.strategies);
    
    return NextResponse.json<VaultApiResponse<typeof response>>({
      success: true,
      data: response,
      message: `Found ${limitedStrategies.length} strategies`,
      timestamp: Date.now()
    });
    
  } catch (error) {
    console.error('Strategies API error:', error);
    
    return NextResponse.json<VaultApiResponse<null>>({
      success: false,
      error: 'Failed to fetch strategies',
      message: error instanceof Error ? error.message : 'Unknown error occurred',
      timestamp: Date.now()
    }, { status: 500 });
  }
}

// POST endpoint for strategy analysis and comparison
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action, strategyIds, userProfile } = body;
    
    if (!action) {
      return NextResponse.json({
        success: false,
        error: 'Missing action parameter'
      }, { status: 400 });
    }
    
    let result;
    
    switch (action) {
      case 'compare':
        if (!strategyIds || strategyIds.length < 2) {
          return NextResponse.json({
            success: false,
            error: 'At least 2 strategy IDs required for comparison'
          }, { status: 400 });
        }
        result = await compareStrategies(strategyIds);
        break;
        
      case 'analyze':
        if (!strategyIds || strategyIds.length !== 1) {
          return NextResponse.json({
            success: false,
            error: 'Exactly 1 strategy ID required for analysis'
          }, { status: 400 });
        }
        result = await analyzeStrategy(strategyIds[0]);
        break;
        
      case 'recommend':
        if (!userProfile) {
          return NextResponse.json({
            success: false,
            error: 'User profile required for recommendations'
          }, { status: 400 });
        }
        result = await strategyService.getRecommendations(userProfile);
        break;
        
      default:
        return NextResponse.json({
          success: false,
          error: `Unknown action: ${action}`
        }, { status: 400 });
    }
    
    return NextResponse.json({
      success: true,
      data: result,
      timestamp: Date.now()
    });
    
  } catch (error) {
    console.error('Strategy analysis error:', error);
    
    return NextResponse.json({
      success: false,
      error: 'Analysis failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 });
  }
}

// Helper functions
function sortStrategies(strategies: VaultStrategy[], sortBy: string): VaultStrategy[] {
  switch (sortBy) {
    case 'apy':
      return strategies.sort((a, b) => b.currentAPY - a.currentAPY);
    case 'risk':
      return strategies.sort((a, b) => a.riskScore - b.riskScore);
    case 'tvl':
      return strategies.sort((a, b) => Number(b.tvl) - Number(a.tvl));
    case 'capacity':
      return strategies.sort((a, b) => {
        const aCapacity = (Number(a.tvl) / Number(a.maxCapacity)) * 100;
        const bCapacity = (Number(b.tvl) / Number(b.maxCapacity)) * 100;
        return aCapacity - bCapacity;
      });
    case 'riskAdjustedAPY':
    default:
      return strategies.sort((a, b) => {
        const aScore = calculateRiskAdjustedAPY(a);
        const bScore = calculateRiskAdjustedAPY(b);
        return bScore - aScore;
      });
  }
}

function calculateRiskAdjustedAPY(strategy: VaultStrategy): number {
  // Sharpe-like ratio calculation
  const riskFreeRate = 3; // 3% risk-free rate
  const adjustedAPY = strategy.currentAPY - riskFreeRate;
  const riskPenalty = 1 + (strategy.riskScore / 10);
  
  return adjustedAPY / riskPenalty;
}

function getDistribution(strategies: VaultStrategy[], field: keyof VaultStrategy): Record<string, number> {
  const distribution: Record<string, number> = {};
  
  strategies.forEach(strategy => {
    const value = strategy[field] as string;
    distribution[value] = (distribution[value] || 0) + 1;
  });
  
  return distribution;
}

function getRiskDistribution(strategies: VaultStrategy[]): Record<string, number> {
  const distribution = { low: 0, medium: 0, high: 0, extreme: 0 };
  
  strategies.forEach(strategy => {
    distribution[strategy.riskLevel]++;
  });
  
  return distribution;
}

function analyzeYieldSources(strategy: VaultStrategy): {
  trading: number;
  rewards: number;
  fees: number;
  compound: number;
} {
  // Mock yield source analysis
  switch (strategy.type) {
    case 'liquidity':
      return {
        trading: 60, // Trading fees
        rewards: 30, // Token rewards
        fees: 5,   // Protocol fees
        compound: 5 // Compound effect
      };
    case 'staking':
      return {
        trading: 0,
        rewards: 85, // Staking rewards
        fees: 10,    // Fee sharing
        compound: 5
      };
    case 'lending':
      return {
        trading: 0,
        rewards: 20, // Protocol tokens
        fees: 75,    // Interest
        compound: 5
      };
    default:
      return {
        trading: 40,
        rewards: 40,
        fees: 15,
        compound: 5
      };
  }
}

function addCompetitiveRankings(strategies: any[]): any[] {
  // Sort by risk-adjusted APY for ranking
  const sortedByPerformance = [...strategies].sort((a, b) => b.riskAdjustedAPY - a.riskAdjustedAPY);
  
  return strategies.map(strategy => {
    const rank = sortedByPerformance.findIndex(s => s.id === strategy.id) + 1;
    const percentile = ((sortedByPerformance.length - rank + 1) / sortedByPerformance.length) * 100;
    
    return {
      ...strategy,
      competitiveRanking: {
        rank,
        percentile,
        category: percentile >= 80 ? 'top' : percentile >= 60 ? 'good' : percentile >= 40 ? 'average' : 'below-average'
      }
    };
  });
}

async function compareStrategies(strategyIds: string[]) {
  const strategies = await Promise.all(
    strategyIds.map(id => strategyService.getStrategy(id))
  );
  
  const validStrategies = strategies.filter(s => s !== null) as VaultStrategy[];
  
  if (validStrategies.length !== strategyIds.length) {
    throw new Error('Some strategies not found');
  }
  
  return {
    strategies: validStrategies,
    comparison: {
      apy: {
        highest: Math.max(...validStrategies.map(s => s.currentAPY)),
        lowest: Math.min(...validStrategies.map(s => s.currentAPY)),
        average: validStrategies.reduce((sum, s) => sum + s.currentAPY, 0) / validStrategies.length
      },
      risk: {
        highest: Math.max(...validStrategies.map(s => s.riskScore)),
        lowest: Math.min(...validStrategies.map(s => s.riskScore)),
        average: validStrategies.reduce((sum, s) => sum + s.riskScore, 0) / validStrategies.length
      },
      tvl: {
        highest: Math.max(...validStrategies.map(s => Number(s.tvl))),
        lowest: Math.min(...validStrategies.map(s => Number(s.tvl))),
        total: validStrategies.reduce((sum, s) => sum + Number(s.tvl), 0)
      },
      fees: {
        depositFee: validStrategies.map(s => ({ name: s.name, fee: s.depositFee })),
        performanceFee: validStrategies.map(s => ({ name: s.name, fee: s.performanceFee }))
      },
      recommendation: {
        bestForConservative: validStrategies.reduce((best, s) => s.riskScore < best.riskScore ? s : best),
        bestForAggressive: validStrategies.reduce((best, s) => s.currentAPY > best.currentAPY ? s : best),
        bestRiskAdjusted: validStrategies.reduce((best, s) => 
          calculateRiskAdjustedAPY(s) > calculateRiskAdjustedAPY(best) ? s : best
        )
      }
    }
  };
}

async function analyzeStrategy(strategyId: string) {
  const strategy = await strategyService.getStrategy(strategyId);
  
  if (!strategy) {
    throw new Error('Strategy not found');
  }
  
  // Get updated metrics
  const updatedStrategy = await strategyService.updateStrategyMetrics(strategyId);
  
  return {
    strategy: updatedStrategy || strategy,
    analysis: {
      riskProfile: {
        overall: strategy.riskScore,
        breakdown: {
          impermanentLoss: strategy.impermanentLossRisk,
          smartContract: strategy.smartContractRisk,
          liquidity: strategy.liquidityRisk,
          market: 5 // Mock market risk
        },
        riskLevel: strategy.riskLevel,
        volatility: strategy.historical.volatility
      },
      performance: {
        currentAPY: strategy.currentAPY,
        predictedAPY: strategy.predictedAPY,
        historical: {
          apy7d: strategy.historical.apy7d,
          apy30d: strategy.historical.apy30d,
          maxDrawdown: strategy.historical.maxDrawdown
        },
        consistency: calculateConsistency(strategy),
        trend: strategy.currentAPY > strategy.historical.apy30d ? 'increasing' : 'decreasing'
      },
      economics: {
        tvl: strategy.tvl,
        capacity: strategy.maxCapacity,
        utilization: strategy.utilizationRate,
        fees: {
          deposit: strategy.depositFee,
          withdrawal: strategy.withdrawalFee,
          performance: strategy.performanceFee,
          management: strategy.managementFee
        }
      },
      competitiveness: {
        rank: 1, // Mock rank
        percentile: 85,
        benchmark: 'Above average for ' + strategy.type + ' strategies'
      }
    }
  };
}

function calculateConsistency(strategy: VaultStrategy): number {
  // Mock consistency calculation based on historical volatility
  const volatility = strategy.historical.volatility;
  return Math.max(0, 100 - volatility * 2); // Lower volatility = higher consistency
}