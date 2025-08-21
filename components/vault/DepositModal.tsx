"use client";

import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Progress } from '@/components/ui/progress';
import type { Vault, Chain, CrossChainRoute, DepositPreview } from '@/types/vault';
import type { Token } from '@/types/token';
import { formatCurrency, formatPercentage } from '@/lib/utils';
import {
  X,
  ArrowRight,
  AlertCircle,
  CheckCircle,
  Clock,
  TrendingUp,
  Zap,
  Shield,
  Globe,
  RefreshCw,
  ExternalLink,
  Info
} from 'lucide-react';

interface DepositModalProps {
  vault?: Vault | null;
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export function DepositModal({ vault, isOpen, onClose, onSuccess }: DepositModalProps) {
  const [step, setStep] = useState<'input' | 'preview' | 'execute' | 'success'>('input');
  const [selectedChain, setSelectedChain] = useState<string>('ethereum');
  const [selectedToken, setSelectedToken] = useState<string>('USDC');
  const [amount, setAmount] = useState<string>('');
  const [route, setRoute] = useState<CrossChainRoute | null>(null);
  const [preview, setPreview] = useState<DepositPreview | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [bridgeStatus, setBridgeStatus] = useState<'pending' | 'bridging' | 'completed' | 'failed'>('pending');
  
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
    { address: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', symbol: 'WETH', decimals: 18 },
    { address: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599', symbol: 'WBTC', decimals: 8 }
  ];

  useEffect(() => {
    if (isOpen) {
      setStep('input');
      setAmount('');
      setRoute(null);
      setPreview(null);
      setError(null);
      setTxHash(null);
    }
  }, [isOpen]);

  useEffect(() => {
    if (amount && parseFloat(amount) > 0 && vault) {
      generatePreview();
    }
  }, [amount, selectedChain, selectedToken, vault]);

  const generatePreview = async () => {
    if (!vault || !amount) return;
    
    setLoading(true);
    try {
      // Simulate API call to generate preview
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      const amountNum = parseFloat(amount);
      const needsCrossChain = !vault.strategy.targetChains.includes(selectedChain);
      
      // Mock route generation
      const mockRoute: CrossChainRoute | undefined = needsCrossChain ? {
        id: 'route-1',
        fromChain: availableChains.find(c => c.id === selectedChain)!,
        toChain: availableChains.find(c => c.id === vault.strategy.targetChains[0])!,
        fromToken: availableTokens.find(t => t.symbol === selectedToken)!,
        toToken: availableTokens.find(t => t.symbol === selectedToken)!,
        amount: BigInt(Math.floor(amountNum * 1e6)),
        estimatedOutput: BigInt(Math.floor(amountNum * 0.999 * 1e6)),
        priceImpact: 0.05,
        bridgeProtocol: 'LayerZero',
        bridgeFee: amountNum * 0.001,
        gasEstimate: {
          origin: BigInt(150000),
          destination: BigInt(200000),
          total: 25
        },
        timeEstimate: 300,
        steps: [
          {
            type: 'bridge',
            protocol: 'LayerZero',
            chain: selectedChain,
            fromToken: availableTokens.find(t => t.symbol === selectedToken)!,
            toToken: availableTokens.find(t => t.symbol === selectedToken)!,
            amount: BigInt(Math.floor(amountNum * 1e6)),
            estimatedOutput: BigInt(Math.floor(amountNum * 0.999 * 1e6)),
            gasEstimate: BigInt(150000),
            description: `Bridge ${selectedToken} to ${vault.strategy.targetChains[0]}`
          },
          {
            type: 'bridge',
            protocol: vault.name,
            chain: vault.strategy.targetChains[0],
            fromToken: availableTokens.find(t => t.symbol === selectedToken)!,
            toToken: availableTokens.find(t => t.symbol === vault.symbol)!,
            amount: BigInt(Math.floor(amountNum * 0.999 * 1e6)),
            estimatedOutput: BigInt(Math.floor(amountNum * 0.999 / vault.sharePrice * 1e18)),
            gasEstimate: BigInt(200000),
            description: `Deposit into ${vault.name}`
          }
        ],
        confidence: 95,
        savings: 15.50
      } : undefined;
      
      const mockPreview: DepositPreview = {
        vault,
        inputAmount: amountNum,
        inputToken: availableTokens.find(t => t.symbol === selectedToken)!,
        route: mockRoute,
        expectedShares: BigInt(Math.floor(amountNum / vault.sharePrice * 1e18)),
        expectedValue: amountNum * 0.995,
        priceImpact: 0.05,
        totalFees: {
          gas: needsCrossChain ? 25 : 15,
          bridge: needsCrossChain ? amountNum * 0.001 : undefined,
          swap: 0,
          deposit: amountNum * vault.fees.management / 100,
          total: (needsCrossChain ? 25 : 15) + (needsCrossChain ? amountNum * 0.001 : 0) + (amountNum * vault.fees.management / 100)
        },
        estimatedTime: needsCrossChain ? 300 : 60,
        minReceived: BigInt(Math.floor(amountNum * 0.99 / vault.sharePrice * 1e18)),
        warnings: [],
        breakdown: [
          {
            step: 'Initial Amount',
            amount: amountNum,
            fee: 0,
            description: `${amountNum} ${selectedToken} on ${selectedChain}`
          },
          ...(needsCrossChain ? [{
            step: 'Cross-Chain Bridge',
            amount: amountNum * 0.999,
            fee: amountNum * 0.001,
            description: `Bridge to ${vault.strategy.targetChains[0]} via LayerZero`
          }] : []),
          {
            step: 'Vault Deposit',
            amount: amountNum * (needsCrossChain ? 0.999 : 1) * 0.995,
            fee: amountNum * vault.fees.management / 100,
            description: `Deposit into ${vault.name} (${vault.fees.management}% fee)`
          }
        ]
      };
      
      // Add warnings based on conditions
      if (mockPreview.totalFees.total > amountNum * 0.05) {
        mockPreview.warnings.push('High fees relative to deposit amount - consider larger deposit');
      }
      if (vault.utilizationRate > 95) {
        mockPreview.warnings.push('Vault is near capacity - deposit may be delayed');
      }
      if (needsCrossChain) {
        mockPreview.warnings.push('Cross-chain deposit may take 5-10 minutes to complete');
      }
      
      setRoute(mockRoute);
      setPreview(mockPreview);
      
    } catch (error) {
      console.error('Failed to generate preview:', error);
      setError('Failed to generate deposit preview. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const executeDeposit = async () => {
    if (!preview) return;
    
    setStep('execute');
    setLoading(true);
    setBridgeStatus('pending');
    
    try {
      // Simulate transaction execution
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      // Mock transaction hash
      const mockTxHash = '0x1234567890abcdef1234567890abcdef12345678';
      setTxHash(mockTxHash);
      
      if (route) {
        // Simulate bridge process
        setBridgeStatus('bridging');
        await new Promise(resolve => setTimeout(resolve, 3000));
        setBridgeStatus('completed');
      }
      
      setStep('success');
      
      // Auto-close after success
      setTimeout(() => {
        onSuccess();
      }, 3000);
      
    } catch (error) {
      console.error('Deposit failed:', error);
      setError('Deposit transaction failed. Please try again.');
      setBridgeStatus('failed');
      setStep('preview');
    } finally {
      setLoading(false);
    }
  };

  if (!isOpen) return null;
  
  if (!vault) {
    return (
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
        <Card className="w-full max-w-md">
          <CardHeader>
            <CardTitle className="flex items-center justify-between">
              Select a Vault
              <Button variant="ghost" size="sm" onClick={onClose}>
                <X className="w-4 h-4" />
              </Button>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-gray-600">Please select a vault first to make a deposit.</p>
            <Button className="w-full mt-4" onClick={onClose}>
              Choose Vault
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <Card className="w-full max-w-2xl max-h-[90vh] overflow-auto">
        <CardHeader className="pb-4">
          <div className="flex items-center justify-between">
            <div>
              <CardTitle className="flex items-center gap-2">
                <Zap className="w-5 h-5 text-blue-600" />
                Deposit to {vault.name}
              </CardTitle>
              <p className="text-sm text-gray-600 mt-1">
                Current APY: <span className="font-semibold text-green-600">
                  {formatPercentage(vault.apy.current)}
                </span>
              </p>
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
                    ? 'bg-blue-600 text-white' 
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
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Source Chain</Label>
                  <Select value={selectedChain} onValueChange={setSelectedChain}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {availableChains.map(chain => (
                        <SelectItem key={chain.id} value={chain.id}>
                          <div className="flex items-center gap-2">
                            <Globe className="w-4 h-4" />
                            {chain.name}
                          </div>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                
                <div className="space-y-2">
                  <Label>Asset</Label>
                  <Select value={selectedToken} onValueChange={setSelectedToken}>
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
              
              <div className="space-y-2">
                <Label>Amount</Label>
                <div className="relative">
                  <input
                    type="number"
                    placeholder="0.00"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    className="w-full p-3 border rounded-lg pr-16 text-lg"
                    min="0"
                    step="0.01"
                  />
                  <div className="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-500">
                    {selectedToken}
                  </div>
                </div>
                <div className="flex justify-between text-sm text-gray-600">
                  <span>Min: {formatCurrency(vault.strategy.minDeposit)}</span>
                  <span>Balance: $1,234.56</span>
                </div>
              </div>
              
              {/* Quick Amount Buttons */}
              <div className="flex gap-2">
                {[100, 500, 1000, 5000].map(quickAmount => (
                  <Button
                    key={quickAmount}
                    variant="outline"
                    size="sm"
                    onClick={() => setAmount(quickAmount.toString())}
                  >
                    ${quickAmount}
                  </Button>
                ))}
              </div>
              
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
                  className="flex-1"
                  onClick={() => setStep('preview')}
                  disabled={!amount || parseFloat(amount) <= 0 || loading}
                >
                  {loading ? (
                    <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                  ) : (
                    'Preview Deposit'
                  )}
                </Button>
              </div>
            </div>
          )}
          
          {step === 'preview' && preview && (
            <div className="space-y-4">
              {/* Route Visualization */}
              {route && (
                <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <div className="flex items-center gap-2 mb-3">
                    <Globe className="w-5 h-5 text-blue-600" />
                    <span className="font-medium text-blue-900">Cross-Chain Route</span>
                    <Badge className="bg-blue-100 text-blue-800">
                      {route.bridgeProtocol}
                    </Badge>
                  </div>
                  
                  <div className="flex items-center justify-between">
                    <div className="text-center">
                      <p className="text-sm text-blue-700">{route.fromChain.name}</p>
                      <p className="font-semibold text-blue-900">
                        {formatCurrency(preview.inputAmount)} {selectedToken}
                      </p>
                    </div>
                    
                    <div className="flex items-center gap-2">
                      <ArrowRight className="w-5 h-5 text-blue-600" />
                      <div className="text-center">
                        <p className="text-xs text-blue-600">~{Math.floor(route.timeEstimate / 60)}m</p>
                        <p className="text-xs text-blue-600">
                          ${formatCurrency(route.gasEstimate.total)}
                        </p>
                      </div>
                      <ArrowRight className="w-5 h-5 text-blue-600" />
                    </div>
                    
                    <div className="text-center">
                      <p className="text-sm text-blue-700">{route.toChain.name}</p>
                      <p className="font-semibold text-blue-900">
                        {formatCurrency(preview.expectedValue)} {vault.symbol}
                      </p>
                    </div>
                  </div>
                  
                  {route.savings && (
                    <div className="mt-2 text-center">
                      <Badge className="bg-green-100 text-green-800">
                        💰 Saves ${formatCurrency(route.savings)} vs alternatives
                      </Badge>
                    </div>
                  )}
                </div>
              )}
              
              {/* Deposit Summary */}
              <div className="bg-gray-50 rounded-lg p-4 space-y-3">
                <h4 className="font-medium">Deposit Summary</h4>
                
                <div className="space-y-2">
                  <div className="flex justify-between text-sm">
                    <span>Input Amount</span>
                    <span className="font-medium">
                      {formatCurrency(preview.inputAmount)} {selectedToken}
                    </span>
                  </div>
                  
                  <div className="flex justify-between text-sm">
                    <span>Expected Shares</span>
                    <span className="font-medium">
                      {formatCurrency(Number(preview.expectedShares) / 1e18, 4)} {vault.symbol}
                    </span>
                  </div>
                  
                  <div className="flex justify-between text-sm">
                    <span>Share Price</span>
                    <span className="font-medium">
                      {formatCurrency(vault.sharePrice)}
                    </span>
                  </div>
                  
                  <div className="border-t pt-2">
                    <div className="flex justify-between text-sm text-gray-600">
                      <span>Total Fees</span>
                      <span>{formatCurrency(preview.totalFees.total)}</span>
                    </div>
                    
                    {preview.totalFees.bridge && (
                      <div className="flex justify-between text-xs text-gray-500">
                        <span>• Bridge Fee</span>
                        <span>{formatCurrency(preview.totalFees.bridge)}</span>
                      </div>
                    )}
                    
                    <div className="flex justify-between text-xs text-gray-500">
                      <span>• Gas Fee</span>
                      <span>{formatCurrency(preview.totalFees.gas)}</span>
                    </div>
                    
                    <div className="flex justify-between text-xs text-gray-500">
                      <span>• Deposit Fee ({vault.fees.management}%)</span>
                      <span>{formatCurrency(preview.totalFees.deposit)}</span>
                    </div>
                  </div>
                  
                  <div className="border-t pt-2">
                    <div className="flex justify-between font-medium">
                      <span>Net Deposit</span>
                      <span className="text-green-600">
                        {formatCurrency(preview.expectedValue)}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
              
              {/* Warnings */}
              {preview.warnings.length > 0 && (
                <div className="space-y-2">
                  {preview.warnings.map((warning, index) => (
                    <div key={index} className="flex items-start gap-2 p-3 bg-yellow-50 border border-yellow-200 rounded-lg">
                      <AlertCircle className="w-4 h-4 text-yellow-600 mt-0.5" />
                      <span className="text-yellow-800 text-sm">{warning}</span>
                    </div>
                  ))}
                </div>
              )}
              
              {/* Breakdown */}
              <div className="space-y-2">
                <h4 className="font-medium flex items-center gap-2">
                  <Info className="w-4 h-4 text-blue-600" />
                  Transaction Breakdown
                </h4>
                {preview.breakdown.map((step, index) => (
                  <div key={index} className="flex items-center justify-between p-2 bg-white border rounded">
                    <div>
                      <p className="text-sm font-medium">{step.step}</p>
                      <p className="text-xs text-gray-600">{step.description}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-sm font-medium">{formatCurrency(step.amount)}</p>
                      {step.fee > 0 && (
                        <p className="text-xs text-red-600">-{formatCurrency(step.fee)}</p>
                      )}
                    </div>
                  </div>
                ))}
              </div>
              
              <div className="flex gap-2">
                <Button variant="outline" onClick={() => setStep('input')} className="flex-1">
                  Back
                </Button>
                <Button
                  className="flex-1 bg-green-600 hover:bg-green-700"
                  onClick={executeDeposit}
                  disabled={loading}
                >
                  {loading ? (
                    <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                  ) : (
                    'Confirm Deposit'
                  )}
                </Button>
              </div>
            </div>
          )}
          
          {step === 'execute' && (
            <div className="text-center space-y-4">
              <div className="w-16 h-16 mx-auto">
                <div className="animate-spin rounded-full h-16 w-16 border-b-2 border-blue-600"></div>
              </div>
              
              <div>
                <h3 className="text-lg font-semibold">Processing Deposit</h3>
                <p className="text-gray-600">Please don't close this window</p>
              </div>
              
              {route && (
                <div className="space-y-2">
                  <div className="flex items-center justify-center gap-2">
                    <div className={`w-3 h-3 rounded-full ${
                      bridgeStatus === 'pending' ? 'bg-yellow-500' :
                      ['bridging', 'completed'].includes(bridgeStatus) ? 'bg-green-500' :
                      'bg-red-500'
                    }`} />
                    <span className="text-sm">Bridging to {route.toChain.name}</span>
                  </div>
                  
                  <div className="flex items-center justify-center gap-2">
                    <div className={`w-3 h-3 rounded-full ${
                      bridgeStatus === 'completed' ? 'bg-green-500' :
                      bridgeStatus === 'bridging' ? 'bg-yellow-500' :
                      'bg-gray-300'
                    }`} />
                    <span className="text-sm">Depositing to Vault</span>
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
          
          {step === 'success' && (
            <div className="text-center space-y-4">
              <div className="w-16 h-16 mx-auto bg-green-100 rounded-full flex items-center justify-center">
                <CheckCircle className="w-10 h-10 text-green-600" />
              </div>
              
              <div>
                <h3 className="text-lg font-semibold text-green-900">Deposit Successful!</h3>
                <p className="text-gray-600">
                  Your deposit has been processed and you'll start earning immediately.
                </p>
              </div>
              
              {preview && (
                <div className="bg-green-50 border border-green-200 rounded-lg p-4">
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    <div>
                      <p className="text-green-700">Deposited</p>
                      <p className="font-semibold text-green-900">
                        {formatCurrency(preview.inputAmount)} {selectedToken}
                      </p>
                    </div>
                    <div>
                      <p className="text-green-700">Shares Received</p>
                      <p className="font-semibold text-green-900">
                        {formatCurrency(Number(preview.expectedShares) / 1e18, 4)} {vault.symbol}
                      </p>
                    </div>
                    <div>
                      <p className="text-green-700">Current APY</p>
                      <p className="font-semibold text-green-900">
                        {formatPercentage(vault.apy.current)}
                      </p>
                    </div>
                    <div>
                      <p className="text-green-700">Expected Annual</p>
                      <p className="font-semibold text-green-900">
                        {formatCurrency(preview.expectedValue * vault.apy.current / 100)}
                      </p>
                    </div>
                  </div>
                </div>
              )}
              
              {txHash && (
                <div className="space-y-2">
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