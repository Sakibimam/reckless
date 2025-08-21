/**
 * POST /api/vault/deposit - Process cross-chain deposits
 */

import { NextRequest, NextResponse } from 'next/server';
import { vaultService } from '@/lib/vault/vaultService';
import { strategyService } from '@/lib/vault/strategyService';
import { priceService } from '@/lib/vault/priceService';
import type { 
  DepositRequest, 
  VaultApiResponse, 
  DepositResponse 
} from '@/types/vault';

export async function POST(request: NextRequest) {
  const requestId = `dep_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  
  try {
    const body: DepositRequest = await request.json();
    
    // Validate required fields
    if (!body.amount || !body.token || !body.strategyId || 
        !body.fromChain || !body.toChain || !body.userAddress) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Missing required fields',
        message: 'amount, token, strategyId, fromChain, toChain, and userAddress are required',
        timestamp: Date.now(),
        requestId
      }, { status: 400 });
    }
    
    // Validate amount
    try {
      const amount = BigInt(body.amount);
      if (amount <= 0) {
        throw new Error('Amount must be positive');
      }
    } catch (error) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Invalid amount',
        message: 'Amount must be a valid positive number',
        timestamp: Date.now(),
        requestId
      }, { status: 400 });
    }
    
    // Validate strategy exists
    const strategy = await strategyService.getStrategy(body.strategyId);
    if (!strategy) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Strategy not found',
        message: `Strategy ${body.strategyId} does not exist`,
        timestamp: Date.now(),
        requestId
      }, { status: 404 });
    }
    
    // Validate deposit amount limits
    const depositAmount = BigInt(body.amount);
    const minDeposit = BigInt(strategy.minDeposit);
    const maxDeposit = BigInt(strategy.maxDeposit);
    
    if (depositAmount < minDeposit) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Deposit amount too low',
        message: `Minimum deposit is ${strategy.minDeposit} ${body.token}`,
        timestamp: Date.now(),
        requestId
      }, { status: 400 });
    }
    
    if (depositAmount > maxDeposit) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Deposit amount too high',
        message: `Maximum deposit is ${strategy.maxDeposit} ${body.token}`,
        timestamp: Date.now(),
        requestId
      }, { status: 400 });
    }
    
    // Check if vault has capacity
    const currentTVL = BigInt(strategy.tvl);
    const maxCapacity = BigInt(strategy.maxCapacity);
    
    if (currentTVL + depositAmount > maxCapacity) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Vault at capacity',
        message: `Vault capacity exceeded. Available: ${maxCapacity - currentTVL}`,
        timestamp: Date.now(),
        requestId
      }, { status: 400 });
    }
    
    // Get current token price for USD value validation
    const tokenPrice = await priceService.getPrice(body.token);
    const usdValue = Number(body.amount) * tokenPrice;
    
    // Log the deposit request
    console.log(`Processing deposit: ${body.amount} ${body.token} ($${usdValue.toFixed(2)}) to ${strategy.name}`);
    
    // Process the deposit
    const result = await vaultService.processDeposit(body);
    
    const response: DepositResponse = {
      transactionId: result.transactionId,
      estimatedShares: result.estimatedShares,
      route: undefined, // Will be populated if cross-chain
      steps: result.steps,
      totalFees: result.fees,
      expectedConfirmationTime: body.fromChain !== body.toChain ? 300 : 60, // 5min cross-chain, 1min same-chain
      positionId: result.positionId
    };
    
    // Add route information if cross-chain
    if (body.fromChain !== body.toChain && result.steps.length > 1) {
      // Route information would be included here
    }
    
    return NextResponse.json<VaultApiResponse<DepositResponse>>({
      success: true,
      data: response,
      message: `Deposit initiated successfully. Position ID: ${result.positionId}`,
      timestamp: Date.now(),
      requestId
    });
    
  } catch (error) {
    console.error('Deposit API error:', error);
    
    const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
    
    return NextResponse.json<VaultApiResponse<null>>({
      success: false,
      error: 'Deposit processing failed',
      message: errorMessage,
      timestamp: Date.now(),
      requestId
    }, { status: 500 });
  }
}

// GET endpoint for deposit estimation (dry run)
export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const amount = searchParams.get('amount');
    const token = searchParams.get('token');
    const strategyId = searchParams.get('strategyId');
    const fromChain = searchParams.get('fromChain');
    const toChain = searchParams.get('toChain');
    
    if (!amount || !token || !strategyId || !fromChain || !toChain) {
      return NextResponse.json({
        success: false,
        error: 'Missing required parameters',
        message: 'amount, token, strategyId, fromChain, and toChain are required'
      }, { status: 400 });
    }
    
    // Get strategy
    const strategy = await strategyService.getStrategy(strategyId);
    if (!strategy) {
      return NextResponse.json({
        success: false,
        error: 'Strategy not found'
      }, { status: 404 });
    }
    
    // Create mock deposit request for estimation
    const mockRequest: DepositRequest = {
      amount,
      token,
      strategyId,
      fromChain,
      toChain,
      userAddress: '0x0000000000000000000000000000000000000000', // Mock address for estimation
      slippageTolerance: 0.5,
      deadline: Date.now() + 300000, // 5 minutes from now
      minReceived: (BigInt(amount) * BigInt(995) / BigInt(1000)).toString() // 0.5% slippage
    };
    
    // Get estimation
    const estimate = await vaultService.estimateDeposit(mockRequest, strategy);
    
    return NextResponse.json({
      success: true,
      data: {
        estimate,
        strategy: {
          id: strategy.id,
          name: strategy.name,
          protocol: strategy.protocol,
          chain: strategy.chain,
          currentAPY: strategy.currentAPY,
          predictedAPY: strategy.predictedAPY,
          riskScore: strategy.riskScore,
          riskLevel: strategy.riskLevel
        }
      },
      timestamp: Date.now()
    });
    
  } catch (error) {
    console.error('Deposit estimation error:', error);
    
    return NextResponse.json({
      success: false,
      error: 'Estimation failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 });
  }
}