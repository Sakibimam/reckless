/**
 * Price Service - Asset price feeds and vault pricing
 * Handles real-time price data, oracle integration, and vault share pricing
 */

import { ethers } from 'ethers';
import axios from 'axios';

interface PriceData {
  symbol: string;
  price: number;
  priceChange24h: number;
  volume24h: number;
  marketCap: number;
  lastUpdated: number;
}

interface VaultSharePrice {
  vaultAddress: string;
  chain: string;
  sharePrice: number;
  totalAssets: string;
  totalSupply: string;
  lastUpdated: number;
}

interface PriceOracle {
  name: string;
  chains: string[];
  getPrices: (symbols: string[]) => Promise<Record<string, PriceData>>;
  getVaultPrice: (vaultAddress: string, chain: string) => Promise<number>;
}

export class PriceService {
  private oracles: Map<string, PriceOracle>;
  private priceCache: Map<string, PriceData>;
  private vaultPriceCache: Map<string, VaultSharePrice>;
  private providers: Map<string, ethers.Provider>;
  private updateInterval: NodeJS.Timeout | null = null;
  
  constructor() {
    this.oracles = new Map();
    this.priceCache = new Map();
    this.vaultPriceCache = new Map();
    this.providers = new Map();
    
    this.initializeProviders();
    this.initializeOracles();
    this.startPriceUpdates();
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
  
  private initializeOracles(): void {
    // CoinGecko Oracle
    this.oracles.set('coingecko', {
      name: 'CoinGecko',
      chains: ['all'],
      getPrices: this.getCoinGeckoPrices.bind(this),
      getVaultPrice: this.getVaultPriceFromChain.bind(this)
    });
    
    // Chainlink Oracle
    this.oracles.set('chainlink', {
      name: 'Chainlink',
      chains: ['ethereum', 'arbitrum', 'polygon', 'avalanche'],
      getPrices: this.getChainlinkPrices.bind(this),
      getVaultPrice: this.getVaultPriceFromChain.bind(this)
    });
    
    // 1inch Oracle
    this.oracles.set('1inch', {
      name: '1inch',
      chains: ['ethereum', 'arbitrum', 'polygon', 'base'],
      getPrices: this.get1inchPrices.bind(this),
      getVaultPrice: this.getVaultPriceFromChain.bind(this)
    });
  }
  
  /**
   * Get current price for a token
   */
  async getPrice(symbol: string, forceUpdate = false): Promise<number> {
    const cacheKey = symbol.toUpperCase();
    
    if (!forceUpdate && this.priceCache.has(cacheKey)) {
      const cached = this.priceCache.get(cacheKey)!;
      // Use cached price if less than 1 minute old
      if (Date.now() - cached.lastUpdated < 60000) {
        return cached.price;
      }
    }
    
    // Try to get price from multiple oracles
    for (const oracle of this.oracles.values()) {
      try {
        const prices = await oracle.getPrices([symbol]);
        if (prices[symbol]) {
          this.priceCache.set(cacheKey, prices[symbol]);
          return prices[symbol].price;
        }
      } catch (error) {
        console.warn(`Failed to get price from ${oracle.name}:`, error);
      }
    }
    
    throw new Error(`Could not fetch price for ${symbol}`);
  }
  
  /**
   * Get multiple token prices
   */
  async getPrices(symbols: string[], forceUpdate = false): Promise<Record<string, number>> {
    const prices: Record<string, number> = {};
    const symbolsToFetch: string[] = [];
    
    // Check cache first
    for (const symbol of symbols) {
      const cacheKey = symbol.toUpperCase();
      if (!forceUpdate && this.priceCache.has(cacheKey)) {
        const cached = this.priceCache.get(cacheKey)!;
        if (Date.now() - cached.lastUpdated < 60000) {
          prices[symbol] = cached.price;
          continue;
        }
      }
      symbolsToFetch.push(symbol);
    }
    
    // Fetch missing prices
    if (symbolsToFetch.length > 0) {
      for (const oracle of this.oracles.values()) {
        try {
          const oraclePrices = await oracle.getPrices(symbolsToFetch);
          for (const [symbol, priceData] of Object.entries(oraclePrices)) {
            if (!prices[symbol]) {
              prices[symbol] = priceData.price;
              this.priceCache.set(symbol.toUpperCase(), priceData);
            }
          }
          
          // If we got all prices, break
          if (Object.keys(prices).length === symbols.length) {
            break;
          }
        } catch (error) {
          console.warn(`Oracle ${oracle.name} failed:`, error);
        }
      }
    }
    
    return prices;
  }
  
  /**
   * Get vault share price
   */
  async getVaultSharePrice(vaultAddress: string, chain: string, forceUpdate = false): Promise<number> {
    const cacheKey = `${chain}_${vaultAddress.toLowerCase()}`;
    
    if (!forceUpdate && this.vaultPriceCache.has(cacheKey)) {
      const cached = this.vaultPriceCache.get(cacheKey)!;
      // Use cached price if less than 30 seconds old for vault prices
      if (Date.now() - cached.lastUpdated < 30000) {
        return cached.sharePrice;
      }
    }
    
    try {
      const provider = this.providers.get(chain);
      if (!provider) {
        throw new Error(`No provider for chain: ${chain}`);
      }
      
      // ERC4626 vault interface
      const vaultABI = [
        'function totalAssets() external view returns (uint256)',
        'function totalSupply() external view returns (uint256)',
        'function decimals() external view returns (uint8)'
      ];
      
      const vaultContract = new ethers.Contract(vaultAddress, vaultABI, provider);
      
      const [totalAssets, totalSupply, decimals] = await Promise.all([
        vaultContract.totalAssets(),
        vaultContract.totalSupply(),
        vaultContract.decimals()
      ]);
      
      // Calculate share price (assets per share)
      const sharePrice = totalSupply > 0 
        ? Number(totalAssets) / Number(totalSupply) 
        : 1.0;
      
      const vaultPrice: VaultSharePrice = {
        vaultAddress,
        chain,
        sharePrice,
        totalAssets: totalAssets.toString(),
        totalSupply: totalSupply.toString(),
        lastUpdated: Date.now()
      };
      
      this.vaultPriceCache.set(cacheKey, vaultPrice);
      return sharePrice;
      
    } catch (error) {
      console.error(`Failed to get vault price for ${vaultAddress}:`, error);
      return 1.0; // Default to 1:1 ratio
    }
  }
  
  /**
   * Calculate portfolio value in USD
   */
  async calculatePortfolioValue(positions: {
    token: string;
    amount: string;
    isVaultShare?: boolean;
    vaultAddress?: string;
    chain?: string;
  }[]): Promise<{
    totalValue: number;
    breakdown: Record<string, number>;
  }> {
    const breakdown: Record<string, number> = {};
    let totalValue = 0;
    
    // Get all required token prices
    const tokenSymbols = positions.map(p => p.token);
    const tokenPrices = await this.getPrices(tokenSymbols);
    
    for (const position of positions) {
      let positionValue = 0;
      
      if (position.isVaultShare && position.vaultAddress && position.chain) {
        // Vault share position
        const sharePrice = await this.getVaultSharePrice(position.vaultAddress, position.chain);
        const tokenPrice = tokenPrices[position.token] || 0;
        positionValue = Number(position.amount) * sharePrice * tokenPrice;
      } else {
        // Regular token position
        const tokenPrice = tokenPrices[position.token] || 0;
        positionValue = Number(position.amount) * tokenPrice;
      }
      
      breakdown[position.token] = (breakdown[position.token] || 0) + positionValue;
      totalValue += positionValue;
    }
    
    return { totalValue, breakdown };
  }
  
  /**
   * Get historical prices for analytics
   */
  async getHistoricalPrices(
    symbol: string,
    days: number = 30,
    interval: '1h' | '1d' | '1w' = '1d'
  ): Promise<{
    timestamps: number[];
    prices: number[];
  }> {
    try {
      // Use CoinGecko for historical data
      const response = await axios.get(
        `https://api.coingecko.com/api/v3/coins/${symbol}/market_chart`,
        {
          params: {
            vs_currency: 'usd',
            days: days,
            interval: interval
          }
        }
      );
      
      const prices = response.data.prices || [];
      return {
        timestamps: prices.map((p: [number, number]) => p[0]),
        prices: prices.map((p: [number, number]) => p[1])
      };
    } catch (error) {
      console.error('Failed to fetch historical prices:', error);
      return { timestamps: [], prices: [] };
    }
  }
  
  // Oracle implementations
  private async getCoinGeckoPrices(symbols: string[]): Promise<Record<string, PriceData>> {
    try {
      const ids = symbols.map(s => this.getCoingeckoId(s)).join(',');
      const response = await axios.get(
        'https://api.coingecko.com/api/v3/simple/price',
        {
          params: {
            ids: ids,
            vs_currencies: 'usd',
            include_24hr_vol: true,
            include_24hr_change: true,
            include_market_cap: true
          }
        }
      );
      
      const prices: Record<string, PriceData> = {};
      
      for (const symbol of symbols) {
        const id = this.getCoingeckoId(symbol);
        const data = response.data[id];
        if (data) {
          prices[symbol] = {
            symbol: symbol,
            price: data.usd,
            priceChange24h: data.usd_24h_change || 0,
            volume24h: data.usd_24h_vol || 0,
            marketCap: data.usd_market_cap || 0,
            lastUpdated: Date.now()
          };
        }
      }
      
      return prices;
    } catch (error) {
      console.error('CoinGecko API error:', error);
      return {};
    }
  }
  
  private async getChainlinkPrices(symbols: string[]): Promise<Record<string, PriceData>> {
    // Implementation for Chainlink price feeds
    // Would require on-chain calls to Chainlink aggregators
    return {};
  }
  
  private async get1inchPrices(symbols: string[]): Promise<Record<string, PriceData>> {
    // Implementation for 1inch price API
    return {};
  }
  
  private async getVaultPriceFromChain(vaultAddress: string, chain: string): Promise<number> {
    return this.getVaultSharePrice(vaultAddress, chain);
  }
  
  // Utility functions
  private getCoingeckoId(symbol: string): string {
    const symbolMap: Record<string, string> = {
      'BTC': 'bitcoin',
      'ETH': 'ethereum',
      'USDC': 'usd-coin',
      'USDT': 'tether',
      'DAI': 'dai',
      'WETH': 'weth',
      'WBTC': 'wrapped-bitcoin',
      'AERO': 'aerodrome-finance',
      'GMX': 'gmx',
      'PENDLE': 'pendle',
      'MATIC': 'matic-network',
      'AVAX': 'avalanche-2',
      'BNB': 'binancecoin'
    };
    
    return symbolMap[symbol.toUpperCase()] || symbol.toLowerCase();
  }
  
  /**
   * Start automatic price updates
   */
  private startPriceUpdates(): void {
    // Update major token prices every minute
    this.updateInterval = setInterval(async () => {
      const majorTokens = ['ETH', 'BTC', 'USDC', 'DAI', 'USDT'];
      try {
        await this.getPrices(majorTokens, true);
      } catch (error) {
        console.error('Failed to update major token prices:', error);
      }
    }, 60000); // 1 minute
  }
  
  /**
   * Stop price updates (cleanup)
   */
  stopPriceUpdates(): void {
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
      this.updateInterval = null;
    }
  }
  
  /**
   * Get price impact for large trades
   */
  async getPriceImpact(
    tokenIn: string,
    tokenOut: string,
    amountIn: string,
    chain: string
  ): Promise<number> {
    try {
      // Implementation would check DEX liquidity and calculate price impact
      // For now, return estimated impact based on trade size
      const tradeValue = Number(amountIn);
      
      if (tradeValue < 10000) return 0.1; // 0.1% for small trades
      if (tradeValue < 100000) return 0.5; // 0.5% for medium trades
      if (tradeValue < 1000000) return 1.5; // 1.5% for large trades
      return 3.0; // 3% for very large trades
      
    } catch (error) {
      console.error('Price impact calculation failed:', error);
      return 1.0; // Default 1% impact
    }
  }
  
  /**
   * Get token information including price and metadata
   */
  async getTokenInfo(tokenAddress: string, chain: string): Promise<{
    symbol: string;
    name: string;
    decimals: number;
    price: number;
    totalSupply: string;
  } | null> {
    try {
      const provider = this.providers.get(chain);
      if (!provider) return null;
      
      const tokenABI = [
        'function symbol() external view returns (string)',
        'function name() external view returns (string)',
        'function decimals() external view returns (uint8)',
        'function totalSupply() external view returns (uint256)'
      ];
      
      const tokenContract = new ethers.Contract(tokenAddress, tokenABI, provider);
      
      const [symbol, name, decimals, totalSupply] = await Promise.all([
        tokenContract.symbol(),
        tokenContract.name(),
        tokenContract.decimals(),
        tokenContract.totalSupply()
      ]);
      
      const price = await this.getPrice(symbol).catch(() => 0);
      
      return {
        symbol,
        name,
        decimals: Number(decimals),
        price,
        totalSupply: totalSupply.toString()
      };
      
    } catch (error) {
      console.error('Failed to get token info:', error);
      return null;
    }
  }
}

// Export singleton instance
export const priceService = new PriceService();