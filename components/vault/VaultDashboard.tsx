"use client";

import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { VaultCard } from './VaultCard';
import { DepositModal } from './DepositModal';
import { WithdrawModal } from './WithdrawModal';
import { PositionTracker } from './PositionTracker';
import { StrategySelector } from './StrategySelector';
import type { Vault, VaultPosition, PortfolioSummary } from '@/types/vault';
import type { RiskProfile } from '@/types/strategy';
import { formatCurrency, formatPercentage } from '@/lib/utils';
import {
  TrendingUp,
  TrendingDown,
  DollarSign,
  PieChart,
  Activity,
  Shield,
  Zap,
  Plus,
  BarChart3,
  Globe,
  AlertCircle,
  Wallet
} from 'lucide-react';

interface VaultDashboardProps {
  userAddress?: string;
  onStrategySelect?: (strategy: any) => void;
}

export function VaultDashboard({ userAddress, onStrategySelect }: VaultDashboardProps) {
  const [vaults, setVaults] = useState<Vault[]>([]);
  const [portfolio, setPortfolio] = useState<PortfolioSummary | null>(null);
  const [selectedVault, setSelectedVault] = useState<Vault | null>(null);
  const [showDepositModal, setShowDepositModal] = useState(false);
  const [showWithdrawModal, setShowWithdrawModal] = useState(false);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'overview' | 'vaults' | 'positions' | 'strategies'>('overview');

  useEffect(() => {
    loadVaultData();
  }, [userAddress]);

  const loadVaultData = async () => {
    setLoading(true);
    try {
      // Simulate API calls
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      // Mock vault data
      const mockVaults: Vault[] = [
        {
          id: 'vault-1',
          name: 'Multi-Chain Yield Maximizer',
          symbol: 'MCYM',
          address: '0x1234...5678',
          strategy: {
            id: 'strategy-1',
            name: 'Multi-Chain Stable Yield',
            description: 'Automatically routes funds to highest yielding stable protocols across Ethereum, Arbitrum, and Optimism',
            targetChains: ['ethereum', 'arbitrum', 'optimism'],
            targetProtocols: ['aave', 'compound', 'pendle'],
            riskLevel: 'conservative',
            expectedAPY: 12.5,
            tvl: 45000000,
            minDeposit: 100,
            fees: { management: 1.0, performance: 10.0, withdrawal: 0.1 },
            autoCompound: true,
            autoRebalance: true,
            pools: [],
            allocation: {}
          },
          totalSupply: BigInt('1000000000000000000000000'),
          totalAssets: BigInt('45000000000000000000000000'),
          sharePrice: 1.156,
          apy: {
            current: 12.5,
            average30d: 11.8,
            projected: 13.2
          },
          tvl: 45000000,
          capacity: 100000000,
          utilizationRate: 92.5,
          createdAt: Date.now() - 90 * 24 * 60 * 60 * 1000,
          lastRebalance: Date.now() - 2 * 24 * 60 * 60 * 1000,
          performance: {
            daily: 0.034,
            weekly: 0.24,
            monthly: 1.04,
            quarterly: 3.15,
            yearly: 12.5
          },
          fees: { management: 1.0, performance: 10.0, withdrawal: 0.1 },
          supportedTokens: [],
          chainDistribution: {
            'ethereum': 40,
            'arbitrum': 35,
            'optimism': 25
          }
        },
        {
          id: 'vault-2',
          name: 'DeFi Blue Chip Strategy',
          symbol: 'DBCS',
          address: '0xabcd...efgh',
          strategy: {
            id: 'strategy-2',
            name: 'Blue Chip DeFi',
            description: 'Focuses on established DeFi protocols with proven track records',
            targetChains: ['ethereum', 'arbitrum'],
            targetProtocols: ['uniswap', 'aave', 'compound'],
            riskLevel: 'moderate',
            expectedAPY: 18.3,
            tvl: 28000000,
            minDeposit: 500,
            fees: { management: 1.5, performance: 15.0, withdrawal: 0.2 },
            autoCompound: true,
            autoRebalance: true,
            pools: [],
            allocation: {}
          },
          totalSupply: BigInt('500000000000000000000000'),
          totalAssets: BigInt('28000000000000000000000000'),
          sharePrice: 1.283,
          apy: {
            current: 18.3,
            average30d: 17.9,
            projected: 19.1
          },
          tvl: 28000000,
          capacity: 50000000,
          utilizationRate: 78.4,
          createdAt: Date.now() - 60 * 24 * 60 * 60 * 1000,
          lastRebalance: Date.now() - 1 * 24 * 60 * 60 * 1000,
          performance: {
            daily: 0.05,
            weekly: 0.35,
            monthly: 1.52,
            quarterly: 4.58,
            yearly: 18.3
          },
          fees: { management: 1.5, performance: 15.0, withdrawal: 0.2 },
          supportedTokens: [],
          chainDistribution: {
            'ethereum': 60,
            'arbitrum': 40
          }
        },
        {
          id: 'vault-3',
          name: 'High Yield Aggregator',
          symbol: 'HYA',
          address: '0x9999...1111',
          strategy: {
            id: 'strategy-3',
            name: 'Degen Yield Hunter',
            description: 'Aggressive strategy targeting emerging protocols and maximum yield',
            targetChains: ['arbitrum', 'base', 'polygon'],
            targetProtocols: ['gmx', 'pendle', 'aerodrome'],
            riskLevel: 'degen',
            expectedAPY: 45.8,
            tvl: 8500000,
            minDeposit: 1000,
            fees: { management: 2.0, performance: 20.0, withdrawal: 0.5 },
            autoCompound: true,
            autoRebalance: true,
            pools: [],
            allocation: {}
          },
          totalSupply: BigInt('150000000000000000000000'),
          totalAssets: BigInt('8500000000000000000000000'),
          sharePrice: 1.675,
          apy: {
            current: 45.8,
            average30d: 42.1,
            projected: 48.9
          },
          tvl: 8500000,
          capacity: 15000000,
          utilizationRate: 89.7,
          createdAt: Date.now() - 30 * 24 * 60 * 60 * 1000,
          lastRebalance: Date.now() - 6 * 60 * 60 * 1000,
          performance: {
            daily: 0.125,
            weekly: 0.88,
            monthly: 3.82,
            quarterly: 11.45,
            yearly: 45.8
          },
          fees: { management: 2.0, performance: 20.0, withdrawal: 0.5 },
          supportedTokens: [],
          chainDistribution: {
            'arbitrum': 45,
            'base': 30,
            'polygon': 25
          }
        }
      ];
      
      setVaults(mockVaults);
      
      if (userAddress) {
        // Mock portfolio data
        const mockPortfolio: PortfolioSummary = {
          userAddress,
          totalValue: 25847.32,
          totalDeposited: 22000.00,
          totalWithdrawn: 0,
          unrealizedPnL: 3847.32,
          realizedPnL: 0,
          totalReturns: 3847.32,
          totalReturnsPct: 17.49,
          positions: [
            {
              id: 'pos-1',
              vaultId: 'vault-1',
              userAddress,
              shares: BigInt('12000000000000000000000'),
              underlyingValue: 15234.56,
              entryPrice: 1.089,
              currentValue: 15234.56,
              unrealizedPnL: 2184.56,
              realizedPnL: 0,
              totalReturns: 2184.56,
              totalReturnsPct: 16.75,
              depositedAmount: 13050.00,
              withdrawnAmount: 0,
              lastActivity: Date.now() - 2 * 24 * 60 * 60 * 1000,
              createdAt: Date.now() - 45 * 24 * 60 * 60 * 1000,
              chain: 'ethereum',
              autoCompound: true,
              rewardsClaimed: 184.32,
              pendingRewards: 23.45
            },
            {
              id: 'pos-2',
              vaultId: 'vault-2',
              userAddress,
              shares: BigInt('7000000000000000000000'),
              underlyingValue: 10612.76,
              entryPrice: 1.156,
              currentValue: 10612.76,
              unrealizedPnL: 1662.76,
              realizedPnL: 0,
              totalReturns: 1662.76,
              totalReturnsPct: 18.58,
              depositedAmount: 8950.00,
              withdrawnAmount: 0,
              lastActivity: Date.now() - 1 * 24 * 60 * 60 * 1000,
              createdAt: Date.now() - 30 * 24 * 60 * 60 * 1000,
              chain: 'arbitrum',
              autoCompound: true,
              rewardsClaimed: 89.23,
              pendingRewards: 45.67
            }
          ],
          chainDistribution: {
            'ethereum': 58.9,
            'arbitrum': 41.1
          },
          protocolDistribution: {
            'Multi-Chain Yield Maximizer': 58.9,
            'DeFi Blue Chip Strategy': 41.1
          },
          riskDistribution: {
            'conservative': 58.9,
            'moderate': 41.1,
            'aggressive': 0,
            'degen': 0
          },
          pendingTransactions: [],
          alerts: [
            {
              id: 'alert-1',
              vaultId: 'vault-1',
              type: 'rebalance',
              severity: 'info',
              title: 'Rebalance Completed',
              message: 'Multi-Chain Yield Maximizer was rebalanced to optimize returns',
              timestamp: Date.now() - 2 * 60 * 60 * 1000,
              acknowledged: false,
              actionRequired: false
            }
          ]
        };
        
        setPortfolio(mockPortfolio);
      }
      
    } catch (error) {
      console.error('Failed to load vault data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleDepositClick = (vault: Vault) => {
    setSelectedVault(vault);
    setShowDepositModal(true);
  };

  const handleWithdrawClick = (vault: Vault) => {
    setSelectedVault(vault);
    setShowWithdrawModal(true);
  };

  if (loading) {
    return (
      <div className="max-w-7xl mx-auto p-6">
        <div className="space-y-6">
          <div className="animate-pulse">
            <div className="h-8 bg-gray-200 rounded w-1/4 mb-4"></div>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {[...Array(3)].map((_, i) => (
                <div key={i} className="h-32 bg-gray-200 rounded"></div>
              ))}
            </div>
            <div className="h-96 bg-gray-200 rounded mt-6"></div>
          </div>
        </div>
      </div>
    );
  }

  const totalTVL = vaults.reduce((sum, vault) => sum + vault.tvl, 0);
  const averageAPY = vaults.reduce((sum, vault) => sum + vault.apy.current, 0) / vaults.length;
  const activeVaults = vaults.length;

  return (
    <div className="max-w-7xl mx-auto p-6 space-y-8">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Vault Dashboard</h1>
          <p className="text-gray-600 mt-2">
            Automated yield strategies across multiple chains and protocols
          </p>
        </div>
        <div className="flex gap-2">
          <Button 
            variant="outline"
            onClick={() => setActiveTab(activeTab === 'strategies' ? 'overview' : 'strategies')}
          >
            <Zap className="w-4 h-4 mr-2" />
            Strategy Builder
          </Button>
          <Button onClick={() => setShowDepositModal(true)}>
            <Plus className="w-4 h-4 mr-2" />
            New Position
          </Button>
        </div>
      </div>

      {/* Tab Navigation */}
      <div className="border-b border-gray-200">
        <nav className="flex space-x-8">
          {[
            { id: 'overview', label: 'Overview', icon: BarChart3 },
            { id: 'vaults', label: 'All Vaults', icon: DollarSign },
            { id: 'positions', label: 'My Positions', icon: Wallet },
            { id: 'strategies', label: 'Strategy Builder', icon: Zap }
          ].map(tab => {
            const Icon = tab.icon;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as any)}
                className={`flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm ${
                  activeTab === tab.id
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                <Icon className="w-4 h-4" />
                {tab.label}
              </button>
            );
          })}
        </nav>
      </div>

      {activeTab === 'overview' && (
        <div className="space-y-8">
          {/* Global Stats */}
          <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
            <Card>
              <CardHeader className="flex flex-row items-center space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Total Value Locked</CardTitle>
                <DollarSign className="h-4 w-4 ml-auto text-green-600" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{formatCurrency(totalTVL)}</div>
                <p className="text-xs text-green-600 flex items-center gap-1">
                  <TrendingUp className="w-3 h-3" />
                  +12.3% this month
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Average APY</CardTitle>
                <TrendingUp className="h-4 w-4 ml-auto text-blue-600" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold text-blue-600">
                  {formatPercentage(averageAPY)}
                </div>
                <p className="text-xs text-gray-600">
                  Across {activeVaults} active strategies
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Active Vaults</CardTitle>
                <Activity className="h-4 w-4 ml-auto text-purple-600" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold text-purple-600">{activeVaults}</div>
                <p className="text-xs text-gray-600">
                  Multi-chain strategies
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Chains Supported</CardTitle>
                <Globe className="h-4 w-4 ml-auto text-orange-600" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold text-orange-600">8</div>
                <p className="text-xs text-gray-600">
                  Cross-chain optimization
                </p>
              </CardContent>
            </Card>
          </div>

          {/* Portfolio Summary for logged in users */}
          {userAddress && portfolio && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Wallet className="w-5 h-5" />
                  Your Portfolio Summary
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                  <div>
                    <p className="text-sm text-gray-600">Total Value</p>
                    <p className="text-2xl font-bold">{formatCurrency(portfolio.totalValue)}</p>
                    <p className="text-xs text-green-600 flex items-center gap-1">
                      <TrendingUp className="w-3 h-3" />
                      +{formatPercentage(portfolio.totalReturnsPct)}
                    </p>
                  </div>
                  <div>
                    <p className="text-sm text-gray-600">Unrealized P&L</p>
                    <p className={`text-2xl font-bold ${
                      portfolio.unrealizedPnL >= 0 ? 'text-green-600' : 'text-red-600'
                    }`}>
                      {portfolio.unrealizedPnL >= 0 ? '+' : ''}{formatCurrency(portfolio.unrealizedPnL)}
                    </p>
                  </div>
                  <div>
                    <p className="text-sm text-gray-600">Active Positions</p>
                    <p className="text-2xl font-bold">{portfolio.positions.length}</p>
                  </div>
                  <div>
                    <p className="text-sm text-gray-600">Pending Rewards</p>
                    <p className="text-2xl font-bold text-blue-600">
                      {formatCurrency(portfolio.positions.reduce((sum, pos) => sum + pos.pendingRewards, 0))}
                    </p>
                  </div>
                </div>
              </CardContent>
            </Card>
          )}

          {/* Alerts */}
          {portfolio?.alerts && portfolio.alerts.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <AlertCircle className="w-5 h-5 text-yellow-600" />
                  Recent Updates
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-3">
                  {portfolio.alerts.slice(0, 3).map(alert => (
                    <div key={alert.id} className="flex items-start gap-3 p-3 bg-gray-50 rounded-lg">
                      <div className={`w-2 h-2 rounded-full mt-2 ${
                        alert.severity === 'error' ? 'bg-red-500' :
                        alert.severity === 'warning' ? 'bg-yellow-500' :
                        'bg-blue-500'
                      }`} />
                      <div className="flex-1">
                        <p className="font-medium">{alert.title}</p>
                        <p className="text-sm text-gray-600">{alert.message}</p>
                        <p className="text-xs text-gray-500 mt-1">
                          {new Date(alert.timestamp).toLocaleString()}
                        </p>
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {activeTab === 'vaults' && (
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <h2 className="text-xl font-semibold">Available Vaults</h2>
            <div className="flex gap-2">
              <Badge variant="outline">{vaults.length} Active</Badge>
              <Badge variant="outline">{formatCurrency(totalTVL)} TVL</Badge>
            </div>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {vaults.map(vault => (
              <VaultCard
                key={vault.id}
                vault={vault}
                onDeposit={() => handleDepositClick(vault)}
                onWithdraw={() => handleWithdrawClick(vault)}
                userPosition={portfolio?.positions.find(p => p.vaultId === vault.id)}
              />
            ))}
          </div>
        </div>
      )}

      {activeTab === 'positions' && portfolio && (
        <PositionTracker 
          portfolio={portfolio}
          vaults={vaults}
          onWithdraw={handleWithdrawClick}
        />
      )}

      {activeTab === 'strategies' && (
        <StrategySelector
          vaults={vaults}
          onStrategySelect={onStrategySelect}
          onCreateVault={(strategy) => {
            // Handle vault creation
            console.log('Creating vault with strategy:', strategy);
            setActiveTab('vaults');
          }}
        />
      )}

      {/* Modals */}
      {showDepositModal && (
        <DepositModal
          vault={selectedVault}
          isOpen={showDepositModal}
          onClose={() => {
            setShowDepositModal(false);
            setSelectedVault(null);
          }}
          onSuccess={() => {
            setShowDepositModal(false);
            setSelectedVault(null);
            loadVaultData(); // Refresh data
          }}
        />
      )}

      {showWithdrawModal && selectedVault && portfolio && (
        <WithdrawModal
          vault={selectedVault}
          position={portfolio.positions.find(p => p.vaultId === selectedVault.id)!}
          isOpen={showWithdrawModal}
          onClose={() => {
            setShowWithdrawModal(false);
            setSelectedVault(null);
          }}
          onSuccess={() => {
            setShowWithdrawModal(false);
            setSelectedVault(null);
            loadVaultData(); // Refresh data
          }}
        />
      )}
    </div>
  );
}