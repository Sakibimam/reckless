"""
Comprehensive Risk Assessment Model for DeFi Yield Strategies
"""

import numpy as np
import pandas as pd
from typing import Dict, List, Tuple
from dataclasses import dataclass
from enum import Enum

class RiskCategory(Enum):
    SMART_CONTRACT = "smart_contract"
    IMPERMANENT_LOSS = "impermanent_loss"
    LIQUIDITY = "liquidity"
    PROTOCOL = "protocol"
    MARKET = "market"
    REGULATORY = "regulatory"
    ORACLE = "oracle"
    BRIDGE = "bridge"

@dataclass
class RiskMetrics:
    category: RiskCategory
    score: float  # 0-10, where 10 is highest risk
    confidence: float  # 0-1
    factors: Dict[str, float]
    mitigation: List[str]

class RiskAssessmentModel:
    """
    Comprehensive risk assessment for DeFi opportunities
    """
    
    def __init__(self):
        self.risk_weights = {
            RiskCategory.SMART_CONTRACT: 0.25,
            RiskCategory.IMPERMANENT_LOSS: 0.20,
            RiskCategory.LIQUIDITY: 0.15,
            RiskCategory.PROTOCOL: 0.15,
            RiskCategory.MARKET: 0.10,
            RiskCategory.REGULATORY: 0.05,
            RiskCategory.ORACLE: 0.05,
            RiskCategory.BRIDGE: 0.05
        }
        
        self.audit_firms = {
            'certik': 0.9,
            'peckshield': 0.85,
            'trail_of_bits': 0.9,
            'consensys': 0.85,
            'openzeppelin': 0.88,
            'quantstamp': 0.82,
            'hacken': 0.75
        }
    
    def assess_opportunity(self, opportunity_data: Dict) -> Dict:
        """
        Perform comprehensive risk assessment
        """
        risk_metrics = []
        
        # Assess each risk category
        risk_metrics.append(self.assess_smart_contract_risk(opportunity_data))
        risk_metrics.append(self.assess_impermanent_loss_risk(opportunity_data))
        risk_metrics.append(self.assess_liquidity_risk(opportunity_data))
        risk_metrics.append(self.assess_protocol_risk(opportunity_data))
        risk_metrics.append(self.assess_market_risk(opportunity_data))
        risk_metrics.append(self.assess_regulatory_risk(opportunity_data))
        risk_metrics.append(self.assess_oracle_risk(opportunity_data))
        risk_metrics.append(self.assess_bridge_risk(opportunity_data))
        
        # Calculate overall risk score
        overall_score = self.calculate_overall_risk(risk_metrics)
        
        # Determine risk tier
        risk_tier = self.determine_risk_tier(overall_score)
        
        # Generate recommendations
        recommendations = self.generate_recommendations(risk_metrics, opportunity_data)
        
        return {
            'overall_score': overall_score,
            'risk_tier': risk_tier,
            'risk_metrics': {rm.category.value: rm for rm in risk_metrics},
            'recommendations': recommendations,
            'suitable_for': self.determine_suitability(overall_score),
            'max_allocation_percentage': self.calculate_max_allocation(overall_score)
        }
    
    def assess_smart_contract_risk(self, data: Dict) -> RiskMetrics:
        """
        Assess smart contract related risks
        """
        factors = {}
        mitigations = []
        
        # Check audit status
        audit_score = 10  # Start with highest risk
        if data.get('audits'):
            audits = data['audits']
            best_audit_score = 10
            for audit in audits:
                firm = audit.get('firm', '').lower()
                if firm in self.audit_firms:
                    firm_reputation = self.audit_firms[firm]
                    audit_age_days = (pd.Timestamp.now() - pd.Timestamp(audit['date'])).days
                    
                    # Decay factor for old audits
                    age_factor = max(0.5, 1 - (audit_age_days / 365))
                    
                    score = (1 - firm_reputation * age_factor) * 10
                    best_audit_score = min(best_audit_score, score)
                    
            audit_score = best_audit_score
            factors['audit_quality'] = 10 - audit_score
            
            if audit_score < 3:
                mitigations.append("Multiple reputable audits completed")
        else:
            factors['audit_quality'] = 0
            mitigations.append("⚠️ Get protocol audited by reputable firm")
        
        # Check for bug bounty
        bug_bounty = data.get('bug_bounty_size', 0)
        if bug_bounty > 1000000:
            factors['bug_bounty'] = 8
            audit_score *= 0.8
            mitigations.append(f"${bug_bounty:,.0f} bug bounty program active")
        elif bug_bounty > 100000:
            factors['bug_bounty'] = 5
            audit_score *= 0.9
        else:
            factors['bug_bounty'] = 2
            mitigations.append("⚠️ Consider larger bug bounty program")
        
        # Check contract age and battle-testing
        contract_age_days = data.get('contract_age_days', 0)
        if contract_age_days > 365:
            factors['battle_tested'] = 8
            audit_score *= 0.7
            mitigations.append("Contract battle-tested for >1 year")
        elif contract_age_days > 90:
            factors['battle_tested'] = 5
            audit_score *= 0.85
        else:
            factors['battle_tested'] = 2
            mitigations.append("⚠️ New contract - wait for battle-testing")
        
        # Check for known vulnerabilities
        if data.get('known_vulnerabilities', 0) > 0:
            audit_score = min(10, audit_score + 3)
            mitigations.append("🚨 Known vulnerabilities detected")
        
        # Check upgrade mechanism
        if data.get('upgradeable', False):
            if data.get('timelock_days', 0) > 2:
                factors['upgrade_risk'] = 5
                mitigations.append(f"{data['timelock_days']} day timelock on upgrades")
            else:
                factors['upgrade_risk'] = 8
                audit_score = min(10, audit_score + 2)
                mitigations.append("⚠️ Upgradeable with short/no timelock")
        else:
            factors['upgrade_risk'] = 2
            mitigations.append("Non-upgradeable contract")
        
        return RiskMetrics(
            category=RiskCategory.SMART_CONTRACT,
            score=min(10, audit_score),
            confidence=0.85,
            factors=factors,
            mitigation=mitigations
        )
    
    def assess_impermanent_loss_risk(self, data: Dict) -> RiskMetrics:
        """
        Assess impermanent loss risk for LP positions
        """
        factors = {}
        mitigations = []
        
        if not data.get('is_lp_position', False):
            return RiskMetrics(
                category=RiskCategory.IMPERMANENT_LOSS,
                score=0,
                confidence=1.0,
                factors={'not_applicable': True},
                mitigation=["Not an LP position"]
            )
        
        # Get token volatilities
        vol1 = data.get('token1_volatility', 0.5)
        vol2 = data.get('token2_volatility', 0.5)
        correlation = data.get('token_correlation', 0)
        
        # Calculate IL risk based on volatility and correlation
        avg_vol = (vol1 + vol2) / 2
        vol_diff = abs(vol1 - vol2)
        
        # Higher volatility = higher IL risk
        vol_risk = min(10, avg_vol * 20)
        
        # Lower correlation = higher IL risk
        correlation_risk = (1 - abs(correlation)) * 5
        
        # Different volatilities = higher IL risk
        divergence_risk = min(5, vol_diff * 10)
        
        il_score = (vol_risk * 0.5 + correlation_risk * 0.3 + divergence_risk * 0.2)
        
        factors['volatility'] = avg_vol
        factors['correlation'] = correlation
        factors['divergence'] = vol_diff
        
        # Check for IL protection
        if data.get('il_protection', False):
            il_score *= 0.3
            mitigations.append("IL protection available")
        
        # Stable pairs have minimal IL
        if data.get('is_stable_pair', False):
            il_score = min(2, il_score)
            mitigations.append("Stable pair - minimal IL risk")
        
        # Concentrated liquidity increases IL risk
        if data.get('concentrated_liquidity', False):
            il_score = min(10, il_score * 1.5)
            mitigations.append("⚠️ Concentrated liquidity - higher IL risk")
        
        # Add mitigation strategies
        if il_score > 7:
            mitigations.append("⚠️ Consider single-sided staking instead")
            mitigations.append("⚠️ Use IL hedging strategies")
        elif il_score > 4:
            mitigations.append("Monitor price ratios regularly")
            mitigations.append("Consider rebalancing if divergence occurs")
        
        return RiskMetrics(
            category=RiskCategory.IMPERMANENT_LOSS,
            score=il_score,
            confidence=0.8,
            factors=factors,
            mitigation=mitigations
        )
    
    def assess_liquidity_risk(self, data: Dict) -> RiskMetrics:
        """
        Assess liquidity and exit risks
        """
        factors = {}
        mitigations = []
        
        tvl = data.get('tvl', 0)
        volume_24h = data.get('volume_24h', 0)
        unique_lps = data.get('unique_liquidity_providers', 0)
        
        # TVL-based risk
        if tvl > 10000000:  # >$10M
            tvl_risk = 1
            factors['tvl_depth'] = 9
            mitigations.append("Deep liquidity pool >$10M")
        elif tvl > 1000000:  # >$1M
            tvl_risk = 3
            factors['tvl_depth'] = 6
        elif tvl > 100000:  # >$100k
            tvl_risk = 6
            factors['tvl_depth'] = 3
        else:
            tvl_risk = 9
            factors['tvl_depth'] = 1
            mitigations.append("⚠️ Low liquidity - difficult exits")
        
        # Volume/TVL ratio (turnover)
        if tvl > 0:
            turnover = volume_24h / tvl
            factors['turnover'] = turnover
            
            if turnover > 1:  # High turnover
                volume_risk = 2
                mitigations.append("High trading activity")
            elif turnover > 0.1:
                volume_risk = 4
            else:
                volume_risk = 7
                mitigations.append("⚠️ Low trading volume")
        else:
            volume_risk = 10
        
        # LP concentration
        if unique_lps > 100:
            concentration_risk = 2
            factors['lp_distribution'] = 8
            mitigations.append("Well-distributed liquidity providers")
        elif unique_lps > 20:
            concentration_risk = 5
            factors['lp_distribution'] = 5
        else:
            concentration_risk = 8
            factors['lp_distribution'] = 2
            mitigations.append("⚠️ Concentrated liquidity providers")
        
        # Lock period
        lock_days = data.get('lock_period_days', 0)
        if lock_days > 30:
            lock_risk = min(10, lock_days / 10)
            factors['lock_period'] = lock_days
            mitigations.append(f"⚠️ {lock_days} day lock period")
        else:
            lock_risk = 0
            factors['lock_period'] = 0
        
        liquidity_score = (
            tvl_risk * 0.4 + 
            volume_risk * 0.3 + 
            concentration_risk * 0.2 + 
            lock_risk * 0.1
        )
        
        return RiskMetrics(
            category=RiskCategory.LIQUIDITY,
            score=liquidity_score,
            confidence=0.9,
            factors=factors,
            mitigation=mitigations
        )
    
    def assess_protocol_risk(self, data: Dict) -> RiskMetrics:
        """
        Assess protocol-level risks
        """
        factors = {}
        mitigations = []
        
        protocol_tvl = data.get('protocol_tvl', 0)
        protocol_age_days = data.get('protocol_age_days', 0)
        team_doxxed = data.get('team_doxxed', False)
        
        # Protocol TVL
        if protocol_tvl > 1000000000:  # >$1B
            tvl_risk = 1
            factors['protocol_size'] = 9
            mitigations.append("Blue-chip protocol with >$1B TVL")
        elif protocol_tvl > 100000000:  # >$100M
            tvl_risk = 3
            factors['protocol_size'] = 7
        elif protocol_tvl > 10000000:  # >$10M
            tvl_risk = 5
            factors['protocol_size'] = 5
        else:
            tvl_risk = 8
            factors['protocol_size'] = 2
            mitigations.append("⚠️ Small protocol - higher risk")
        
        # Protocol age
        if protocol_age_days > 365:
            age_risk = 2
            factors['maturity'] = 8
            mitigations.append("Established protocol >1 year")
        elif protocol_age_days > 90:
            age_risk = 5
            factors['maturity'] = 5
        else:
            age_risk = 8
            factors['maturity'] = 2
            mitigations.append("⚠️ New protocol <3 months")
        
        # Team assessment
        if team_doxxed:
            team_risk = 3
            factors['team_trust'] = 7
            mitigations.append("Team is doxxed/known")
        else:
            team_risk = 7
            factors['team_trust'] = 3
            mitigations.append("⚠️ Anonymous team")
        
        # Check for previous exploits
        previous_exploits = data.get('previous_exploits', 0)
        if previous_exploits > 0:
            exploit_risk = min(10, 5 + previous_exploits * 2)
            factors['exploit_history'] = previous_exploits
            mitigations.append(f"🚨 {previous_exploits} previous exploits")
        else:
            exploit_risk = 0
            factors['exploit_history'] = 0
        
        protocol_score = (
            tvl_risk * 0.3 + 
            age_risk * 0.3 + 
            team_risk * 0.2 + 
            exploit_risk * 0.2
        )
        
        return RiskMetrics(
            category=RiskCategory.PROTOCOL,
            score=protocol_score,
            confidence=0.85,
            factors=factors,
            mitigation=mitigations
        )
    
    def assess_market_risk(self, data: Dict) -> RiskMetrics:
        """
        Assess market and systemic risks
        """
        factors = {}
        mitigations = []
        
        # Token type risks
        token_types = data.get('token_types', [])
        if 'stablecoin' in token_types:
            type_risk = 2
            factors['token_stability'] = 8
            mitigations.append("Stablecoin exposure reduces volatility")
        elif 'bluechip' in token_types:  # ETH, BTC, etc
            type_risk = 4
            factors['token_stability'] = 6
        elif 'altcoin' in token_types:
            type_risk = 7
            factors['token_stability'] = 3
        else:  # memecoins, new tokens
            type_risk = 9
            factors['token_stability'] = 1
            mitigations.append("⚠️ High volatility token exposure")
        
        # Market correlation
        btc_correlation = abs(data.get('btc_correlation', 0.5))
        factors['market_correlation'] = btc_correlation
        
        if btc_correlation > 0.8:
            correlation_risk = 7
            mitigations.append("⚠️ High correlation with BTC")
        elif btc_correlation > 0.5:
            correlation_risk = 5
        else:
            correlation_risk = 3
            mitigations.append("Low market correlation")
        
        # Macro factors
        if data.get('sensitive_to_rates', False):
            macro_risk = 6
            factors['macro_sensitive'] = True
            mitigations.append("⚠️ Sensitive to interest rate changes")
        else:
            macro_risk = 3
            factors['macro_sensitive'] = False
        
        market_score = (
            type_risk * 0.5 + 
            correlation_risk * 0.3 + 
            macro_risk * 0.2
        )
        
        return RiskMetrics(
            category=RiskCategory.MARKET,
            score=market_score,
            confidence=0.75,
            factors=factors,
            mitigation=mitigations
        )
    
    def assess_regulatory_risk(self, data: Dict) -> RiskMetrics:
        """
        Assess regulatory and compliance risks
        """
        factors = {}
        mitigations = []
        
        # Geographic restrictions
        restricted_regions = data.get('restricted_regions', [])
        if 'US' in restricted_regions:
            geo_risk = 7
            factors['us_restricted'] = True
            mitigations.append("⚠️ US restrictions apply")
        else:
            geo_risk = 3
            factors['us_restricted'] = False
        
        # KYC requirements
        if data.get('kyc_required', False):
            kyc_risk = 2
            factors['kyc'] = True
            mitigations.append("KYC compliance required")
        else:
            kyc_risk = 5
            factors['kyc'] = False
        
        # Token classification
        if data.get('potential_security', False):
            security_risk = 8
            factors['security_risk'] = True
            mitigations.append("🚨 Potential security classification risk")
        else:
            security_risk = 3
            factors['security_risk'] = False
        
        regulatory_score = (
            geo_risk * 0.4 + 
            kyc_risk * 0.2 + 
            security_risk * 0.4
        )
        
        return RiskMetrics(
            category=RiskCategory.REGULATORY,
            score=regulatory_score,
            confidence=0.7,
            factors=factors,
            mitigation=mitigations
        )
    
    def assess_oracle_risk(self, data: Dict) -> RiskMetrics:
        """
        Assess oracle and price feed risks
        """
        factors = {}
        mitigations = []
        
        oracle_provider = data.get('oracle_provider', 'unknown')
        
        # Oracle reputation
        oracle_scores = {
            'chainlink': 2,
            'band': 4,
            'dia': 5,
            'api3': 5,
            'pyth': 3,
            'uma': 4,
            'twap': 6,
            'spot': 8,
            'unknown': 9
        }
        
        oracle_risk = oracle_scores.get(oracle_provider.lower(), 9)
        factors['oracle_provider'] = oracle_provider
        
        if oracle_risk <= 3:
            mitigations.append(f"Reputable oracle: {oracle_provider}")
        elif oracle_risk >= 7:
            mitigations.append(f"⚠️ Weak price feed: {oracle_provider}")
        
        # Multiple oracle sources
        if data.get('multi_oracle', False):
            oracle_risk *= 0.6
            factors['multi_oracle'] = True
            mitigations.append("Multiple oracle sources for redundancy")
        else:
            factors['multi_oracle'] = False
        
        # TWAP protection
        if data.get('twap_enabled', False):
            oracle_risk *= 0.8
            factors['twap_protection'] = True
            mitigations.append("TWAP protection against manipulation")
        else:
            factors['twap_protection'] = False
        
        return RiskMetrics(
            category=RiskCategory.ORACLE,
            score=oracle_risk,
            confidence=0.8,
            factors=factors,
            mitigation=mitigations
        )
    
    def assess_bridge_risk(self, data: Dict) -> RiskMetrics:
        """
        Assess cross-chain bridge risks
        """
        factors = {}
        mitigations = []
        
        if not data.get('uses_bridge', False):
            return RiskMetrics(
                category=RiskCategory.BRIDGE,
                score=0,
                confidence=1.0,
                factors={'not_applicable': True},
                mitigation=["No bridge required"]
            )
        
        bridge_provider = data.get('bridge_provider', 'unknown')
        
        # Bridge reputation
        bridge_scores = {
            'native': 2,  # Native chain bridge
            'layerzero': 3,
            'wormhole': 4,
            'axelar': 4,
            'celer': 5,
            'multichain': 7,
            'unknown': 9
        }
        
        bridge_risk = bridge_scores.get(bridge_provider.lower(), 9)
        factors['bridge_provider'] = bridge_provider
        
        # Bridge TVL and history
        bridge_tvl = data.get('bridge_tvl', 0)
        if bridge_tvl > 1000000000:  # >$1B
            bridge_risk *= 0.7
            factors['bridge_security'] = 7
            mitigations.append("High-security bridge with >$1B locked")
        elif bridge_tvl < 10000000:  # <$10M
            bridge_risk = min(10, bridge_risk * 1.5)
            factors['bridge_security'] = 3
            mitigations.append("⚠️ Low-security bridge")
        
        # Previous bridge hacks
        if data.get('bridge_hacked_before', False):
            bridge_risk = min(10, bridge_risk + 3)
            mitigations.append("🚨 Bridge has been hacked before")
        
        return RiskMetrics(
            category=RiskCategory.BRIDGE,
            score=bridge_risk,
            confidence=0.75,
            factors=factors,
            mitigation=mitigations
        )
    
    def calculate_overall_risk(self, risk_metrics: List[RiskMetrics]) -> float:
        """
        Calculate weighted overall risk score
        """
        total_score = 0
        total_weight = 0
        
        for metric in risk_metrics:
            weight = self.risk_weights.get(metric.category, 0.1)
            total_score += metric.score * weight * metric.confidence
            total_weight += weight * metric.confidence
        
        return total_score / total_weight if total_weight > 0 else 5
    
    def determine_risk_tier(self, overall_score: float) -> str:
        """
        Categorize risk into tiers
        """
        if overall_score < 2:
            return "MINIMAL"
        elif overall_score < 4:
            return "LOW"
        elif overall_score < 6:
            return "MEDIUM"
        elif overall_score < 8:
            return "HIGH"
        else:
            return "EXTREME"
    
    def determine_suitability(self, overall_score: float) -> List[str]:
        """
        Determine suitable investor profiles
        """
        suitable = []
        
        if overall_score < 4:
            suitable.extend(["Conservative", "Moderate", "Aggressive", "Degen"])
        elif overall_score < 6:
            suitable.extend(["Moderate", "Aggressive", "Degen"])
        elif overall_score < 8:
            suitable.extend(["Aggressive", "Degen"])
        else:
            suitable.append("Degen")
        
        return suitable
    
    def calculate_max_allocation(self, overall_score: float) -> float:
        """
        Calculate maximum recommended portfolio allocation
        """
        if overall_score < 2:
            return 40  # Up to 40% for minimal risk
        elif overall_score < 4:
            return 25  # Up to 25% for low risk
        elif overall_score < 6:
            return 15  # Up to 15% for medium risk
        elif overall_score < 8:
            return 8   # Up to 8% for high risk
        else:
            return 3   # Max 3% for extreme risk
    
    def generate_recommendations(self, risk_metrics: List[RiskMetrics], data: Dict) -> List[str]:
        """
        Generate actionable recommendations
        """
        recommendations = []
        
        # Find highest risk categories
        sorted_metrics = sorted(risk_metrics, key=lambda x: x.score, reverse=True)
        
        for metric in sorted_metrics[:3]:  # Top 3 risks
            if metric.score > 6:
                recommendations.extend(metric.mitigation[:2])  # Add top mitigations
        
        # Position sizing recommendation
        overall_score = self.calculate_overall_risk(risk_metrics)
        max_allocation = self.calculate_max_allocation(overall_score)
        recommendations.append(f"💰 Maximum allocation: {max_allocation}% of portfolio")
        
        # Entry timing
        if overall_score > 7:
            recommendations.append("⏰ Consider waiting for risk factors to improve")
        elif data.get('apy', 0) > 100:
            recommendations.append("⏰ Enter gradually to avoid FOMO")
        
        # Hedging strategies
        if any(m.category == RiskCategory.IMPERMANENT_LOSS and m.score > 6 for m in risk_metrics):
            recommendations.append("🛡️ Consider IL hedging strategies or insurance")
        
        return recommendations


# Initialize global instance
risk_assessor = RiskAssessmentModel()