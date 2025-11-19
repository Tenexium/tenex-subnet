import sys
import time
import os
import bittensor as bt
from scalecodec.types import Bool

from utils import TenexUtils
from data_store import ValidatorDataStore
from metrics_poller import MetricsPoller

class TenexiumValidator:   
    def __init__(self):
        """Initializes the Tenexium Validator"""
        self.w3, self.network, self.wallet, self.netuid, self.endpoint, self.logging_level, self.weight_update_interval_blocks = TenexUtils.get_signer_for_normal_validator()
        self.subtensor = bt.subtensor(self.endpoint)
        self.metagraph = self.subtensor.metagraph(self.netuid)
        self.hyperparams = self.subtensor.query_runtime_api(
            runtime_api="SubnetInfoRuntimeApi",
            method="get_subnet_hyperparams",
            params=[self.netuid],
            block=self.subtensor.get_current_block(),
        )
        self.last_weight_update_block = self.subtensor.get_current_block()
        self.tenexium_contract = TenexUtils.get_contract(self.w3, self.network, "tenexiumProtocol")
        
        # Initialize data store and metrics poller for 24h data collection
        db_path = os.getenv("VALIDATOR_DB_PATH", "validator_data.db")
        self.data_store = ValidatorDataStore(db_path=db_path)
        self.metrics_poller = MetricsPoller(
            w3=self.w3,
            tenexium_contract=self.tenexium_contract,
            subtensor=self.subtensor,
            netuid=self.netuid,
            data_store=self.data_store,
            poll_interval_seconds=60  # Poll every 1 minute
        )
        
        # Check if the hotkey is registered
        self.check_registered()
        bt.logging.setLevel(self.logging_level)
        bt.logging.info(f"Initialized Tenexium Validator")
    
    def check_registered(self):
        """
        Method to check if the hotkey configured to be used by the neuron is registered in the subnet.
        """
        bt.logging.debug("Checking registration...")
        if not self.subtensor.is_hotkey_registered(
            netuid=self.netuid,
            hotkey_ss58=self.wallet.hotkey.ss58_address,
        ):
            bt.logging.error(
                f"Hotkey {self.wallet.hotkey.ss58_address} is not registered on netuid {self.netuid}."
                f"Please register the hotkey using `btcli s register`."
            )
            exit()        
        bt.logging.debug(f"Hotkey ({self.wallet.hotkey.ss58_address}) is registered.")
    
    def run_validator(self):
        """Main validator loop """
        bt.logging.info("Starting Tenexium Validator ...")
        bt.logging.info(f"Netuid: {self.netuid}")
        bt.logging.info(f"Endpoint: {self.subtensor.chain_endpoint}")
        bt.logging.info(f"Validator Hotkey: {self.wallet.hotkey.ss58_address}")
        bt.logging.info(f"Last Weight Update Block: {self.last_weight_update_block}")
        
        # Start background metrics polling
        self.metrics_poller.start()
        bt.logging.info("Metrics poller started - collecting data every minute")
        
        # Log data collection status
        status = self.metrics_poller.get_data_status()
        bt.logging.info(
            f"Data collection status: {status['record_count']} records, "
            f"{status['data_age_hours']:.2f}h of data, "
            f"{status['coverage_percentage']:.1f}% coverage"
        )
        
        self.update_weights(self.subtensor.get_current_block())

        while True:
            try:
                current_block = self.subtensor.get_current_block()

                if self.should_update_weights(current_block):
                    self.metagraph = self.subtensor.metagraph(self.netuid)
                    self.update_weights(current_block)
                time.sleep(60)
                
            except KeyboardInterrupt:
                bt.logging.info("Validator stopped by user")
                break
            except Exception as e:
                bt.logging.error(f"Validator error: {e}")
    
    def should_update_weights(self, current_block: int) -> bool:
        bt.logging.info(f"Current block: {current_block}")
        bt.logging.info(f"Should update weights: {(current_block - self.last_weight_update_block) >= self.weight_update_interval_blocks}")
        return (current_block - self.last_weight_update_block) >= self.weight_update_interval_blocks
    
    def update_weights(self, current_block: int):
        """Calculate and set weights based on miner contributions"""
        try:
            bt.logging.info(f"Updating weights at block {current_block}")
            result, msg = self.set_weights()
            if result:
                self.last_weight_update_block = current_block
                bt.logging.info(f"Successfully updated weights at block {current_block}")
            else:
                bt.logging.error(f"Failed to update weights: {msg}")
        except Exception as e:
            bt.logging.error(f"Failed to update weights: {e}")
            raise e
    
    def set_weights(self):
        """
        Weight setting function
        """
        bt.logging.info("Setting weights...")
        # Get relevant hyperparameters
        version_key = self.hyperparams["weights_version"]
        commit_reveal_weights_enabled = bool(self.hyperparams["commit_reveal_weights_enabled"])
        # Prepare weights for submission
        uint_uids, uint_weights = self.prepare_weights()
        bt.logging.debug(f"commit_reveal_weights_enabled : {commit_reveal_weights_enabled}")
        bt.logging.debug(f"Weights: {uint_weights}")
        result, msg = self.subtensor.set_weights(
            wallet=self.wallet,
            netuid=self.netuid,
            uids=uint_uids,
            weights=uint_weights,
            wait_for_inclusion=False,
            wait_for_finalization=False,
            version_key=version_key,
        )
        return result, msg
    
    def prepare_weights(self):
        """
        Prepare weights for submission
        """
        bt.logging.info("Preparing weights...")
        U16_MAX = 65535
        uint_uids, weights = self.get_unnormalized_weights()
        bt.logging.debug(f"Unnormalized weights: {weights}")
        uint_weights = [0] * len(weights)
        total_weight = sum(weights)

        if total_weight == 0:
            uint_weights[0] = U16_MAX
        else:
            for i in range(0, len(weights)):
                uint_weights[i] = (weights[i] * U16_MAX) / total_weight
        return uint_uids, uint_weights
    
    def get_unnormalized_weights(self):
        """
        Get unnormalized weights based on 24-hour historical data.
        """
        current_block = self.w3.eth.get_block_number()
        # Get 24-hour aggregated data from metrics poller
        calculations = self.metrics_poller.get_24h_calculations()
        
        if calculations is None:
            # Fallback: use spot values if we don't have enough historical data yet
            bt.logging.warning(
                "Insufficient 24h data, using spot values. "
                "Weights may be less accurate until 24h of data is collected."
            )
            
            # Get latest data point to estimate daily values
            data = self.data_store.get_24h_data()
            if data:
                oldest, newest = data
                time_span_hours = (newest['timestamp'] - oldest['timestamp']) / 3600.0
                if time_span_hours > 0:
                    normalization_factor = 24.0 / time_span_hours
                    trading_fees_diff = newest['total_trading_fees'] - oldest['total_trading_fees']
                    borrowing_fees_diff = newest['total_borrowing_fees'] - oldest['total_borrowing_fees']
                    daily_lp_reward = (trading_fees_diff * 0.2625 + borrowing_fees_diff * 0.30625) * normalization_factor
                    miner_daily_emission = ((oldest['subnet_price'] + newest['subnet_price']) / 2.0) * 7200 * 0.41
                else:
                    # Absolute fallback if even partial data isn't available
                    daily_lp_reward = 0.0
                    miner_daily_emission = float(self.subtensor.get_subnet_price(self.netuid)) * 7200 * 0.41
            else:
                daily_lp_reward = 0.0
                miner_daily_emission = float(self.subtensor.get_subnet_price(self.netuid)) * 7200 * 0.41
        else:
            # Use accurate 24-hour calculations
            daily_lp_reward, miner_daily_emission = calculations
            bt.logging.info(
                f"Using 24h data - Daily LP Reward: {daily_lp_reward:.6f}, "
                f"Miner Daily Emission: {miner_daily_emission:.6f}"
            )
        
        # Get current total liquidity (spot value is fine for this)
        total_liquidity = float(self.tenexium_contract.functions.totalLpStakes().call()) / 10**18
        
        # Calculate LP emission percentage
        miner_apy = 1
        if miner_daily_emission + daily_lp_reward > 0:
            lp_emission_percentage = min(
                1.0,
                (total_liquidity * ((1 + miner_apy)**(1/365) - 1) - daily_lp_reward) / miner_daily_emission 
            )
        else:
            lp_emission_percentage = 0.0
        
        liquidator_emission_percentage = 1.0 - lp_emission_percentage

        bt.logging.info("Getting unnormalized weights...")
        uint_uids = self.metagraph.uids
        max_liquidity_providers_per_hotkey = self.tenexium_contract.functions.maxLiquidityProvidersPerHotkey().call()
        bt.logging.debug(f"Max liquidity providers per hotkey: {max_liquidity_providers_per_hotkey}")
        weights = [0.0] * len(uint_uids)

        for uid in uint_uids:
            if uid == 0:
                continue
            hotkey_ss58_address = self.metagraph.hotkeys[uid]
            bt.logging.info(f"Computing weight for uid {uid} (hotkey {hotkey_ss58_address})")
            hotkey_bytes32 = TenexUtils.ss58_to_bytes(hotkey_ss58_address)
            # Get liquidity provider count with retries
            liquidity_provider_count = self.tenexium_contract.functions.liquidityProviderSetLength(hotkey_bytes32).call()
            if liquidity_provider_count is None:
                continue

            max_liquidity_providers = min(liquidity_provider_count, max_liquidity_providers_per_hotkey)
            for i in range(max_liquidity_providers):
                liquidity_provider = self.tenexium_contract.functions.groupLiquidityProviders(hotkey_bytes32, i).call()
                if liquidity_provider is None:
                    continue

                liquidity_provider_balance = (float) (self.tenexium_contract.functions.liquidityProviders(liquidity_provider).call()[0]) / 10**18
                if liquidity_provider_balance is None:
                    continue
                bt.logging.debug(f"Liquidity provider balance: {liquidity_provider_balance}τ")
                weights[uid] += lp_emission_percentage * liquidity_provider_balance / total_liquidity

        liq_weights = [0.0] * len(uint_uids)
        total_liq_weights = 0.0
        for uid in uint_uids:
            if uid == 0:
                continue
            hotkey_ss58_address = self.metagraph.hotkeys[uid]
            bt.logging.info(f"Computing weight for uid {uid} (hotkey {hotkey_ss58_address})")
            hotkey_bytes32 = TenexUtils.ss58_to_bytes(hotkey_ss58_address)
            # Get liquidity provider count with retries
            liquidity_provider_count = self.tenexium_contract.functions.liquidityProviderSetLength(hotkey_bytes32).call()
            if liquidity_provider_count is None:
                continue

            max_liquidity_providers = min(liquidity_provider_count, max_liquidity_providers_per_hotkey)
            for i in range(max_liquidity_providers):
                liquidity_provider = self.tenexium_contract.functions.groupLiquidityProviders(hotkey_bytes32, i).call()
                if liquidity_provider is None:
                    continue

                totalLiquidatorLiquidationValue = self.tenexium_contract.functions.totalLiquidatorLiquidationValue(liquidity_provider).call()
                current_day = (int)(current_block / 7200)
                weeklyLiquidatorLiquidationValue = 0
                for j in range(current_day - 7, current_day):
                    weeklyLiquidatorLiquidationValue += self.tenexium_contract.functions.dailyLiquidatorLiquidationValue(liquidity_provider, j).call()
                dailyLiquidatorLiquidationValue = self.tenexium_contract.functions.dailyLiquidatorLiquidationValue(liquidity_provider, current_day).call()

                liq_weights[uid] += totalLiquidatorLiquidationValue * 0.2 + weeklyLiquidatorLiquidationValue * 0.3 + dailyLiquidatorLiquidationValue * 0.5

            total_liq_weights += liq_weights[uid]

        if total_liq_weights <= 0.0:
            weights[0] = liquidator_emission_percentage
        else:
            for uid in uint_uids:
                weights[uid] += liquidator_emission_percentage * liq_weights[uid] / total_liq_weights

        return uint_uids, weights
    
    def cleanup(self):
        """Cleanup resources before shutdown"""
        bt.logging.info("Cleaning up validator resources...")
        
        # Stop metrics poller
        if hasattr(self, 'metrics_poller'):
            self.metrics_poller.stop()
        
        # Close database connection
        if hasattr(self, 'data_store'):
            self.data_store.close()
        
        bt.logging.info("Cleanup complete")

def main():
    validator = TenexiumValidator()
    try:
        validator.run_validator()
    except KeyboardInterrupt:
        bt.logging.info("Validator shutdown requested")
    finally:
        validator.cleanup()
        sys.exit(0)

if __name__ == "__main__":
    main() 
