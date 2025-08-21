/**
 * POST /api/vault/withdraw - Handle redemptions on any chain
 */

import { NextRequest, NextResponse } from 'next/server';
import { vaultService } from '@/lib/vault/vaultService';
import { priceService } from '@/lib/vault/priceService';
import type { 
  WithdrawRequest, 
  VaultApiResponse, 
  WithdrawResponse 
} from '@/types/vault';

export async function POST(request: NextRequest) {
  const requestId = `wdw_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  
  try {
    const body: WithdrawRequest = await request.json();
    
    // Validate required fields
    if (!body.amount || !body.type || !body.positionId || 
        !body.fromChain || !body.toChain || !body.userAddress) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Missing required fields',
        message: 'amount, type, positionId, fromChain, toChain, and userAddress are required',
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
    
    // Validate withdraw type
    if (!['shares', 'assets'].includes(body.type)) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Invalid withdrawal type',
        message: 'Type must be either "shares" or "assets"',
        timestamp: Date.now(),
        requestId
      }, { status: 400 });
    }
    
    // Get user positions to validate position exists and user owns it
    const userPositions = await vaultService.getUserPositions(body.userAddress);
    const position = userPositions.find(p => p.id === body.positionId);
    
    if (!position) {
      return NextResponse.json<VaultApiResponse<null>>({
        success: false,
        error: 'Position not found',
        message: `Position ${body.positionId} not found for user ${body.userAddress}`,
        timestamp: Date.now(),
        requestId
      }, { status: 404 });
    }
    
    // Validate withdrawal amount against position
    if (body.type === 'shares') {
      const userShares = BigInt(position.sharesOwned);
      const withdrawShares = BigInt(body.amount);
      
      if (withdrawShares > userShares) {
        return NextResponse.json<VaultApiResponse<null>>({
          success: false,
          error: 'Insufficient shares',
          message: `You have ${position.sharesOwned} shares, requested ${body.amount}`,
          timestamp: Date.now(),
          requestId
        }, { status: 400 });
      }
      
      // Set partial withdraw flag
      body.partialWithdraw = withdrawShares < userShares;
    }
    
    // Check for emergency withdrawal
    if (body.emergency) {
      console.log(`Emergency withdrawal requested for position ${body.positionId}`);
    }
    
    // Get current position value for logging
    const currentValue = Number(position.currentValue);
    const tokenPrice = await priceService.getPrice(position.strategy.name.includes('USDC') ? 'USDC' : 'ETH');
    const usdValue = body.type === 'shares' 
      ? (Number(body.amount) / Number(position.sharesOwned)) * currentValue
      : Number(body.amount) * tokenPrice;
    
    console.log(`Processing withdrawal: ${body.amount} ${body.type} (~$${usdValue.toFixed(2)}) from ${position.strategy.name}`);
    
    // Process the withdrawal
    const result = await vaultService.processWithdraw(body);
    
    const response: WithdrawResponse = {
      transactionId: result.transactionId,
      estimatedAmount: result.estimatedAmount,
      route: undefined, // Will be populated if cross-chain
      steps: result.steps,
      totalFees: result.fees,
      expectedConfirmationTime: body.fromChain !== body.toChain ? 400 : 120, // 6.5min cross-chain, 2min same-chain
      partialWithdraw: body.partialWithdraw,
      remainingShares: body.partialWithdraw 
        ? (BigInt(position.sharesOwned) - BigInt(body.amount)).toString()
        : undefined
    };
    
    // Add route information if cross-chain
    if (body.fromChain !== body.toChain && result.steps.length > 1) {
      // Route information would be included here
    }
    
    return NextResponse.json<VaultApiResponse<WithdrawResponse>>({
      success: true,
      data: response,
      message: `Withdrawal initiated successfully. ${body.partialWithdraw ? 'Partial withdrawal' : 'Full position closed'}`,
      timestamp: Date.now(),
      requestId
    });
    
  } catch (error) {
    console.error('Withdrawal API error:', error);
    
    const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
    
    return NextResponse.json<VaultApiResponse<null>>({
      success: false,
      error: 'Withdrawal processing failed',
      message: errorMessage,
      timestamp: Date.now(),
      requestId
    }, { status: 500 });
  }
}

// GET endpoint for withdrawal estimation
export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const amount = searchParams.get('amount');
    const type = searchParams.get('type');
    const positionId = searchParams.get('positionId');
    const userAddress = searchParams.get('userAddress');
    const fromChain = searchParams.get('fromChain');
    const toChain = searchParams.get('toChain');
    
    if (!amount || !type || !positionId || !userAddress || !fromChain || !toChain) {
      return NextResponse.json({
        success: false,
        error: 'Missing required parameters',
        message: 'amount, type, positionId, userAddress, fromChain, and toChain are required'
      }, { status: 400 });
    }
    
    // Get user positions
    const userPositions = await vaultService.getUserPositions(userAddress);
    const position = userPositions.find(p => p.id === positionId);
    
    if (!position) {
      return NextResponse.json({
        success: false,
        error: 'Position not found'
      }, { status: 404 });
    }
    
    // Calculate estimated withdrawal amounts
    let estimatedAmount = '0';
    let fees = {
      withdrawal: '0',
      gas: '0',
      bridge: '0',
      total: '0'
    };
    
    if (type === 'shares') {
      // Calculate asset amount from shares
      const shareRatio = Number(amount) / Number(position.sharesOwned);
      estimatedAmount = (Number(position.currentValue) * shareRatio).toString();
    } else {
      // Direct asset amount
      estimatedAmount = amount;
    }
    
    // Estimate fees (simplified)
    const withdrawalFee = BigInt(estimatedAmount) * BigInt(10) / BigInt(10000); // 0.1% withdrawal fee
    const gasFee = fromChain === toChain ? '50000' : '200000'; // Higher gas for cross-chain
    const bridgeFee = fromChain !== toChain ? (BigInt(estimatedAmount) * BigInt(10) / BigInt(10000)).toString() : '0'; // 0.1% bridge fee
    
    fees = {
      withdrawal: withdrawalFee.toString(),
      gas: gasFee,
      bridge: bridgeFee,
      total: (withdrawalFee + BigInt(gasFee) + BigInt(bridgeFee)).toString()
    };
    
    const netAmount = (BigInt(estimatedAmount) - BigInt(fees.total)).toString();
    
    return NextResponse.json({
      success: true,
      data: {
        position: {
          id: position.id,
          sharesOwned: position.sharesOwned,
          currentValue: position.currentValue,
          strategy: position.strategy
        },
        withdrawal: {
          requestedAmount: amount,
          requestedType: type,
          estimatedAssetAmount: estimatedAmount,
          netAmount,
          fees,
          partialWithdraw: type === 'shares' && BigInt(amount) < BigInt(position.sharesOwned),
          remainingShares: type === 'shares' 
            ? (BigInt(position.sharesOwned) - BigInt(amount)).toString()
            : undefined
        },
        crossChain: fromChain !== toChain,
        estimatedTime: fromChain !== toChain ? 400 : 120 // seconds
      },
      timestamp: Date.now()
    });
    
  } catch (error) {
    console.error('Withdrawal estimation error:', error);
    
    return NextResponse.json({
      success: false,
      error: 'Estimation failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 });
  }
}