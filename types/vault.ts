export interface VaultPosition {
  id: string;
  userAddress: string;
  vaultAddress: string;
  chain: string;
  protocol: string;
  depositAmount: string;
  sharesOwned: string;
  currentValue: string;
  entryPrice: string;
  currentPrice: string;
  apy: number;
  pnl: string;
  pnlPercentage: number;
  depositTimestamp: number;
  lastUpdateTimestamp: number;
  strategy: {
    name: string;
    type: 'lending' | 'liquidity' | 'yield-farming' | 'staking' | 'options' | 'perpetuals';
    riskLevel: 'low' | 'medium' | 'high' | 'extreme';
    autoCompound: boolean;
  };
  crossChain: {
    originChain: string;
    bridgeUsed?: string;
    bridgeFees?: string;
  };
}

export interface VaultStrategy {
  id: string;
  name: string;
  protocol: string;
  chain: string;
  type: 'lending' | 'liquidity' | 'yield-farming' | 'staking' | 'options' | 'perpetuals';
  description: string;
  currentAPY: number;
  predictedAPY: number;
  tvl: string;
  maxCapacity: string;
  utilizationRate: number;
  riskScore: number;
  riskLevel: 'low' | 'medium' | 'high' | 'extreme';
  minDeposit: string;
  maxDeposit: string;
  depositFee: number; // percentage
  withdrawalFee: number; // percentage
  performanceFee: number; // percentage
  managementFee: number; // annual percentage
  autoCompound: boolean;
  lockupPeriod: number; // seconds
  impermanentLossRisk: number;
  smartContractRisk: number;
  liquidityRisk: number;
  assets: {
    primary: string;
    secondary?: string;
    lpToken?: string;
  };
  rewards: {
    tokens: string[];
    emissions: string[];
    claimable: boolean;
  };
  historical: {
    apy7d: number;
    apy30d: number;
    maxDrawdown: number;
    volatility: number;
  };
  lastUpdated: number;
}

export interface DepositRequest {
  amount: string;
  token: string;
  strategyId: string;
  fromChain: string;
  toChain: string;
  userAddress: string;
  slippageTolerance: number; // percentage
  deadline: number; // timestamp
  bridgePreference?: 'layerzero' | 'wormhole' | 'axelar' | 'celer' | 'auto';
  minReceived: string;
  referrer?: string;
}

export interface WithdrawRequest {
  amount: string; // amount of shares or underlying asset
  type: 'shares' | 'assets';
  positionId: string;
  fromChain: string;
  toChain: string;
  userAddress: string;
  slippageTolerance: number;
  deadline: number;
  emergency?: boolean;
  partialWithdraw?: boolean;
}

export interface VaultEstimate {
  depositAmount: string;
  expectedShares: string;
  expectedAPY: number;
  estimatedYearlyReturn: string;
  estimatedDailyReturn: string;
  fees: {
    deposit: string;
    bridge?: string;
    gas: string;
    total: string;
  };
  risks: {
    overall: number;
    impermanentLoss: number;
    smartContract: number;
    liquidity: number;
    market: number;
  };
  timeline: {
    depositTime: number; // seconds
    withdrawTime: number; // seconds
    lockupPeriod: number; // seconds
  };
  breakdown: {
    baseYield: number;
    rewardTokens: number;
    compoundEffect: number;
    feeImpact: number;
  };
}

export interface CrossChainRoute {
  id: string;
  fromChain: string;
  toChain: string;
  bridge: string;
  steps: CrossChainStep[];
  totalGas: string;
  totalFees: string;
  estimatedTime: number; // seconds
  success: boolean;
  reliability: number; // percentage
}

export interface CrossChainStep {
  type: 'bridge' | 'swap' | 'deposit' | 'approval';
  protocol: string;
  fromToken: string;
  toToken: string;
  fromAmount: string;
  toAmount: string;
  gasEstimate: string;
  fee: string;
  description: string;
  contractAddress: string;
  calldata?: string;
}

export interface VaultTransaction {
  id: string;
  hash: string;
  type: 'deposit' | 'withdraw' | 'harvest' | 'compound' | 'rebalance';
  status: 'pending' | 'confirmed' | 'failed' | 'cancelled';
  userAddress: string;
  vaultAddress: string;
  positionId?: string;
  chain: string;
  amount: string;
  token: string;
  gasUsed: string;
  gasPrice: string;
  fees: string;
  timestamp: number;
  blockNumber: number;
  confirmations: number;
  error?: string;
  crossChain?: {
    originChain: string;
    destinationChain: string;
    bridgeHash?: string;
    routeId: string;
  };
}

export interface VaultMetrics {
  totalValueLocked: string;
  totalUsers: number;
  totalPositions: number;
  averageAPY: number;
  totalVolume24h: string;
  totalFees24h: string;
  chainDistribution: Record<string, number>;
  protocolDistribution: Record<string, number>;
  riskDistribution: Record<string, number>;
  performanceHistory: {
    timestamp: number;
    apy: number;
    tvl: string;
  }[];
}

export interface UserVaultSummary {
  totalValue: string;
  totalPositions: number;
  averageAPY: number;
  totalPnL: string;
  totalPnLPercentage: number;
  dailyReturn: string;
  weeklyReturn: string;
  monthlyReturn: string;
  positions: VaultPosition[];
  chainDistribution: Record<string, {
    value: string;
    percentage: number;
    positions: number;
  }>;
  protocolDistribution: Record<string, {
    value: string;
    percentage: number;
    positions: number;
  }>;
  riskDistribution: Record<string, {
    value: string;
    percentage: number;
    positions: number;
  }>;
}

export interface RebalanceRecommendation {
  currentAllocation: Record<string, number>;
  recommendedAllocation: Record<string, number>;
  reasoning: string[];
  expectedImprovementAPY: number;
  rebalanceCost: string;
  positions: {
    close: string[];
    open: {
      strategyId: string;
      amount: string;
      reasoning: string;
    }[];
  };
  riskAdjustment: number;
  urgency: 'low' | 'medium' | 'high' | 'critical';
}

// API Response types
export interface VaultApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
  timestamp: number;
  requestId?: string;
}

export interface DepositResponse {
  transactionId: string;
  estimatedShares: string;
  route?: CrossChainRoute;
  steps: CrossChainStep[];
  totalFees: string;
  expectedConfirmationTime: number;
  positionId: string;
}

export interface WithdrawResponse {
  transactionId: string;
  estimatedAmount: string;
  route?: CrossChainRoute;
  steps: CrossChainStep[];
  totalFees: string;
  expectedConfirmationTime: number;
  partialWithdraw?: boolean;
  remainingShares?: string;
}

// Database schema types
export interface VaultPositionDB {
  id: string;
  user_address: string;
  vault_address: string;
  strategy_id: string;
  chain: string;
  protocol: string;
  deposit_amount: string;
  shares_owned: string;
  entry_price: string;
  deposit_timestamp: Date;
  last_update_timestamp: Date;
  origin_chain?: string;
  bridge_used?: string;
  bridge_fees?: string;
  status: 'active' | 'withdrawn' | 'liquidated';
  created_at: Date;
  updated_at: Date;
}

export interface VaultTransactionDB {
  id: string;
  hash: string;
  type: 'deposit' | 'withdraw' | 'harvest' | 'compound' | 'rebalance';
  status: 'pending' | 'confirmed' | 'failed' | 'cancelled';
  user_address: string;
  vault_address: string;
  position_id?: string;
  chain: string;
  amount: string;
  token: string;
  gas_used: string;
  gas_price: string;
  fees: string;
  timestamp: Date;
  block_number: number;
  confirmations: number;
  error?: string;
  origin_chain?: string;
  destination_chain?: string;
  bridge_hash?: string;
  route_id?: string;
  created_at: Date;
  updated_at: Date;
}

export interface StrategyPerformanceDB {
  id: string;
  strategy_id: string;
  timestamp: Date;
  apy: number;
  tvl: string;
  utilization_rate: number;
  total_deposits: string;
  total_withdrawals: string;
  performance_fee_collected: string;
  management_fee_collected: string;
  impermanent_loss: string;
  created_at: Date;
}