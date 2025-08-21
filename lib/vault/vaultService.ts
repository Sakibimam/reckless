/**
 * Vault Service - Core vault interaction logic
 * Handles deposits, withdrawals, and position management
 */

import { ethers } from 'ethers';
import type { 
  VaultPosition, 
  VaultStrategy, 
  DepositRequest, 
  WithdrawRequest,
  VaultEstimate,
  VaultTransaction,
  UserVaultSummary,
  RebalanceRecommendation
} from '@/types/vault';
import { crossChainService } from './crossChainService';
import { strategyService } from './strategyService';
import { priceService } from './priceService';
import { yieldDiscoveryEngine } from '@/lib/yield-discovery-engine';
import { realTimeMonitor } from '@/lib/real-time-monitor';

// Vault contract ABIs (simplified)
const VAULT_ABI = [
  'function deposit(uint256 assets, address receiver) external returns (uint256 shares)',
  'function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares)',
  'function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets)',
  'function previewDeposit(uint256 assets) external view returns (uint256 shares)',
  'function previewWithdraw(uint256 assets) external view returns (uint256 shares)',
  'function previewRedeem(uint256 shares) external view returns (uint256 assets)',
  'function totalAssets() external view returns (uint256)',
  'function totalSupply() external view returns (uint256)',
  'function balanceOf(address account) external view returns (uint256)',
  'function getCurrentAPY() external view returns (uint256)',
  'function emergencyWithdraw(uint256 shares, address receiver) external returns (uint256 assets)'
];

const CROSS_CHAIN_VAULT_ABI = [
  ...VAULT_ABI,
  'function crossChainDeposit(uint16 destinationChain, uint256 amount, address receiver, bytes calldata adapterParams) external payable returns (bytes32 nonce)',
  'function crossChainWithdraw(uint16 destinationChain, uint256 shares, address receiver, bytes calldata adapterParams) external payable returns (bytes32 nonce)',
  'function estimateFees(uint16 destinationChain, bool payInZRO, bytes calldata adapterParams) external view returns (uint256 nativeFee, uint256 zroFee)'
];

interface ChainConfig {
  name: string;
  chainId: number;
  rpcUrl: string;
  vaultFactory: string;
  crossChainVaultFactory: string;
  nativeToken: string;
}

export class VaultService {
  private providers: Map<string, ethers.Provider>;
  private vaultContracts: Map<string, ethers.Contract>;
  private positions: Map<string, VaultPosition>;
  private strategies: Map<string, VaultStrategy>;
  private chainConfigs: Map<string, ChainConfig>;
  
  constructor() {
    this.providers = new Map();
    this.vaultContracts = new Map();
    this.positions = new Map();
    this.strategies = new Map();
    this.chainConfigs = this.initializeChainConfigs();
    
    this.initializeProviders();
    this.startPositionMonitoring();
  }
  
  private initializeChainConfigs(): Map<string, ChainConfig> {
    const configs = new Map<string, ChainConfig>();
    
    configs.set('ethereum', {
      name: 'Ethereum',
      chainId: 1,
      rpcUrl: process.env.ETH_RPC_URL || '',
      vaultFactory: '0x...', // Deploy address
      crossChainVaultFactory: '0x...', // Deploy address
      nativeToken: 'ETH'
    });
    
    configs.set('arbitrum', {
      name: 'Arbitrum',
      chainId: 42161,
      rpcUrl: process.env.ARB_RPC_URL || '',
      vaultFactory: '0x...',
      crossChainVaultFactory: '0x...',
      nativeToken: 'ETH'
    });
    
    configs.set('base', {
      name: 'Base',
      chainId: 8453,
      rpcUrl: process.env.BASE_RPC_URL || '',
      vaultFactory: '0x...',
      crossChainVaultFactory: '0x...',
      nativeToken: 'ETH'
    });
    
    configs.set('polygon', {
      name: 'Polygon',
      chainId: 137,
      rpcUrl: process.env.POLY_RPC_URL || '',
      vaultFactory: '0x...',
      crossChainVaultFactory: '0x...',
      nativeToken: 'MATIC'
    });
    
    configs.set('avalanche', {
      name: 'Avalanche',
      chainId: 43114,
      rpcUrl: process.env.AVAX_RPC_URL || '',
      vaultFactory: '0x...',
      crossChainVaultFactory: '0x...',
      nativeToken: 'AVAX'
    });
    
    return configs;
  }
  
  private initializeProviders(): void {
    for (const [chain, config] of this.chainConfigs) {
      if (config.rpcUrl) {
        this.providers.set(chain, new ethers.JsonRpcProvider(config.rpcUrl));
      }
    }
  }
  
  /**
   * Process cross-chain deposit request
   */
  async processDeposit(request: DepositRequest): Promise<{
    transactionId: string;
    positionId: string;
    steps: any[];
    estimatedShares: string;
    fees: string;
  }> {
    try {
      // Validate request
      await this.validateDepositRequest(request);
      
      // Get strategy details
      const strategy = await this.getStrategy(request.strategyId);
      if (!strategy) {
        throw new Error('Strategy not found');
      }
      
      // Generate position ID
      const positionId = this.generatePositionId(request.userAddress, request.strategyId);
      
      // Determine if cross-chain deposit is needed
      const isCrossChain = request.fromChain !== request.toChain;
      let route = null;
      let steps: any[] = [];
      
      if (isCrossChain) {
        // Find optimal cross-chain route
        route = await crossChainService.findOptimalRoute(
          request.fromChain,
          request.toChain,
          request.amount,
          strategy.protocol
        );
        steps = route.steps;
      } else {
        // Direct deposit on same chain
        steps = [{
          type: 'deposit',
          protocol: strategy.protocol,
          chain: request.toChain,
          amount: request.amount,
          description: `Deposit ${request.amount} ${request.token} to ${strategy.name}`
        }];
      }
      
      // Estimate shares and fees
      const estimate = await this.estimateDeposit(request, strategy);
      
      // Create position record
      const position: VaultPosition = {
        id: positionId,
        userAddress: request.userAddress,
        vaultAddress: strategy.id, // Assuming strategy.id is vault address
        chain: request.toChain,
        protocol: strategy.protocol,
        depositAmount: request.amount,
        sharesOwned: estimate.expectedShares,
        currentValue: request.amount,
        entryPrice: '1.0', // Will be updated after deposit
        currentPrice: '1.0',
        apy: strategy.currentAPY,
        pnl: '0',
        pnlPercentage: 0,
        depositTimestamp: Date.now(),
        lastUpdateTimestamp: Date.now(),
        strategy: {
          name: strategy.name,
          type: strategy.type,
          riskLevel: strategy.riskLevel,
          autoCompound: strategy.autoCompound
        },
        crossChain: {
          originChain: request.fromChain,
          bridgeUsed: isCrossChain ? route?.bridge : undefined,
          bridgeFees: isCrossChain ? route?.totalFees : undefined
        }
      };
      
      this.positions.set(positionId, position);
      
      // Execute deposit transaction
      const transactionId = await this.executeDeposit(request, strategy, route);
      
      return {
        transactionId,
        positionId,
        steps,
        estimatedShares: estimate.expectedShares,
        fees: estimate.fees.total
      };
      
    } catch (error) {
      console.error('Deposit processing failed:', error);
      throw error;
    }
  }
  
  /**
   * Process withdrawal request
   */
  async processWithdraw(request: WithdrawRequest): Promise<{
    transactionId: string;
    estimatedAmount: string;
    steps: any[];
    fees: string;
  }> {
    try {
      // Get position details
      const position = this.positions.get(request.positionId);
      if (!position) {
        throw new Error('Position not found');
      }
      
      // Validate withdrawal amount
      if (request.type === 'shares') {
        const userShares = BigInt(position.sharesOwned);
        const withdrawShares = BigInt(request.amount);
        if (withdrawShares > userShares) {
          throw new Error('Insufficient shares');
        }
      }
      
      // Get strategy for vault
      const strategy = Array.from(this.strategies.values())
        .find(s => s.id === position.vaultAddress);
      
      if (!strategy) {
        throw new Error('Strategy not found for position');
      }
      
      // Determine if cross-chain withdrawal is needed
      const isCrossChain = request.fromChain !== request.toChain;
      let route = null;
      let steps: any[] = [];
      
      if (isCrossChain) {
        // Find cross-chain withdrawal route
        route = await crossChainService.findWithdrawalRoute(
          request.fromChain,
          request.toChain,
          request.amount,
          strategy.assets.primary
        );
        steps = route.steps;
      } else {
        // Direct withdrawal
        steps = [{
          type: 'withdraw',
          protocol: strategy.protocol,
          chain: request.fromChain,
          amount: request.amount,
          description: `Withdraw ${request.amount} from ${strategy.name}`
        }];
      }
      
      // Estimate withdrawal amount
      const estimatedAmount = await this.estimateWithdrawal(position, request);
      
      // Calculate fees
      const fees = await this.calculateWithdrawalFees(request, strategy, route);
      
      // Execute withdrawal
      const transactionId = await this.executeWithdraw(request, position, strategy, route);
      
      // Update position
      if (request.partialWithdraw) {
        position.sharesOwned = (BigInt(position.sharesOwned) - BigInt(request.amount)).toString();
        position.lastUpdateTimestamp = Date.now();
        this.positions.set(request.positionId, position);
      } else {
        // Full withdrawal - remove position
        this.positions.delete(request.positionId);
      }
      
      return {
        transactionId,
        estimatedAmount,
        steps,
        fees: fees.total
      };
      
    } catch (error) {
      console.error('Withdrawal processing failed:', error);
      throw error;
    }
  }
  
  /**
   * Get user's vault positions
   */
  async getUserPositions(userAddress: string): Promise<VaultPosition[]> {
    const userPositions = Array.from(this.positions.values())
      .filter(p => p.userAddress.toLowerCase() === userAddress.toLowerCase());
    
    // Update current values and PnL
    for (const position of userPositions) {
      await this.updatePositionMetrics(position);
    }
    
    return userPositions.sort((a, b) => b.lastUpdateTimestamp - a.lastUpdateTimestamp);
  }
  
  /**
   * Get user vault summary
   */
  async getUserVaultSummary(userAddress: string): Promise<UserVaultSummary> {
    const positions = await this.getUserPositions(userAddress);
    
    if (positions.length === 0) {
      return {
        totalValue: '0',
        totalPositions: 0,
        averageAPY: 0,
        totalPnL: '0',
        totalPnLPercentage: 0,
        dailyReturn: '0',
        weeklyReturn: '0',
        monthlyReturn: '0',
        positions: [],
        chainDistribution: {},
        protocolDistribution: {},
        riskDistribution: {}
      };
    }
    
    // Calculate aggregated metrics
    let totalValue = BigInt(0);
    let totalDeposits = BigInt(0);
    let weightedAPY = 0;
    const chainDistribution: Record<string, any> = {};
    const protocolDistribution: Record<string, any> = {};
    const riskDistribution: Record<string, any> = {};
    
    for (const position of positions) {
      const value = BigInt(position.currentValue);
      const deposit = BigInt(position.depositAmount);
      
      totalValue += value;
      totalDeposits += deposit;
      weightedAPY += position.apy * Number(value);
      
      // Chain distribution
      if (!chainDistribution[position.chain]) {
        chainDistribution[position.chain] = { value: '0', percentage: 0, positions: 0 };
      }
      chainDistribution[position.chain].value = 
        (BigInt(chainDistribution[position.chain].value) + value).toString();
      chainDistribution[position.chain].positions += 1;
      
      // Protocol distribution
      if (!protocolDistribution[position.protocol]) {
        protocolDistribution[position.protocol] = { value: '0', percentage: 0, positions: 0 };
      }
      protocolDistribution[position.protocol].value = 
        (BigInt(protocolDistribution[position.protocol].value) + value).toString();
      protocolDistribution[position.protocol].positions += 1;
      
      // Risk distribution
      const riskLevel = position.strategy.riskLevel;
      if (!riskDistribution[riskLevel]) {
        riskDistribution[riskLevel] = { value: '0', percentage: 0, positions: 0 };
      }
      riskDistribution[riskLevel].value = 
        (BigInt(riskDistribution[riskLevel].value) + value).toString();
      riskDistribution[riskLevel].positions += 1;
    }
    
    // Calculate percentages
    const totalValueNum = Number(totalValue);
    for (const chain in chainDistribution) {
      chainDistribution[chain].percentage = 
        Number(chainDistribution[chain].value) / totalValueNum * 100;
    }
    for (const protocol in protocolDistribution) {
      protocolDistribution[protocol].percentage = 
        Number(protocolDistribution[protocol].value) / totalValueNum * 100;
    }
    for (const risk in riskDistribution) {
      riskDistribution[risk].percentage = 
        Number(riskDistribution[risk].value) / totalValueNum * 100;
    }
    
    const averageAPY = weightedAPY / totalValueNum;
    const totalPnL = totalValue - totalDeposits;
    const totalPnLPercentage = Number(totalDeposits) > 0 
      ? Number(totalPnL) / Number(totalDeposits) * 100 
      : 0;
    
    return {
      totalValue: totalValue.toString(),
      totalPositions: positions.length,
      averageAPY,
      totalPnL: totalPnL.toString(),
      totalPnLPercentage,
      dailyReturn: (totalValueNum * averageAPY / 365 / 100).toString(),
      weeklyReturn: (totalValueNum * averageAPY / 52 / 100).toString(),
      monthlyReturn: (totalValueNum * averageAPY / 12 / 100).toString(),
      positions,
      chainDistribution,
      protocolDistribution,
      riskDistribution
    };
  }
  
  /**
   * Get available strategies
   */
  async getAvailableStrategies(
    chain?: string,
    minAPY?: number,
    maxRisk?: number
  ): Promise<VaultStrategy[]> {
    let strategies = Array.from(this.strategies.values());
    
    // Apply filters
    if (chain) {
      strategies = strategies.filter(s => s.chain === chain);
    }
    if (minAPY) {
      strategies = strategies.filter(s => s.currentAPY >= minAPY);
    }
    if (maxRisk) {
      strategies = strategies.filter(s => s.riskScore <= maxRisk);
    }
    
    // Sort by risk-adjusted APY
    return strategies.sort((a, b) => {
      const aScore = a.currentAPY / (1 + a.riskScore);
      const bScore = b.currentAPY / (1 + b.riskScore);
      return bScore - aScore;
    });
  }
  
  /**
   * Estimate deposit returns
   */
  async estimateDeposit(
    request: DepositRequest,
    strategy: VaultStrategy
  ): Promise<VaultEstimate> {
    const amount = BigInt(request.amount);
    
    // Get current vault metrics
    const vaultContract = await this.getVaultContract(strategy.id, request.toChain);
    const previewShares = await vaultContract.previewDeposit(amount);
    
    // Calculate fees
    const depositFee = BigInt(request.amount) * BigInt(Math.floor(strategy.depositFee * 100)) / BigInt(10000);
    const gasFee = await this.estimateGasFee(request.toChain, 'deposit');
    let bridgeFee = BigInt(0);
    
    if (request.fromChain !== request.toChain) {
      const route = await crossChainService.findOptimalRoute(
        request.fromChain,
        request.toChain,
        request.amount,
        strategy.protocol
      );
      bridgeFee = BigInt(route.totalFees);
    }
    
    const totalFees = depositFee + gasFee + bridgeFee;
    
    // Risk assessment
    const risks = {
      overall: strategy.riskScore,
      impermanentLoss: strategy.impermanentLossRisk,
      smartContract: strategy.smartContractRisk,
      liquidity: strategy.liquidityRisk,
      market: this.calculateMarketRisk(strategy)
    };
    
    // Timeline estimates
    const timeline = {
      depositTime: request.fromChain !== request.toChain ? 300 : 60, // 5min cross-chain, 1min same-chain
      withdrawTime: strategy.lockupPeriod > 0 ? strategy.lockupPeriod : 300,
      lockupPeriod: strategy.lockupPeriod
    };
    
    // Yield breakdown
    const baseYield = strategy.currentAPY * 0.7; // Assume 70% base
    const rewardTokens = strategy.currentAPY * 0.25; // 25% from rewards
    const compoundEffect = strategy.autoCompound ? strategy.currentAPY * 0.05 : 0; // 5% compound bonus
    const feeImpact = -(strategy.performanceFee + strategy.managementFee);
    
    const netAPY = Math.max(0, strategy.currentAPY + compoundEffect + feeImpact);
    
    return {
      depositAmount: request.amount,
      expectedShares: previewShares.toString(),
      expectedAPY: netAPY,
      estimatedYearlyReturn: (Number(request.amount) * netAPY / 100).toString(),
      estimatedDailyReturn: (Number(request.amount) * netAPY / 365 / 100).toString(),
      fees: {
        deposit: depositFee.toString(),
        bridge: bridgeFee > 0 ? bridgeFee.toString() : undefined,
        gas: gasFee.toString(),
        total: totalFees.toString()
      },
      risks,
      timeline,
      breakdown: {
        baseYield,
        rewardTokens,
        compoundEffect,
        feeImpact
      }
    };
  }
  
  // Helper methods
  private async validateDepositRequest(request: DepositRequest): Promise<void> {
    if (!request.userAddress || !ethers.isAddress(request.userAddress)) {
      throw new Error('Invalid user address');
    }
    
    if (BigInt(request.amount) <= 0) {
      throw new Error('Amount must be greater than 0');
    }
    
    if (!this.chainConfigs.has(request.fromChain) || !this.chainConfigs.has(request.toChain)) {
      throw new Error('Unsupported chain');
    }
    
    if (request.deadline < Date.now()) {
      throw new Error('Deadline has passed');
    }
  }
  
  private generatePositionId(userAddress: string, strategyId: string): string {
    return `pos_${userAddress.slice(2, 8)}_${strategyId.slice(2, 8)}_${Date.now()}`;
  }
  
  private async getStrategy(strategyId: string): Promise<VaultStrategy | null> {
    return this.strategies.get(strategyId) || null;
  }
  
  private async executeDeposit(
    request: DepositRequest,
    strategy: VaultStrategy,
    route: any
  ): Promise<string> {
    // Implementation would execute the actual blockchain transactions
    // For now, return a mock transaction ID
    return `tx_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }
  
  private async executeWithdraw(
    request: WithdrawRequest,
    position: VaultPosition,
    strategy: VaultStrategy,
    route: any
  ): Promise<string> {
    // Implementation would execute withdrawal transactions
    return `tx_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }
  
  private async updatePositionMetrics(position: VaultPosition): Promise<void> {
    // Get current vault share price
    const strategy = this.strategies.get(position.vaultAddress);
    if (!strategy) return;
    
    const currentPrice = await priceService.getVaultSharePrice(position.vaultAddress, position.chain);
    const currentValue = (BigInt(position.sharesOwned) * BigInt(Math.floor(currentPrice * 1e18)) / BigInt(1e18)).toString();
    
    position.currentPrice = currentPrice.toString();
    position.currentValue = currentValue;
    position.pnl = (BigInt(currentValue) - BigInt(position.depositAmount)).toString();
    position.pnlPercentage = Number(position.depositAmount) > 0 
      ? Number(position.pnl) / Number(position.depositAmount) * 100 
      : 0;
    position.apy = strategy.currentAPY;
    position.lastUpdateTimestamp = Date.now();
  }
  
  private async getVaultContract(vaultAddress: string, chain: string): Promise<ethers.Contract> {
    const key = `${chain}_${vaultAddress}`;
    
    if (this.vaultContracts.has(key)) {
      return this.vaultContracts.get(key)!;
    }
    
    const provider = this.providers.get(chain);
    if (!provider) {
      throw new Error(`No provider for chain: ${chain}`);
    }
    
    const contract = new ethers.Contract(vaultAddress, VAULT_ABI, provider);
    this.vaultContracts.set(key, contract);
    
    return contract;
  }
  
  private async estimateGasFee(chain: string, operation: string): Promise<bigint> {
    const provider = this.providers.get(chain);
    if (!provider) return BigInt(100000); // Default estimate
    
    const feeData = await provider.getFeeData();
    const gasPrice = feeData.gasPrice || BigInt(30000000000); // 30 gwei
    
    // Estimate gas usage by operation
    const gasEstimates = {
      deposit: BigInt(200000),
      withdraw: BigInt(300000),
      crossChainDeposit: BigInt(500000),
      crossChainWithdraw: BigInt(600000)
    };
    
    const gasLimit = gasEstimates[operation as keyof typeof gasEstimates] || BigInt(200000);
    return gasPrice * gasLimit;
  }
  
  private calculateMarketRisk(strategy: VaultStrategy): number {
    // Simplified market risk based on asset volatility and protocol type
    const baseRisk = {
      lending: 2,
      liquidity: 4,
      'yield-farming': 5,
      staking: 3,
      options: 8,
      perpetuals: 9
    }[strategy.type] || 5;
    
    return Math.min(baseRisk + strategy.historical.volatility / 10, 10);
  }
  
  private async estimateWithdrawal(
    position: VaultPosition,
    request: WithdrawRequest
  ): Promise<string> {
    const vaultContract = await this.getVaultContract(position.vaultAddress, position.chain);
    
    if (request.type === 'shares') {
      return (await vaultContract.previewRedeem(BigInt(request.amount))).toString();
    } else {
      return request.amount;
    }
  }
  
  private async calculateWithdrawalFees(
    request: WithdrawRequest,
    strategy: VaultStrategy,
    route: any
  ): Promise<{ total: string; breakdown: Record<string, string> }> {
    const amount = BigInt(request.amount);
    const withdrawalFee = amount * BigInt(Math.floor(strategy.withdrawalFee * 100)) / BigInt(10000);
    const gasFee = await this.estimateGasFee(request.fromChain, 'withdraw');
    const bridgeFee = route ? BigInt(route.totalFees) : BigInt(0);
    
    const total = withdrawalFee + gasFee + bridgeFee;
    
    return {
      total: total.toString(),
      breakdown: {
        withdrawal: withdrawalFee.toString(),
        gas: gasFee.toString(),
        bridge: bridgeFee.toString()
      }
    };
  }
  
  private async startPositionMonitoring(): Promise<void> {
    // Start real-time monitoring of positions
    setInterval(async () => {
      for (const position of this.positions.values()) {
        await this.updatePositionMetrics(position);
      }
    }, 30000); // Update every 30 seconds
  }
  
  /**
   * Initialize with mock strategies for testing
   */
  async initializeMockStrategies(): Promise<void> {
    const mockStrategies: VaultStrategy[] = [
      {
        id: 'aerodrome-weth-usdc-vault',
        name: 'Aerodrome WETH/USDC Vault',
        protocol: 'Aerodrome',
        chain: 'base',
        type: 'liquidity',
        description: 'High-yield WETH/USDC liquidity provision on Base via Aerodrome',
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
      },
      {
        id: 'gmx-staking-vault',
        name: 'GMX Staking Vault',
        protocol: 'GMX',
        chain: 'arbitrum',
        type: 'staking',
        description: 'Stake GMX tokens for fees and esGMX rewards',
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
      },
      {
        id: 'pendle-lrt-vault',
        name: 'Pendle LRT Yield Vault',
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
      }
    ];
    
    for (const strategy of mockStrategies) {
      this.strategies.set(strategy.id, strategy);
    }
  }
}

// Export singleton instance
export const vaultService = new VaultService();