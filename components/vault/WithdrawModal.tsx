"use client";

import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import type { Vault, VaultPosition, Chain, WithdrawPreview } from '@/types/vault';
import type { Token } from '@/types/token';
import { formatCurrency, formatPercentage } from '@/lib/utils';
import {
  X,
  ArrowRight,
  AlertCircle,
  CheckCircle,
  Clock,
  TrendingUp,
  TrendingDown,
  DollarSign,
  Globe,
  RefreshCw,
  ExternalLink,
  Info,
  Wallet,
  Target,
  Receipt
} from 'lucide-react';

interface WithdrawModalProps {
  vault: Vault;
  position: VaultPosition;
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export function WithdrawModal({ vault, position, isOpen, onClose, onSuccess }: WithdrawModalProps) {
  const [step, setStep] = useState<'input' | 'preview' | 'execute' | 'success'>('input');
  const [withdrawType, setWithdrawType] = useState<'percentage' | 'amount'>('percentage');
  const [withdrawPercentage, setWithdrawPercentage] = useState<number>(25);
  const [withdrawAmount, setWithdrawAmount] = useState<string>('');
  const [targetChain, setTargetChain] = useState<string>('ethereum');
  const [targetToken, setTargetToken] = useState<string>('USDC');
  const [preview, setPreview] = useState<WithdrawPreview | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [claimRewards, setClaimRewards] = useState(true);
  
  // Mock data for demonstration
  const availableChains: Chain[] = [
    {
      id: 'ethereum',
      name: 'Ethereum',
      chainId: 1,
      rpcUrl: '',
      blockExplorer: 'https://etherscan.io',
      nativeCurrency: { name: 'Ethereum', symbol: 'ETH', decimals: 18 },
      isTestnet: false,
      bridgeSupported: true
    },
    {
      id: 'arbitrum',
      name: 'Arbitrum',
      chainId: 42161,
      rpcUrl: '',
      blockExplorer: 'https://arbiscan.io',
      nativeCurrency: { name: 'Ethereum', symbol: 'ETH', decimals: 18 },
      isTestnet: false,
      bridgeSupported: true
    },
    {
      id: 'optimism',
      name: 'Optimism',
      chainId: 10,
      rpcUrl: '',
      blockExplorer: 'https://optimistic.etherscan.io',
      nativeCurrency: { name: 'Ethereum', symbol: 'ETH', decimals: 18 },
      isTestnet: false,
      bridgeSupported: true
    },
    {
      id: 'base',
      name: 'Base',
      chainId: 8453,
      rpcUrl: '',
      blockExplorer: 'https://basescan.org',
      nativeCurrency: { name: 'Ethereum', symbol: 'ETH', decimals: 18 },
      isTestnet: false,
      bridgeSupported: true
    }
  ];

  const availableTokens: Token[] = [
    { address: '0xA0b86a33E6441e5F6421E1e8f4b6D0c4F8b7E6D3', symbol: 'USDC', decimals: 6 },
    { address: '0xdAC17F958D2ee523a2206206994597C13D831ec7', symbol: 'USDT', decimals: 6 },
    { address: '0x6B175474E89094C44Da98b954EedeAC495271d0F', symbol: 'DAI', decimals: 18 },
    { address: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', symbol: 'WETH', decimals: 18 }
  ];

  useEffect(() => {
    if (isOpen) {
      setStep('input');
      setWithdrawPercentage(25);
      setWithdrawAmount('');
      setPreview(null);
      setError(null);
      setTxHash(null);
    }
  }, [isOpen]);

  useEffect(() => {
    if ((withdrawType === 'percentage' && withdrawPercentage > 0) || 
        (withdrawType === 'amount' && withdrawAmount && parseFloat(withdrawAmount) > 0)) {
      generatePreview();
    }
  }, [withdrawType, withdrawPercentage, withdrawAmount, targetChain, targetToken, claimRewards]);

  const getWithdrawAmountInUSD = () => {
    if (withdrawType === 'percentage') {
      return (position.currentValue * withdrawPercentage) / 100;
    } else {
      return parseFloat(withdrawAmount) || 0;
    }
  };

  const generatePreview = async () => {
    setLoading(true);
    try {
      await new Promise(resolve => setTimeout(resolve, 800));
      
      const withdrawAmountUSD = getWithdrawAmountInUSD();
      const sharesWithdrawing = withdrawType === 'percentage' 
        ? (Number(position.shares) * withdrawPercentage) / 100
        : (parseFloat(withdrawAmount) || 0) / vault.sharePrice;
      
      const needsCrossChain = targetChain !== position.chain;
      const needsSwap = targetToken !== 'USDC'; // Assume vault outputs USDC
      
      // Calculate fees
      const withdrawalFee = withdrawAmountUSD * vault.fees.withdrawal / 100;
      const gasFee = needsCrossChain ? 45 : 20;
      const bridgeFee = needsCrossChain ? withdrawAmountUSD * 0.001 : 0;
      const swapFee = needsSwap ? withdrawAmountUSD * 0.003 : 0;
      
      const totalFees = withdrawalFee + gasFee + bridgeFee + swapFee;
      const netAmount = withdrawAmountUSD - totalFees;
      
      // Calculate capital gains (if any)
      const costBasis = (position.depositedAmount * sharesWithdrawing) / Number(position.shares);
      const capitalGains = Math.max(0, withdrawAmountUSD - costBasis);
      const holdingPeriodDays = Math.floor((Date.now() - position.createdAt) / (24 * 60 * 60 * 1000));
      
      const mockPreview: WithdrawPreview = {
        vault,
        position,
        withdrawAmount: sharesWithdrawing,
        withdrawType: 'shares',
        targetChain,
        targetToken: availableTokens.find(t => t.symbol === targetToken),
        expectedOutput: BigInt(Math.floor(netAmount * 1e6)),
        expectedValue: netAmount,
        totalFees: {
          withdrawal: withdrawalFee,
          gas: gasFee,
          bridge: needsCrossChain ? bridgeFee : undefined,
          swap: needsSwap ? swapFee : undefined,
          total: totalFees
        },
        estimatedTime: needsCrossChain ? 600 : 120,
        minReceived: BigInt(Math.floor(netAmount * 0.99 * 1e6)),
        warnings: [],
        taxImplications: capitalGains > 0 ? {
          realizingGains: true,
          capitalGains,
          holdingPeriod: holdingPeriodDays
        } : undefined
      };
      
      // Add warnings
      if (withdrawPercentage === 100) {
        mockPreview.warnings.push('You are withdrawing your entire position from this vault.');
      }
      
      if (totalFees > withdrawAmountUSD * 0.05) {
        mockPreview.warnings.push('High fees relative to withdrawal amount - consider withdrawing a larger amount.');
      }
      
      if (needsCrossChain) {
        mockPreview.warnings.push('Cross-chain withdrawal may take up to 10 minutes to complete.');
      }
      
      if (capitalGains > 1000) {
        mockPreview.warnings.push('This withdrawal will realize significant capital gains. Consider tax implications.');
      }
      
      if (holdingPeriodDays < 365 && capitalGains > 0) {
        mockPreview.warnings.push('Short-term capital gains may apply (held for less than 1 year).');
      }
      
      setPreview(mockPreview);
      
    } catch (error) {
      console.error('Failed to generate preview:', error);
      setError('Failed to generate withdrawal preview. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const executeWithdraw = async () => {
    if (!preview) return;
    
    setStep('execute');
    setLoading(true);
    
    try {
      // Simulate transaction execution
      await new Promise(resolve => setTimeout(resolve, 3000));
      
      const mockTxHash = '0xabcdef1234567890abcdef1234567890abcdef12';
      setTxHash(mockTxHash);
      
      setStep('success');
      
      // Auto-close after success
      setTimeout(() => {
        onSuccess();
      }, 4000);
      
    } catch (error) {
      console.error('Withdrawal failed:', error);
      setError('Withdrawal transaction failed. Please try again.');
      setStep('preview');
    } finally {
      setLoading(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <Card className="w-full max-w-2xl max-h-[90vh] overflow-auto">
        <CardHeader className="pb-4">
          <div className="flex items-center justify-between">
            <div>
              <CardTitle className="flex items-center gap-2">
                <Wallet className="w-5 h-5 text-purple-600" />
                Withdraw from {vault.name}
              </CardTitle>
              <div className="flex items-center gap-4 mt-2 text-sm text-gray-600">
                <span>Position Value: <span className="font-semibold text-green-600">
                  {formatCurrency(position.currentValue)}
                </span></span>
                <span>P&L: <span className={`font-semibold ${
                  position.unrealizedPnL >= 0 ? 'text-green-600' : 'text-red-600'
                }`}>
                  {position.unrealizedPnL >= 0 ? '+' : ''}{formatCurrency(position.unrealizedPnL)}
                </span></span>
              </div>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-4 h-4" />
            </Button>
          </div>
          
          {/* Progress Indicator */}
          <div className="flex items-center gap-2 mt-4">
            {['input', 'preview', 'execute', 'success'].map((stepName, index) => (
              <div key={stepName} className="flex items-center gap-2">
                <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm ${
                  step === stepName 
                    ? 'bg-purple-600 text-white' 
                    : index < ['input', 'preview', 'execute', 'success'].indexOf(step)
                      ? 'bg-green-600 text-white'
                      : 'bg-gray-200 text-gray-600'
                }`}>
                  {index < ['input', 'preview', 'execute', 'success'].indexOf(step) ? (
                    <CheckCircle className="w-4 h-4" />
                  ) : (
                    index + 1
                  )}
                </div>
                {index < 3 && (
                  <ArrowRight className={`w-4 h-4 ${
                    index < ['input', 'preview', 'execute', 'success'].indexOf(step)
                      ? 'text-green-600'
                      : 'text-gray-400'
                  }`} />
                )}
              </div>
            ))}
          </div>
        </CardHeader>

        <CardContent className="space-y-6">
          {step === 'input' && (
            <div className="space-y-6">
              {/* Position Summary */}
              <div className="bg-gray-50 rounded-lg p-4">
                <h4 className="font-medium mb-3">Your Position</h4>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <p className="text-gray-600">Shares Owned</p>
                    <p className="font-semibold">{formatCurrency(Number(position.shares) / 1e18, 4)} {vault.symbol}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Current Value</p>
                    <p className="font-semibold">{formatCurrency(position.currentValue)}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Entry Price</p>
                    <p className="font-semibold">{formatCurrency(position.entryPrice)}</p>
                  </div>
                  <div>
                    <p className="text-gray-600">Current Price</p>
                    <p className="font-semibold">{formatCurrency(vault.sharePrice)}</p>
                  </div>
                  {position.pendingRewards > 0 && (
                    <div>
                      <p className="text-gray-600">Pending Rewards</p>
                      <p className="font-semibold text-blue-600">{formatCurrency(position.pendingRewards)}</p>
                    </div>
                  )}
                </div>
              </div>
              
              {/* Withdrawal Amount */}
              <div className="space-y-4">
                <div>
                  <Label className="text-base font-medium">Withdrawal Amount</Label>
                  <div className="flex gap-2 mt-2">
                    <Button
                      variant={withdrawType === 'percentage' ? 'default' : 'outline'}
                      size="sm"
                      onClick={() => setWithdrawType('percentage')}
                    >
                      Percentage
                    </Button>
                    <Button
                      variant={withdrawType === 'amount' ? 'default' : 'outline'}
                      size="sm"
                      onClick={() => setWithdrawType('amount')}
                    >
                      USD Amount
                    </Button>
                  </div>
                </div>
                
                {withdrawType === 'percentage' ? (
                  <div className="space-y-4">
                    <div className="px-3">
                      <Slider
                        value={[withdrawPercentage]}
                        onValueChange={(value) => setWithdrawPercentage(value[0])}
                        max={100}
                        min={1}
                        step={1}
                        className="w-full"
                      />
                    </div>
                    
                    <div className="flex justify-between items-center">
                      <span className="text-lg font-semibold text-purple-600">
                        {withdrawPercentage}%
                      </span>
                      <span className="text-lg font-semibold">
                        ~{formatCurrency(getWithdrawAmountInUSD())}
                      </span>
                    </div>
                    
                    <div className="flex gap-2">
                      {[25, 50, 75, 100].map(percent => (
                        <Button
                          key={percent}
                          variant="outline"
                          size="sm"
                          onClick={() => setWithdrawPercentage(percent)}
                          className={withdrawPercentage === percent ? 'bg-purple-100 border-purple-300' : ''}
                        >
                          {percent}%
                        </Button>
                      ))}
                    </div>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <div className="relative">
                      <input
                        type="number"
                        placeholder="0.00"
                        value={withdrawAmount}
                        onChange={(e) => setWithdrawAmount(e.target.value)}
                        className="w-full p-3 border rounded-lg pr-12 text-lg"
                        min="0"
                        max={position.currentValue}
                        step="0.01"
                      />
                      <div className="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-500">
                        USD
                      </div>
                    </div>
                    <div className="flex justify-between text-sm text-gray-600">
                      <span>Min: $1.00</span>
                      <span>Max: {formatCurrency(position.currentValue)}</span>
                    </div>
                  </div>
                )}
              </div>
              
              {/* Output Configuration */}
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Target Chain</Label>
                  <Select value={targetChain} onValueChange={setTargetChain}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {availableChains.map(chain => (
                        <SelectItem key={chain.id} value={chain.id}>
                          <div className="flex items-center gap-2">
                            <Globe className="w-4 h-4" />
                            {chain.name}
                            {chain.id === position.chain && (
                              <Badge variant="outline" className="text-xs">Current</Badge>
                            )}
                          </div>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                
                <div className="space-y-2">
                  <Label>Output Token</Label>
                  <Select value={targetToken} onValueChange={setTargetToken}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {availableTokens.map(token => (
                        <SelectItem key={token.symbol} value={token.symbol}>
                          {token.symbol}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>
              
              {/* Claim Rewards */}
              {position.pendingRewards > 0 && (
                <div className="flex items-center justify-between p-3 bg-blue-50 border border-blue-200 rounded-lg">
                  <div>
                    <p className="font-medium text-blue-900">Claim Pending Rewards</p>
                    <p className="text-sm text-blue-700">
                      {formatCurrency(position.pendingRewards)} available
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      id="claimRewards"
                      checked={claimRewards}
                      onChange={(e) => setClaimRewards(e.target.checked)}
                      className="w-4 h-4"
                    />
                    <Label htmlFor="claimRewards" className="text-blue-900">Claim</Label>
                  </div>
                </div>
              )}
              
              {error && (
                <div className="flex items-center gap-2 p-3 bg-red-50 border border-red-200 rounded-lg">
                  <AlertCircle className="w-4 h-4 text-red-600" />
                  <span className="text-red-700 text-sm">{error}</span>
                </div>
              )}
              
              <div className="flex gap-2">
                <Button variant="outline" onClick={onClose} className="flex-1">
                  Cancel
                </Button>
                <Button
                  className="flex-1 bg-purple-600 hover:bg-purple-700"
                  onClick={() => setStep('preview')}
                  disabled={getWithdrawAmountInUSD() <= 0 || loading}
                >
                  {loading ? (
                    <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                  ) : (
                    'Preview Withdrawal'
                  )}
                </Button>
              </div>
            </div>
          )}
          
          {step === 'preview' && preview && (
            <div className="space-y-4">
              {/* Withdrawal Summary */}
              <div className="bg-purple-50 border border-purple-200 rounded-lg p-4">
                <h4 className="font-medium text-purple-900 mb-3">Withdrawal Summary</h4>
                
                <div className="space-y-3">
                  <div className="flex justify-between">
                    <span className="text-purple-700">Shares Withdrawing</span>
                    <span className="font-semibold text-purple-900">
                      {formatCurrency(preview.withdrawAmount / 1e18, 4)} {vault.symbol}
                    </span>
                  </div>
                  
                  <div className="flex justify-between">
                    <span className="text-purple-700">Gross Amount</span>
                    <span className="font-semibold text-purple-900">
                      {formatCurrency(getWithdrawAmountInUSD())}
                    </span>
                  </div>
                  
                  <div className="border-t pt-2">
                    <div className="flex justify-between text-sm text-gray-600 mb-1">
                      <span>Withdrawal Fee ({vault.fees.withdrawal}%)</span>
                      <span>-{formatCurrency(preview.totalFees.withdrawal)}</span>
                    </div>
                    
                    <div className="flex justify-between text-sm text-gray-600 mb-1">
                      <span>Gas Fee</span>
                      <span>-{formatCurrency(preview.totalFees.gas)}</span>
                    </div>
                    
                    {preview.totalFees.bridge && (
                      <div className="flex justify-between text-sm text-gray-600 mb-1">
                        <span>Bridge Fee</span>
                        <span>-{formatCurrency(preview.totalFees.bridge)}</span>
                      </div>
                    )}
                    
                    {preview.totalFees.swap && (
                      <div className="flex justify-between text-sm text-gray-600 mb-1">
                        <span>Swap Fee</span>
                        <span>-{formatCurrency(preview.totalFees.swap)}</span>
                      </div>
                    )}
                    
                    <div className="flex justify-between font-medium pt-2 border-t">
                      <span>Net Amount</span>
                      <span className="text-green-600">
                        {formatCurrency(preview.expectedValue)} {targetToken}
                      </span>
                    </div>
                  </div>
                </div>
                
                {claimRewards && position.pendingRewards > 0 && (
                  <div className="mt-3 pt-3 border-t border-purple-200">
                    <div className="flex justify-between">
                      <span className="text-purple-700">+ Rewards Claimed</span>
                      <span className="font-semibold text-blue-600">
                        +{formatCurrency(position.pendingRewards)}
                      </span>
                    </div>
                  </div>
                )}
              </div>
              
              {/* Cross-chain Details */}
              {targetChain !== position.chain && (
                <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <div className="flex items-center gap-2 mb-2">
                    <Globe className="w-5 h-5 text-blue-600" />
                    <span className="font-medium text-blue-900">Cross-Chain Withdrawal</span>
                  </div>
                  
                  <div className="flex items-center justify-between">
                    <div className="text-center">
                      <p className="text-sm text-blue-700 capitalize">{position.chain}</p>
                      <p className="font-semibold text-blue-900">Vault</p>
                    </div>
                    
                    <div className="flex items-center gap-2">
                      <ArrowRight className="w-5 h-5 text-blue-600" />
                      <div className="text-center">
                        <p className="text-xs text-blue-600">~{Math.floor(preview.estimatedTime / 60)}m</p>
                        <p className="text-xs text-blue-600">Bridge</p>
                      </div>
                      <ArrowRight className="w-5 h-5 text-blue-600" />
                    </div>
                    
                    <div className="text-center">
                      <p className="text-sm text-blue-700 capitalize">{targetChain}</p>
                      <p className="font-semibold text-blue-900">{targetToken}</p>
                    </div>
                  </div>
                </div>
              )}
              
              {/* Tax Implications */}
              {preview.taxImplications && (
                <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
                  <div className="flex items-center gap-2 mb-2">
                    <Receipt className="w-5 h-5 text-yellow-600" />
                    <span className="font-medium text-yellow-900">Tax Implications</span>
                  </div>
                  
                  <div className="space-y-2 text-sm">
                    <div className="flex justify-between">
                      <span className="text-yellow-700">Capital Gains</span>
                      <span className="font-semibold text-yellow-900">
                        {formatCurrency(preview.taxImplications.capitalGains)}
                      </span>
                    </div>
                    
                    <div className="flex justify-between">
                      <span className="text-yellow-700">Holding Period</span>
                      <span className="font-semibold text-yellow-900">
                        {preview.taxImplications.holdingPeriod} days
                        {preview.taxImplications.holdingPeriod < 365 && (
                          <Badge className="ml-2 bg-orange-100 text-orange-800">Short-term</Badge>
                        )}
                      </span>
                    </div>
                    
                    <p className="text-xs text-yellow-700 mt-2">
                      {preview.taxImplications.holdingPeriod < 365 
                        ? "Short-term capital gains may apply. Consult a tax professional."
                        : "Long-term capital gains rates may apply. Consult a tax professional."}
                    </p>
                  </div>
                </div>
              )}
              
              {/* Warnings */}
              {preview.warnings.length > 0 && (
                <div className="space-y-2">
                  {preview.warnings.map((warning, index) => (
                    <div key={index} className="flex items-start gap-2 p-3 bg-orange-50 border border-orange-200 rounded-lg">
                      <AlertCircle className="w-4 h-4 text-orange-600 mt-0.5" />
                      <span className="text-orange-800 text-sm">{warning}</span>
                    </div>
                  ))}
                </div>
              )}
              
              {/* Impact on Position */}
              {withdrawPercentage !== 100 && (
                <div className="bg-gray-50 rounded-lg p-4">
                  <h4 className="font-medium mb-2">Remaining Position</h4>
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    <div>
                      <p className="text-gray-600">Remaining Value</p>
                      <p className="font-semibold">
                        {formatCurrency(position.currentValue - getWithdrawAmountInUSD())}
                      </p>
                    </div>
                    <div>
                      <p className="text-gray-600">Remaining Shares</p>
                      <p className="font-semibold">
                        {formatCurrency((Number(position.shares) * (100 - withdrawPercentage)) / 100 / 1e18, 4)}
                      </p>
                    </div>
                  </div>
                </div>
              )}
              
              <div className="flex gap-2">
                <Button variant="outline" onClick={() => setStep('input')} className="flex-1">
                  Back
                </Button>
                <Button
                  className="flex-1 bg-purple-600 hover:bg-purple-700"
                  onClick={executeWithdraw}
                  disabled={loading}
                >
                  {loading ? (
                    <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                  ) : (
                    'Confirm Withdrawal'
                  )}
                </Button>
              </div>
            </div>
          )}
          
          {step === 'execute' && (
            <div className="text-center space-y-4">
              <div className="w-16 h-16 mx-auto">
                <div className="animate-spin rounded-full h-16 w-16 border-b-2 border-purple-600"></div>
              </div>
              
              <div>
                <h3 className="text-lg font-semibold">Processing Withdrawal</h3>
                <p className="text-gray-600">This may take a few moments</p>
              </div>
              
              {targetChain !== position.chain && (
                <div className="space-y-2">
                  <div className="flex items-center justify-center gap-2">
                    <div className="w-3 h-3 rounded-full bg-yellow-500" />
                    <span className="text-sm">Withdrawing from vault</span>
                  </div>
                  
                  <div className="flex items-center justify-center gap-2">
                    <div className="w-3 h-3 rounded-full bg-gray-300" />
                    <span className="text-sm">Bridging to {targetChain}</span>
                  </div>
                </div>
              )}
              
              {txHash && (
                <div className="mt-4">
                  <a
                    href={`https://etherscan.io/tx/${txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-blue-600 hover:text-blue-700 text-sm"
                  >
                    View Transaction
                    <ExternalLink className="w-3 h-3" />
                  </a>
                </div>
              )}
            </div>
          )}
          
          {step === 'success' && preview && (
            <div className="text-center space-y-4">
              <div className="w-16 h-16 mx-auto bg-green-100 rounded-full flex items-center justify-center">
                <CheckCircle className="w-10 h-10 text-green-600" />
              </div>
              
              <div>
                <h3 className="text-lg font-semibold text-green-900">Withdrawal Successful!</h3>
                <p className="text-gray-600">
                  Your funds {targetChain !== position.chain ? 'are being bridged and ' : ''}have been sent to your wallet.
                </p>
              </div>
              
              <div className="bg-green-50 border border-green-200 rounded-lg p-4">
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <p className="text-green-700">Amount Withdrawn</p>
                    <p className="font-semibold text-green-900">
                      {formatCurrency(getWithdrawAmountInUSD())}
                    </p>
                  </div>
                  <div>
                    <p className="text-green-700">Net Received</p>
                    <p className="font-semibold text-green-900">
                      {formatCurrency(preview.expectedValue)} {targetToken}
                    </p>
                  </div>
                  {claimRewards && position.pendingRewards > 0 && (
                    <>
                      <div>
                        <p className="text-green-700">Rewards Claimed</p>
                        <p className="font-semibold text-green-900">
                          {formatCurrency(position.pendingRewards)}
                        </p>
                      </div>
                      <div>
                        <p className="text-green-700">Total Received</p>
                        <p className="font-semibold text-green-900">
                          {formatCurrency(preview.expectedValue + position.pendingRewards)}
                        </p>
                      </div>
                    </>
                  )}
                </div>
              </div>
              
              {withdrawPercentage !== 100 && (
                <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
                  <p className="text-sm text-blue-700">
                    You still have {formatCurrency(position.currentValue - getWithdrawAmountInUSD())} 
                    remaining in this vault, continuing to earn {formatPercentage(vault.apy.current)} APY.
                  </p>
                </div>
              )}
              
              {txHash && (
                <div>
                  <a
                    href={`https://etherscan.io/tx/${txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-blue-600 hover:text-blue-700 text-sm"
                  >
                    View Transaction
                    <ExternalLink className="w-3 h-3" />
                  </a>
                </div>
              )}
              
              <Button className="w-full" onClick={onSuccess}>
                Continue to Dashboard
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}