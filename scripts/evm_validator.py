import asyncio
import logging
import sys

from utils import TenexUtils


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class TenexiumValidator:   
    def __init__(self):
        """Initializes the Tenexium Validator"""
        self.w3, self.network, self.account, self.weight_update_interval_blocks = TenexUtils.get_signer_for_evm_validator()
        self.contract = TenexUtils.get_contract(self.w3, self.network, "subnetManager")
        self.contract_hotkey = TenexUtils.h160_to_ss58(self.contract.address)
        self.last_weight_update_block = self.w3.eth.get_block_number()
        self.signer_hotkey = TenexUtils.h160_to_ss58(self.account.address)
        logger.info(f"Initialized Tenexium Validator")
    
    async def run_validator(self):
        """Main validator loop (block-driven)"""
        logger.info("Starting Tenexium Validator (block-driven)...")
        logger.info(f"Network: {self.network}")
        logger.info(f"Signer: {self.account.address}")
        logger.info(f"Signer Hotkey: {self.signer_hotkey}")
        logger.info(f"Contract: {self.contract.address}")
        logger.info(f"Contract Hotkey: {self.contract_hotkey}")
        balance = self.w3.eth.get_balance(self.account.address)
        balance_tao = self.w3.from_wei(balance, 'ether')
        logger.info(f"Balance: {balance_tao} TAO")

        while True:
            try:
                current_block = self.w3.eth.get_block_number()

                # Update weights
                if self.should_update_weights(current_block):
                    await self.update_weights(current_block)
                await asyncio.sleep(12)
                
            except KeyboardInterrupt:
                logger.info("Validator stopped by user")
                break
            except Exception as e:
                logger.error(f"Validator error: {e}")
                await asyncio.sleep(12)
    
    def should_update_weights(self, current_block: int) -> bool:
        return (current_block - self.last_weight_update_block) >= self.weight_update_interval_blocks
    
    async def update_weights(self, current_block: int):
        """Calculate and set weights based on miner contributions"""
        try:
            logger.info(f"Updating weights at block {current_block}")
            nonce = self.w3.eth.get_transaction_count(self.account.address)
            gas_price = self.w3.eth.gas_price
            estimated_gas = self.contract.functions.setWeights().estimate_gas({
                'from': self.account.address,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': self.w3.eth.chain_id,
            })
            transaction = self.contract.functions.setWeights().build_transaction({
                'from': self.account.address,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': self.w3.eth.chain_id,
            })
            signed_txn = self.w3.eth.account.sign_transaction(transaction, self.account.key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            logger.info(f"Transaction hash: {tx_hash.hex()}")
            logger.info(f"Waiting for confirmation...")
            self.w3.eth.wait_for_transaction_receipt(tx_hash)
            logger.info(f"Successfully updated weights at block {current_block}")
            self.last_weight_update_block = current_block
        except Exception as e:
            logger.error(f"Failed to update weights: {e}")
            raise e

def main():
    validator = TenexiumValidator()
    try:
        asyncio.run(validator.run_validator())
    except KeyboardInterrupt:
        logger.info("Validator is shutdown requested")
    finally:
        sys.exit(0)

if __name__ == "__main__":
    main() 
