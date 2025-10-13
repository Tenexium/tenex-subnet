#!/usr/bin/env python3

import argparse
import sys
from web3 import Web3
from utils import TenexUtils

class TenexCLI:
    def __init__(self):
        pass
    
    def associate(self):
        """Associate the miner with the protocol"""
        try:
            w3, network, account, hotkey = TenexUtils.get_signer_for_miner()
            contract_address = TenexUtils.get_proxy_address(network, "tenexiumProtocol")
            contract = TenexUtils.get_contract("setAssociate", w3, network, "tenexiumProtocol")
            print(f" Associating {network}...")
            print(f"📝 Transaction details:")
            print(f"   Network: {network}")
            print(f"   Hotkey: {hotkey}")
            print(f"   From: {account.address}")
            print(f"   To: {contract_address}")
            
            # Check current balance
            balance = w3.eth.get_balance(account.address)
            balance_tao = w3.from_wei(balance, 'ether')
            print(f"   Current balance: {balance_tao} TAO")

            # Build transaction
            nonce = w3.eth.get_transaction_count(account.address)
            gas_price = w3.eth.gas_price
            estimated_gas = contract.functions.setAssociate(hotkey).estimate_gas(
                {
                    'from': account.address,
                    'value': 0,
                }
            )

            transaction = contract.functions.setAssociate(hotkey).build_transaction({
                'from': account.address,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': w3.eth.chain_id,
            })

            # Sign and send transaction
            signed_txn = w3.eth.account.sign_transaction(transaction, account.key)
            tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            
            print(f"   Transaction hash: {tx_hash.hex()}")
            print(f"⏳ Waiting for confirmation...")
            
            # Wait for transaction receipt
            receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
            
            print(f"✅ Associated successfully!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed}")
        
        except Exception as error:
            print(f"❌ Failed to associate: {error}")
            sys.exit(1)

    def add_liquidity(self, amount: str):
        """Add liquidity to the protocol"""
        try:
            w3, network, account, hotkey = TenexUtils.get_signer_for_miner()
            contract_address = TenexUtils.get_proxy_address(network, "tenexiumProtocol")
            contract = TenexUtils.get_contract("addLiquidity", w3, network, "tenexiumProtocol")
            amount_wei = w3.to_wei(amount, 'ether')
            
            print(f" Adding {amount} TAO liquidity to {network}...")
            print(f"📝 Transaction details:")
            print(f"   Network: {network}")
            print(f"   Amount: {amount} TAO ({amount_wei} wei)")
            print(f"   From: {account.address}")
            print(f"   To: {contract_address}")
            
            # Check current balance
            balance = w3.eth.get_balance(account.address)
            balance_tao = w3.from_wei(balance, 'ether')
            print(f"   Current balance: {balance_tao} TAO")

            # Check LP info
            lp_info = TenexUtils.get_contract("liquidityProviders", w3, network, "tenexiumProtocol").functions.liquidityProviders(account.address).call()
            lp_stake = w3.from_wei(lp_info[0], 'ether')  # stake is first element
            print(f"   Current LP stake: {lp_stake} TAO")
            
            if balance < amount_wei:
                raise ValueError(f"Insufficient balance. Need {amount} TAO, have {balance_tao} TAO")
            
            # Build transaction
            nonce = w3.eth.get_transaction_count(account.address)
            gas_price = w3.eth.gas_price
            
            estimated_gas = contract.functions.addLiquidity().estimate_gas(
                {
                    'from': account.address,
                    'value': amount_wei,
                }
            )

            transaction = contract.functions.addLiquidity().build_transaction({
                'from': account.address,
                'value': amount_wei,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': w3.eth.chain_id,
            })
            
            # Sign and send transaction
            signed_txn = w3.eth.account.sign_transaction(transaction, account.key)
            tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            
            print(f"   Transaction hash: {tx_hash.hex()}")
            print(f"⏳ Waiting for confirmation...")
            
            # Wait for transaction receipt
            receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
            
            print(f"✅ Liquidity added successfully!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed}")
            
            # Show updated stats
            self.show_liquidity_stats(account.address, w3, network)
            
        except Exception as error:
            print(f"❌ Failed to add liquidity: {error}")
            sys.exit(1)
    
    def remove_liquidity(self, amount: str):
        """Remove liquidity from the protocol"""
        try:
            w3, network, account, hotkey = TenexUtils.get_signer_for_miner()
            contract_address = TenexUtils.get_proxy_address(network, "tenexiumProtocol")
            contract = TenexUtils.get_contract("removeLiquidity", w3, network, "tenexiumProtocol")
            amount_wei = w3.to_wei(amount, 'ether')
            
            print(f" Removing {amount} TAO liquidity from {network}...")
            print(f"📝 Transaction details:")
            print(f"   Network: {network}")
            print(f"   Amount: {amount} TAO ({amount_wei} wei)")
            print(f"   From: {account.address}")
            print(f"   To: {contract_address}")
            
            # Check LP info
            lp_info = TenexUtils.get_contract("liquidityProviders", w3, network, "tenexiumProtocol").functions.liquidityProviders(account.address).call()
            lp_stake = w3.from_wei(lp_info[0], 'ether')  # stake is first element
            print(f"   Current LP stake: {lp_stake} TAO")
            
            if lp_info[0] < amount_wei:
                raise ValueError(f"Insufficient LP stake. Have {lp_stake} TAO, trying to remove {amount} TAO")
            
            # Build transaction
            nonce = w3.eth.get_transaction_count(account.address)
            gas_price = w3.eth.gas_price
            estimated_gas = contract.functions.removeLiquidity(amount_wei).estimate_gas(
                {
                    'from': account.address,
                    'value': 0,
                }
            )

            transaction = contract.functions.removeLiquidity(amount_wei).build_transaction({
                'from': account.address,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': w3.eth.chain_id,
            })
            
            # Sign and send transaction
            signed_txn = w3.eth.account.sign_transaction(transaction, account.key)
            tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            
            print(f"   Transaction hash: {tx_hash.hex()}")
            print(f"⏳ Waiting for confirmation...")
            
            # Wait for transaction receipt
            receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
            
            print(f"✅ Liquidity removed successfully!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed}")
            
            # Show updated stats
            self.show_liquidity_stats(account.address, w3, network)
            
        except Exception as error:
            print(f"❌ Failed to remove liquidity: {error}")
            sys.exit(1)
    
    def show_liquidity_stats(self, address, w3: Web3, network: str):
        """Show updated liquidity statistics"""
        try:
            total_lp_stakes = w3.from_wei(TenexUtils.get_contract("totalLpStakes", w3, network, "tenexiumProtocol").functions.totalLpStakes().call(), 'ether')
            total_lp_fees = w3.from_wei(TenexUtils.get_contract("totalPendingLpFees", w3, network, "tenexiumProtocol").functions.totalPendingLpFees().call(), 'ether')
            lp_info = TenexUtils.get_contract("liquidityProviders", w3, network, "tenexiumProtocol").functions.liquidityProviders(address).call()
            liquidity_circuit_breaker = TenexUtils.get_contract("liquidityCircuitBreaker", w3, network, "tenexiumProtocol").functions.liquidityCircuitBreaker().call()
            
            print(f"\n📊 Updated Protocol Stats:")
            print(f"   Total LP Stakes: {total_lp_stakes} TAO")  # totalLpStakesAmount
            print(f"   Total PendingLP Fees: {total_lp_fees} TAO")   # totalLpFeesAmount
            print(f"   Liquidity Circuit Breaker: {liquidity_circuit_breaker}")
            
            print(f"\n👤 Your LP Info:")
            print(f"   LP Stake: {w3.from_wei(lp_info[0], 'ether')} TAO")
            print(f"   LP Shares: {w3.from_wei(lp_info[3], 'ether')}")
            print(f"   Is Active: {lp_info[5]}")
            
        except Exception as error:
            print(f"⚠️  Could not fetch updated stats: {error}")

def validate_amount(amount: str):
    try:
        amount = float(amount)
        if amount <= 0:
            raise ValueError("Amount must be positive")
    except ValueError as e:
        print(f"❌ Invalid amount: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(
        description="Tenex CLI - Liquidity Management Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 tenex.py associate
  python3 tenex.py addliq --amount <amount>
  python3 tenex.py removeliq --amount <amount>
  python3 tenex.py showstats
        """
    )
    
    parser.add_argument(
        "command",
        choices=["associate", "addliq", "removeliq", "showstats"],
        help="Command to execute"
    )
    
    parser.add_argument(
        "--amount",
        required=False,
        help="Amount of TAO to add/remove"
    )
    
    parser.add_argument(
        "--network",
        default="mainnet",
        choices=["testnet", "mainnet"],
        help="Network to use (default: mainnet)"
    )
    
    args = parser.parse_args()
    
    cli = TenexCLI()
    
    if args.command == "associate":
        cli.associate()
    elif args.command == "addliq":
        validate_amount(args.amount)
        cli.add_liquidity(args.amount)
    elif args.command == "removeliq":
        validate_amount(args.amount)
        cli.remove_liquidity(args.amount)
    elif args.command == "showstats":
        w3, network, account, hotkey = TenexUtils.get_signer_for_miner()
        cli.show_liquidity_stats(account.address, w3, network)

if __name__ == "__main__":
    main()
