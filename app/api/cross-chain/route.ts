import { NextRequest, NextResponse } from 'next/server';
import { crossChainAggregator } from '@/lib/cross-chain-aggregator';

export async function POST(request: NextRequest) {
  try {
    const { fromChain, toChain, amount, targetProtocol } = await request.json();
    
    // Validate input
    if (!fromChain || !toChain || !amount || !targetProtocol) {
      return NextResponse.json(
        { success: false, error: 'Missing required parameters' },
        { status: 400 }
      );
    }
    
    // Find optimal cross-chain route
    const route = await crossChainAggregator.findOptimalRoute(
      fromChain,
      toChain,
      BigInt(amount),
      targetProtocol
    );
    
    return NextResponse.json({
      success: true,
      route: {
        ...route,
        estimatedGas: route.estimatedGas.toString(),
        steps: route.steps.map(step => ({
          ...step,
          gasEstimate: step.gasEstimate.toString()
        }))
      },
      timestamp: Date.now()
    });
  } catch (error) {
    console.error('Error finding cross-chain route:', error);
    
    return NextResponse.json(
      {
        success: false,
        error: 'Failed to find cross-chain route',
        message: error instanceof Error ? error.message : 'Unknown error'
      },
      { status: 500 }
    );
  }
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const userAddress = searchParams.get('address');
    
    if (!userAddress) {
      // Return demo data when no address provided
      return NextResponse.json({
        success: true,
        demo: true,
        data: {
          totalValue: "1250000",
          averageAPY: 35.8,
          chainDistribution: {
            ethereum: 30,
            arbitrum: 25,
            base: 20,
            polygon: 15,
            bsc: 10
          },
          protocolDistribution: {
            Aerodrome: 25,
            GMX: 20,
            Pendle: 15,
            Beefy: 15,
            Convex: 10,
            Other: 15
          }
        },
        message: "Demo data - provide address parameter for real data",
        timestamp: Date.now()
      });
    }
    
    // Get aggregated yields across chains
    const aggregatedData = await crossChainAggregator.aggregateYields(userAddress);
    
    return NextResponse.json({
      success: true,
      data: {
        totalValue: aggregatedData.totalValue.toString(),
        averageAPY: aggregatedData.averageAPY,
        chainDistribution: aggregatedData.chainDistribution,
        protocolDistribution: aggregatedData.protocolDistribution
      },
      timestamp: Date.now()
    });
  } catch (error) {
    console.error('Error aggregating yields:', error);
    
    return NextResponse.json(
      {
        success: false,
        error: 'Failed to aggregate yields',
        message: error instanceof Error ? error.message : 'Unknown error'
      },
      { status: 500 }
    );
  }
}