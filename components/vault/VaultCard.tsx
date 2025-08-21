"use client";

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import type { Vault, VaultPosition } from '@/types/vault';
import { formatCurrency, formatPercentage } from '@/lib/utils';
import {
  TrendingUp,
  TrendingDown,
  DollarSign,
  Shield,
  Activity,
  Globe,
  Clock,
  AlertCircle,
  ChevronRight,
  Zap,
  BarChart3
} from 'lucide-react';

interface VaultCardProps {
  vault: Vault;
  onDeposit: () => void;
  onWithdraw: () => void;
  userPosition?: VaultPosition;
  compact?: boolean;
}

export function VaultCard({ 
  vault, 
  onDeposit, 
  onWithdraw, 
  userPosition,
  compact = false 
}: VaultCardProps) {
  const [showDetails, setShowDetails] = useState(false);
  
  const getRiskColor = (risk: string) => {
    switch (risk) {
      case 'conservative': return 'text-green-600 bg-green-100';
      case 'moderate': return 'text-blue-600 bg-blue-100';
      case 'aggressive': return 'text-orange-600 bg-orange-100';
      case 'degen': return 'text-red-600 bg-red-100';
      default: return 'text-gray-600 bg-gray-100';
    }
  };

  const getRiskIcon = (risk: string) => {
    switch (risk) {
      case 'conservative': return <Shield className="w-4 h-4" />;
      case 'moderate': return <BarChart3 className="w-4 h-4" />;
      case 'aggressive': return <TrendingUp className="w-4 h-4" />;
      case 'degen': return <Zap className="w-4 h-4" />;
      default: return <Shield className="w-4 h-4" />;
    }
  };

  const getPerformanceColor = (perf: number) => {
    if (perf > 0) return 'text-green-600';
    if (perf < 0) return 'text-red-600';
    return 'text-gray-600';
  };

  const hasUserPosition = userPosition && Number(userPosition.shares) > 0;
  const utilizationColor = vault.utilizationRate > 90 ? 'bg-red-500' : 
                          vault.utilizationRate > 75 ? 'bg-yellow-500' : 
                          'bg-green-500';

  if (compact) {
    return (
      <Card className="cursor-pointer hover:shadow-md transition-all duration-200">
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div className="flex-1">
              <div className="flex items-center gap-2 mb-1">
                <h4 className="font-semibold text-sm">{vault.name}</h4>
                <Badge className={`text-xs ${getRiskColor(vault.strategy.riskLevel)}`}>
                  {vault.strategy.riskLevel}
                </Badge>
              </div>
              <div className="flex items-center gap-4 text-sm">
                <div>
                  <span className="text-gray-600">APY: </span>
                  <span className="font-semibold text-green-600">
                    {formatPercentage(vault.apy.current)}
                  </span>
                </div>
                <div>
                  <span className="text-gray-600">TVL: </span>
                  <span className="font-semibold">
                    {formatCurrency(vault.tvl)}
                  </span>
                </div>
              </div>
            </div>
            <div className="flex items-center gap-2">
              {hasUserPosition && (
                <div className="text-right">
                  <p className="text-xs text-gray-600">Your Position</p>
                  <p className="text-sm font-semibold text-blue-600">
                    {formatCurrency(userPosition.currentValue)}
                  </p>
                </div>
              )}
              <Button size="sm" onClick={hasUserPosition ? onWithdraw : onDeposit}>
                {hasUserPosition ? 'Manage' : 'Deposit'}
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="hover:shadow-lg transition-all duration-300 border-0 bg-gradient-to-br from-white to-gray-50">
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between">
          <div className="flex-1">
            <div className="flex items-center gap-2 mb-1">
              <CardTitle className="text-lg">{vault.name}</CardTitle>
              <Badge className={`text-xs px-2 py-1 ${getRiskColor(vault.strategy.riskLevel)}`}>
                {getRiskIcon(vault.strategy.riskLevel)}
                {vault.strategy.riskLevel}
              </Badge>
            </div>
            <p className="text-sm text-gray-600 leading-relaxed">
              {vault.strategy.description}
            </p>
          </div>
          {vault.utilizationRate > 95 && (
            <AlertCircle className="w-5 h-5 text-yellow-600 flex-shrink-0" />
          )}
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* Key Metrics */}
        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-2">
            <div className="flex items-center gap-2">
              <TrendingUp className="w-4 h-4 text-green-600" />
              <span className="text-sm text-gray-600">Current APY</span>
            </div>
            <div className="text-2xl font-bold text-green-600">
              {formatPercentage(vault.apy.current)}
            </div>
            <div className="text-xs text-gray-500">
              30d avg: {formatPercentage(vault.apy.average30d)}
            </div>
          </div>
          
          <div className="space-y-2">
            <div className="flex items-center gap-2">
              <DollarSign className="w-4 h-4 text-blue-600" />
              <span className="text-sm text-gray-600">TVL</span>
            </div>
            <div className="text-2xl font-bold text-blue-600">
              {formatCurrency(vault.tvl / 1000000, 1)}M
            </div>
            <div className="text-xs text-gray-500">
              Cap: {formatCurrency(vault.capacity / 1000000, 1)}M
            </div>
          </div>
        </div>

        {/* Utilization */}
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span className="text-gray-600">Capacity Utilization</span>
            <span className="font-medium">{vault.utilizationRate.toFixed(1)}%</span>
          </div>
          <Progress 
            value={vault.utilizationRate} 
            className={`h-2 ${utilizationColor}`}
          />
          {vault.utilizationRate > 95 && (
            <p className="text-xs text-yellow-700 bg-yellow-50 p-2 rounded">
              ⚠️ Vault is near capacity - deposits may be limited
            </p>
          )}
        </div>

        {/* Chain Distribution */}
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <Globe className="w-4 h-4 text-purple-600" />
            <span className="text-sm text-gray-600">Chain Distribution</span>
          </div>
          <div className="flex flex-wrap gap-1">
            {Object.entries(vault.chainDistribution).map(([chain, percentage]) => (
              <Badge 
                key={chain} 
                variant="outline" 
                className="text-xs capitalize px-2 py-1"
              >
                {chain}: {percentage}%
              </Badge>
            ))}
          </div>
        </div>

        {/* Performance Indicators */}
        <div className="grid grid-cols-3 gap-2 text-xs">
          <div className="text-center p-2 bg-gray-50 rounded">
            <p className="text-gray-600">24h</p>
            <p className={`font-semibold ${getPerformanceColor(vault.performance.daily)}`}>
              {vault.performance.daily > 0 ? '+' : ''}{vault.performance.daily.toFixed(2)}%
            </p>
          </div>
          <div className="text-center p-2 bg-gray-50 rounded">
            <p className="text-gray-600">7d</p>
            <p className={`font-semibold ${getPerformanceColor(vault.performance.weekly)}`}>
              {vault.performance.weekly > 0 ? '+' : ''}{vault.performance.weekly.toFixed(2)}%
            </p>
          </div>
          <div className="text-center p-2 bg-gray-50 rounded">
            <p className="text-gray-600">30d</p>
            <p className={`font-semibold ${getPerformanceColor(vault.performance.monthly)}`}>
              {vault.performance.monthly > 0 ? '+' : ''}{vault.performance.monthly.toFixed(2)}%
            </p>
          </div>
        </div>

        {/* User Position (if exists) */}
        {hasUserPosition && (
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-3 space-y-2">
            <div className="flex items-center gap-2">
              <Activity className="w-4 h-4 text-blue-600" />
              <span className="text-sm font-medium text-blue-900">Your Position</span>
            </div>
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <p className="text-blue-700">Current Value</p>
                <p className="font-semibold text-blue-900">
                  {formatCurrency(userPosition.currentValue)}
                </p>
              </div>
              <div>
                <p className="text-blue-700">Unrealized P&L</p>
                <p className={`font-semibold ${
                  userPosition.unrealizedPnL >= 0 ? 'text-green-600' : 'text-red-600'
                }`}>
                  {userPosition.unrealizedPnL >= 0 ? '+' : ''}
                  {formatCurrency(userPosition.unrealizedPnL)}
                </p>
              </div>
              <div>
                <p className="text-blue-700">Returns</p>
                <p className={`font-semibold ${
                  userPosition.totalReturnsPct >= 0 ? 'text-green-600' : 'text-red-600'
                }`}>
                  {userPosition.totalReturnsPct >= 0 ? '+' : ''}
                  {formatPercentage(userPosition.totalReturnsPct)}
                </p>
              </div>
              <div>
                <p className="text-blue-700">Pending Rewards</p>
                <p className="font-semibold text-blue-900">
                  {formatCurrency(userPosition.pendingRewards)}
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Fees */}
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <span className="text-sm text-gray-600">Fees</span>
          </div>
          <div className="flex justify-between text-xs text-gray-600">
            <span>Management: {vault.fees.management}%</span>
            <span>Performance: {vault.fees.performance}%</span>
            <span>Withdrawal: {vault.fees.withdrawal}%</span>
          </div>
        </div>

        {/* Last Rebalance */}
        <div className="flex items-center gap-2 text-xs text-gray-500">
          <Clock className="w-3 h-3" />
          <span>
            Last rebalanced: {new Date(vault.lastRebalance).toLocaleDateString()}
          </span>
        </div>

        {/* Action Buttons */}
        <div className="flex gap-2 pt-2">
          {hasUserPosition ? (
            <>
              <Button 
                variant="outline" 
                size="sm" 
                className="flex-1"
                onClick={() => setShowDetails(!showDetails)}
              >
                Details
                <ChevronRight className={`w-4 h-4 ml-1 transition-transform ${
                  showDetails ? 'rotate-90' : ''
                }`} />
              </Button>
              <Button 
                variant="outline" 
                size="sm" 
                onClick={onDeposit}
              >
                Add Funds
              </Button>
              <Button 
                size="sm" 
                onClick={onWithdraw}
                className="bg-blue-600 hover:bg-blue-700"
              >
                Manage
              </Button>
            </>
          ) : (
            <>
              <Button 
                variant="outline" 
                size="sm" 
                className="flex-1"
                onClick={() => setShowDetails(!showDetails)}
              >
                Learn More
                <ChevronRight className={`w-4 h-4 ml-1 transition-transform ${
                  showDetails ? 'rotate-90' : ''
                }`} />
              </Button>
              <Button 
                size="sm" 
                onClick={onDeposit}
                className="bg-green-600 hover:bg-green-700 flex-1"
              >
                Deposit
              </Button>
            </>
          )}
        </div>

        {/* Expandable Details */}
        {showDetails && (
          <div className="mt-4 pt-4 border-t border-gray-200 space-y-3">
            <div>
              <h5 className="font-medium text-sm mb-2">Strategy Details</h5>
              <div className="text-xs text-gray-600 space-y-1">
                <p><span className="font-medium">Target Protocols:</span> {vault.strategy.targetProtocols.join(', ')}</p>
                <p><span className="font-medium">Target Chains:</span> {vault.strategy.targetChains.join(', ')}</p>
                <p><span className="font-medium">Min Deposit:</span> {formatCurrency(vault.strategy.minDeposit)}</p>
                <p><span className="font-medium">Auto Compound:</span> {vault.strategy.autoCompound ? 'Yes' : 'No'}</p>
                <p><span className="font-medium">Auto Rebalance:</span> {vault.strategy.autoRebalance ? 'Yes' : 'No'}</p>
              </div>
            </div>
            
            <div>
              <h5 className="font-medium text-sm mb-2">Risk Assessment</h5>
              <div className="text-xs text-gray-600">
                <p>This is a <span className="font-medium capitalize">{vault.strategy.riskLevel}</span> risk strategy targeting established protocols with proven track records.</p>
              </div>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}