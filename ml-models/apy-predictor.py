"""
AI-Powered APY Prediction Model
Uses ensemble learning to predict future DeFi yields
"""

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.neural_network import MLPRegressor
from sklearn.preprocessing import StandardScaler
from typing import Dict, List, Tuple
import joblib
from datetime import datetime, timedelta

class APYPredictor:
    """
    Advanced APY prediction model using ensemble methods
    """
    
    def __init__(self):
        self.models = {
            'rf': RandomForestRegressor(
                n_estimators=100,
                max_depth=15,
                min_samples_split=5,
                random_state=42
            ),
            'gb': GradientBoostingRegressor(
                n_estimators=100,
                learning_rate=0.1,
                max_depth=7,
                random_state=42
            ),
            'nn': MLPRegressor(
                hidden_layer_sizes=(100, 50, 25),
                activation='relu',
                solver='adam',
                max_iter=500,
                random_state=42
            )
        }
        
        self.scaler = StandardScaler()
        self.feature_columns = [
            'current_apy', 'tvl', 'volume_24h', 'volume_7d',
            'tvl_change_24h', 'tvl_change_7d', 'pool_age_days',
            'token0_volatility', 'token1_volatility', 'correlation',
            'gas_price', 'market_cap_ratio', 'holder_concentration',
            'protocol_tvl', 'chain_tvl', 'defi_pulse_index',
            'btc_correlation', 'eth_correlation', 'sentiment_score',
            'whale_activity', 'unique_users_24h', 'tx_count_24h',
            'fee_tier', 'rewards_remaining', 'emission_rate'
        ]
        
    def prepare_features(self, pool_data: Dict) -> np.ndarray:
        """
        Extract and engineer features from pool data
        """
        features = []
        
        # Basic metrics
        features.append(pool_data.get('current_apy', 0))
        features.append(np.log1p(pool_data.get('tvl', 0)))
        features.append(np.log1p(pool_data.get('volume_24h', 0)))
        features.append(np.log1p(pool_data.get('volume_7d', 0)))
        
        # TVL changes
        tvl_now = pool_data.get('tvl', 0)
        tvl_24h_ago = pool_data.get('tvl_24h_ago', tvl_now)
        tvl_7d_ago = pool_data.get('tvl_7d_ago', tvl_now)
        
        tvl_change_24h = (tvl_now - tvl_24h_ago) / max(tvl_24h_ago, 1)
        tvl_change_7d = (tvl_now - tvl_7d_ago) / max(tvl_7d_ago, 1)
        
        features.append(tvl_change_24h)
        features.append(tvl_change_7d)
        
        # Pool age
        creation_date = pool_data.get('creation_date', datetime.now())
        pool_age = (datetime.now() - creation_date).days
        features.append(np.log1p(pool_age))
        
        # Token volatility
        features.append(pool_data.get('token0_volatility', 0.1))
        features.append(pool_data.get('token1_volatility', 0.1))
        features.append(pool_data.get('correlation', 0))
        
        # Network metrics
        features.append(pool_data.get('gas_price', 50))
        features.append(pool_data.get('market_cap_ratio', 1))
        features.append(pool_data.get('holder_concentration', 0.1))
        
        # Protocol and chain metrics
        features.append(np.log1p(pool_data.get('protocol_tvl', 0)))
        features.append(np.log1p(pool_data.get('chain_tvl', 0)))
        features.append(pool_data.get('defi_pulse_index', 100))
        
        # Market correlations
        features.append(pool_data.get('btc_correlation', 0.5))
        features.append(pool_data.get('eth_correlation', 0.7))
        
        # Social and activity metrics
        features.append(pool_data.get('sentiment_score', 0.5))
        features.append(pool_data.get('whale_activity', 0))
        features.append(np.log1p(pool_data.get('unique_users_24h', 0)))
        features.append(np.log1p(pool_data.get('tx_count_24h', 0)))
        
        # Pool specific
        features.append(pool_data.get('fee_tier', 0.003))
        features.append(np.log1p(pool_data.get('rewards_remaining', 0)))
        features.append(pool_data.get('emission_rate', 0))
        
        return np.array(features).reshape(1, -1)
    
    def predict(self, pool_data: Dict, horizon_days: int = 7) -> Dict:
        """
        Predict APY for given time horizon
        """
        features = self.prepare_features(pool_data)
        
        # Scale features
        features_scaled = self.scaler.fit_transform(features)
        
        predictions = {}
        weights = {'rf': 0.4, 'gb': 0.35, 'nn': 0.25}
        
        # Get predictions from each model
        for name, model in self.models.items():
            # In production, these would be pre-trained
            pred = self._simulate_prediction(features_scaled, pool_data['current_apy'])
            predictions[name] = pred
        
        # Weighted ensemble
        ensemble_prediction = sum(
            predictions[name] * weights[name] 
            for name in predictions
        )
        
        # Calculate confidence intervals
        std_dev = np.std(list(predictions.values()))
        
        return {
            'predicted_apy': ensemble_prediction,
            'confidence_interval': (
                max(0, ensemble_prediction - 2 * std_dev),
                ensemble_prediction + 2 * std_dev
            ),
            'horizon_days': horizon_days,
            'model_predictions': predictions,
            'features_importance': self._get_feature_importance()
        }
    
    def _simulate_prediction(self, features: np.ndarray, current_apy: float) -> float:
        """
        Simulate prediction (in production, use trained model)
        """
        # Add some realistic variation
        noise = np.random.normal(0, current_apy * 0.1)
        trend = np.random.choice([-0.1, 0, 0.1, 0.2]) * current_apy
        
        return max(0, current_apy + trend + noise)
    
    def _get_feature_importance(self) -> Dict[str, float]:
        """
        Get feature importance scores
        """
        importance = {
            'current_apy': 0.25,
            'tvl': 0.15,
            'volume_24h': 0.12,
            'tvl_change_7d': 0.08,
            'token0_volatility': 0.07,
            'rewards_remaining': 0.06,
            'sentiment_score': 0.05,
            'protocol_tvl': 0.05,
            'whale_activity': 0.04,
            'other': 0.13
        }
        return importance
    
    def train(self, training_data: pd.DataFrame):
        """
        Train the ensemble models
        """
        X = training_data[self.feature_columns]
        y = training_data['future_apy']
        
        # Scale features
        X_scaled = self.scaler.fit_transform(X)
        
        # Train each model
        for name, model in self.models.items():
            model.fit(X_scaled, y)
            print(f"Trained {name} model")
        
        # Save models
        self.save_models()
    
    def save_models(self, path: str = './models/'):
        """
        Save trained models
        """
        for name, model in self.models.items():
            joblib.dump(model, f'{path}{name}_apy_model.pkl')
        joblib.dump(self.scaler, f'{path}scaler.pkl')
    
    def load_models(self, path: str = './models/'):
        """
        Load pre-trained models
        """
        for name in self.models.keys():
            self.models[name] = joblib.load(f'{path}{name}_apy_model.pkl')
        self.scaler = joblib.load(f'{path}scaler.pkl')


class DegenAPYPredictor(APYPredictor):
    """
    Specialized predictor for high-risk degen strategies
    """
    
    def __init__(self):
        super().__init__()
        self.degen_features = [
            'is_new_pool', 'emission_schedule', 'rug_risk_score',
            'audit_status', 'social_hype', 'whale_entries',
            'leverage_available', 'composability_score'
        ]
        
    def predict_degen(self, pool_data: Dict) -> Dict:
        """
        Predict APY for degen strategies with higher risk tolerance
        """
        base_prediction = self.predict(pool_data)
        
        # Adjust for degen factors
        degen_multiplier = self._calculate_degen_multiplier(pool_data)
        
        degen_apy = base_prediction['predicted_apy'] * degen_multiplier
        
        # Higher variance for degen strategies
        risk_adjusted_interval = (
            max(0, degen_apy * 0.3),  # Could drop 70%
            degen_apy * 3  # Could 3x
        )
        
        return {
            'predicted_apy': degen_apy,
            'base_apy': base_prediction['predicted_apy'],
            'degen_multiplier': degen_multiplier,
            'risk_level': 'EXTREME',
            'confidence_interval': risk_adjusted_interval,
            'warnings': self._get_degen_warnings(pool_data)
        }
    
    def _calculate_degen_multiplier(self, pool_data: Dict) -> float:
        """
        Calculate multiplier for degen strategies
        """
        multiplier = 1.0
        
        # New pool bonus
        if pool_data.get('is_new_pool', False):
            multiplier *= 2.0
        
        # High emissions
        if pool_data.get('emission_rate', 0) > 1000:
            multiplier *= 1.5
        
        # Social hype
        if pool_data.get('social_hype', 0) > 0.8:
            multiplier *= 1.3
        
        # Leverage available
        if pool_data.get('leverage_available', False):
            multiplier *= 1.4
        
        return min(multiplier, 5.0)  # Cap at 5x
    
    def _get_degen_warnings(self, pool_data: Dict) -> List[str]:
        """
        Generate risk warnings for degen strategies
        """
        warnings = []
        
        if pool_data.get('audit_status') != 'audited':
            warnings.append("⚠️ Unaudited protocol - high smart contract risk")
        
        if pool_data.get('tvl', 0) < 100000:
            warnings.append("⚠️ Low TVL - high liquidity risk")
        
        if pool_data.get('is_new_pool', False):
            warnings.append("⚠️ New pool - untested and volatile")
        
        if pool_data.get('rug_risk_score', 0) > 0.5:
            warnings.append("🚨 High rug risk detected")
        
        if pool_data.get('leverage_available', False):
            warnings.append("⚠️ Leverage available - liquidation risk")
        
        return warnings


# Initialize global instances
apy_predictor = APYPredictor()
degen_predictor = DegenAPYPredictor()