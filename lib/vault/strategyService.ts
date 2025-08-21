/**
 * Strategy Service - Connect to yield strategies
 * Manages strategy discovery, analysis, and optimization
 */

import { ethers } from 'ethers';
import type { VaultStrategy } from '@/types/vault';
import { yieldDiscoveryEngine } from '@/lib/yield-discovery-engine';
import { priceService } from './priceService';

interface ProtocolAdapter {
  name: string;
  chains: string[];
  type: 'lending' | 'dex' | 'yield-aggregator' | 'options' | 'perpetuals' | 'staking';
  contracts: Record<string, string>;
  getStrategies: () => Promise<VaultStrategy[]>;
  getAPY: (strategyId: string) => Promise<number>;
  getTVL: (strategyId: string) => Promise<string>;
  getRiskMetrics: (strategyId: string) => Promise<{
    impermanentLoss: number;
    smartContract: number;
    liquidity: number;
  }>;
}

export class StrategyService {
  private adapters: Map<string, ProtocolAdapter>;
  private strategies: Map<string, VaultStrategy>;
  private providers: Map<string, ethers.Provider>;
  
  constructor() {
    this.adapters = new Map();
    this.strategies = new Map();
    this.providers = new Map();
    
    this.initializeProviders();
    this.initializeAdapters();
    this.startStrategyMonitoring();
  }
  
  private initializeProviders(): void {
    const rpcUrls: Record<string, string> = {
      ethereum: process.env.ETH_RPC_URL || '',
      arbitrum: process.env.ARB_RPC_URL || '',
      base: process.env.BASE_RPC_URL || '',
      polygon: process.env.POLY_RPC_URL || '',
      avalanche: process.env.AVAX_RPC_URL || ''
    };
    
    for (const [chain, url] of Object.entries(rpcUrls)) {
      if (url) {
        this.providers.set(chain, new ethers.JsonRpcProvider(url));
      }
    }
  }
  
  private initializeAdapters(): void {
    // Aerodrome Adapter (Base)
    this.adapters.set('aerodrome', {
      name: 'Aerodrome',
      chains: ['base'],
      type: 'dex',
      contracts: {
        factory: '0x420DD381b31aEf6683db6B902084cB0FFECe40Da',
        router: '0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43',
        voter: '0x16613524e02ad97eDfeF371bC883F2F5d6C480A5'
      },
      getStrategies: this.getAerodromeStrategies.bind(this),
      getAPY: this.getAerodromeAPY.bind(this),
      getTVL: this.getAerodromeTVL.bind(this),
      getRiskMetrics: this.getAerodromeRiskMetrics.bind(this)
    });
    
    // GMX Adapter (Arbitrum)
    this.adapters.set('gmx', {
      name: 'GMX',
      chains: ['arbitrum'],
      type: 'perpetuals',
      contracts: {
        vault: '0x489ee077994B6658eAfA855C308275EAd8097C4A',
        router: '0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064',
        rewardRouter: '0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1'
      },
      getStrategies: this.getGMXStrategies.bind(this),
      getAPY: this.getGMXAPY.bind(this),
      getTVL: this.getGMXTVL.bind(this),
      getRiskMetrics: this.getGMXRiskMetrics.bind(this)
    });
    
    // Pendle Adapter (Ethereum)
    this.adapters.set('pendle', {
      name: 'Pendle',
      chains: ['ethereum'],
      type: 'yield-aggregator',
      contracts: {
        router: '0x00000000005BBc6afDfF3894081585A0788aC2B0',
        factory: '0x27b1dAcd74688aF24a64BD3C9C1B143118740784'
      },
      getStrategies: this.getPendleStrategies.bind(this),
      getAPY: this.getPendleAPY.bind(this),
      getTVL: this.getPendleTVL.bind(this),
      getRiskMetrics: this.getPendleRiskMetrics.bind(this)
    });
    
    // Beefy Adapter (Multi-chain)
    this.adapters.set('beefy', {
      name: 'Beefy',
      chains: ['ethereum', 'polygon', 'arbitrum', 'avalanche'],
      type: 'yield-aggregator',
      contracts: {
        vault: '0x...', // Different per chain
      },
      getStrategies: this.getBeefyStrategies.bind(this),
      getAPY: this.getBeefyAPY.bind(this),
      getTVL: this.getBeefyTVL.bind(this),
      getRiskMetrics: this.getBeefyRiskMetrics.bind(this)
    });
  }
  
  /**
   * Discover all available strategies across protocols
   */
  async discoverAllStrategies(
    filters?: {
      chains?: string[];
      minAPY?: number;
      maxRisk?: number;
      protocols?: string[];
      types?: string[];
    }
  ): Promise<VaultStrategy[]> {
    const allStrategies: VaultStrategy[] = [];
    
    // Collect strategies from all adapters
    for (const [protocolName, adapter] of this.adapters) {
      if (filters?.protocols && !filters.protocols.includes(protocolName)) {
        continue;
      }
      
      try {
        const strategies = await adapter.getStrategies();
        allStrategies.push(...strategies);
      } catch (error) {
        console.error(`Failed to get strategies from ${protocolName}:`, error);
      }
    }
    
    // Apply filters
    let filtered = allStrategies;
    
    if (filters?.chains) {
      filtered = filtered.filter(s => filters.chains!.includes(s.chain));
    }
    
    if (filters?.minAPY) {
      filtered = filtered.filter(s => s.currentAPY >= filters.minAPY!);
    }
    
    if (filters?.maxRisk) {
      filtered = filtered.filter(s => s.riskScore <= filters.maxRisk!);
    }
    
    if (filters?.types) {
      filtered = filtered.filter(s => filters.types!.includes(s.type));
    }
    
    // Sort by risk-adjusted APY
    return filtered.sort((a, b) => {
      const aScore = a.currentAPY / (1 + a.riskScore / 10);
      const bScore = b.currentAPY / (1 + b.riskScore / 10);
      return bScore - aScore;
    });
  }
  
  /**
   * Get strategy by ID
   */
  async getStrategy(strategyId: string): Promise<VaultStrategy | null> {
    if (this.strategies.has(strategyId)) {
      return this.strategies.get(strategyId)!;
    }
    
    // Try to find in all adapters
    for (const adapter of this.adapters.values()) {
      try {
        const strategies = await adapter.getStrategies();
        const strategy = strategies.find(s => s.id === strategyId);
        if (strategy) {
          this.strategies.set(strategyId, strategy);
          return strategy;
        }
      } catch (error) {
        console.error('Error searching for strategy:', error);
      }
    }
    
    return null;
  }
  
  /**
   * Update strategy metrics
   */
  async updateStrategyMetrics(strategyId: string): Promise<VaultStrategy | null> {
    const strategy = await this.getStrategy(strategyId);
    if (!strategy) return null;
    
    const adapter = this.adapters.get(strategy.protocol.toLowerCase());
    if (!adapter) return null;
    
    try {
      // Update key metrics
      strategy.currentAPY = await adapter.getAPY(strategyId);
      strategy.tvl = await adapter.getTVL(strategyId);
      
      const riskMetrics = await adapter.getRiskMetrics(strategyId);
      strategy.impermanentLossRisk = riskMetrics.impermanentLoss;
      strategy.smartContractRisk = riskMetrics.smartContract;
      strategy.liquidityRisk = riskMetrics.liquidity;
      
      // Recalculate overall risk score
      strategy.riskScore = this.calculateOverallRiskScore(strategy);
      
      // Update predicted APY using ML if available
      strategy.predictedAPY = await this.predictAPY(strategy);
      
      strategy.lastUpdated = Date.now();
      
      this.strategies.set(strategyId, strategy);
      return strategy;
    } catch (error) {
      console.error('Failed to update strategy metrics:', error);
      return strategy;
    }
  }
  
  /**
   * Get strategy recommendations based on user profile
   */
  async getRecommendations(profile: {
    riskTolerance: 'conservative' | 'moderate' | 'aggressive' | 'degen';
    investmentAmount: string;
    preferredChains?: string[];
    timeHorizon: 'short' | 'medium' | 'long';
    diversification: boolean;
  }): Promise<VaultStrategy[]> {
    const allStrategies = await this.discoverAllStrategies({
      chains: profile.preferredChains
    });
    
    // Risk filtering
    const riskLimits = {
      conservative: 3,
      moderate: 5,
      aggressive: 7,
      degen: 10
    };
    
    let filtered = allStrategies.filter(s => s.riskScore <= riskLimits[profile.riskTolerance]);
    
    // Minimum deposit filtering
    const investmentAmount = BigInt(profile.investmentAmount);
    filtered = filtered.filter(s => 
      BigInt(s.minDeposit) <= investmentAmount && 
      BigInt(s.maxDeposit) >= investmentAmount
    );
    
    // Time horizon filtering
    if (profile.timeHorizon === 'short') {
      filtered = filtered.filter(s => s.lockupPeriod === 0); // No lockup for short term
    }
    
    // Diversification
    if (profile.diversification && filtered.length > 1) {
      // Select strategies from different protocols/types
      const diversified: VaultStrategy[] = [];
      const usedProtocols = new Set<string>();
      const usedTypes = new Set<string>();
      
      for (const strategy of filtered) {
        if (diversified.length >= 5) break; // Max 5 strategies
        
        const isNewProtocol = !usedProtocols.has(strategy.protocol);
        const isNewType = !usedTypes.has(strategy.type);
        
        if (isNewProtocol || isNewType) {
          diversified.push(strategy);
          usedProtocols.add(strategy.protocol);
          usedTypes.add(strategy.type);
        }
      }
      
      filtered = diversified;
    }
    
    return filtered.slice(0, 10); // Return top 10 recommendations
  }
  
  // Protocol-specific implementations
  private async getAerodromeStrategies(): Promise<VaultStrategy[]> {
    const strategies: VaultStrategy[] = [];
    
    try {
      // Mock Aerodrome strategies - in production, query the protocol
      const mockStrategy: VaultStrategy = {
        id: 'aerodrome-weth-usdc-volatile',
        name: 'WETH/USDC Volatile Pool',
        protocol: 'Aerodrome',
        chain: 'base',
        type: 'liquidity',
        description: 'High-yield WETH/USDC liquidity provision with AERO rewards',
        currentAPY: 28.5,
        predictedAPY: 30.2,
        tvl: '45000000',
        maxCapacity: '100000000',
        utilizationRate: 0.45,
        riskScore: 4.5,
        riskLevel: 'medium',
        minDeposit: '100',
        maxDeposit: '1000000',
        depositFee: 0.1,
        withdrawalFee: 0.1,
        performanceFee: 10,
        managementFee: 2,
        autoCompound: true,
        lockupPeriod: 0,
        impermanentLossRisk: 5,
        smartContractRisk: 3,
        liquidityRisk: 2,
        assets: {
          primary: 'WETH',
          secondary: 'USDC',
          lpToken: 'AERO-WETH-USDC'
        },
        rewards: {
          tokens: ['AERO'],
          emissions: ['1000'],
          claimable: true
        },
        historical: {
          apy7d: 26.8,
          apy30d: 29.2,
          maxDrawdown: 5.2,
          volatility: 15.8
        },
        lastUpdated: Date.now()
      };
      
      strategies.push(mockStrategy);
      
      // Add stable pool strategy
      strategies.push({
        ...mockStrategy,
        id: 'aerodrome-usdc-dai-stable',
        name: 'USDC/DAI Stable Pool',
        description: 'Low-risk stable pair with minimal impermanent loss',
        currentAPY: 12.3,
        predictedAPY: 13.1,
        riskScore: 2.8,
        riskLevel: 'low',
        impermanentLossRisk: 1,
        assets: {
          primary: 'USDC',
          secondary: 'DAI',
          lpToken: 'AERO-USDC-DAI'
        },
        tvl: '120000000',
        historical: {
          apy7d: 11.8,
          apy30d: 12.9,
          maxDrawdown: 1.2,
          volatility: 3.4
        }
      });
      
    } catch (error) {
      console.error('Failed to fetch Aerodrome strategies:', error);
    }
    
    return strategies;
  }
  
  private async getGMXStrategies(): Promise<VaultStrategy[]> {
    const strategies: VaultStrategy[] = [];
    
    try {
      const gmxStrategy: VaultStrategy = {
        id: 'gmx-staking-arbitrum',
        name: 'GMX Staking',
        protocol: 'GMX',
        chain: 'arbitrum',
        type: 'staking',
        description: 'Stake GMX tokens for fees, esGMX, and multiplier points',
        currentAPY: 23.8,
        predictedAPY: 25.5,
        tvl: '380000000',
        maxCapacity: '500000000',
        utilizationRate: 0.76,
        riskScore: 4.2,
        riskLevel: 'medium',
        minDeposit: '50',
        maxDeposit: '500000',
        depositFee: 0,
        withdrawalFee: 0,
        performanceFee: 15,
        managementFee: 2,
        autoCompound: false,
        lockupPeriod: 0,
        impermanentLossRisk: 0,
        smartContractRisk: 3,
        liquidityRisk: 1,
        assets: {
          primary: 'GMX'
        },
        rewards: {
          tokens: ['ETH', 'esGMX'],
          emissions: ['0', '100'],
          claimable: true
        },
        historical: {
          apy7d: 22.1,
          apy30d: 24.6,
          maxDrawdown: 3.8,
          volatility: 12.4
        },
        lastUpdated: Date.now()
      };
      
      strategies.push(gmxStrategy);
    } catch (error) {
      console.error('Failed to fetch GMX strategies:', error);
    }
    
    return strategies;
  }
  
  private async getPendleStrategies(): Promise<VaultStrategy[]> {
    const strategies: VaultStrategy[] = [];
    
    try {
      const pendleStrategy: VaultStrategy = {
        id: 'pendle-steth-lrt',
        name: 'Pendle stETH LRT Strategy',
        protocol: 'Pendle',
        chain: 'ethereum',
        type: 'yield-farming',
        description: 'Liquid Restaking Token yield optimization via Pendle',
        currentAPY: 15.7,
        predictedAPY: 18.2,
        tvl: '220000000',
        maxCapacity: '300000000',
        utilizationRate: 0.73,
        riskScore: 5.1,
        riskLevel: 'medium',
        minDeposit: '1000',
        maxDeposit: '100000',
        depositFee: 0.2,
        withdrawalFee: 0.1,
        performanceFee: 12,
        managementFee: 2,
        autoCompound: true,
        lockupPeriod: 0,
        impermanentLossRisk: 2,
        smartContractRisk: 4,
        liquidityRisk: 3,
        assets: {
          primary: 'stETH',
          lpToken: 'PT-stETH'
        },
        rewards: {
          tokens: ['PENDLE'],
          emissions: ['50'],
          claimable: true
        },
        historical: {
          apy7d: 14.2,
          apy30d: 16.8,
          maxDrawdown: 2.1,
          volatility: 8.9
        },
        lastUpdated: Date.now()
      };
      
      strategies.push(pendleStrategy);
    } catch (error) {
      console.error('Failed to fetch Pendle strategies:', error);
    }
    
    return strategies;
  }
  
  private async getBeefyStrategies(): Promise<VaultStrategy[]> {
    // Implementation for Beefy Finance strategies across multiple chains
    return [];
  }
  
  // Protocol-specific APY fetchers
  private async getAerodromeAPY(strategyId: string): Promise<number> {
    // Implementation to fetch real APY from Aerodrome
    return Math.random() * 50 + 10; // Mock 10-60% APY
  }
  
  private async getGMXAPY(strategyId: string): Promise<number> {
    // Implementation to fetch GMX staking APY
    return Math.random() * 30 + 15; // Mock 15-45% APY
  }
  
  private async getPendleAPY(strategyId: string): Promise<number> {
    // Implementation to fetch Pendle yield
    return Math.random() * 25 + 8; // Mock 8-33% APY
  }
  
  private async getBeefyAPY(strategyId: string): Promise<number> {
    return Math.random() * 40 + 5; // Mock 5-45% APY
  }
  
  // TVL fetchers
  private async getAerodromeTVL(strategyId: string): Promise<string> {
    return (Math.random() * 100000000 + 10000000).toString(); // 10M-110M
  }
  
  private async getGMXTVL(strategyId: string): Promise<string> {
    return '380000000'; // ~380M for GMX
  }
  
  private async getPendleTVL(strategyId: string): Promise<string> {
    return (Math.random() * 300000000 + 100000000).toString(); // 100M-400M
  }
  
  private async getBeefyTVL(strategyId: string): Promise<string> {
    return (Math.random() * 50000000 + 5000000).toString(); // 5M-55M
  }
  
  // Risk metrics fetchers
  private async getAerodromeRiskMetrics(strategyId: string): Promise<any> {
    return {
      impermanentLoss: strategyId.includes('stable') ? 1 : 5,
      smartContract: 3,
      liquidity: 2
    };
  }
  
  private async getGMXRiskMetrics(strategyId: string): Promise<any> {
    return {
      impermanentLoss: 0, // No IL for single asset staking
      smartContract: 3,
      liquidity: 1
    };
  }
  
  private async getPendleRiskMetrics(strategyId: string): Promise<any> {
    return {
      impermanentLoss: 2,
      smartContract: 4,
      liquidity: 3
    };
  }
  
  private async getBeefyRiskMetrics(strategyId: string): Promise<any> {
    return {
      impermanentLoss: 3,
      smartContract: 4,
      liquidity: 2
    };
  }
  
  // Helper methods
  private calculateOverallRiskScore(strategy: VaultStrategy): number {
    const weights = {
      impermanentLoss: 0.3,
      smartContract: 0.25,
      liquidity: 0.2,
      market: 0.25
    };
    
    const marketRisk = this.calculateMarketRisk(strategy);
    
    return Math.round(
      strategy.impermanentLossRisk * weights.impermanentLoss +
      strategy.smartContractRisk * weights.smartContract +
      strategy.liquidityRisk * weights.liquidity +
      marketRisk * weights.market
    );
  }
  
  private calculateMarketRisk(strategy: VaultStrategy): number {
    // Market risk based on volatility and asset type
    const baseRisk = {
      lending: 2,
      liquidity: 4,
      'yield-farming': 5,
      staking: 3,
      options: 8,
      perpetuals: 9
    }[strategy.type] || 5;
    
    const volatilityAdjustment = (strategy.historical?.volatility || 15) / 15; // Normalize to 15%
    
    return Math.min(Math.round(baseRisk * volatilityAdjustment), 10);
  }
  
  private async predictAPY(strategy: VaultStrategy): Promise<number> {
    try {
      // Call ML prediction API
      const response = await fetch('http://localhost:8000/predict/apy', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          protocol: strategy.protocol,
          tvl: strategy.tvl,
          current_apy: strategy.currentAPY,
          volatility: strategy.historical?.volatility || 15,
          utilization_rate: strategy.utilizationRate
        })
      });
      
      if (response.ok) {
        const data = await response.json();
        return data.predicted_apy || strategy.currentAPY * 1.05; // 5% optimistic if no prediction
      }
    } catch (error) {
      console.error('APY prediction failed:', error);
    }
    
    // Fallback prediction
    return strategy.currentAPY * (0.95 + Math.random() * 0.1); // ±5% variation
  }
  
  private startStrategyMonitoring(): void {
    // Update strategies every 5 minutes
    setInterval(async () => {
      console.log('Updating strategy metrics...');
      
      for (const strategyId of this.strategies.keys()) {
        try {
          await this.updateStrategyMetrics(strategyId);
        } catch (error) {
          console.error(`Failed to update strategy ${strategyId}:`, error);
        }
      }
    }, 5 * 60 * 1000); // 5 minutes
  }
}

// Export singleton instance
export const strategyService = new StrategyService();