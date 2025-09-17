import sys
import time
import bittensor as bt

from utils import TenexUtils

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
        self.tenexium_contract = TenexUtils.get_contract("NormalValidationFunctions", self.w3, self.network, "tenexiumProtocol")
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
        
        self.update_weights(self.subtensor.get_current_block())

        while True:
            try:
                current_block = self.subtensor.get_current_block()

                if self.should_update_weights(current_block):
                    self.update_weights(current_block)
                time.sleep(12)
                
            except KeyboardInterrupt:
                bt.logging.info("Validator stopped by user")
                break
            except Exception as e:
                bt.logging.error(f"Validator error: {e}")
                time.sleep(12)
    
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
        uint_uids, uint_weights = self.get_unnormalized_weights()
        bt.logging.debug(f"Unnormalized weights: {uint_weights}")

        total_weight = sum(uint_weights)
        
        if total_weight == 0:
            uint_weights[0] = U16_MAX
        else:
            for i in range(1, len(uint_weights)):
                uint_weights[i] = (uint_weights[i] * U16_MAX) / total_weight
        return uint_uids, uint_weights
    
    def get_unnormalized_weights(self):
        """
        Get unnormalized weights
        """
        bt.logging.info("Getting unnormalized weights...")
        uint_uids = self.metagraph.uids
        max_liquidity_providers_per_hotkey = self.tenexium_contract.functions.maxLiquidityProvidersPerHotkey().call()
        bt.logging.debug(f"Max liquidity providers per hotkey: {max_liquidity_providers_per_hotkey}")
        uint_weights = [0] * len(uint_uids)
        for uid in uint_uids:
            if uid == 0:
                continue
            hotkey_ss58_address = self.metagraph.hotkeys[uid]
            bt.logging.info(f"Computing weight for uid {uid} (hotkey {hotkey_ss58_address})")
            hotkey_bytes32 = TenexUtils.ss58_to_bytes(hotkey_ss58_address)
            liquidity_provider_count = self.tenexium_contract.functions.liquidityProviderSetLength(hotkey_bytes32).call()
            if liquidity_provider_count > max_liquidity_providers_per_hotkey:
                max_liquidity_providers = max_liquidity_providers_per_hotkey
            else:
                max_liquidity_providers = liquidity_provider_count
            for i in range(max_liquidity_providers):
                liquidity_provider = self.tenexium_contract.functions.groupLiquidityProviders(hotkey_bytes32, i).call()
                liquidity_provider_balance = self.tenexium_contract.functions.liquidityProviders(liquidity_provider).call()[0]
                bt.logging.debug(f"Liquidity provider balance: {liquidity_provider_balance / 10**18}τ")
                uint_weights[uid] += liquidity_provider_balance
                time.sleep(2)
            bt.logging.info(f"Derived weight for uid {uid} (hotkey {hotkey_ss58_address})")
            bt.logging.debug(f"Weight for uid {uid}: {uint_weights[uid]}")
            time.sleep(10)
        return uint_uids, uint_weights


def main():
    validator = TenexiumValidator()
    try:
        validator.run_validator()
    except KeyboardInterrupt:
        bt.logging.info("Validator is shutdown requested")
    finally:
        sys.exit(0)

if __name__ == "__main__":
    main() 
